--@ module = true

local common = reqscript('internal/pivot_trade/common')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local pivot_common = reqscript('internal/pivot_trade/common')
local gui = require('gui')
local widgets = require('gui.widgets')

local QTY_COL_WIDTH = 6
local VALUE_COL_WIDTH = 9

local DEFAULT_CLASS_COL_WIDTH = 20
local DEFAULT_SUBCLASS_COL_WIDTH = 15
local DEFAULT_GROUPED_COL_WIDTH = 20

local MIN_CLASS_COL_WIDTH = #('Class')
local MIN_SUBCLASS_COL_WIDTH = #('Subclass')
local MIN_GROUPED_COL_WIDTH = #('Grouped')

local class_col_width = DEFAULT_CLASS_COL_WIDTH
local subclass_col_width = DEFAULT_SUBCLASS_COL_WIDTH
local grouped_col_width = DEFAULT_GROUPED_COL_WIDTH

local TOTALS_W = 26
local MAX_COL_WIDTH = 60

local MIN_W, MIN_H = 78, 30

local MARGIN_L, MARGIN_R, MARGIN_T, MARGIN_B = 16, 37, 7, 4

local FILTER_COL_W = 31
local FILTER_LABEL_W = 21

local FILTER_OPTIONS = {
    {label='Include', value='include', pen=COLOR_GREEN},
    {label='Only',    value='only',    pen=COLOR_YELLOW},
    {label='Exclude', value='exclude', pen=COLOR_LIGHTRED},
}

local uniform_assigned = {}

function is_unrevealed(item)
    local x, y, z = dfhack.items.getPosition(item)
    if not x then return false end
    return not dfhack.maps.isTileVisible(x, y, z)
end

local DEFAULT_STATUS_COLUMNS = {
    {id='noflags',         label='No status'},
    {id='forbid',          label='Forbidden (F)',         letter='F', pen=COLOR_RED,          test=function(i) return i.flags.forbid end},
    {id='dump',            label='Dump (D)',              letter='D', pen=COLOR_LIGHTMAGENTA, test=function(i) return i.flags.dump end},
    {id='melt',            label='Melt (M)',              letter='M', pen=COLOR_LIGHTBLUE,    test=function(i) return i.flags.melt end},
    {id='trade',           label='Marked for Trade (T)',  letter='T', pen=COLOR_LIGHTGREEN,   test=function(i) return is_trade_marked(i) end},
    {id='hidden',          label='Hidden (H)',            letter='H', pen=COLOR_GREY,         test=function(i) return i.flags.hidden end},
    {id='owned',           label='Owned (O)',             letter='O', pen=COLOR_GREEN,        test=function(i) return i.flags.owned end},
    {id='uniform',         label='In Uniform (U)',        letter='U', pen=COLOR_MAGENTA,      test=function(i) return uniform_assigned[i.id] or false end},
    {id='in_inventory',    label='In Inventory (I)',      letter='I', pen=COLOR_WHITE,        test=function(i) return i.flags.in_inventory end},
    {id='construction',    label='In Construction (C)',   letter='C', pen=COLOR_BROWN,        test=function(i) return i.flags.construction end},
    {id='in_building',     label='In Building (B)',       letter='B', pen=COLOR_YELLOW,       test=function(i) return i.flags.in_building end},
    {id='garbage_collect', label='Garbage (G)',           letter='G', pen=COLOR_DARKGREY,     test=function(i) return i.flags.garbage_collect end},
    {id='imported',        label='Imported (P)',          letter='P', pen=COLOR_BROWN,        test=function(i) return i.flags.foreign end},
    {id='trader',          label='Caravan Owned (N)',     letter='N', pen=COLOR_LIGHTGREEN,   test=function(i) return i.flags.trader end},
    {id='hostile',         label='Hostile Owned (L)',     letter='L', pen=COLOR_RED,          test=function(i) return i.flags.hostile end},
    {id='dead_dwarf',      label='Buried (Y)',            letter='Y', pen=COLOR_DARKGREY,     test=function(i) return i.flags.dead_dwarf end},
    {id='caged',           label='Caged (A)',             letter='A', pen=COLOR_CYAN,         test=function(i) return is_caged(i) end},
    {id='in_job',          label='In Job (J)',            letter='J', pen=COLOR_LIGHTCYAN,    test=function(i) return i.flags.in_job end},
    {id='on_fire',         label='On fire (E)',           letter='E', pen=COLOR_LIGHTRED,     test=function(i) return i.flags.on_fire end},
    {id='rotten',          label='Rotten (R)',            letter='R', pen=COLOR_BROWN,        test=function(i) return i.flags.rotten end},
    {id='spider_web',      label='Spider web (S)',        letter='S', pen=COLOR_GREY,         test=function(i) return i.flags.spider_web end},
    {id='artifact',        label='Artifact (Z)',          letter='Z', pen=COLOR_YELLOW,       test=function(i) return i.flags.artifact end},
}

