--@ module = true

-- TODO: the category checkbox that indicates whether all items in the category
-- are selected can be incorrect after the overlay adjusts the container
-- selection. the state is in trade.current_type_a_flag, but figuring out which
-- index to modify is non-trivial.


local version = 'v0.51'
local common = reqscript('internal/pivot_trade/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local predicates = reqscript('internal/pivot_trade/predicates')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local sorting = reqscript('internal/pivot_trade/sorting')
local ethics = reqscript('internal/pivot_trade/ethics')
local tradeoverlay = reqscript('internal/pivot_trade/tradeoverlay')
local utils = require('utils')
local widgets = require('gui.widgets')

local trade = df.global.game.main_interface.trade

LuaTrade = defclass(LuaTrade, widgets.Window)
LuaTrade.ATTRS {
    frame_title='Select trade goods',
    frame={w=150, h=47, l=10, t=10},
    resizable=true,
    resize_min={w=48, h=40},
}


local STATUS_COL_WIDTH = 2
local COUNT_COL_WIDTH = 4
local VALUE_COL_WIDTH = 6
local FILTER_HEIGHT = 18
local DEFAULT_CLASS_COL_WIDTH = 20
local DEFAULT_SUBCLASS_COL_WIDTH = 15
local DEFAULT_GROUPED_COL_WIDTH = 20
local DEFAULT_DESCRIPTION_COL_WIDTH = 50

local MIN_CLASS_COL_WIDTH = #('Class')
local MIN_SUBCLASS_COL_WIDTH = #('Subclass')
local MIN_GROUPED_COL_WIDTH = #('Grouped')
local MIN_DESCRIPTION_COL_WIDTH = #('Item Description')


local class_col_width = DEFAULT_CLASS_COL_WIDTH
local subclass_col_width = DEFAULT_SUBCLASS_COL_WIDTH
local grouped_col_width = DEFAULT_GROUPED_COL_WIDTH
local description_col_width = DEFAULT_DESCRIPTION_COL_WIDTH
local during_init = false

local function get_generic_description(item)
    local desc = dfhack.items.getReadableDescription(item)
    desc = desc:gsub("[%-%+%*#≡%(%){}%[%]<>%z\174\175\240]", "")
    
    -- Strip "left" and "right" specifically for shoes/gloves
    desc = desc:gsub("%f[%a][Ll]eft%f[%A]", "")
    desc = desc:gsub("%f[%a][Rr]ight%f[%A]", "")
    
    -- Clean up double spaces from the removals
    desc = desc:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
    
    return desc
end



function LuaTrade:init()
    during_init = true
    self.path = {}
    self.cur_page = trade.open and 1 or 2
    self.filters = {'', ''}
    self.predicate_contexts = {{name='trade_caravan'}, {name='trade_fort'}}

    self.animal_ethics = trade.open and common.is_animal_lover_caravan(trade.mer) or false
    self.wood_ethics = trade.open and common.is_tree_lover_caravan(trade.mer) or false
    self.banned_items = common.get_banned_items()
    self.risky_items = common.get_risky_items(self.banned_items)
    self.stock_selection = {}

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort',
            visible=false,
            frame={t=0, l=0, w=21},
            label='Sort by:',
            key='CUSTOM_SHIFT_S',
            options={
                {label='status'..common.CH_DN, value=sorting.sort_by_status_desc},
                {label='status'..common.CH_UP, value=sorting.sort_by_status_asc},
                {label='cnt'..common.CH_DN, value=sorting.sort_by_count_desc},
                {label='cnt'..common.CH_UP, value=sorting.sort_by_count_asc},
                {label='value'..common.CH_DN, value=sorting.sort_by_value_desc},
                {label='value'..common.CH_UP, value=sorting.sort_by_value_asc},
                {label='class'..common.CH_DN, value=sorting.sort_by_class_desc},
                {label='class'..common.CH_UP, value=sorting.sort_by_class_asc},
                {label='subclass'..common.CH_DN, value=sorting.sort_by_subclass_desc},
                {label='subclass'..common.CH_UP, value=sorting.sort_by_subclass_asc},
                {label='grp'..common.CH_DN, value=sorting.sort_by_grouped_desc},
                {label='grp'..common.CH_UP, value=sorting.sort_by_grouped_asc},
                {label='name'..common.CH_DN, value=sorting.sort_by_name_desc},
                {label='name'..common.CH_UP, value=sorting.sort_by_name_asc},
            },
            initial_option=sorting.sort_by_status_desc,
            on_change=self:callback('on_sort_change'),
        },
        widgets.ToggleHotkeyLabel{
            view_id='trade_bins',
            frame={t=0, l=0, w=36},
            label='Bins:',
            key='CUSTOM_SHIFT_B',
            options={
                {label='Trade bin with contents', value=true, pen=COLOR_YELLOW},
                {label='Trade contents only', value=false, pen=COLOR_GREEN},
            },
            initial_option=false,
            on_change=function() self:refresh_list() end,
            visible=function() return trade.open end,
        },
        widgets.TabBar{
            frame={t=2, l=0},
            labels={
                'Caravan goods',
                'Fort goods',
            },
            on_select=function(idx)
                local list = self.subviews.list
                self.filters[self.cur_page] = list:getFilter()
                list:setFilter(self.filters[idx])
                self.cur_page = idx
                self:refresh_list()
            end,
            get_cur_page=function() return self.cur_page end,
            visible=function() return trade.open end,
        },
        widgets.Label{
            frame={t=2, l=0},
            text='Fort Stocks (Pivoted)',
            visible=function() return not trade.open end,
        },

        widgets.ToggleHotkeyLabel{
            view_id='filters',
            frame={t=5, l=0, w=36},
            label='Show filters:',
            key='CUSTOM_SHIFT_F',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=false,
            on_change=function() self:updateLayout() end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='auto_resize_cols',
            frame={t=0, l=40, w=40},
            label='Auto columns widths:',
            key='CUSTOM_SHIFT_R',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=true,
            on_change=function() self:refresh_list() end,
        },
        widgets.HotkeyLabel{
            view_id='search',
            frame={t=5, l=40},
            label='Search:',
            key='CUSTOM_ALT_S',
            on_activate=function() self:activate_search() end,
            auto_width=true,
        },
        widgets.EditField{
            view_id='search_edit',
            frame={t=5, l=55, r=1},
            label_text='',
            visible=false,
            enabled=false,
            on_char=function(ch) return ch:match('[%l%u%d %-%_\'\"]') end,
        },
        widgets.Panel{
            frame={t=7, l=0, r=0, h=FILTER_HEIGHT},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                local panel_frame = self.subviews.list_panel.frame
                if self.subviews.filters:getOptionValue() then
                    panel_frame.t = 7 + FILTER_HEIGHT + 1
                else
                    panel_frame.t = 7
                end
            end,
            subviews={
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_slider_widgets(self, '1'),
                },
                widgets.Panel{
                    frame={t=0, l=0, w=38},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_slider_widgets(self, '2'),
                },
                widgets.Panel{
                    frame={b=0, l=40, r=0, h=2},
                    visible=function() return self.cur_page == 1 end,
                    subviews=common.get_advanced_filter_widgets(self, self.predicate_contexts[1]),
                },
                widgets.Panel{
                    frame={t=1, l=40, r=0},
                    visible=function() return self.cur_page == 2 end,
                    subviews=common.get_info_widgets(self, {trade.mer.buy_prices}, true, self.predicate_contexts[2]),
                },
                widgets.Panel{
                    frame={t=1, l=0, r=0, h=1},
                    visible=function() return #self.path > 0 end,
                    subviews={
                        widgets.Label{
                            frame={t=0, l=0},
                            text={
                                {text="< Back", pen=COLOR_LIGHTRED, key="CUSTOM_ESC", on_activate=function() self:go_back() end},
                                {gap=1, text=function() return table.concat(self.path, " > ") end}
                            },
                            on_click=function() self:go_back() end,
                        }
                    }
                },
            },
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=7, l=0, r=0, b=5},
            subviews={
                widgets.Label{
                    view_id='click_guide',
                    frame={t=0},
                    text='+-- SELECT ---+---- DRILL DOWN ----+',
                    text_pen=COLOR_LIGHTGREEN,
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_status',
                    frame={t=1, l=0, w=STATUS_COL_WIDTH},
                    options={
                        {label='X', value=sorting.sort_noop},
                        {label='X'..common.CH_DN, value=sorting.sort_by_status_desc},
                        {label='X'..common.CH_UP, value=sorting.sort_by_status_asc},
                    },
                    initial_option=sorting.sort_by_status_desc,
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_status'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_count',
                    frame={t=1, l=STATUS_COL_WIDTH+1, w=COUNT_COL_WIDTH},
                    options={
                        {label='Cnt', value=sorting.sort_noop},
                        {label='Cnt'..common.CH_DN, value=sorting.sort_by_count_desc},
                        {label='Cnt'..common.CH_UP, value=sorting.sort_by_count_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_count'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_value',
                    frame={t=1, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1, w=VALUE_COL_WIDTH},
                    options={
                        {label='Value', value=sorting.sort_noop},
                        {label='Value'..common.CH_DN, value=sorting.sort_by_value_desc},
                        {label='Value'..common.CH_UP, value=sorting.sort_by_value_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_value'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_class',
                    frame={t=1, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+1, w=class_col_width},
                    options={
                        {label='Class', value=sorting.sort_noop},
                        {label='Class'..common.CH_DN, value=sorting.sort_by_class_desc},
                        {label='Class'..common.CH_UP, value=sorting.sort_by_class_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('refresh_list', 'sort_class'),
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_subclass',
                    frame={t=1, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+1+class_col_width, w=subclass_col_width},
                    options={
                        {label='Subclass', value=sorting.sort_noop},
                        {label='Subclass'..common.CH_DN, value=sorting.sort_by_subclass_desc},
                        {label='Subclass'..common.CH_UP, value=sorting.sort_by_subclass_asc},
                    },
                    on_change=self:callback('on_sort_change', 'sort_subclass'),
                    enabled=function() return #self.path >= 1 end,
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_grouped',
                    frame={t=1, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+1+class_col_width+2+subclass_col_width+1, w=grouped_col_width},
                    options={
                        {label='Grouped', value=sorting.sort_noop},
                        {label='Grouped'..common.CH_DN, value=sorting.sort_by_grouped_desc},
                        {label='Grouped'..common.CH_UP, value=sorting.sort_by_grouped_asc},
                    },
                    on_change=self:callback('on_sort_change', 'sort_grouped'),
                    enabled=function() return #self.path >= 2 end,
                },
                widgets.CycleHotkeyLabel{
                    view_id='sort_name',
                    frame={t=1, l=STATUS_COL_WIDTH+1+COUNT_COL_WIDTH+1+VALUE_COL_WIDTH+1+class_col_width+2+subclass_col_width+2+grouped_col_width+2, r=1},
                    options={
                        {label='Item Description', value=sorting.sort_noop},
                        {label='Item Description'..common.CH_DN, value=sorting.sort_by_name_desc},
                        {label='Item Description'..common.CH_UP, value=sorting.sort_by_name_asc},
                    },
                    option_gap=0,
                    on_change=self:callback('on_sort_change', 'sort_name'),
                    enabled=function() return #self.path >= 3 end,
                },
                widgets.FilteredList{
                    view_id='list',
                    frame={l=0, t=2, r=0, b=0},
                    icon_width=2,
                    on_submit2=self:callback('toggle_range'),
                    on_select=self:callback('select_item'),
                },
            }
        },
        widgets.Divider{
            frame={b=4, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        widgets.Label{
            frame={b=2, l=0, r=0},
            text='Click X/Cnt/Value to mark/unmark for trade. Click Class/Subclass/Grouped/Item Description to drill down. ENTER to drill down, SPACE to select.',
        },
        widgets.HotkeyLabel{
            frame={l=0, b=0},
            label='Select all/none',
            key='CUSTOM_CTRL_N',
            on_activate=self:callback('toggle_visible'),
            auto_width=true,
        },
        widgets.Label{
            frame={b=3, l=0, r=0},
            text={
                'Total value of selected items: ',
                {text=function() return common.obfuscate_value(self:get_total_selected_value()) end, pen=COLOR_GREEN}
            },
        },
        widgets.Label{
            frame={r=1, b=0},
            text=version,
            auto_width=true,
        },
    }

    self.subviews.list.list.frame.t = 0
    self.subviews.list.edit = self.subviews.search_edit
    self.subviews.search_edit.on_change = function(text)
        self.subviews.list:onFilterChange(text)
        self:refresh_list()
    end

    self.search_active = false
    local list_widget = self.subviews.list.list
    local orig_onInput = list_widget.onInput
    list_widget.onInput = function(widget, keys)
        if not self.search_active and (keys.SEC_SELECT or keys._STRING == 32) then
            local idx = widget:getSelected()
            if not idx then return end
            local choices = self.subviews.list:getVisibleChoices()
            if choices and choices[idx] then
                self:toggle_item_base(choices[idx])
                return true
            end
        end

        if keys.SELECT then
            local idx = widget:getSelected()
            if not idx then return end
            local choices = self.subviews.list:getVisibleChoices()
            if choices and choices[idx] then
                self:toggle_item(idx, choices[idx], false)
                return true
            end
        end

        if not self.search_active and keys.STRING_A00 then
            return false
        end

        local was_click = keys._MOUSE_L
        local handled = orig_onInput(widget, keys)
        if was_click and handled then
            -- Get local mouse coords from the widget. If unavailable, let the
            -- original handler manage the event (likely a drag/scroll).
            local x, y = nil, nil
            if widget.getMousePos then x, y = widget:getMousePos() end
            
            
            -- Try fix scrollbar clicks being interpreted as drill downs
            local widget_w = nil
            if widget.frame and widget.frame.w then widget_w = widget.frame.w end
            if (not widget_w) and self.subviews.list and self.subviews.list.frame and self.subviews.list.frame.w then
                widget_w = self.subviews.list.frame.w
            end
            if (not widget_w) and self.frame and self.frame.w then widget_w = self.frame.w end

            local scrollbar_reserved = 3
            if widget_w and widget_w > 0 and x >= widget_w - scrollbar_reserved then
                return handled
            end

            local modifiers = dfhack.internal.getModifiers()
            if modifiers.shift then
                return handled
            end

            local idx = widget:getSelected()
            if not idx then return end
            local choices = self.subviews.list:getVisibleChoices()
            if choices and choices[idx] then
                self:toggle_item(idx, choices[idx], true)
            end
        end
        return handled
    end

    self:reset_cache()
    during_init = false
end

function LuaTrade:activate_search()
    self.search_active = true
    self.subviews.search_edit.visible = true
    self.subviews.search_edit.enabled = true
    self.subviews.search_edit:setFocus(true)
    return true
end

function LuaTrade:deactivate_search()
    self.search_active = false
    self.subviews.search_edit:setFocus(false)
    self:setFocus(true)
end

function LuaTrade:onInput(keys)
    if self.search_active then
        if keys.LEAVESCREEN or keys.CUSTOM_ESC or keys.CUSTOM_ALT_S then
            self:deactivate_search()
            return true
        end
        if self.subviews.search_edit:onInput(keys) then
            return true
        end
        if keys._STRING or keys.STRING_A00 or keys.BACKSPACE or keys.SELECT or
            keys.CURSOR_LEFT or keys.CURSOR_RIGHT or keys.CURSOR_UP or keys.CURSOR_DOWN
        then
            return true
        end
    end
    if keys.CUSTOM_ALT_S then
        return self:activate_search()
    end
    return LuaTrade.super.onInput(self, keys)
end

function LuaTrade:onBack()
    if #self.path > 0 then
        self:go_back()
        return true
    end
    return false
end

function LuaTrade:go_back()
    if #self.path > 0 then
        table.remove(self.path)
        self.subviews.list.list.page_top = 0
        self:refresh_list()
    end
end

function LuaTrade:is_sort_fn_valid(sort_fn)
    -- Allow cycling between asc/desc of the current sort level
    local current_sort_fn = self.subviews.sort:getOptionValue()
    if sorting.get_sort_level(sort_fn) == sorting.get_sort_level(current_sort_fn) then
        return true
    end

    local path_len = #self.path
    if path_len >= 3 then return true end -- All sorts are valid at item level

    local sort_level = sorting.get_sort_level(sort_fn)

    if sort_level == 'name' then return path_len >= 3 end
    if sort_level == 'grouped' then return path_len >= 2 end
    if sort_level == 'subclass' then return path_len >= 1 end
    if sort_level == 'class' then return path_len >= 0 end

    return true -- Status, Count, Value are always valid
end

function LuaTrade:on_sort_change(sort_widget_name, sort_fn)
    sort_widget_name = sort_widget_name or 'sort'
    local sort_widget = self.subviews[sort_widget_name]
    sort_fn = sort_fn or sort_widget:getOptionValue()

    if sort_fn == sorting.sort_noop then
        sort_widget:cycle()
        return
    end

    if not self:is_sort_fn_valid(sort_fn) then
        if sort_widget_name ~= 'sort' then
            sort_widget:cycle(-1) -- revert cycle
            return
        end
        -- If we used the main sort hotkey, cycle until we find a valid one.
        local initial_sort_fn = sort_fn
        repeat
            self.subviews.sort:cycle(1, true) -- cycle without triggering on_change
            sort_fn = self.subviews.sort:getOptionValue()
            -- break if we've looped all the way around to prevent infinite loops
        until self:is_sort_fn_valid(sort_fn) or sort_fn == initial_sort_fn
    end
    self:refresh_list(sort_widget_name, sort_fn)
end

function LuaTrade:refresh_list(sort_widget, sort_fn)
    if self._refreshing then return end
    self._refreshing = true
    sort_fn = sort_fn or self.subviews.sort:getOptionValue()

    -- Update ALL sort-related widgets to match the current active sort function
    local sort_widgets = {
        'sort', 'sort_status', 'sort_value', 'sort_count', 
        'sort_name', 'sort_class', 'sort_subclass', 'sort_grouped'
    }

    for _, widget_name in ipairs(sort_widgets) do
        if self.subviews[widget_name] then
            self.subviews[widget_name]:setOption(sort_fn)
        end
    end

    local list = self.subviews.list
    local saved_filter = list:getFilter()
    local saved_top = list.list.page_top
    local choices = self:get_choices()

    list:setFilter('')
    list:setChoices(choices, list:getSelected())
    list:setFilter(saved_filter)
    list.list:on_scrollbar(math.max(0, saved_top - list.list.page_top))

    local auto_resize = self.subviews.auto_resize_cols:getOptionValue()
    local class_w, subclass_w, grouped_w, description_w
    if auto_resize then
        local visible = list:getVisibleChoices() or {}
        class_w, subclass_w, grouped_w, description_w = self:compute_column_widths(visible)
    else
        class_w, subclass_w, grouped_w, description_w = DEFAULT_CLASS_COL_WIDTH, DEFAULT_SUBCLASS_COL_WIDTH, DEFAULT_GROUPED_COL_WIDTH, DEFAULT_DESCRIPTION_COL_WIDTH
    end

    if self:set_column_widths(class_w, subclass_w, grouped_w, description_w, not auto_resize) then
        self:update_choice_texts(choices)
        list:setFilter('')
        list:setChoices(choices, list:getSelected())
        list:setFilter(saved_filter)
        list.list:on_scrollbar(math.max(0, saved_top - list.list.page_top))
    end

    if self.search_active then
        self.subviews.search_edit:setFocus(true)
    end
    self._refreshing = false
end

function LuaTrade:get_total_selected_value()
    local list_idx = self.cur_page - 1
    local goodflags = trade.goodflag[list_idx]
    local goods = trade.good[list_idx]
    if not goodflags or not goods then return 0 end
    
    local total = 0
    for i, item in ipairs(goods) do
        if goodflags[i].selected then
            total = total + common.get_perceived_value(item, trade.mer)
        end
    end
    return total
end

local function make_choice_text(value, count, desc, class, subclass, grouped)
    return {
        {width=STATUS_COL_WIDTH-3, text=''},
        {gap=1, width=COUNT_COL_WIDTH, rjustify=true, text=count},
        {gap=1, width=VALUE_COL_WIDTH, rjustify=true, text=common.obfuscate_value(value)},
        {gap=2, width=class_col_width, text=class, pen=COLOR_CYAN},   
        {gap=2, width=subclass_col_width, text=subclass, pen=COLOR_GREY}, 
        {gap=2, width=grouped_col_width, text=grouped, pen=COLOR_CYAN},
        {gap=2, width=description_col_width, text=desc, pen=COLOR_GREY},
    } 
end

function LuaTrade:cache_choices(list_idx, trade_bins)
    if self.choices[list_idx][trade_bins] then return self.choices[list_idx][trade_bins] end

    local goodflags = trade.goodflag[list_idx]
    local trade_bins_choices, notrade_bins_choices = {}, {}
    local parent_data
    for item_idx, item in ipairs(trade.good[list_idx]) do
        local goodflag = goodflags[item_idx]
        if not goodflag.contained then
            parent_data = nil
        end
        local is_banned, is_risky = common.scan_banned(item, self.risky_items)
        local is_requested = dfhack.items.isRequestedTradeGood(item, trade.mer)
        local wear_level = item:getWear()
        local desc = dfhack.items.getReadableDescription(item)
        local is_ethical = ethics.is_ethical_product(item, self.animal_ethics, self.wood_ethics)
        local class, subclass = classifier.classify_item(item)
        local group = get_generic_description(item) or "Other"
        local data = {
            desc=desc,
            value=common.get_perceived_value(item, trade.mer),
            list_idx=list_idx,
            item=item,
            item_idx=item_idx,
            class=class or 'Other',
            subclass=subclass or 'Other',
            grouped=group,
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=wear_level,
            has_foreign=item.flags.foreign,
            has_banned=is_banned,
            has_risky=is_risky,
            has_requested=is_requested,
            has_ethical=is_ethical,
            ethical_mixed=false,
        }
        if parent_data then
            data.update_container_fn = function(from, to)
                -- TODO
            end
            parent_data.has_banned = parent_data.has_banned or is_banned
            parent_data.has_risky = parent_data.has_risky or is_risky
            parent_data.has_requested = parent_data.has_requested or is_requested
            parent_data.ethical_mixed = parent_data.ethical_mixed or (parent_data.has_ethical ~= is_ethical)
            parent_data.has_ethical = parent_data.has_ethical or is_ethical
        end
        local is_container = df.item_binst:is_instance(item)
        local search_str = ('%s %s %s %s'):format(desc, data.class, data.subclass, data.grouped)
        -- store normalized search key on the data so searching can operate across
        -- all items, even when aggregated/grouped
        if (trade_bins and is_container) or item:isFoodStorage() then
            data.search_key = common.make_container_search_key(item, search_str)
        else
            data.search_key = common.make_search_key(search_str)
        end
        local choice = {
            search_key = data.search_key,
            icon = curry(sorting.get_entry_icon, data),
            data = data,
            text = make_choice_text(data.value, data.count or 1, desc, data.class, data.subclass, data.grouped),
        }
        if not data.update_container_fn then
            table.insert(trade_bins_choices, choice)
        end
        if data.update_container_fn or not is_container then
            table.insert(notrade_bins_choices, choice)
        end
        if is_container then parent_data = data end
    end

    self.choices[list_idx][true] = trade_bins_choices
    self.choices[list_idx][false] = notrade_bins_choices
    return self:cache_choices(list_idx, trade_bins)
end


function LuaTrade:get_flat_choices()
    local raw_choices = self:cache_choices(self.cur_page-1, self.subviews.trade_bins:getOptionValue())
    local provenance = self.subviews.provenance:getOptionValue()
    local banned = self.cur_page == 1 and 'ignore' or self.subviews.banned:getOptionValue()
    local only_agreement = self.cur_page == 2 and self.subviews.only_agreement:getOptionValue() or false
    local ethical = self.cur_page == 1 and 'show' or self.subviews.ethical:getOptionValue()
    local strict_ethical_bins = self.subviews.strict_ethical_bins:getOptionValue()
    local min_condition = self.subviews['min_condition'..self.cur_page]:getOptionValue()
    local max_condition = self.subviews['max_condition'..self.cur_page]:getOptionValue()
    local min_quality = self.subviews['min_quality'..self.cur_page]:getOptionValue()
    local max_quality = self.subviews['max_quality'..self.cur_page]:getOptionValue()
    local min_value = self.subviews['min_value'..self.cur_page]:getOptionValue().value
    local max_value = self.subviews['max_value'..self.cur_page]:getOptionValue().value
    local choices = {}
    for _,choice in ipairs(raw_choices) do
        local data = choice.data
        if ethical ~= 'show' then
            if strict_ethical_bins and data.ethical_mixed then goto continue end
            if ethical == 'hide' and data.has_ethical then goto continue end
            if ethical == 'only' and not data.has_ethical then goto continue end
        end
        if provenance ~= 'all' then
            if (provenance == 'local' and data.has_foreign) or
                (provenance == 'foreign' and not data.has_foreign)
            then
                goto continue
            end
        end
        if min_condition < data.wear then goto continue end
        if max_condition > data.wear then goto continue end
        if min_quality > data.quality then goto continue end
        if max_quality < data.quality then goto continue end
        if min_value > data.value then goto continue end
        if max_value < data.value then goto continue end
        if only_agreement and not data.has_requested then goto continue end
        if banned ~= 'ignore' then
            if data.has_banned or (banned ~= 'banned_only' and data.has_risky) then
                goto continue
            end
        end
        if not predicates.pass_predicates(self.predicate_contexts[self.cur_page], data.item) then
            goto continue
        end
        table.insert(choices, choice)
        ::continue::
    end
    table.sort(choices, self.subviews.sort:getOptionValue())
    return choices
end

function LuaTrade:aggregate_choices(flat_choices, filter_str)
    if #self.path == 3 then
        -- Leaf level: Items
        local filtered = {}
        for _, choice in ipairs(flat_choices) do
            local d = choice.data
            if d.class == self.path[1] and d.subclass == self.path[2] and d.grouped == self.path[3] then
                table.insert(filtered, choice)
            end
        end
        return filtered
    end

    local groups = {}
    local order = {}
    for _, choice in ipairs(flat_choices) do
        local d = choice.data

        -- NEW: Only include items in the totals if they match the search filter
        if filter_str and filter_str ~= '' and not choice.search_key:lower():find(filter_str, 1, true) then
            goto continue
        end

        local match = true
        for i, p in ipairs(self.path) do
            if i == 1 and d.class ~= p then match = false break end
            if i == 2 and d.subclass ~= p then match = false break end
        end
        
        if match then
            local key
            local class_val, subclass_val, grouped_val = "", "", ""
            
            if #self.path == 0 then 
                key = d.class 
                class_val = key
            elseif #self.path == 1 then 
                key = d.subclass 
                class_val = self.path[1]
                subclass_val = key
            elseif #self.path == 2 then 
                key = d.grouped 
                class_val = self.path[1]
                subclass_val = self.path[2]
                grouped_val = key
            end
            
            if not groups[key] then
                groups[key] = {
                    key = key,
                    count = 0,
                    value = 0,
                    selected_count = 0,
                    items = {},
                    class = class_val,
                    subclass = subclass_val,
                    grouped = grouped_val
                }
                table.insert(order, key)
            end
            local g = groups[key]
            g.count = g.count + 1
            g.value = g.value + d.value
            if trade.goodflag[d.list_idx][d.item_idx].selected then
                g.selected_count = g.selected_count + 1
            end
            table.insert(g.items, choice)
        end
        ::continue::
    end
    
    local choices = {}
    -- Preserve the order groups were first encountered in the already-sorted
    -- flat_choices so aggregation doesn't disrupt the active sort order.
    for _, key in ipairs(order) do
        local g = groups[key]
        local choice = {
            data = {
                desc = key,
                value = g.value,
                quantity = g.count,
                is_group = true,
                items = g.items,
                class = g.class,
                subclass = g.subclass,
                grouped = g.grouped
            },
        }
        -- Build a combined search_key from all child items plus the group labels
        local combined = {key, g.class, g.subclass, g.grouped}
        for _,c in ipairs(g.items) do
            if c.search_key then table.insert(combined, c.search_key) end
        end
        choice.search_key = common.make_search_key(table.concat(combined, ' '))
        choice.icon = function() 
            local sel = 0
            for _, c in ipairs(g.items) do
                if trade.goodflag[c.data.list_idx][c.data.item_idx].selected then
                    sel = sel + 1
                end
            end
            if sel == g.count then return common.ALL_PEN end
            if sel > 0 then return common.SOME_PEN end
            return nil
        end
        choice.text = make_choice_text(g.value, g.count, '', g.class, g.subclass, g.grouped)
        table.insert(choices, choice)
    end
    
    -- If the user selected sorting by an aggregated field (value or count),
    -- sort the groups by the aggregated metric rather than by the underlying
    -- item-level ordering.
    local sort_fn = nil
    if self.subviews and self.subviews.sort then sort_fn = self.subviews.sort:getOptionValue() end
    if sort_fn == sorting.sort_by_value_desc then
        table.sort(choices, sorting.sort_by_value_desc)
    elseif sort_fn == sorting.sort_by_value_asc then
        table.sort(choices, sorting.sort_by_value_asc)
    elseif sort_fn == sorting.sort_by_count_desc then
        table.sort(choices, sorting.sort_by_count_desc)
    elseif sort_fn == sorting.sort_by_count_asc then
        table.sort(choices, sorting.sort_by_count_asc)
    end

    return choices
end

function LuaTrade:get_choices()
    local flat = self:get_flat_choices()
    -- Capture the search text from the edit field
    local filter_str = self.subviews.search_edit.text:lower()
    return self:aggregate_choices(flat, filter_str)
end

local function toggle_item_base(choice, target_value)
    local goodflag = trade.goodflag[choice.data.list_idx][choice.data.item_idx]
    if target_value == nil then
        target_value = not goodflag.selected
    end
    local prev_value = goodflag.selected
    goodflag.selected = target_value
    if choice.data.update_container_fn then
        choice.data.update_container_fn(prev_value, target_value)
    end
    return target_value
end

function LuaTrade:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function LuaTrade:toggle_group(choice, target_value)
    if target_value == nil then
        local target = true
        for _, item_choice in ipairs(choice.data.items) do
            local goodflag = trade.goodflag[item_choice.data.list_idx][item_choice.data.item_idx]
            if not goodflag.selected then
                target = true
                goto found
            end
        end
        target = false
        ::found::
        target_value = target
    end
    
    for _, item_choice in ipairs(choice.data.items) do
        toggle_item_base(item_choice, target_value)
    end
end


function LuaTrade:toggle_item(idx, choice, is_click)
    local modifiers = dfhack.internal.getModifiers()
    local list_widget = self.subviews.list.list
    local selection_width = STATUS_COL_WIDTH + 1 + COUNT_COL_WIDTH + 1 + VALUE_COL_WIDTH + 1
    
    if choice.data.is_group then
        -- if ctrl is pressed, toggle the group regardless of click position
        local drill_down = true
        if is_click then
            local x, y = list_widget:getMousePos()
            if x and x < selection_width then
                drill_down = false
            end
        end
        
        local drill_down_start = selection_width + 2
        if x and x < drill_down_start then
            -- in the dead zone, do nothing
        elseif not drill_down or modifiers.ctrl then
             self:toggle_group(choice)
        else
            table.insert(self.path, choice.data.desc)
            self.subviews.list.list.page_top = 0
            self:refresh_list()
        end
    else
        toggle_item_base(choice)
    end
end


function LuaTrade:toggle_range(idx, choice)
    local list_idx = self.subviews.list.list:getSelected()
    if not self.prev_list_idx or self.prev_list_idx == list_idx then
        self:toggle_item_base(choice)
        self.prev_list_idx = list_idx
        return
    end
    local choices = self.subviews.list:getVisibleChoices()
    local function choice_is_fully_selected(current_choice)
        if current_choice.data.is_group then
            for _, item_choice in ipairs(current_choice.data.items) do
                local goodflag = trade.goodflag[item_choice.data.list_idx][item_choice.data.item_idx]
                if not goodflag.selected then return false end
            end
            return true
        end
        local goodflag = trade.goodflag[current_choice.data.list_idx][current_choice.data.item_idx]
        return goodflag.selected
    end

    local all_selected = true
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        local current_choice = choices[i]
        if current_choice and not choice_is_fully_selected(current_choice) then
            all_selected = false
            break
        end
    end

    local target_value = not all_selected
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        local current_choice = choices[i]
        if current_choice then
            self:toggle_item_base(current_choice, target_value)
        end
    end
    self.prev_list_idx = list_idx
end


function LuaTrade:toggle_group(choice, target_value, dry_run)
    if target_value == nil then
        local should_select = false
        for _, item_choice in ipairs(choice.data.items) do
            local goodflag = trade.goodflag[item_choice.data.list_idx][item_choice.data.item_idx]
            if not goodflag.selected then
                should_select = true
                break
            end
        end
        target_value = should_select
    end

    if dry_run then return target_value end

    for _, item_choice in ipairs(choice.data.items) do
        toggle_item_base(item_choice, target_value)
    end
end

function LuaTrade:toggle_item_base(choice, target_value, dry_run)
    if choice.data.is_group then
        return self:toggle_group(choice, target_value, dry_run)
    else
        local goodflag = trade.goodflag[choice.data.list_idx][choice.data.item_idx]
        if target_value == nil then
            target_value = not goodflag.selected
        end
        if dry_run then return target_value end
        local prev_value = goodflag.selected
        goodflag.selected = target_value
        if choice.data.update_container_fn then
            choice.data.update_container_fn(prev_value, target_value)
        end
        return target_value
    end
end

function LuaTrade:toggle_visible()
    local all_items = {}
    local function collect_items(choices)
        for _, choice in ipairs(choices) do
            if choice.data.is_group then
                collect_items(choice.data.items)
            else
                table.insert(all_items, choice)
            end
        end
    end

    collect_items(self.subviews.list:getVisibleChoices())

    local target_value = false
    for _, item_choice in ipairs(all_items) do
        if not trade.goodflag[item_choice.data.list_idx][item_choice.data.item_idx].selected then
            target_value = true
            break
        end
    end

    for _, item_choice in ipairs(all_items) do
        toggle_item_base(item_choice, target_value)
    end
end

function LuaTrade:reset_cache()
    self.choices = {[0]={}, [1]={}}
    self:refresh_list()
end

function LuaTrade:update_column_layout()
    local base = STATUS_COL_WIDTH + 1 + COUNT_COL_WIDTH + 1 + VALUE_COL_WIDTH + 1
    local class_l = base
    local subclass_l = class_l + class_col_width + 1
    local grouped_l = subclass_l + subclass_col_width + 2
    local name_l = grouped_l + grouped_col_width + 3

    local sv = self.subviews.list_panel.subviews
    sv.sort_class.frame.w = class_col_width
    sv.sort_subclass.frame.w = subclass_col_width
    sv.sort_grouped.frame.w = grouped_col_width
    sv.sort_name.frame.w = description_col_width

    sv.sort_class.frame.l = class_l
    sv.sort_subclass.frame.l = subclass_l
    sv.sort_grouped.frame.l = grouped_l
    sv.sort_name.frame.l = name_l
end

function LuaTrade:set_column_widths(class_w, subclass_w, grouped_w, description_w, use_default_minimums)
    if use_default_minimums == nil then
        use_default_minimums = true
    end

    local min_class = use_default_minimums and DEFAULT_CLASS_COL_WIDTH or MIN_CLASS_COL_WIDTH
    local min_subclass = use_default_minimums and DEFAULT_SUBCLASS_COL_WIDTH or MIN_SUBCLASS_COL_WIDTH
    local min_grouped = use_default_minimums and DEFAULT_GROUPED_COL_WIDTH or MIN_GROUPED_COL_WIDTH
    local min_description = use_default_minimums and DEFAULT_DESCRIPTION_COL_WIDTH or MIN_DESCRIPTION_COL_WIDTH

    class_w = math.max(min_class, class_w or DEFAULT_CLASS_COL_WIDTH)
    subclass_w = math.max(min_subclass, subclass_w or DEFAULT_SUBCLASS_COL_WIDTH)
    grouped_w = math.max(min_grouped, grouped_w or DEFAULT_GROUPED_COL_WIDTH)
    
    -- Calculate how much width we've used for the metadata columns
    local used_width = STATUS_COL_WIDTH + 1 + COUNT_COL_WIDTH + 1 + VALUE_COL_WIDTH + 1 
                       + class_w + 2 + subclass_w + 2 + grouped_w + 2
    
    -- The description should take the remaining space. 
    -- We subtract a small buffer (4-5) for scrollbars and margins.
    local winrect = self.frame
    local available_w = winrect.w - used_width - 5
    description_w = math.max(min_description, available_w)

    if class_w == class_col_width and subclass_w == subclass_col_width and 
       grouped_w == grouped_col_width and description_w == description_col_width then
        return false
    end

    class_col_width = class_w
    subclass_col_width = subclass_w+1
    grouped_col_width = grouped_w+1
    description_col_width = description_w + 5
    
    self:update_column_layout()
    if not during_init then
       self:updateLayout()
    end
    return true
end

function LuaTrade:compute_column_widths(choices)
    local max_class = #('Class')
    local max_subclass = #('Subclass')
    local max_grouped = #('Grouped')
    
    for _, choice in ipairs(choices or {}) do
        local d = choice.data or {}
        -- Only measure if the fields exist to avoid nil errors
        if d.class then max_class = math.max(max_class, #tostring(d.class)) end
        if d.subclass then max_subclass = math.max(max_subclass, #tostring(d.subclass)) end
        if d.grouped then max_grouped = math.max(max_grouped, #tostring(d.grouped)) end
    end
    
    -- We no longer return a fixed 99 for description; 
    -- set_column_widths will handle the "remaining space" logic.
    return max_class, max_subclass, max_grouped, DEFAULT_DESCRIPTION_COL_WIDTH
end

function LuaTrade:update_choice_texts(choices)
    for _, choice in ipairs(choices or {}) do
        local d = choice.data or {}
        local desc = d.is_group and '' or (d.desc or '')
        local count = d.count or d.quantity or 1
        choice.text = make_choice_text(d.value or 0, count, desc, d.class or '', d.subclass or '', d.grouped or '')
    end
end

-- THIS FUNCTION NEVER GETS CALLED
function LuaTrade:resize_columns_for_visible_list()
    local list = self.subviews.list
    local visible = list:getVisibleChoices() or {}
    local class_w, subclass_w, grouped_w = self:compute_column_widths(visible)
    if self:set_column_widths(class_w, subclass_w, grouped_w, nil, false) then
        self:update_choice_texts(visible)
    end
end

-- -------------------
-- PivotTradeScreen
--

trade_view = trade_view or nil

PivotTradeScreen = defclass(PivotTradeScreen, gui.ZScreen)
PivotTradeScreen.ATTRS {
    focus_path='pivot_trade/trade',
}

function PivotTradeScreen:init()
    self.trade_window = LuaTrade{}
    self:addviews{self.trade_window}
end

function PivotTradeScreen:onInput(keys)
    if self.reset_pending then return false end
    if (keys.LEAVESCREEN or keys._MOUSE_R) and self.trade_window:onBack() then
        return true
    end

    local handled = PivotTradeScreen.super.onInput(self, keys)
    if keys._MOUSE_L and not self.trade_window:getMouseFramePos() then
        -- "trade" or "offer" buttons may have been clicked and we need to reset the cache
        self.reset_pending = true
    end
    return handled
end

function PivotTradeScreen:onRenderFrame()
    if not df.global.game.main_interface.trade.open and not dfhack.gui.getCurFocus():find('Stocks') then
        if trade_view then trade_view:dismiss() end
    elseif self.reset_pending and
        (dfhack.gui.matchFocusString('dfhack/lua/pivot_trade/trade') or
         dfhack.gui.matchFocusString('dwarfmode/Trade/Default') or
         dfhack.gui.matchFocusString('dwarfmode/Stocks'))
    then
        self.reset_pending = nil
        self.trade_window:reset_cache()
    end
end

function PivotTradeScreen:onDismiss()
    trade_view = nil
end

EthicsScreen = ethics.EthicsScreen
TradeEthicsWarningOverlay = ethics.TradeEthicsWarningOverlay

PivotTradeOverlay = tradeoverlay.TradeOverlay

-- -------------------
-- PivotTradeBannerOverlay
--

PivotTradeBannerOverlay = defclass(PivotTradeBannerOverlay, overlay.OverlayWidget)
PivotTradeBannerOverlay.ATTRS{
    desc='Adds link to the trade screen to launch the DFHack trade UI.',
    default_pos={x=-31,y=-5},
    default_enabled=true,
    viewscreens={'dwarfmode/Trade/Default', 'dwarfmode/Stocks', 'dfhack/lua/caravan/trade'},
    frame={w=25, h=1},
    frame_background=gui.CLEAR_PEN,
}

function PivotTradeBannerOverlay:init()
    local function get_label()
        local focus = dfhack.gui.getCurFocus()
        if focus and focus:find('Stocks') then
            return 'Pivot Stocks UI'
        end
        return 'Pivot trade UI'
    end

    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            -- label=get_label(),
            label='Pivot trade UI',
            key='CUSTOM_CTRL_P',
            enabled=true,
            -- enabled=function()
            --     local focus = dfhack.gui.getCurFocus()
            --     if focus and focus:find('Stocks') then return true end
            --     return trade.stillunloading == 0 and trade.havetalker == 1
            -- end,
            on_activate=function() trade_view = trade_view and trade_view:raise() or PivotTradeScreen{}:show() end,
        },
    }
end

function PivotTradeBannerOverlay:onInput(keys)
    if PivotTradeBannerOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if trade_view then
            trade_view:dismiss()
        end
    end
end

OVERLAY_WIDGETS = {
    banner = PivotTradeBannerOverlay,
    trade_overlay = PivotTradeOverlay,
    ethics_warning = TradeEthicsWarningOverlay,
}

if not dfhack_flags or not dfhack_flags.module then
    local focus = dfhack.gui.getCurFocus()
    if trade.open or (focus and focus:find('Stocks')) then
        trade_view = trade_view and trade_view:raise() or PivotTradeScreen{}:show()
    else
        print('The trade screen or stocks screen must be open to use this UI.')
    end
end
