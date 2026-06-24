-- Trade goods browser using DrillDownList.
--@ module = true

local common = reqscript('internal/caravan/common')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local pivot_common = reqscript('internal/pivot_trade/common')
local drilldown = reqscript('internal/pivot_trade/drill_down_list')
local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local trade = df.global.game.main_interface.trade

local STATUS_COLUMNS = {
    {id='noflags',    label='No status'},
    {id='artifact',   label='Artifact (Z)',     letter='Z', pen=COLOR_YELLOW,    test=function(i) return i.flags.artifact end},
    {id='spider_web', label='Spider web (S)',   letter='S', pen=COLOR_GREY,      test=function(i) return i.flags.spider_web end},
    {id='trader',     label='Caravan Owned (N)', letter='N', pen=COLOR_LIGHTGREEN, test=function(i) return i.flags.trader end},
}

DrillDownTrade = defclass(DrillDownTrade, drilldown.DrillDownList)
DrillDownTrade.ATTRS{
    frame_title='Trade goods',
    status_columns=STATUS_COLUMNS,
    has_own_layout=true,
    filters_visible=false,
}

function DrillDownTrade:before_build_ui()
    self.top_offset = 2
    self:addviews{
        widgets.TabBar{
            frame={t=0, l=0},
            labels={'Caravan Goods', 'Depot Goods'},
            on_select=function(idx)
                self.cur_page = idx
                self.choices_cache = nil
                self:refresh_list()
            end,
            get_cur_page=function() return self.cur_page end,
        },
    }
end

function DrillDownTrade:init()
    self._sort_columns = nil
    self.path = {}
    self.choices_cache = nil
    self.header_ranges = {}
    self:update_column_layout()
    self.frame = {w=150, h=47, l=10, t=10}
    self.cur_page = 1
    self:build_ui()
end

function DrillDownTrade:get_data_list()
    return trade.open and trade.good[self.cur_page - 1] or {}
end

function DrillDownTrade:get_data_flags()
    return trade.open and trade.goodflag[self.cur_page - 1] or {}
end

function DrillDownTrade:cache_choices()
    if self.choices_cache then return self.choices_cache end
    self.choice_by_id = {}
    local items_data = {}
    for i, item in ipairs(self:get_data_list()) do
        local gf = self:get_data_flags()[i]
        if not gf then goto continue end
        local value = pivot_common.get_perceived_value(item, trade.mer)
        local desc = dfhack.items.getReadableDescription(item)
        local class, subclass = classifier.classify_item(item)
        local group = pivot_common.get_generic_description(item) or "Other"
        local attrs = self:get_item_attrs(item)
        local search_key = pivot_common.make_search_key(('%s %s %s %s'):format(desc, class, subclass, group))
        local data = {
            item=item, desc=desc, per_item_value=value,
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=item:getWear(), class=class or 'Other',
            subclass=subclass or 'Other', grouped=group, attrs=attrs,
            pending=gf.selected or false,
            list_idx=self.cur_page - 1, item_idx=i,
        }
        local choice = {
            search_key=search_key, data=data, item_id=item.id,
            icon=function() return data.pending and pivot_common.ALL_PEN or nil end,
        }
        self.choice_by_id[item.id] = choice
        table.insert(items_data, choice)
        ::continue::
    end
    self.choices_cache = items_data
    return self.choices_cache
end

function DrillDownTrade:get_flat_choices()
    local flat = self:cache_choices()
    local filtered = {}
    for _, choice in ipairs(flat) do
        local d = choice.data
        local min_cond = self.subviews.min_condition:getOptionValue()
        local max_cond = self.subviews.max_condition:getOptionValue()
        local min_qual = self.subviews.min_quality:getOptionValue()
        local max_qual = self.subviews.max_quality:getOptionValue()
        local min_val_opt = self.subviews.min_value:getOptionValue()
        local min_val = min_val_opt.index == 1 and 0 or min_val_opt.value
        local max_val = self.subviews.max_value:getOptionValue().value
        if min_cond < d.wear then goto continue end
        if max_cond > d.wear then goto continue end
        if min_qual > d.quality then goto continue end
        if max_qual < d.quality then goto continue end
        if min_val > d.per_item_value then goto continue end
        if max_val < d.per_item_value then goto continue end
        table.insert(filtered, choice)
        ::continue::
    end
    return filtered
end

function DrillDownTrade:set_trade_flag(choice, value)
    local gf = self:get_data_flags()[choice.data.item_idx]
    if not gf then return end
    gf.selected = value
end

function DrillDownTrade:sync_trade_flags(choice, value)
    if choice.data.is_group then
        for _, ic in ipairs(choice.data.items) do self:set_trade_flag(ic, value) end
    else
        self:set_trade_flag(choice, value)
    end
end