function rebuild_uniform_assigned()
    local set = uniform_assigned
    for k in pairs(set) do set[k] = nil end
    for _, squad in ipairs(df.global.world.squads.all) do
        for _, pos in ipairs(squad.positions) do
            local eq = pos.equipment
            for _, id in ipairs(eq.assigned_items) do set[id] = true end
            for _, slot in ipairs(eq.uniform) do
                for _, spec in ipairs(slot) do
                    for _, id in ipairs(spec.assigned) do set[id] = true end
                end
            end
            for _, field in ipairs{'quiver', 'backpack', 'flask'} do
                local id = eq[field]
                if id ~= -1 then set[id] = true end
            end
        end
    end
end

function is_caged(item)
    local container = dfhack.items.getContainer(item)
    while container do
        if container:getType() == df.item_type.CAGE then return true end
        container = dfhack.items.getContainer(container)
    end
    return false
end

function is_trade_marked(item)
    local spec_ref = dfhack.items.getSpecificRef(item, df.specific_ref_type.JOB)
    return spec_ref and spec_ref.data.job and
        spec_ref.data.job.job_type == df.job_type.BringItemToDepot or false
end

local function get_default_frame()
    local sw, sh = dfhack.screen.getWindowSize()
    return {
        l=MARGIN_L, t=MARGIN_T,
        w=math.max(MIN_W, sw - MARGIN_L - MARGIN_R),
        h=math.max(MIN_H, sh - MARGIN_T - MARGIN_B),
    }
end

function resolve_frame(saved_frame)
    local frame = get_default_frame()
    if saved_frame then
        local sw, sh = dfhack.screen.getWindowSize()
        frame.w = math.max(MIN_W, math.min(saved_frame.w or frame.w, sw))
        frame.h = math.max(MIN_H, math.min(saved_frame.h or frame.h, sh))
        if saved_frame.l then frame.l = saved_frame.l end
        if saved_frame.t then frame.t = saved_frame.t end
        frame.l = math.max(0, math.min(frame.l, sw - frame.w))
        frame.t = math.max(0, math.min(frame.t, sh - frame.h))
    end
    return frame
end

local function hl_pen(color)
    return dfhack.pen.parse{fg=COLOR_BLACK, bg=color}
end

function path_contains(path_level, value)
    for _, v in ipairs(path_level) do
        if v == value then return true end
    end
    return false
end

function path_level_str(path_level)
    local s = table.concat(path_level, ', ')
    if #s > 60 then return 'Multiple' end
    return s
end
DrillDownList = defclass(DrillDownList, widgets.Window)
DrillDownList.ATTRS{
    frame_title='',
    resizable=true,
    resize_min={w=MIN_W, h=MIN_H},
    status_columns=DEFAULT_NIL,
    selection_width=DEFAULT_NIL,
    save_settings_id=DEFAULT_NIL,
    has_own_layout=false,
    filters_visible=true,
}

function DrillDownList:get_status_columns()
    return self.status_columns or DEFAULT_STATUS_COLUMNS
end

function DrillDownList:get_status_columns_with_letters()
    local result = {}
    for _, f in ipairs(self:get_status_columns()) do
        if f.letter then table.insert(result, f) end
    end
    return result
end

function DrillDownList:get_selection_width()
    if self.selection_width then return self.selection_width end
    local icons = 2
    local status = #self:get_status_columns_with_letters()
    return icons + status + 1 + QTY_COL_WIDTH + 2 + VALUE_COL_WIDTH
end

function DrillDownList:get_item_attrs(item)
    local attrs = {}
    local any = false
    for _, f in ipairs(self:get_status_columns()) do
        if f.test then
            local v = not not f.test(item)
            attrs[f.id] = v
            any = any or v
        end
    end
    attrs.noflags = not any
    return attrs
end

function DrillDownList:choice_has(choice, id)
    if choice.item_id then return choice.data.attrs[id] end
    return (choice.data['count_'..id] or 0) > 0
end

function DrillDownList:passes_flag_filters(choice, states, has_only)
    local matched_only = false
    for id, state in pairs(states) do
        if state ~= 'include' and self:choice_has(choice, id) then
            if state == 'exclude' then return false end
            matched_only = true
        end
    end
    return not (has_only and not matched_only)
end

function DrillDownList:get_action_items()
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
    return items
end

function DrillDownList:apply_status_changes(items)
    for _, item in ipairs(items) do
        if self.choice_by_id and self.choice_by_id[item.id] then
            local choice = self.choice_by_id[item.id]
            if choice then choice.data.attrs = self:get_item_attrs(item) end
        end
    end
    self:refresh_list()
end

local function value_of(c)
    return c.item_id and c.data.per_item_value or c.data.total_value
end

function DrillDownList:make_sort_columns()
    local cols = {
        name    = {key=function(c) return c.search_key end, is_string=true},
        qty     = {key=function(c) return c.item_id and 1 or c.data.quantity end},
        value   = {key=value_of},
        quality = {key=function(c) return c.data.quality end},
        wear    = {key=function(c) return c.data.wear end},
        class   = {key=function(c) return c.data.class or '' end, is_string=true},
        subclass= {key=function(c) return c.data.subclass or '' end, is_string=true},
        grouped = {key=function(c) return c.data.grouped or '' end, is_string=true},
    }
    for _, f in ipairs(self:get_status_columns_with_letters()) do
        local id = f.id
        cols[id] = {key=function(c)
            if c.item_id then return c.data.attrs[id] and 1 or 0 end
            return (c.data['count_'..id] or 0) > 0 and 1 or 0
        end}
    end
    return cols
