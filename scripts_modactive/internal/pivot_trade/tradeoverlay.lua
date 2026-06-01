--@ module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')
local utils = require('utils')

local trade = df.global.game.main_interface.trade

trader_selected_state = trader_selected_state or {}
broker_selected_state = broker_selected_state or {}
handle_ctrl_click_on_render = handle_ctrl_click_on_render or false
handle_shift_click_on_render = handle_shift_click_on_render or false

-- -------------------
-- TradeOverlay
--

local MARGIN_HEIGHT = 26 -- screen height *other* than the list

local function set_height(list_idx, delta)
    trade.i_height[list_idx] = trade.i_height[list_idx] + delta
    if delta >= 0 then return end
    _,screen_height = dfhack.screen.getWindowSize()
    -- list only increments in three tiles at a time
    local page_height = ((screen_height - MARGIN_HEIGHT) // 3) * 3
    trade.scroll_position_item[list_idx] = math.max(0,
            math.min(trade.scroll_position_item[list_idx],
                     trade.i_height[list_idx] - page_height))
end

local function flags_match(goodflag1, goodflag2)
    return goodflag1.selected == goodflag2.selected and
        goodflag1.contained == goodflag2.contained and
        goodflag1.container_collapsed == goodflag2.container_collapsed and
        goodflag1.filtered_off == goodflag2.filtered_off
end

local function select_shift_clicked_container_items(new_state, old_state_fn, list_idx)
    -- if ctrl is also held, collapse the container too
    local also_collapse = dfhack.internal.getModifiers().ctrl
    local collapsed_item_count, collapsing_container, in_target_container = 0, false, false
    for k, goodflag in ipairs(new_state) do
        if in_target_container then
            if not goodflag.contained then break end
            goodflag.selected = true
            if collapsing_container then
                collapsed_item_count = collapsed_item_count + 1
            end
            goto continue
        end

        local old_goodflag = old_state_fn(k)
        if flags_match(goodflag, old_goodflag) then goto continue end
        local is_container = df.item_binst:is_instance(trade.good[list_idx][k])
        if not is_container then goto continue end

        -- deselect the container itself
        goodflag.selected = false

        if also_collapse or old_goodflag.container_collapsed then
            goodflag.container_collapsed = true
            collapsing_container = not old_goodflag.container_collapsed
        end
        in_target_container = true

        ::continue::
    end

    if collapsed_item_count > 0 then
        set_height(list_idx, collapsed_item_count * -3)
    end
end

-- collapses uncollapsed containers and restores the selection state for the container
-- and contained items
local function toggle_ctrl_clicked_containers(new_state, old_state_fn, list_idx)
    local toggled_item_count, in_target_container, is_collapsing = 0, false, false
    for k, goodflag in ipairs(new_state) do
        local old_goodflag = old_state_fn(k)
        if in_target_container then
            if not goodflag.contained then break end
            toggled_item_count = toggled_item_count + 1
            utils.assign(goodflag, old_goodflag)
            goto continue
        end

        if flags_match(goodflag, old_goodflag) or goodflag.contained then goto continue end
        local is_container = df.item_binst:is_instance(trade.good[list_idx][k])
        if not is_container then goto continue end

        goodflag.selected = old_goodflag.selected
        goodflag.container_collapsed = not old_goodflag.container_collapsed
        in_target_container = true
        is_collapsing = goodflag.container_collapsed

        ::continue::
    end

    if toggled_item_count > 0 then
        set_height(list_idx, toggled_item_count * 3 * (is_collapsing and -1 or 1))
    end
end

local function collapseTypes(types_list, list_idx)
    local type_on_count = 0

    for k in ipairs(types_list) do
        local type_on = trade.current_type_a_on[list_idx][k]
        if type_on then
            type_on_count = type_on_count + 1
        end
        types_list[k] = false
    end

    trade.i_height[list_idx] = type_on_count * 3
    trade.scroll_position_item[list_idx] = 0
end

local function collapseAllTypes()
   collapseTypes(trade.current_type_a_expanded[0], 0)
   collapseTypes(trade.current_type_a_expanded[1], 1)
end

local function collapseContainers(item_list, list_idx)
    local num_items_collapsed = 0
    for k, goodflag in ipairs(item_list) do
        if goodflag.contained then goto continue end

        local item = trade.good[list_idx][k]
        local is_container = df.item_binst:is_instance(item)
        if not is_container then goto continue end

        if not goodflag.container_collapsed then
            goodflag.container_collapsed = true
            num_items_collapsed = num_items_collapsed + #dfhack.items.getContainedItems(item)
        end

        ::continue::
    end

    if num_items_collapsed > 0 then
        set_height(list_idx, num_items_collapsed * -3)
    end
end

local function collapseAllContainers()
    collapseContainers(trade.goodflag[0], 0)
    collapseContainers(trade.goodflag[1], 1)
end

local function collapseEverything()
    collapseAllContainers()
    collapseAllTypes()
end

local function copyGoodflagState()
    -- utils.clone will return a lua table, with indices offset by 1
    -- we'll use getSavedGoodflag to map the index back to the original value
    trader_selected_state = utils.clone(trade.goodflag[0], true)
    broker_selected_state = utils.clone(trade.goodflag[1], true)
end

local function getSavedGoodflag(saved_state, k)
    return saved_state[k+1]
end

PivotTradeOverlay = defclass(PivotTradeOverlay, overlay.OverlayWidget)
PivotTradeOverlay.ATTRS{
    desc='Adds convenience functions for working with bins to the trade screen.',
    default_pos={x=-3,y=-12},
    default_enabled=true,
    viewscreens={'dwarfmode/Trade/Default', 'dwarfmode/Stocks', 'dfhack/lua/caravan/trade'},
    frame={w=27, h=13},
    frame_style=gui.MEDIUM_FRAME,
    frame_background=gui.CLEAR_PEN,
}

function PivotTradeOverlay:init()
    self:addviews{
        widgets.BannerPanel{
            frame={t=0, l=0, r=0, b=0},
            subviews={
                widgets.Label{
                    frame={t=0, l=0},
                    text={
                        {text='Shift+Click checkbox', pen=COLOR_LIGHTGREEN}, ':',
                        NEWLINE,
                        '  select items inside bin',
                    },
                },
                widgets.Label{
                    frame={t=3, l=0},
                    text={
                        {text='Ctrl+Click checkbox', pen=COLOR_LIGHTGREEN}, ':',
                        NEWLINE,
                        '  collapse/expand bin',
                    },
                },
                widgets.HotkeyLabel{
                    frame={t=6, l=0},
                    label='collapse bins',
                    key='CUSTOM_CTRL_C',
                    on_activate=collapseAllContainers,
                },
                widgets.HotkeyLabel{
                    frame={t=7, l=0},
                    label='collapse all',
                    key='CUSTOM_CTRL_X',
                    on_activate=collapseEverything,
                },
                widgets.Label{
                    frame={t=9, l=0},
                    text = 'Shift+Scroll',
                    text_pen=COLOR_LIGHTGREEN,
                },
                widgets.Label{
                    frame={t=9, l=12},
                    text = ': fast scroll',
                },
            }
        }
    }
end

-- do our alterations *after* the vanilla response to the click has registered. otherwise
-- it's very difficult to figure out which item has been clicked
function PivotTradeOverlay:onRenderBody(dc)
    if handle_shift_click_on_render then
        handle_shift_click_on_render = false
        select_shift_clicked_container_items(trade.goodflag[0], curry(getSavedGoodflag, trader_selected_state), 0)
        select_shift_clicked_container_items(trade.goodflag[1], curry(getSavedGoodflag, broker_selected_state), 1)
    elseif handle_ctrl_click_on_render then
        handle_ctrl_click_on_render = false
        toggle_ctrl_clicked_containers(trade.goodflag[0], curry(getSavedGoodflag, trader_selected_state), 0)
        toggle_ctrl_clicked_containers(trade.goodflag[1], curry(getSavedGoodflag, broker_selected_state), 1)
    end
end

function PivotTradeOverlay:onInput(keys)
    if PivotTradeOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_L then
        if dfhack.internal.getModifiers().shift then
            handle_shift_click_on_render = true
            copyGoodflagState()
        elseif dfhack.internal.getModifiers().ctrl then
            handle_ctrl_click_on_render = true
            copyGoodflagState()
        end
    end
end