function DrillDownTrade:toggle_item_base(choice, target_value)
    local result = drilldown.DrillDownList.toggle_item_base(self, choice, target_value)
    self:sync_trade_flags(choice, result)
    return result
end

function DrillDownTrade:get_action_items()
    local items = {}
    local all_choices = {}
    for _, c in ipairs(self.subviews.list:getVisibleChoices()) do
        if c.data.is_group then
            for _, ic in ipairs(c.data.items) do table.insert(all_choices, ic) end
        else table.insert(all_choices, c) end
    end
    for _, choice in ipairs(all_choices) do
        if choice.data.pending then table.insert(items, choice.data.item) end
    end
    if #items > 0 then return items end
    local _, choice = self.subviews.list:getSelected()
    if choice then
        if not choice.data.is_group then table.insert(items, choice.data.item)
        else for _, ic in ipairs(choice.data.items) do table.insert(items, ic.data.item) end end
    end
    for _, item in ipairs(items) do
        for i, gf in ipairs(self:get_data_flags()) do
            if gf.item == item then
                gf.selected = true
                local c = self.choice_by_id[item.id]
                if c then c.data.pending = true end
                break
            end
        end
    end
    return items
end

function DrillDownTrade:onInput(keys)
    if keys._MOUSE_L and self.subviews.list then
        local mx, my = dfhack.screen.getMousePos()
        if mx and my then
            local lf = self.subviews.list.frame
            local sf = self.frame
            if lf and sf then
                local lx, ly = mx - sf.l - lf.l, my - sf.t - lf.t
                local lw, lh = lf.w or 0, lf.h or 0
                if lx >= 0 and lx < lw and ly >= 0 and ly < lh then
                    local idx = self.subviews.list.list:getSelected()
                    local choices = self.subviews.list:getVisibleChoices()
                    local choice = choices and choices[idx]
                    if choice then self:toggle_item(idx, choice, lx); return true end
                end
            end
        end
    end
    return drilldown.DrillDownList.onInput(self, keys)
end

function DrillDownTrade:make_bottom_actions()
    return {
        widgets.HotkeyLabel{frame={t=0, l=0}, auto_width=true, label='Drill down all', key='CUSTOM_CTRL_PGDN', on_activate=self:callback('drill_down_all_visible')},
        widgets.HotkeyLabel{frame={t=0, l=28}, auto_width=true, label='Drill up', key='CUSTOM_CTRL_PGUP', on_activate=self:callback('go_back')},
        widgets.HotkeyLabel{frame={t=0, l=48}, auto_width=true, label='Select all/none', key='CUSTOM_CTRL_N', on_activate=self:callback('toggle_visible')},
        widgets.Label{
            view_id='subtotal',
            frame={t=1, l=0},
            text={{text=function()
                local total = 0
                for _, c in ipairs(self.subviews.list:getVisibleChoices()) do
                    if c.data.is_group then
                        for _, ic in ipairs(c.data.items) do
                            if ic.data.pending then total = total + (ic.data.per_item_value or 0) end
                        end
                    elseif c.data.pending then
                        total = total + (c.data.per_item_value or 0)
                    end
                end
                return 'Selected value: '..dfhack.formatInt(total)
            end, pen=COLOR_GREEN}},
        },
    }
end

-- -------------------
-- Screen / overlay
-- -------------------

DrillDownTradeScreen = defclass(DrillDownTradeScreen, gui.ZScreenModal)
DrillDownTradeScreen.ATTRS{focus_path='tradepivot'}
function DrillDownTradeScreen:init()
    local w = DrillDownTrade{view_id='tradepivot'}
    self.trade_window = w
    self:addviews{w}
end
function DrillDownTradeScreen:onDismiss()
    view = nil
end

DrillDownTradeLauncher = defclass(DrillDownTradeLauncher, overlay.OverlayWidget)
DrillDownTradeLauncher.ATTRS{
    desc='Opens a drill-down browser for trade screen goods.',
    default_pos={x=-31, y=-6}, default_enabled=true,
    viewscreens={'dwarfmode/Trade/Default', 'dfhack/lua/caravan/trade'},
    frame={w=25, h=1},
    frame_background=gui.CLEAR_PEN,
}
function DrillDownTradeLauncher:init()
    self:addviews{widgets.TextButton{frame={t=0,l=0}, label='Drill Down UI', key='CUSTOM_CTRL_Z',
        on_activate=function() view = view and view:raise() or DrillDownTradeScreen{}:show() end}}
end

OVERLAY_WIDGETS = {launcher=DrillDownTradeLauncher}

if dfhack_flags.module then return end
if not dfhack.world.isFortressMode() then qerror('gui/tradepivot requires fortress mode') end

view = view and view:raise() or DrillDownTradeScreen{}:show()