end

local function make_comparator(sort_cols, col, dir)
    local key = sort_cols[col].key
    local ascending = dir == 'asc'
    return function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then
            if ascending then return ka < kb end
            return ka > kb
        end
        if a.data.desc ~= b.data.desc then return a.data.desc < b.data.desc end
        local va, vb = value_of(a), value_of(b)
        if va ~= vb then return va > vb end
        return (a.item_id or 0) < (b.item_id or 0)
    end
end

function DrillDownList:make_sort_options()
    local options = {}
    local col_order = {'name', 'qty', 'value', 'quality', 'wear', 'class', 'subclass', 'grouped'}
    for _, col in ipairs(col_order) do
        local sort_cols = self:get_sort_columns()
        if not sort_cols[col] then goto continue end
        local primary_dir = sort_cols[col].is_string and 'asc' or 'desc'
        local dirs = {primary_dir}
        if primary_dir == 'asc' then table.insert(dirs, 'desc') else table.insert(dirs, 'asc') end
        for _, dir in ipairs(dirs) do
            local spec = {col=col, dir=dir}
            local updown = dir == 'asc' and common.CH_UP or common.CH_DN
            table.insert(options, {label=col..updown, value=spec})
        end
        ::continue::
    end
    return options
end

function DrillDownList:sort_default_dir(col)
    local sort_cols = self:get_sort_columns()
    return sort_cols[col].is_string and 'asc' or 'desc'
end
function DrillDownList:make_status_tokens(has_count, group_size)
    local tokens = {}
    for _, f in ipairs(self:get_status_columns_with_letters()) do
        local count = has_count(f.id)
        if count == group_size and group_size > 0 then
            table.insert(tokens, {text=f.letter:upper(), pen=f.pen})
        elseif count > 0 then
            table.insert(tokens, {text=f.letter:lower(), pen=f.pen})
        else
            table.insert(tokens, {text=' '})
        end
    end
    return tokens
end

function DrillDownList:make_choice_text(status, value, qty, desc, class, subclass, grouped)
    local text = {}
    for _, t in ipairs(status) do table.insert(text, t) end
    table.insert(text, {gap=1, width=QTY_COL_WIDTH, rjustify=true, text=qty})
    table.insert(text, {gap=2, width=VALUE_COL_WIDTH, rjustify=true, text=dfhack.formatInt(value)})
    table.insert(text, {gap=2, width=class_col_width, text=class or '', pen=COLOR_CYAN})
    table.insert(text, {gap=2, width=subclass_col_width, text=subclass or '', pen=COLOR_GREY})
    table.insert(text, {gap=2, width=grouped_col_width, text=grouped or '', pen=COLOR_CYAN})
    table.insert(text, {gap=2, width=MAX_COL_WIDTH, text=desc or ''})
    return text
end

function DrillDownList:group_status_text(d)
    return self:make_choice_text(
        self:make_status_tokens(function(id) return d['count_'..id] or 0 end, d.quantity),
        d.total_value, d.quantity, '', d.class, d.subclass, d.grouped)
end

function DrillDownList:item_status_text(d, item_id)
    local attrs = d.attrs or d.items[item_id].attrs
    return self:make_choice_text(
        self:make_status_tokens(function(id) return attrs[id] and 1 or 0 end, 1),
        d.per_item_value, 1, d.desc, d.class, d.subclass, d.grouped)
end

function DrillDownList:build_header_tokens(sort)
    local text = {}
    for _, f in ipairs(self:get_status_columns_with_letters()) do
        local active = sort.col == f.id
        table.insert(text, {text=f.letter, pen=active and hl_pen(f.pen) or f.pen})
    end
    local function data_header(gap, w, col, label)
        local active = sort.col == col
        if active then label = label..(sort.dir == 'asc' and common.CH_UP or common.CH_DN) end
        local t = {gap=gap, text=label, pen=active and COLOR_WHITE or COLOR_GRAY}
        if w then t.width, t.rjustify = w, true end
        return t
    end
    table.insert(text, data_header(1, QTY_COL_WIDTH, 'qty', 'qty'))
    table.insert(text, data_header(2, VALUE_COL_WIDTH, 'value', 'value'))
    table.insert(text, data_header(2, class_col_width, 'class', 'class'))
    table.insert(text, data_header(2, subclass_col_width, 'subclass', 'subclass'))
    table.insert(text, data_header(2, grouped_col_width, 'grouped', 'grouped'))
    table.insert(text, data_header(2, MAX_COL_WIDTH, 'name', 'item'))
    return text
end

HeaderRow = defclass(nil, widgets.Label)
HeaderRow.ATTRS{on_sort=DEFAULT_NIL, drilldown=DEFAULT_NIL}
function HeaderRow:onInput(keys)
    if keys._MOUSE_L then
        local x = self:getMousePos()
        local col
        for _, r in ipairs(self.drilldown.header_ranges or {}) do
            if x and x >= r.x1 and x <= r.x2 then
                col = r.col
                break
            end
        end
        if col then
            self.on_sort(col)
            return true
        end
    end
    return HeaderRow.super.onInput(self, keys)
