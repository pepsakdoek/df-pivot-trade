-- Enhanced fortress-wide stocks browser.
--@ module = true

local common = reqscript('internal/caravan/common')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local pivot_common = reqscript('internal/pivot_trade/common')
local drilldown = reqscript('internal/pivot_trade/drill_down_list')
local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local function get_active_depot()
    for _, bld in ipairs(df.global.world.buildings.all) do
        if df.building_tradedepotst:is_instance(bld) and
            bld:getBuildStage() >= bld:getMaxBuildStage() then
            return bld
        end
    end
end

StockView = defclass(StockView, drilldown.DrillDownList)
StockView.ATTRS{
    frame_title='Stocks',
    save_settings_id='stockview',
}

function StockView:cache_choices()
    if self.choices_cache then return self.choices_cache end
    drilldown.rebuild_uniform_assigned()
    self.choice_by_id = {}
    local items_data = {}
    for _, item in ipairs(df.global.world.items.other.IN_PLAY) do
        if not item or item.flags.removed then goto continue end
        if drilldown.is_unrevealed(item) then goto continue end
        local value = dfhack.items.getValue(item)
        local desc = dfhack.items.getReadableDescription(item)
        local class, subclass = classifier.classify_item(item)
        local group = pivot_common.get_generic_description(item) or "Other"
        local attrs = self:get_item_attrs(item)
        local search_key = pivot_common.make_search_key(('%s %s %s %s'):format(desc, class, subclass, group))
        local data = {
            item=item, desc=desc, per_item_value=value,
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=item:getWear(), class=class or 'Other',
            subclass=subclass or 'Other', grouped=group, attrs=attrs, pending=false,
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

function StockView:get_flat_choices()
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

function StockView:act_dump()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do if not item.flags.dump then all = false; break end end
    for _, item in ipairs(items) do item.flags.dump = not all end
    self:apply_status_changes(items)
end

function StockView:act_forbid()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do if not item.flags.forbid then all = false; break end end
    for _, item in ipairs(items) do item.flags.forbid = not all end
    self:apply_status_changes(items)
end

function StockView:act_melt()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do if not item.flags.melt then all = false; break end end
    for _, item in ipairs(items) do
        if all then dfhack.items.cancelMelting(item)
        elseif dfhack.items.canMelt(item) then dfhack.items.markForMelting(item) end
    end
    self:apply_status_changes(items)
end

function StockView:act_hide()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do if not item.flags.hidden then all = false; break end end
    for _, item in ipairs(items) do item.flags.hidden = not all end
    self:apply_status_changes(items)
end

function StockView:act_trade()
    local depot = get_active_depot()
    if not depot then return end
    local items = self:get_action_items()
    for _, item in ipairs(items) do
        if dfhack.items.canTrade(item) and not drilldown.is_trade_marked(item) then
            dfhack.items.markForTrade(item, depot)
        end
    end
    self:apply_status_changes(items)
end

local function get_target_item(choice)
    if choice.item_id then return choice.data.item end
    local items = choice.data.items
    if not items then return end
    for _, c in ipairs(items) do
        if c.data.pending then return c.data.item end
    end
    local first = items[1]
    return first and first.data.item
end

function StockView:act_zoom()
    local _, choice = self.subviews.list:getSelected()
    if not choice then return end
    local item = get_target_item(choice)
    if not item then return end
    local x, y, z = dfhack.items.getPosition(item)
    if not x then return end
    self.parent_view:dismiss()
    dfhack.gui.revealInDwarfmodeMap(xyz2pos(x, y, z), true, true)
end

function StockView:act_view_item()
    local _, choice = self.subviews.list:getSelected()
    if not choice then return end
    local item = get_target_item(choice)
    if not item then return end
    dfhack.gui.showItemDescription(item)
end

function StockView:make_bottom_actions()
    return {
        -- Row 0: item flag toggles
        widgets.HotkeyLabel{frame={t=0, l=0}, auto_width=true, label='Dump', key='CUSTOM_CTRL_D', on_activate=self:callback('act_dump')},
        widgets.HotkeyLabel{frame={t=0, l=13}, auto_width=true, label='Forbid', key='CUSTOM_CTRL_F', on_activate=self:callback('act_forbid')},
        widgets.HotkeyLabel{frame={t=0, l=28}, auto_width=true, label='Melt', key='CUSTOM_CTRL_M', on_activate=self:callback('act_melt')},
        widgets.HotkeyLabel{frame={t=0, l=41}, auto_width=true, label='Hide/Unhide', key='CUSTOM_CTRL_H', on_activate=self:callback('act_hide')},
        widgets.HotkeyLabel{frame={t=0, l=62}, auto_width=true, label='Trade', key='CUSTOM_CTRL_T', on_activate=self:callback('act_trade'), enabled=function() return get_active_depot() ~= nil end},
        -- Row 1: navigation and view
        widgets.HotkeyLabel{frame={t=1, l=0}, auto_width=true, label='Close and Zoom', key='CUSTOM_CTRL_O', on_activate=self:callback('act_zoom')},
        -- widgets.HotkeyLabel{frame={t=1, l=24}, auto_width=true, label='View Item Sheet', key='CUSTOM_CTRL_I', on_activate=self:callback('act_view_item')},
        widgets.HotkeyLabel{frame={t=1, l=49}, auto_width=true, label='Drill down all', key='CUSTOM_CTRL_PGDN', on_activate=self:callback('drill_down_all_visible')},
        widgets.HotkeyLabel{frame={t=1, l=80}, auto_width=true, label='Drill up', key='CUSTOM_CTRL_PGUP', on_activate=self:callback('go_back')},
        -- Row 2: selection and settings
        widgets.HotkeyLabel{frame={t=2, l=0}, auto_width=true, label='Select all/none', key='CUSTOM_CTRL_N', on_activate=self:callback('toggle_visible')},
        widgets.HotkeyLabel{frame={t=2, l=26}, auto_width=true, label='Save default', key='CUSTOM_ALT_S', on_activate=self:callback('save_default')},
        widgets.HotkeyLabel{frame={t=2, l=48}, auto_width=true, label='Restore default', key='CUSTOM_ALT_R', on_activate=self:callback('restore_default')},
    }
end

StockViewScreen = defclass(StockViewScreen, gui.ZScreenModal)
StockViewScreen.ATTRS{focus_path='stockview'}
function StockViewScreen:init()
    self:addviews{StockView{view_id='stockview'}}
end
function StockViewScreen:onDismiss()
    self.subviews.stockview:save_last()
    view = nil
end

StockViewLauncher = defclass(StockViewLauncher, overlay.OverlayWidget)
StockViewLauncher.ATTRS{
    desc='Adds a hotkey to open the enhanced stockview item browser.',
    default_pos={x=-3, y=-12}, default_enabled=true,
    viewscreens='dwarfmode/Stocks', frame={w=27, h=3},
    frame_style=gui.MEDIUM_FRAME, frame_background=gui.CLEAR_PEN,
}
function StockViewLauncher:init()
    self:addviews{widgets.TextButton{frame={t=0,l=0}, label='enhanced view', key='CUSTOM_SHIFT_Z', on_activate=function() view = view and view:raise() or StockViewScreen{}:show() end}}
end

OVERLAY_WIDGETS = {launcher=StockViewLauncher}

local function reset_window()
    for _, key in ipairs{'stockview/last', 'stockview/default'} do
        local s = dfhack.persistent.getSiteData(key)
        if s and s.frame then s.frame = nil; dfhack.persistent.saveSiteData(key, s) end
    end
    if view and view.subviews.stockview then
        local win = view.subviews.stockview
        win.frame = nil
        win:updateLayout()
    end
end

if dfhack_flags.module then return end
if not dfhack.world.isFortressMode() then qerror('gui/stockview requires fortress mode') end

local args = {...}
if args[1] == 'reset-window' then
    reset_window()
    print('stockview: window size and position reset to default')
    return
elseif args[1] then qerror('unknown command: '..args[1]) end

view = view and view:raise() or StockViewScreen{}:show()
