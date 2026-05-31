--@ module = true
local common = reqscript('internal/pivot_trade/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local utils = require('utils')
local widgets = require('gui.widgets')

local trade = df.global.game.main_interface.trade


function is_ethical_product(item, animal_ethics, wood_ethics)
    if not animal_ethics and not wood_ethics then return true end
    -- bin contents are already split out; no need to double-check them
    if iteflags.container and not df.item_binst:is_instance(item) then
        for _, contained_item in ipairs(dfhack.items.getContainedItems(item)) do
            if (animal_ethics and contained_item:isAnimalProduct()) or
                (wood_ethics and common.has_wood(contained_item))
            then
                return false
            end
        end
    end

    return (not animal_ethics or not item:isAnimalProduct()) and
        (not wood_ethics or not common.has_wood(item))
end

-- also used by confirm
function for_selected_item(list_idx, fn)
    local goodflags = trade.goodflag[list_idx]
    local in_selected_container = false
    for item_idx, item in ipairs(trade.good[list_idx]) do
        local goodflag = goodflags[item_idx]
        if not goodflag.contained then
            in_selected_container = goodflag.selected
        end
        if in_selected_container or goodflag.selected then
            if fn(item_idx, item) then
                return
            end
        end
    end
end

local function for_ethics_violation(fn, animal_ethics, wood_ethics)
    if not animal_ethics and not wood_ethics then return end
    for_selected_item(1, function(item_idx, item)
        if not is_ethical_product(item, animal_ethics, wood_ethics) then
            if fn(item_idx, item) then return true end
        end
    end)
end

-- also called by confirm
function has_ethics_violation()
    local violated = false
    for_ethics_violation(function()
        violated = true
        return true
    end, common.is_animal_lover_caravan(trade.mer), common.is_tree_lover_caravan(trade.mer))
    return violated
end


local Ethics = defclass(Ethics, widgets.Window)
Ethics.ATTRS {
    frame_title='Ethical transgressions',
    frame={w=45, h=30},
    resizable=true,
}

function Ethics:init()
    self.choices = {}
    self.animal_ethics = common.is_animal_lover_caravan(trade.mer)
    self.wood_ethics = common.is_tree_lover_caravan(trade.mer)

    self:addviews{
        widgets.Label{
            frame={l=0, t=0},
            text={
                'You have ',
                {text=self:callback('get_transgression_count'), pen=self:callback('get_transgression_color')},
                ' item',
                {text=function() return self:get_transgression_count() == 1 and '' or 's' end},
                ' selected for trade', NEWLINE,
                'that would offend the merchants:',
            },
        },
        widgets.List{
            view_id='list',
            frame={l=0, r=0, t=3, b=2},
        },
        widgets.HotkeyLabel{
            frame={l=0, b=0},
            key='CUSTOM_CTRL_N',
            label='Deselect items in trade list',
            auto_width=true,
            on_activate=self:callback('deselect_transgressions'),
        },
    }

    self:rescan()
end

function Ethics:get_transgression_count()
    return #self.choices
end

function Ethics:get_transgression_color()
    return next(self.choices) and COLOR_LIGHTRED or COLOR_LIGHTGREEN
end

function Ethics:rescan()
    local choices = {}
    for_ethics_violation(function(item_idx, item)
        local choice = {
            text=dfhack.items.getReadableDescription(item),
            data={item_idx=item_idx},
        }
        table.insert(choices, choice)
    end, self.animal_ethics, self.wood_ethics)

    self.subviews.list:setChoices(choices)
    self.choices = choices
end

function Ethics:deselect_transgressions()
    local goodflags = trade.goodflag[1]
    for _,choice in ipairs(self.choices) do
        goodflags[choice.data.item_idx].selected = false
    end
    self:rescan()
end

-- -------------------
-- EthicsScreen
--

local ethics_view = ethics_view or nil

EthicsScreen = defclass(EthicsScreen, gui.ZScreen)
EthicsScreen.ATTRS {
    focus_path='pivot_trade/trade/ethics',
}

function EthicsScreen:init()
    self.ethics_window = Ethics{}
    self:addviews{self.ethics_window}
end

function EthicsScreen:onInput(keys)
    if self.reset_pending then return false end
    local handled = EthicsScreen.super.onInput(self, keys)
    if keys._MOUSE_L and not self.ethics_window:getMouseFramePos() then
        -- check for modified selection
        self.reset_pending = true
    end
    return handled
end

function EthicsScreen:onRenderFrame()
    if not df.global.game.main_interface.trade.open then
        if ethics_view then ethics_view:dismiss() end
    elseif self.reset_pending and
        (dfhack.gui.matchFocusString('dfhack/lua/pivot_trade/trade') or
         dfhack.gui.matchFocusString('dwarfmode/Trade/Default'))
    then
        self.reset_pending = nil
        self.ethics_window:rescan()
    end
end

function EthicsScreen:onDismiss()
    ethics_view = nil
end

-- --------------------------
-- TradeEthicsWarningOverlay
--

TradeEthicsWarningOverlay = defclass(TradeEthicsWarningOverlay, overlay.OverlayWidget)
TradeEthicsWarningOverlay.ATTRS{
    desc='Adds warning to the trade screen when you are about to offend the elves.',
    default_pos={x=-54,y=-5},
    default_enabled=true,
    viewscreens={'dwarfmode/Trade/Default', 'dwarfmode/Stocks', 'dfhack/lua/caravan/trade'},
    frame={w=9, h=2},
    visible=has_ethics_violation,
}

function TradeEthicsWarningOverlay:init()
    self:addviews{
        widgets.BannerPanel{
            frame={l=0, w=9},
            subviews={
                widgets.Label{
                    frame={l=1, r=1},
                    text={
                        'Ethics', NEWLINE,
                        'warning',
                    },
                    on_click=function() ethics_view = ethics_view and ethics_view:raise() or EthicsScreen{}:show() end,
                    text_pen=COLOR_LIGHTRED,
                    auto_width=false,
                },
            },
        },
    }
end

function TradeEthicsWarningOverlay:preUpdateLayout(rect)
    self.frame.w = (rect.width - 95) // 2
end

function TradeEthicsWarningOverlay:onInput(keys)
    if TradeEthicsWarningOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if ethics_view then
            ethics_view:dismiss()
        end
    end
end