end
function DrillDownList:make_filter_widgets(filters, ncols, base_l, base_t)
    local views = {}
    local nrows = math.ceil(#filters / ncols)
    for i, f in ipairs(filters) do
        local col = math.floor((i-1) / nrows)
        local row = (i-1) % nrows
        local text = f.label..':'
        local label = (' '):rep(math.max(0, FILTER_LABEL_W - #text))..text
        table.insert(views, widgets.CycleHotkeyLabel{
            view_id='f_'..f.id,
            frame={t=base_t+row, l=base_l+col*FILTER_COL_W, w=FILTER_COL_W-1},
            label=label,
            label_width=FILTER_LABEL_W,
            text_pen=f.pen or COLOR_GRAY,
            option_gap=1,
            options=FILTER_OPTIONS,
            initial_option='include',
            on_change=function() self:refresh_list() end,
        })
    end
    return views
end

function DrillDownList:update_column_layout()
    local x = 0
    local ranges = {}
    for _, f in ipairs(self:get_status_columns_with_letters()) do
        table.insert(ranges, {x1=x, x2=x, col=f.id})
        x = x + 1
    end
    for _, dc in ipairs{{col='qty', gap=1, w=QTY_COL_WIDTH},
                        {col='value', gap=2, w=VALUE_COL_WIDTH},
                        {col='class', gap=2, w=class_col_width},
                        {col='subclass', gap=2, w=subclass_col_width},
                        {col='grouped', gap=2, w=grouped_col_width},
                        {col='name', gap=2, w=MAX_COL_WIDTH}} do
        local x1 = x; x = x1 + dc.gap + dc.w
        table.insert(ranges, {x1=x1, x2=x-1, col=dc.col})
    end
    self.header_ranges = ranges
end

function DrillDownList:set_column_widths(class_w, subclass_w, grouped_w)
    class_w = math.max(MIN_CLASS_COL_WIDTH, class_w or DEFAULT_CLASS_COL_WIDTH)
    subclass_w = math.max(MIN_SUBCLASS_COL_WIDTH, subclass_w or DEFAULT_SUBCLASS_COL_WIDTH)
    grouped_w = math.max(MIN_GROUPED_COL_WIDTH, grouped_w or DEFAULT_GROUPED_COL_WIDTH)
    if class_w == class_col_width and subclass_w == subclass_col_width and grouped_w == grouped_col_width then
        return false
    end
    class_col_width = class_w
    subclass_col_width = subclass_w
    grouped_col_width = grouped_w
    self:update_column_layout()
    if self.subviews and self.subviews.header then
        self.subviews.header:setText(self:build_header_tokens(self.current_sort))
    end
    self:updateLayout()
    return true
end

function DrillDownList:compute_column_widths(choices)
    local max_class = MIN_CLASS_COL_WIDTH
    local max_subclass = MIN_SUBCLASS_COL_WIDTH
    local max_grouped = MIN_GROUPED_COL_WIDTH
    for _, choice in ipairs(choices or {}) do
        local d = choice.data or {}
        if d.class then max_class = math.max(max_class, #tostring(d.class)) end
        if d.subclass then max_subclass = math.max(max_subclass, #tostring(d.subclass)) end
        if d.grouped then max_grouped = math.max(max_grouped, #tostring(d.grouped)) end
    end
    return max_class, max_subclass, max_grouped
end

function DrillDownList:update_choice_texts(choices)
    for _, choice in ipairs(choices or {}) do
        local d = choice.data or {}
        if d.is_group then
            choice.text = self:group_status_text(d)
        else
            choice.text = self:item_status_text(d, choice.item_id)
        end
    end
end
function DrillDownList:init()
    self._sort_columns = nil
    self.path = {}
    self.choices_cache = nil
    self.header_ranges = {}
    self:update_column_layout()
    if self.has_own_layout then
        self:on_init_complete()
        return
    end
    self.frame = get_default_frame()
    self:build_ui()
    self:on_init_complete()
end

function DrillDownList:before_build_ui()
    self.top_offset = 0
end

function DrillDownList:build_ui()
    self:before_build_ui()
    local T = self.top_offset or 0

    local FILTER_MAX_ROWS, SLIDER_ROWS = 14, 16
    local status_cols = self:get_status_columns()
    local has_filters = #status_cols > 0
    local width_cols = math.max(1, math.floor(((self.frame.w - 4) - 40) / FILTER_COL_W))
    local filter_cols = has_filters and math.min(width_cols, math.max(1, math.ceil(#status_cols / FILTER_MAX_ROWS))) or 0
    local filter_rows = has_filters and math.ceil(#status_cols / filter_cols) or 0
    local content_rows = math.max(SLIDER_ROWS, 2 + filter_rows)
    local filter_panel_h = content_rows + 2
    local list_t = 3 + filter_panel_h

    local filter_subviews = {
        widgets.Panel{frame={t=0, l=0, w=38}, subviews=common.get_slider_widgets(self)},
    }
    if has_filters then
        table.insert(filter_subviews, widgets.HotkeyLabel{
            frame={t=0, l=40}, auto_width=true,
            label='Reset filters', text_pen=COLOR_GREEN,
            on_activate=function() self:set_all_filters('include') end,
        })
        for _, w in ipairs(self:make_filter_widgets(status_cols, filter_cols, 40, 2)) do
            table.insert(filter_subviews, w)
        end
    end
    local extra_filter = self:make_extra_filter_widgets()
    for _, w in ipairs(extra_filter) do table.insert(filter_subviews, w) end

    local sort_options = self:make_sort_options()
    local sort_initial = nil
    for _, opt in ipairs(sort_options) do
        if opt.value and opt.value.col == 'name' and opt.value.dir == 'asc' then
            sort_initial = opt.value; break
        end
    end
    local header_widgets = self:make_header_widgets()

    local bottom_actions = self:make_bottom_actions()
    if self.save_settings_id then
        table.insert(bottom_actions, widgets.Label{view_id='status_msg', frame={t=2, r=0, w=16}, text='', visible=false})
    end

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort', frame={l=1, t=T+0, w=22},
            label='Sort:', key='CUSTOM_SHIFT_S',
            options=sort_options, initial_option=sort_initial,
            on_change=function(spec) self:set_current_sort(spec.col, spec.dir); self:refresh_list() end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='filters', frame={l=24, t=T+0, w=24},
            label='Show filters:', key='CUSTOM_SHIFT_F',
            options={{label='Yes', value=true, pen=COLOR_GREEN},{label='No', value=false}},
            initial_option=self.filters_visible, on_change=function() self:updateLayout() end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='auto_resize_cols', frame={l=49, t=T+0, w=24},
            label='Auto cols:', key='CUSTOM_SHIFT_R',
            options={{label='Yes', value=true, pen=COLOR_GREEN},{label='No', value=false}},
            initial_option=true, on_change=function() self:refresh_list() end,
        },
        widgets.HotkeyLabel{
            view_id='search_btn', frame={l=75, t=T+0}, auto_width=true,
            label='Search:', key='CUSTOM_ALT_S',
            on_activate=function() self:activate_search() end,
        },
        widgets.EditField{
            view_id='search', frame={l=75, t=T+0, r=1},
            label_text='', visible=false, enabled=false,
            on_char=function(ch) return ch:match('[%w -]') end,
        },
        widgets.Panel{
            frame={t=T+1, l=0, r=0, h=1},
            visible=function() return #self.path > 0 end,
            subviews={
                widgets.Label{
                    frame={t=0, l=2},
                    text={
                        {text="< Back", pen=COLOR_LIGHTRED, key="LEAVESCREEN",
                            on_activate=function() self:go_back() end},
                        {gap=1, text=function()
                            local parts = {}
                            for _, level in ipairs(self.path) do
                                table.insert(parts, path_level_str(level))
                            end
                            return table.concat(parts, ' > ')
                        end}
                    },
                    on_click=function() self:go_back() end,
                }
            }
        },
        widgets.Panel{
            view_id='filter_panel', frame={t=T+2, l=0, r=0, h=filter_panel_h},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                if not self.subviews or not self.subviews.list_panel then return end
                local pf = self.subviews.list_panel.frame
                pf.t = self.subviews.filters:getOptionValue() and filter_panel_h + 3 + T or 2 + T
            end,
            subviews=filter_subviews,
        },
        widgets.Panel{
            view_id='list_panel', frame={t=T+list_t, l=0, r=0, b=4},
            on_layout=function() self.subviews.list_panel.frame.t = T + list_t end,
            subviews={
                widgets.Label{
                    view_id='click_guide', frame={t=0},
                    text={{text=function()
                        local sw = self:get_selection_width()
                        local left = ('-'):rep(math.max(0, sw - 11))
                        local right = ('-'):rep(math.max(0, 67 - sw))
                        return '+--- SELECT '..left..'+--- DRILL DOWN '..right..'+'
                    end}},
                    text_pen=COLOR_LIGHTGREEN,
                },
                table.unpack(header_widgets),
                widgets.Label{
                    view_id='totals', frame={t=1, r=1, w=TOTALS_W}, text='',
                },
                widgets.FilteredList{
                    view_id='list', frame={l=0, t=3, r=0, b=0}, icon_width=2,
                    on_submit2=self:callback('toggle_range'),
                    on_select=self:callback('select_item'),
                },
            },
        },
        widgets.Divider{
            frame={b=3, h=1}, frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false, frame_style_r=false,
        },
        widgets.Panel{frame={l=1, r=1, b=0, h=3}, subviews=bottom_actions},
    }
    self.search_active = false
    self.subviews.list.list.frame.t = 0
    self.subviews.list.edit.visible = false
    self.subviews.list.edit = self.subviews.search
    local on_filter = self.subviews.list:callback('onFilterChange')
    self.subviews.search.on_change = function(text)
        on_filter(text)
        self:update_totals()
    end

    local list_widget = self.subviews.list.list
    local orig_onInput = list_widget.onInput
    list_widget.onInput = function(widget, keys)
        if not self.search_active and keys.SELECT then
            local idx = widget:getSelected()
            local choices = self.subviews.list:getVisibleChoices()
            local choice = choices and choices[idx]
            if choice then self:toggle_item(idx, choice, nil); return true end
        end
        if not self.search_active and keys._STRING == 32 then
            local idx = widget:getSelected()
            local choices = self.subviews.list:getVisibleChoices()
            local choice = choices and choices[idx]
            if choice then self:toggle_item_base(choice); self:refresh_list(); return true end
        end
        if not self.search_active and keys.STRING_A00 then return false end
        local was_click = keys._MOUSE_L
        local handled = orig_onInput(widget, keys)
        if was_click and handled then
            local x = widget:getMousePos()
            if x then
                local widget_w
                if widget.frame and widget.frame.w then widget_w = widget.frame.w end
                if (not widget_w) and self.subviews.list and self.subviews.list.frame and self.subviews.list.frame.w then
                    widget_w = self.subviews.list.frame.w
                end
                if (not widget_w) and self.frame and self.frame.w then widget_w = self.frame.w end
                local scrollbar_reserved = 3
                if widget_w and widget_w > 0 and x >= widget_w - scrollbar_reserved then
                    return handled
                end
                local idx = widget:getSelected()
                local choices = self.subviews.list:getVisibleChoices()
                local choice = choices and choices[idx]
                if choice then self:toggle_item(idx, choice, x) end
            end
        end
        return handled
    end

    self:set_current_sort('name', 'asc')
    self.subviews.list:setChoices(self:get_choices())
    self:update_totals()
end

function DrillDownList:make_header_widgets()
    return {HeaderRow{
        view_id='header', frame={t=1, l=2},
        text=self:build_header_tokens({col='name', dir='asc'}),
        text_pen=COLOR_GRAY, on_sort=self:callback('set_sort'), drilldown=self,
    }}
end

function DrillDownList:make_bottom_actions()
    return {}
end

function DrillDownList:make_extra_filter_widgets()
    return {}
end

function DrillDownList:get_flat_choices()
    return {}
end

function DrillDownList:activate_search()
    self.search_active = true
    self.subviews.search.visible = true
    self.subviews.search.enabled = true
    self.subviews.search:setFocus(true)
end

function DrillDownList:deactivate_search()
    self.search_active = false
    self.subviews.search:setFocus(false)
    self:setFocus(true)
end

function DrillDownList:onInput(keys)
    if (keys.LEAVESCREEN or keys._MOUSE_R) and #self.path > 0 then
        self:go_back(); return true
    end
    if keys.CUSTOM_CTRL_PGUP and #self.path > 0 then
        self:go_back(); return true
    end
    if keys.CUSTOM_CTRL_PGDN then
        self:drill_down_all_visible(); return true
    end
    if self.search_active then
        if keys.LEAVESCREEN or keys.CUSTOM_ALT_S then
            self:deactivate_search(); return true
        end
        if self.subviews.search:onInput(keys) then return true end
        if keys._STRING or keys.STRING_A00 or keys.BACKSPACE or keys.SELECT or
            keys.CURSOR_LEFT or keys.CURSOR_RIGHT or keys.CURSOR_UP or keys.CURSOR_DOWN then
            return true
        end
    end
    if keys.CUSTOM_ALT_S then
        self:activate_search(); return true
    end
    return DrillDownList.super.onInput(self, keys)
end

function DrillDownList:go_back()
    if #self.path > 0 then
        table.remove(self.path)
        self.subviews.list.list.page_top = 0
        self:refresh_list()
    end
end

function DrillDownList:drill_down_all_visible()
    if #self.path >= 3 then return end
    local keys = {}
    local seen = {}
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        if choice.data.is_group then
            local desc = choice.data.desc
            if desc and not seen[desc] then
                seen[desc] = true; table.insert(keys, desc)
            end
        end
    end
    if #keys == 0 then return end
    table.insert(self.path, keys)
    self.subviews.list.list.page_top = 0
    self:refresh_list()
end

function DrillDownList:get_sort_columns()
    if not self._sort_columns then self._sort_columns = self:make_sort_columns() end
    return self._sort_columns
end

function DrillDownList:aggregate_choices(flat_choices, filter_str)
    if #self.path == 3 then
        local filtered = {}
        for _, choice in ipairs(flat_choices) do
            local d = choice.data
            if path_contains(self.path[1], d.class) and path_contains(self.path[2], d.subclass) and path_contains(self.path[3], d.grouped) then
                choice.text = self:item_status_text(d, choice.item_id)
                table.insert(filtered, choice)
            end
        end
        return filtered
    end

    local groups = {}
    local order = {}
    for _, choice in ipairs(flat_choices) do
        local d = choice.data
        if filter_str and filter_str ~= '' and not choice.search_key:lower():find(filter_str, 1, true) then
            goto continue
        end
        local match = true
        for i, p in ipairs(self.path) do
            if i == 1 and not path_contains(p, d.class) then match = false; break end
            if i == 2 and not path_contains(p, d.subclass) then match = false; break end
        end
        if match then
            local key
            local class_val, subclass_val, grouped_val = '', '', ''
            if #self.path == 0 then key = d.class; class_val = key
            elseif #self.path == 1 then key = d.subclass; class_val = d.class; subclass_val = key
            elseif #self.path == 2 then key = d.grouped; class_val = d.class; subclass_val = d.subclass; grouped_val = key
            end
            if not groups[key] then
                groups[key] = {
                    key = key, count = 0, value = 0, selected_count = 0,
                    items = {}, class = class_val, subclass = subclass_val, grouped = grouped_val
                }
                for _, f in ipairs(self:get_status_columns()) do groups[key]['count_'..f.id] = 0 end
                table.insert(order, key)
            end
            local g = groups[key]
            g.count = g.count + 1; g.value = g.value + d.per_item_value
            if d.pending then g.selected_count = g.selected_count + 1 end
            for _, f in ipairs(self:get_status_columns()) do
                if d.attrs[f.id] then g['count_'..f.id] = g['count_'..f.id] + 1 end
            end
            table.insert(g.items, choice)
        end
        ::continue::
    end

    local choices = {}
    for _, key in ipairs(order) do
        local g = groups[key]
        local d = {
            desc = key, total_value = g.value, quantity = g.count,
            selected = g.selected_count, is_group = true, items = g.items,
            class = g.class, subclass = g.subclass, grouped = g.grouped
        }
        for _, f in ipairs(self:get_status_columns()) do d['count_'..f.id] = g['count_'..f.id] end

        local combined = {key, g.class, g.subclass, g.grouped}
        for _,c in ipairs(g.items) do
            if c.search_key then table.insert(combined, c.search_key) end
        end
        local choice = {
            data = d,
            search_key = pivot_common.make_search_key(table.concat(combined, ' ')),
            icon = function()
                if d.selected == d.quantity and d.quantity > 0 then return pivot_common.ALL_PEN end
                if d.selected > 0 then return pivot_common.SOME_PEN end
                return nil
            end,
            text = self:group_status_text(d),
        }
        table.insert(choices, choice)
    end
    return choices
end
function DrillDownList:get_choices()
    local flat_choices = self:get_flat_choices()
    local states, has_only = {}, false
    for _, f in ipairs(self:get_status_columns()) do
        local state = self.subviews['f_'..f.id] and self.subviews['f_'..f.id]:getOptionValue() or 'include'
        states[f.id] = state
        if state == 'only' then has_only = true end
    end
    local filtered = {}
    for _, choice in ipairs(flat_choices) do
        if not self:passes_flag_filters(choice, states, has_only) then goto continue end
        table.insert(filtered, choice)
        ::continue::
    end
    local filter_str = self.subviews.search.text:lower()
    local aggregated = self:aggregate_choices(filtered, filter_str)
    if self.current_sort and self.current_sort.fn then
        table.sort(aggregated, self.current_sort.fn)
    end
    return aggregated
end

function DrillDownList:refresh_list()
    local list = self.subviews.list
    local saved_filter = list:getFilter()
    list:setFilter('')
    local choices = self:get_choices()
    local auto_resize = self.subviews.auto_resize_cols:getOptionValue()
    if auto_resize then
        local cw, sw, gw = self:compute_column_widths(choices)
        if self:set_column_widths(cw, sw, gw) then self:update_choice_texts(choices) end
    end
    list:setChoices(choices, list:getSelected())
    list:setFilter(saved_filter)
    self:update_totals()
end

function DrillDownList:update_totals()
    local rows, qty = 0, 0
    for _, c in ipairs(self.subviews.list:getVisibleChoices()) do
        rows = rows + 1
        if c.data.is_group then qty = qty + c.data.quantity else qty = qty + 1 end
    end
    local items_str, qty_str = dfhack.formatInt(rows), dfhack.formatInt(qty)
    local cw = 7 + #items_str + 2 + 5 + #qty_str
    self.subviews.totals:setText{
        {text=(' '):rep(math.max(0, TOTALS_W - cw))},
        {text='Items: ', pen=COLOR_GRAY},
        {text=items_str, pen=COLOR_WHITE},
        {gap=2, text='Qty: ', pen=COLOR_GRAY},
        {text=qty_str, pen=COLOR_WHITE},
    }
end

function DrillDownList:set_current_sort(col, dir)
    local sort_cols = self:get_sort_columns()
    if not sort_cols[col] then col, dir = 'name', 'asc' end
    self.current_sort = {col=col, dir=dir, fn=make_comparator(sort_cols, col, dir)}
    if self.subviews.sort then
        for _, opt in ipairs(self.subviews.sort.options) do
            if opt.value and opt.value.col == col and opt.value.dir == dir then
                self.subviews.sort:setOption(opt.value); break
            end
        end
    end
    if self.subviews.header then
        self.subviews.header:setText(self:build_header_tokens(self.current_sort))
    end
end

function DrillDownList:set_sort(col)
    local cur = self.current_sort
    local dir = (cur and cur.col == col) and (cur.dir == 'asc' and 'desc' or 'asc')
        or self:sort_default_dir(col)
    self:set_current_sort(col, dir)
    self:refresh_list()
end

function DrillDownList:set_all_filters(state)
    for _, f in ipairs(self:get_status_columns()) do
        if self.subviews['f_'..f.id] then self.subviews['f_'..f.id]:setOption(state) end
    end
    self:refresh_list()
end

function DrillDownList:get_settings()
    local settings = {
        filters={}, sliders={},
        sort={col=self.current_sort.col, dir=self.current_sort.dir},
        frame={w=self.frame.w, h=self.frame.h, l=self.frame.l, t=self.frame.t},
    }
    for _, f in ipairs(self:get_status_columns()) do
        settings.filters[f.id] = self.subviews['f_'..f.id] and self.subviews['f_'..f.id]:getOptionValue()
    end
    for _, name in ipairs{'min_condition','max_condition','min_quality','max_quality'} do
        if self.subviews[name] then settings.sliders[name] = self.subviews[name]:getOptionValue() end
    end
    if self.subviews.min_value then settings.sliders.min_value = self.subviews.min_value:getOptionValue().index end
    if self.subviews.max_value then settings.sliders.max_value = self.subviews.max_value:getOptionValue().index end
    return settings
end

function DrillDownList:apply_settings(settings)
    if not settings then return end
    if settings.filters then
        for _, f in ipairs(self:get_status_columns()) do
            local v = settings.filters[f.id]
            if v == true or v == 'hide' then v = 'exclude'
            elseif v == false or v == 'shown' then v = 'include' end
            if v ~= nil and self.subviews['f_'..f.id] then self.subviews['f_'..f.id]:setOption(v) end
        end
    end
    if settings.sliders then
        for _, name in ipairs{'min_condition','max_condition','min_quality','max_quality','min_value','max_value'} do
            if settings.sliders[name] ~= nil and self.subviews[name] then self.subviews[name]:setOption(settings.sliders[name]) end
        end
    end
    if type(settings.sort) == 'table' then self:set_current_sort(settings.sort.col, settings.sort.dir) end
end

function DrillDownList:flash_status(text, pen)
    local label = self.subviews.status_msg
    if not label then return end
    label:setText{{text=text, pen=pen or COLOR_GREEN}}
    label.visible = true
    local end_ms = dfhack.getTickCount() + 3000
    local function reset_fn()
        if dfhack.getTickCount() < end_ms then
            dfhack.timeout(10, 'frames', reset_fn)
        else
            label.visible = false
        end
    end
    reset_fn()
end

function DrillDownList:save_default()
    if not self.save_settings_id then return end
    dfhack.persistent.saveSiteData(self.save_settings_id..'/default', self:get_settings())
    self:flash_status('Saved as default')
end

function DrillDownList:restore_default()
    if not self.save_settings_id then return end
    self:apply_settings(dfhack.persistent.getSiteData(self.save_settings_id..'/default') or self.baseline)
    self:refresh_list()
    self:flash_status('Restored default')
end

function DrillDownList:save_last()
    if not self.save_settings_id then return end
    dfhack.persistent.saveSiteData(self.save_settings_id..'/last', self:get_settings())
end

function DrillDownList:on_init_complete()
    if not self.save_settings_id then return end
    local saved = dfhack.persistent.getSiteData(self.save_settings_id..'/last')
        or dfhack.persistent.getSiteData(self.save_settings_id..'/default')
    if saved then
        if saved.frame then
            local sw, sh = dfhack.screen.getWindowSize()
            local f = get_default_frame()
            f.w = math.max(MIN_W, math.min(saved.frame.w or f.w, sw))
            f.h = math.max(MIN_H, math.min(saved.frame.h or f.h, sh))
            if saved.frame.l then f.l = math.max(0, math.min(saved.frame.l, sw - f.w)) end
            if saved.frame.t then f.t = math.max(0, math.min(saved.frame.t, sh - f.h)) end
            self.frame = f
        end
        self:set_current_sort('name', 'asc')
        self.baseline = self:get_settings()
        self:apply_settings(saved)
    end
end

function DrillDownList:toggle_item_base(choice, target_value)
    local d = choice.data
    if not d.is_group then
        if target_value == nil then target_value = not d.pending end
        d.pending = target_value
    else
        if target_value == nil then target_value = d.selected ~= d.quantity end
        d.selected = target_value and d.quantity or 0
        for _, ic in ipairs(d.items) do ic.data.pending = target_value end
    end
    return target_value
end

function DrillDownList:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function DrillDownList:toggle_item(idx, choice, x)
    local modifiers = dfhack.internal.getModifiers()
    local drill_down_start = self:get_selection_width() + 2
    if #self.path == 3 then
        self:toggle_item_base(choice); self:refresh_list(); return
    end
    if choice.data.is_group then
        local drill_down = true
        if x then
            if x < self:get_selection_width() then drill_down = false end
            if x >= self:get_selection_width() and x < drill_down_start then return end
        end
        if not drill_down or modifiers.ctrl then
            self:toggle_item_base(choice); self:refresh_list()
        else
            table.insert(self.path, {choice.data.desc})
            self.subviews.list.list.page_top = 0; self:refresh_list()
        end
    else
        self:toggle_item_base(choice); self:refresh_list()
    end
end

function DrillDownList:toggle_range(idx, choice)
    if not self.prev_list_idx then self:toggle_item(idx, choice, nil); return end
    local choices = self.subviews.list:getVisibleChoices()
    local list_idx = self.subviews.list.list:getSelected()
    local target_value
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        target_value = self:toggle_item_base(choices[i], target_value)
    end
    self.prev_list_idx = list_idx
end

function DrillDownList:toggle_visible()
    local target_value
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        target_value = self:toggle_item_base(choice, target_value)
    end
end

return _ENV

