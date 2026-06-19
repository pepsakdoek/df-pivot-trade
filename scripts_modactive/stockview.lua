-- Enhanced fortress-wide stocks browser.
--@ module = true

local common = reqscript('internal/caravan/common')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local pivot_common = reqscript('internal/pivot_trade/common')
local gui = require('gui')
local overlay = require('plugins.overlay')
local widgets = require('gui.widgets')

local QTY_COL_WIDTH = 6
local VALUE_COL_WIDTH = 9

-- icon_width(2) + #STATUS_COLUMNS(20) + 1 (gap) + QTY_COL_WIDTH(6) + 2 (gap) + VALUE_COL_WIDTH(9)
local SELECTION_WIDTH = 40

local DEFAULT_CLASS_COL_WIDTH = 20
local DEFAULT_SUBCLASS_COL_WIDTH = 15
local DEFAULT_GROUPED_COL_WIDTH = 20

local MIN_CLASS_COL_WIDTH = #('Class')
local MIN_SUBCLASS_COL_WIDTH = #('Subclass')
local MIN_GROUPED_COL_WIDTH = #('Grouped')

local class_col_width = DEFAULT_CLASS_COL_WIDTH
local subclass_col_width = DEFAULT_SUBCLASS_COL_WIDTH
local grouped_col_width = DEFAULT_GROUPED_COL_WIDTH

-- width of the right-aligned "Items: N  Qty: N" totals readout on the header line
local TOTALS_W = 26

-- minimum usable window dimensions
local MIN_W, MIN_H = 78, 30

-- open as a tall panel anchored toward the top-left, leaving margins from the
-- screen edges
-- margins (in grid tiles) left around the window to clear DF's persistent UI.
-- the window fills the rest of the screen, so it scales with any resolution or
-- tile size (dfhack.screen.getWindowSize reports tiles, not pixels). a deeper
-- top margin clears the status/tab bar; the bottom clears the hotbar.
local MARGIN_L, MARGIN_R, MARGIN_T, MARGIN_B = 16, 37, 7, 4

local function get_default_frame()
    local sw, sh = dfhack.screen.getWindowSize()
    return {
        l=MARGIN_L,
        t=MARGIN_T,
        w=math.max(MIN_W, sw - MARGIN_L - MARGIN_R),
        h=math.max(MIN_H, sh - MARGIN_T - MARGIN_B),
    }
end

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

-- merge a persisted size/position over the default and clamp it onto the screen
local function resolve_frame(saved_frame)
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

-- -------------------
-- filters
--
-- Each filter has its own show/hide toggle (see FILTERS below for defaults).

local function is_caged(item)
    local container = dfhack.items.getContainer(item)
    while container do
        if container:getType() == df.item_type.CAGE then return true end
        container = dfhack.items.getContainer(container)
    end
    return false
end

local function is_trade_marked(item)
    local spec_ref = dfhack.items.getSpecificRef(item, df.specific_ref_type.JOB)
    return spec_ref and spec_ref.data.job and
        spec_ref.data.job.job_type == df.job_type.BringItemToDepot or false
end

-- items sitting in undiscovered parts of the map (e.g. cave-spider silk in
-- unrevealed caverns) shouldn't appear in stocks at all: the player hasn't
-- found them, and zooming to one just lands the view on unrevealed space.
-- items with no map position (nil) are kept; only items on a known-hidden tile
-- are dropped.
local function is_unrevealed(item)
    local x, y, z = dfhack.items.getPosition(item)
    if not x then return false end
    return not dfhack.maps.isTileVisible(x, y, z)
end

-- set of item ids assigned to a uniform; rebuilt by rebuild_uniform_assigned()
local uniform_assigned = {}

-- order here is both the filter-toggle order and the status-column order.
-- 'letter'/'pen' drive the single-letter status columns in the item list.
-- everything is shown by default; set default_hide=true on an entry to start it
-- hidden.
local FILTERS = {
    -- 'noflags' has no test of its own: it is computed in get_item_attrs as
    -- "matches none of the other filters", so it never overlaps another category.
    -- it also has no letter, so it gets no status column.
    {id='noflags',         label='No status'},
    {id='forbid',          label='[F]orbidden',     letter='F', pen=COLOR_RED,          test=function(i) return i.flags.forbid end},
    {id='dump',            label='[D]ump',          letter='D', pen=COLOR_LIGHTMAGENTA, test=function(i) return i.flags.dump end},
    {id='melt',            label='[M]elt',          letter='M', pen=COLOR_LIGHTBLUE,    test=function(i) return i.flags.melt end},
    {id='trade',           label='[T]rade',         letter='T', pen=COLOR_LIGHTGREEN,   test=is_trade_marked},
    {id='hidden',          label='[H]idden',        letter='H', pen=COLOR_GREY,         test=function(i) return i.flags.hidden end},
    {id='owned',           label='[O]wned',         letter='O', pen=COLOR_GREEN,        test=function(i) return i.flags.owned end},
    {id='uniform',         label='In [U]niform',    letter='U', pen=COLOR_MAGENTA,      test=function(i) return uniform_assigned[i.id] or false end},
    {id='in_inventory',    label='In [I]nventory',  letter='I', pen=COLOR_WHITE,        test=function(i) return i.flags.in_inventory end},
    {id='construction',    label='[C]onstruction',  letter='C', pen=COLOR_BROWN,        test=function(i) return i.flags.construction end},
    {id='in_building',     label='In [B]uilding',   letter='B', pen=COLOR_YELLOW,       test=function(i) return i.flags.in_building end},
    {id='garbage_collect', label='[G]arbage',       letter='G', pen=COLOR_DARKGREY,     test=function(i) return i.flags.garbage_collect end},
    {id='imported',        label='[I]mported',      letter='P', pen=COLOR_BROWN,        test=function(i) return i.flags.foreign end},
    {id='trader',          label='Carava[n] Owned', letter='N', pen=COLOR_LIGHTGREEN,   test=function(i) return i.flags.trader end},
    {id='hostile',         label='Hosti[l]e Owned', letter='L', pen=COLOR_RED,          test=function(i) return i.flags.hostile end},
    {id='dead_dwarf',      label='Bur[y]',          letter='Y', pen=COLOR_DARKGREY,     test=function(i) return i.flags.dead_dwarf end},
    {id='caged',           label='C[a]ged',         letter='A', pen=COLOR_CYAN,         test=is_caged},
    {id='in_job',          label='In [J]ob',        letter='J', pen=COLOR_LIGHTCYAN,    test=function(i) return i.flags.in_job end},
    {id='on_fire',         label='On fir[e]',       letter='E', pen=COLOR_LIGHTRED,     test=function(i) return i.flags.on_fire end},
    {id='rotten',          label='[R]otten',        letter='R', pen=COLOR_BROWN,        test=function(i) return i.flags.rotten end},
    {id='spider_web',      label='[S]pider web',    letter='S', pen=COLOR_GREY,         test=function(i) return i.flags.spider_web end},
}

-- the subset of filters that get a single-letter status column, in order
local STATUS_COLUMNS = {}
for _, f in ipairs(FILTERS) do
    if f.letter then table.insert(STATUS_COLUMNS, f) end
end

local function get_item_attrs(item)
    local attrs = {}
    local any = false
    for _, f in ipairs(FILTERS) do
        if f.test then
            local v = not not f.test(item)
            attrs[f.id] = v
            any = any or v
        end
    end
    -- "No status" means the item matched none of the real categories above
    attrs.noflags = not any
    return attrs
end

-- -------------------
-- sorting
--

local function value_of(c)
    return c.item_id and c.data.per_item_value or c.data.total_value
end

-- columns we can sort by: the data columns plus one per status column (sorting
-- on whether the item/group carries that flag)
local SORT_COLUMNS = {
    name    = {key=function(c) return c.search_key end, is_string=true},
    qty     = {key=function(c) return c.item_id and 1 or c.data.quantity end},
    value   = {key=value_of},
    quality = {key=function(c) return c.data.quality end},
    wear    = {key=function(c) return c.data.wear end},
    class   = {key=function(c) return c.data.class or '' end, is_string=true},
    subclass= {key=function(c) return c.data.subclass or '' end, is_string=true},
    grouped = {key=function(c) return c.data.grouped or '' end, is_string=true},
}
for _, f in ipairs(STATUS_COLUMNS) do
    local id = f.id
    SORT_COLUMNS[id] = {key=function(c)
        if c.item_id then return c.data.attrs[id] and 1 or 0 end
        return (c.data['count_'..id] or 0) > 0 and 1 or 0
    end}
end

local function default_dir(col)
    -- string fields sort ascending first, everything else descending first
    return SORT_COLUMNS[col].is_string and 'asc' or 'desc'
end

local function make_comparator(col, dir)
    local key = SORT_COLUMNS[col].key
    local ascending = dir == 'asc'
    return function(a, b)
        local ka, kb = key(a), key(b)
        if ka ~= kb then
            if ascending then return ka < kb end
            return ka > kb
        end
        -- stable tie-break
        if a.data.desc ~= b.data.desc then return a.data.desc < b.data.desc end
        local va, vb = value_of(a), value_of(b)
        if va ~= vb then return va > vb end
        return (a.item_id or 0) < (b.item_id or 0)
    end
end

-- data-column sorts offered by the 'Sort by' fallback selector (status columns
-- are only reachable by clicking their header)
local SORT_OPTIONS, SELECTOR_SPECS = {}, {}
for _, col in ipairs{'name', 'qty', 'value', 'quality', 'wear', 'class', 'subclass', 'grouped'} do
    SELECTOR_SPECS[col] = {}
    for _, dir in ipairs{default_dir(col), default_dir(col) == 'asc' and 'desc' or 'asc'} do
        local spec = {col=col, dir=dir}
        SELECTOR_SPECS[col][dir] = spec
        table.insert(SORT_OPTIONS, {
            label=col..(dir == 'asc' and common.CH_UP or common.CH_DN),
            value=spec,
        })
    end
end

-- -------------------
-- trade depot lookup (for the optional mark-for-trade action)
--

local function get_active_depot()
    for _, bld in ipairs(df.global.world.buildings.all) do
        if df.building_tradedepotst:is_instance(bld) and
            bld:getBuildStage() >= bld:getMaxBuildStage()
        then
            return bld
        end
    end
end

-- rebuild the set of items assigned to a military uniform (squad equipment)
local function rebuild_uniform_assigned()
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

-- -------------------
-- StockView (the window)
--

StockView = defclass(StockView, widgets.Window)
StockView.ATTRS{
    frame_title='Stocks',
    resizable=true,
    resize_min={w=MIN_W, h=MIN_H},
}

local function hl_pen(color)
    return dfhack.pen.parse{fg=COLOR_BLACK, bg=color}
end

-- one colored single-letter cell per status column (blank when inactive)
local function make_status_tokens(has_count, group_size)
    local tokens = {}
    for _, f in ipairs(STATUS_COLUMNS) do
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

local function make_choice_text(status, value, qty, desc, class, subclass, grouped)
    local text = {}
    for _, t in ipairs(status) do table.insert(text, t) end
    table.insert(text, {gap=1, width=QTY_COL_WIDTH, rjustify=true, text=qty})
    table.insert(text, {gap=2, width=VALUE_COL_WIDTH, rjustify=true, text=dfhack.formatInt(value)})
    table.insert(text, {gap=2, width=class_col_width, text=class or '', pen=COLOR_CYAN})
    table.insert(text, {gap=2, width=subclass_col_width, text=subclass or '', pen=COLOR_GREY})
    table.insert(text, {gap=2, width=grouped_col_width, text=grouped or '', pen=COLOR_CYAN})
    table.insert(text, {gap=2, text=desc or ''})
    return text
end

-- a grouped row's status letter shows if any item in the group has the flag
local function group_status_text(d)
    return make_choice_text(
        make_status_tokens(function(id) return d['count_'..id] or 0 end, d.quantity),
        d.total_value, d.quantity, '', d.class, d.subclass, d.grouped)
end

local function item_status_text(d, item_id)
    local attrs = d.attrs or d.items[item_id].attrs
    return make_choice_text(
        make_status_tokens(function(id) return attrs[id] and 1 or 0 end, 1),
        d.per_item_value, 1, d.desc, d.class, d.subclass, d.grouped)
end

-- Click ranges for each header column are dynamically updated in update_column_layout

-- the active status column is shown inverse-highlighted; the active data column
-- gets a direction arrow and brighter text
local function build_header_tokens(sort)
    local text = {}
    for _, f in ipairs(STATUS_COLUMNS) do
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
    table.insert(text, data_header(2, nil, 'name', 'item'))
    return text
end

-- a header row whose columns sort the list when clicked
local HeaderRow = defclass(nil, widgets.Label)
HeaderRow.ATTRS{on_sort=DEFAULT_NIL, stockview=DEFAULT_NIL}
function HeaderRow:onInput(keys)
    if keys._MOUSE_L then
        local x = self:getMousePos()
        local col
        for _, r in ipairs(self.stockview.header_ranges or {}) do
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

local FILTER_COL_W = 23
local FILTER_LABEL_W = 13

-- three-state filters, styled like the squad-assignment screen: Include (no
-- constraint, default), Only (require), Exclude (exclude, and wins). cycling in
-- this order means a single left-click from the default reaches the common
-- 'Only' state, with no need for right-click.
local FILTER_OPTIONS = {
    {label='Include', value='include', pen=COLOR_GREEN},
    {label='Only',    value='only',    pen=COLOR_YELLOW},
    {label='Exclude', value='exclude', pen=COLOR_LIGHTRED},
}

local function make_filter_widgets(self, filters, ncols, base_l, base_t)
    local views = {}
    local nrows = math.ceil(#filters / ncols)
    for i, f in ipairs(filters) do
        -- column-major fill: stack down a column before starting the next one
        local col = math.floor((i-1) / nrows)
        local row = (i-1) % nrows
        -- right-align the label, tinted in the status color to tie to its column
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

function StockView:update_column_layout()
    local x = 0
    local ranges = {}
    for _, f in ipairs(STATUS_COLUMNS) do
        table.insert(ranges, {x1=x, x2=x, col=f.id})
        x = x + 1
    end
    for _, dc in ipairs{{col='qty', gap=1, w=QTY_COL_WIDTH},
                        {col='value', gap=2, w=VALUE_COL_WIDTH},
                        {col='class', gap=2, w=class_col_width},
                        {col='subclass', gap=2, w=subclass_col_width},
                        {col='grouped', gap=2, w=grouped_col_width},
                        {col='name', gap=2, w=1000}} do
        local x1 = x
        x = x1 + dc.gap + dc.w
        table.insert(ranges, {x1=x1, x2=x-1, col=dc.col})
    end
    self.header_ranges = ranges
end

function StockView:set_column_widths(class_w, subclass_w, grouped_w)
    class_w = math.max(MIN_CLASS_COL_WIDTH, class_w or DEFAULT_CLASS_COL_WIDTH)
    subclass_w = math.max(MIN_SUBCLASS_COL_WIDTH, subclass_w or DEFAULT_SUBCLASS_COL_WIDTH)
    grouped_w = math.max(MIN_GROUPED_COL_WIDTH, grouped_w or DEFAULT_GROUPED_COL_WIDTH)

    if class_w == class_col_width and subclass_w == subclass_col_width and 
       grouped_w == grouped_col_width then
        return false
    end

    class_col_width = class_w
    subclass_col_width = subclass_w
    grouped_col_width = grouped_w
    
    self:update_column_layout()
    if self.subviews and self.subviews.header then
        self.subviews.header:setText(build_header_tokens(self.current_sort))
    end
    self:updateLayout()
    return true
end

function StockView:compute_column_widths(choices)
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

function StockView:update_choice_texts(choices)
    for _, choice in ipairs(choices or {}) do
        local d = choice.data or {}
        if d.is_group then
            choice.text = group_status_text(d)
        else
            choice.text = item_status_text(d, choice.item_id)
        end
    end
end

function StockView:init()
    self.path = {}
    self.choices_cache = nil
    self.header_ranges = {}
    self:update_column_layout()
    local saved = dfhack.persistent.getSiteData('stockview/last') or
        dfhack.persistent.getSiteData('stockview/default')
    self.frame = resolve_frame(saved and saved.frame)

    -- wrap filters down the vertical space the sliders give us (~14 rows) before
    -- adding a column, rather than spreading wide; never exceed the width
    local FILTER_MAX_ROWS, SLIDER_ROWS = 14, 16
    local width_cols = math.max(1, math.floor(((self.frame.w - 4) - 40) / FILTER_COL_W))
    local filter_cols = math.min(width_cols, math.max(1, math.ceil(#FILTERS / FILTER_MAX_ROWS)))
    local filter_rows = math.ceil(#FILTERS / filter_cols)
    -- two rows reserved at the top: the show/hide/invert controls and a gap
    local content_rows = math.max(SLIDER_ROWS, 2 + filter_rows)
    local filter_panel_h = content_rows + 2
    local list_t = 3 + filter_panel_h

    local filter_subviews = {
        widgets.Panel{
            frame={t=0, l=0, w=38},
            subviews=common.get_slider_widgets(self),
        },
        widgets.HotkeyLabel{
            frame={t=0, l=40}, auto_width=true,
            label='Reset filters', text_pen=COLOR_GREEN,
            on_activate=function() self:set_all_filters('include') end,
        },
    }
    for _, w in ipairs(make_filter_widgets(self, FILTERS, filter_cols, 40, 2)) do
        table.insert(filter_subviews, w)
    end

    self:addviews{
        widgets.CycleHotkeyLabel{
            view_id='sort',
            frame={l=1, t=0, w=22},
            label='Sort:',
            key='CUSTOM_SHIFT_S',
            options=SORT_OPTIONS,
            initial_option=SELECTOR_SPECS.name.asc,
            on_change=function(spec)
                self:set_current_sort(spec.col, spec.dir)
                self:refresh_list()
            end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='filters',
            frame={l=24, t=0, w=24},
            label='Show filters:',
            key='CUSTOM_SHIFT_F',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false}
            },
            initial_option=true,
            on_change=function() self:updateLayout() end,
        },
        widgets.ToggleHotkeyLabel{
            view_id='auto_resize_cols',
            frame={l=49, t=0, w=24},
            label='Auto cols:',
            key='CUSTOM_SHIFT_R',
            options={
                {label='Yes', value=true, pen=COLOR_GREEN},
                {label='No', value=false},
            },
            initial_option=true,
            on_change=function() self:refresh_list() end,
        },
        widgets.EditField{
            view_id='search',
            frame={l=75, t=0, r=1},
            label_text='Search: ',
            on_char=function(ch) return ch:match('[%w -]') end,
        },
        widgets.Panel{
            frame={t=1, l=0, r=0, h=1},
            visible=function() return #self.path > 0 end,
            subviews={
                widgets.Label{
                    frame={t=0, l=2},
                    text={
                        {text="< Back", pen=COLOR_LIGHTRED, key="LEAVESCREEN", on_activate=function() self:go_back() end},
                        {gap=1, text=function() return table.concat(self.path, " > ") end}
                    },
                    on_click=function() self:go_back() end,
                }
            }
        },
        widgets.Panel{
            view_id='filter_panel',
            frame={t=2, l=0, r=0, h=filter_panel_h},
            frame_style=gui.FRAME_INTERIOR,
            visible=function() return self.subviews.filters:getOptionValue() end,
            on_layout=function()
                local panel_frame = self.subviews.list_panel.frame
                if self.subviews.filters:getOptionValue() then
                    panel_frame.t = filter_panel_h + 3
                else
                    panel_frame.t = 2
                end
            end,
            subviews=filter_subviews,
        },
        widgets.Panel{
            view_id='list_panel',
            frame={t=list_t, l=0, r=0, b=4},
            on_layout=function(panel)
                local panel_frame = self.subviews.list_panel.frame
                panel_frame.t = list_t
            end,
            subviews={
                widgets.Label{
                    view_id='click_guide',
                    frame={t=0},
                    text= "+---- SELECT -----------------------------+---- DRILL DOWN ------------------------------+",
                    -- Functions in text for some reason results in cv nil value errors
                    -- function()
                    --     local str = '+-- SELECT '..('-'):rep(SELECTION_WIDTH-11)..'+---- DRILL DOWN '..('-'):rep(30)..'+'
                    --     return str
                    -- end,
                    text_pen=COLOR_LIGHTGREEN,
                },
                HeaderRow{
                    view_id='header',
                    frame={t=1, l=2},
                    text=build_header_tokens({col='name', dir='asc'}),
                    text_pen=COLOR_GRAY,
                    on_sort=self:callback('set_sort'),
                    stockview=self,
                },
                -- running totals for the currently visible (post-filter) list,
                -- right-aligned on the header line
                widgets.Label{
                    view_id='totals',
                    frame={t=1, r=1, w=TOTALS_W},
                    text='',
                },
                widgets.FilteredList{
                    view_id='list',
                    frame={l=0, t=3, r=0, b=0},
                    icon_width=2,
                    on_submit2=self:callback('toggle_range'),
                    on_select=self:callback('select_item'),
                },
            },
        },
        widgets.Divider{
            frame={b=3, h=1},
            frame_style=gui.FRAME_INTERIOR,
            frame_style_l=false,
            frame_style_r=false,
        },
        widgets.Panel{
            frame={l=1, r=1, b=0, h=3},
            subviews={
                widgets.HotkeyLabel{
                    frame={t=0, l=0}, auto_width=true,
                    label='Dump', key='CUSTOM_CTRL_D',
                    on_activate=self:callback('act_dump'),
                },
                widgets.HotkeyLabel{
                    frame={t=0, l=13}, auto_width=true,
                    label='Forbid', key='CUSTOM_CTRL_F',
                    on_activate=self:callback('act_forbid'),
                },
                widgets.HotkeyLabel{
                    frame={t=0, l=28}, auto_width=true,
                    label='Melt', key='CUSTOM_CTRL_M',
                    on_activate=self:callback('act_melt'),
                },
                widgets.HotkeyLabel{
                    frame={t=0, l=41}, auto_width=true,
                    label='Trade', key='CUSTOM_CTRL_T',
                    on_activate=self:callback('act_trade'),
                    enabled=function() return get_active_depot() ~= nil end,
                },
                widgets.HotkeyLabel{
                    frame={t=0, l=55}, auto_width=true,
                    label='Zoom', key='CUSTOM_CTRL_O',
                    on_activate=self:callback('act_zoom'),
                },
                widgets.HotkeyLabel{
                    frame={t=2, l=0}, auto_width=true,
                    label='Select all/none', key='CUSTOM_CTRL_N',
                    on_activate=self:callback('toggle_visible'),
                },
                widgets.HotkeyLabel{
                    frame={t=2, l=26}, auto_width=true,
                    label='Save default', key='CUSTOM_ALT_S',
                    on_activate=self:callback('save_default'),
                },
                widgets.HotkeyLabel{
                    frame={t=2, l=48}, auto_width=true,
                    label='Restore default', key='CUSTOM_ALT_R',
                    on_activate=self:callback('restore_default'),
                },
                -- transient confirmation shown in-dialog (right-aligned) so we
                -- don't spam DF's announcement log on the left
                widgets.Label{
                    view_id='status_msg',
                    frame={t=2, r=0, w=16},
                    text='',
                    visible=false,
                },
            },
        },
    }

    -- replace the FilteredList's built-in EditField with our own search field
    self.subviews.list.list.frame.t = 0
    self.subviews.list.edit.visible = false
    self.subviews.list.edit = self.subviews.search
    -- keep the totals in sync as the search narrows the visible list
    local on_filter = self.subviews.list:callback('onFilterChange')
    self.subviews.search.on_change = function(text)
        on_filter(text)
        self:update_totals()
    end

    local list_widget = self.subviews.list.list
    local orig_onInput = list_widget.onInput
    list_widget.onInput = function(widget, keys)
        if keys.SELECT then
            local idx = widget:getSelected()
            local choices = self.subviews.list:getVisibleChoices()
            local choice = choices and choices[idx]
            if choice then
                self:toggle_item(idx, choice, nil) -- nil means keyboard Enter
                return true
            end
        end
        if keys._STRING == 32 then -- Space
            local idx = widget:getSelected()
            local choices = self.subviews.list:getVisibleChoices()
            local choice = choices and choices[idx]
            if choice then
                self:toggle_item_base(choice)
                self:refresh_list()
                return true
            end
        end

        local was_click = keys._MOUSE_L
        local handled = orig_onInput(widget, keys)
        if was_click and handled then
            local x, y = widget:getMousePos()
            
            -- Try fix scrollbar clicks being interpreted as row actions
            local widget_w = nil
            if widget.frame and widget.frame.w then widget_w = widget.frame.w end
            if (not widget_w) and self.subviews.list and self.subviews.list.frame and self.subviews.list.frame.w then
                widget_w = self.subviews.list.frame.w
            end
            if (not widget_w) and self.frame and self.frame.w then widget_w = self.frame.w end

            local scrollbar_reserved = 3
            if widget_w and widget_w > 0 and x and x >= widget_w - scrollbar_reserved then
                return handled
            end

            local idx = widget:getSelected()
            local choices = self.subviews.list:getVisibleChoices()
            local choice = choices and choices[idx]
            if choice then
                self:toggle_item(idx, choice, x)
            end
        end
        return handled
    end

    -- the widget defaults define the baseline; apply persisted settings on top
    -- (window size was already applied above)
    self:set_current_sort('name', 'asc')
    self.baseline = self:get_settings()
    self:apply_settings(saved)

    self.subviews.list:setChoices(self:get_choices())
    self:update_totals()
end

function StockView:onInput(keys)
    if (keys.LEAVESCREEN or keys._MOUSE_R) and #self.path > 0 then
        self:go_back()
        return true
    end
    return StockView.super.onInput(self, keys)
end

function StockView:go_back()
    if #self.path > 0 then
        table.remove(self.path)
        self.subviews.list.list.page_top = 0
        self:refresh_list()
    end
end

-- -------------------
-- data
--

function StockView:cache_choices()
    if self.choices_cache then return self.choices_cache end

    rebuild_uniform_assigned()

    -- item id -> its choice entry, for in-place updates
    self.choice_by_id = {}

    local items_data = {}
    for _, item in ipairs(df.global.world.items.other.IN_PLAY) do
        -- 'removed' items are defunct records with no position; never show them
        if not item or item.flags.removed then goto continue end
        -- items in unrevealed map areas haven't been discovered yet; hide them
        if is_unrevealed(item) then goto continue end
        local value = dfhack.items.getValue(item)
        local desc = dfhack.items.getReadableDescription(item)
        local class, subclass = classifier.classify_item(item)
        local group = get_generic_description(item) or "Other"
        local attrs = get_item_attrs(item)

        local search_str = ('%s %s %s %s'):format(desc, class, subclass, group)
        local search_key = pivot_common.make_search_key(search_str)

        local data = {
            item=item,
            desc=desc,
            per_item_value=value,
            quality=item.flags.artifact and 6 or item:getQuality(),
            wear=item:getWear(),
            class=class or 'Other',
            subclass=subclass or 'Other',
            grouped=group,
            attrs=attrs,
            pending=false,
        }

        local choice = {
            search_key=search_key,
            data=data,
            item_id=item.id,
            icon=function() return data.pending and pivot_common.ALL_PEN or nil end,
        }

        self.choice_by_id[item.id] = choice
        table.insert(items_data, choice)
        ::continue::
    end

    self.choices_cache = items_data
    return self.choices_cache
end

-- after a bulk action changes item flags, recompute the affected items' status
-- in the cache (attrs, group aggregates, and row text) and re-render
function StockView:apply_status_changes(items)
    self:cache_choices()
    for _, item in ipairs(items) do
        local choice = self.choice_by_id[item.id]
        if choice then
            choice.data.attrs = get_item_attrs(item)
        end
    end
    self:refresh_list()
end

local function choice_has(choice, id)
    if choice.item_id then return choice.data.attrs[id] end
    return (choice.data['count_'..id] or 0) > 0
end

-- 'exclude' wins; if any filter is set to 'only', the item must carry at least
-- one such status
local function passes_flag_filters(choice, states, has_only)
    local matched_only = false
    for id, state in pairs(states) do
        if state ~= 'include' and choice_has(choice, id) then
            if state == 'exclude' then return false end
            matched_only = true
        end
    end
    return not (has_only and not matched_only)
end

function StockView:aggregate_choices(flat_choices, filter_str)
    if #self.path == 3 then
        -- Leaf level: Items
        local filtered = {}
        for _, choice in ipairs(flat_choices) do
            local d = choice.data
            if d.class == self.path[1] and d.subclass == self.path[2] and d.grouped == self.path[3] then
                choice.text = item_status_text(d, choice.item_id)
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
                for _, f in ipairs(FILTERS) do groups[key]['count_'..f.id] = 0 end
                table.insert(order, key)
            end
            local g = groups[key]
            g.count = g.count + 1
            g.value = g.value + d.per_item_value
            if d.pending then
                g.selected_count = g.selected_count + 1
            end
            for _, f in ipairs(FILTERS) do
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
            desc = key,
            total_value = g.value,
            quantity = g.count,
            selected = g.selected_count,
            is_group = true,
            items = g.items,
            class = g.class,
            subclass = g.subclass,
            grouped = g.grouped
        }
        for _, f in ipairs(FILTERS) do d['count_'..f.id] = g['count_'..f.id] end

        -- Build a combined search_key from all child items plus the group labels
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
            text = group_status_text(d),
        }
        table.insert(choices, choice)
    end

    return choices
end

function StockView:get_choices()
    local flat_choices = self:cache_choices()

    local min_condition = self.subviews.min_condition:getOptionValue()
    local max_condition = self.subviews.max_condition:getOptionValue()
    local min_quality = self.subviews.min_quality:getOptionValue()
    local max_quality = self.subviews.max_quality:getOptionValue()
    local min_value_opt = self.subviews.min_value:getOptionValue()
    -- the lowest value option (index 1) means "no minimum" so that 0-value
    -- items (e.g. some refuse) remain visible by default
    local min_value = min_value_opt.index == 1 and 0 or min_value_opt.value
    local max_value = self.subviews.max_value:getOptionValue().value

    local states, has_only = {}, false
    for _, f in ipairs(FILTERS) do
        local state = self.subviews['f_'..f.id]:getOptionValue()
        states[f.id] = state
        if state == 'only' then has_only = true end
    end

    local filtered = {}
    for _, choice in ipairs(flat_choices) do
        local d = choice.data
        if min_condition < d.wear then goto continue end
        if max_condition > d.wear then goto continue end
        if min_quality > d.quality then goto continue end
        if max_quality < d.quality then goto continue end
        if min_value > d.per_item_value then goto continue end
        if max_value < d.per_item_value then goto continue end
        if not passes_flag_filters(choice, states, has_only) then goto continue end
        table.insert(filtered, choice)
        ::continue::
    end

    local filter_str = self.subviews.search.text:lower()
    local aggregated = self:aggregate_choices(filtered, filter_str)

    table.sort(aggregated, self.current_sort.fn)
    return aggregated
end

function StockView:refresh_list()
    local list = self.subviews.list
    local saved_filter = list:getFilter()
    list:setFilter('')
    
    local choices = self:get_choices()
    
    local auto_resize = self.subviews.auto_resize_cols:getOptionValue()
    if auto_resize then
        local class_w, subclass_w, grouped_w = self:compute_column_widths(choices)
        if self:set_column_widths(class_w, subclass_w, grouped_w) then
            self:update_choice_texts(choices)
        end
    end

    list:setChoices(choices, list:getSelected())
    list:setFilter(saved_filter)
    self:update_totals()
end

-- recompute the header-line totals from the visible (post-filter, post-search)
-- list: 'Items' is the number of rows shown; 'Qty' is the physical item count
-- (a grouped row counts its whole stack, an ungrouped row counts as one)
function StockView:update_totals()
    local rows, qty = 0, 0
    for _, c in ipairs(self.subviews.list:getVisibleChoices()) do
        rows = rows + 1
        if c.data.is_group then
            qty = qty + c.data.quantity
        else
            qty = qty + 1
        end
    end
    local items_str, qty_str = dfhack.formatInt(rows), dfhack.formatInt(qty)
    -- right-justify by padding to the box width, so the readout hugs the right
    -- edge regardless of how many digits it carries
    local content_w = 7 + #items_str + 2 + 5 + #qty_str  -- 'Items: '..N..'  '..'Qty: '..N
    local pad = (' '):rep(math.max(0, TOTALS_W - content_w))
    self.subviews.totals:setText{
        {text=pad},
        {text='Items: ', pen=COLOR_GRAY},
        {text=items_str, pen=COLOR_WHITE},
        {gap=2, text='Qty: ', pen=COLOR_GRAY},
        {text=qty_str, pen=COLOR_WHITE},
    }
end

-- set the active sort and reflect it in the selector and header (no list refresh)
function StockView:set_current_sort(col, dir)
    if not SORT_COLUMNS[col] then col, dir = 'name', 'asc' end
    self.current_sort = {col=col, dir=dir, fn=make_comparator(col, dir)}
    local opt = SELECTOR_SPECS[col] and SELECTOR_SPECS[col][dir]
    if opt then self.subviews.sort:setOption(opt) end
    self.subviews.header:setText(build_header_tokens(self.current_sort))
end

-- header click: sort by the column, or reverse it if it's already active
function StockView:set_sort(col)
    local cur = self.current_sort
    local dir = (cur and cur.col == col) and (cur.dir == 'asc' and 'desc' or 'asc')
        or default_dir(col)
    self:set_current_sort(col, dir)
    self:refresh_list()
end

function StockView:set_all_filters(state)
    for _, f in ipairs(FILTERS) do
        self.subviews['f_'..f.id]:setOption(state)
    end
    self:refresh_list()
end

-- -------------------
-- selection
--

function StockView:toggle_item_base(choice, target_value)
    local d = choice.data
    if not d.is_group then
        if target_value == nil then target_value = not d.pending end
        d.pending = target_value
    else
        if target_value == nil then target_value = d.selected ~= d.quantity end
        d.selected = target_value and d.quantity or 0
        for _, item_choice in ipairs(d.items) do
            item_choice.data.pending = target_value
        end
    end
    return target_value
end

function StockView:select_item(idx, choice)
    if not dfhack.internal.getModifiers().shift then
        self.prev_list_idx = self.subviews.list.list:getSelected()
    end
end

function StockView:toggle_item(idx, choice, x)
    local modifiers = dfhack.internal.getModifiers()
    local drill_down_start = SELECTION_WIDTH + 2

    -- If we're at the lowest level, left click 'everywhere' should select / deselect
    if #self.path == 3 then
        self:toggle_item_base(choice)
        self:refresh_list()
        return
    end

    if choice.data.is_group then
        local drill_down = true
        if x then
            if x < SELECTION_WIDTH then
                drill_down = false
            end
            
            -- dead zone check
            if x >= SELECTION_WIDTH and x < drill_down_start then
                return
            end
        end

        if not drill_down or modifiers.ctrl then
            self:toggle_item_base(choice)
            self:refresh_list()
        else
            table.insert(self.path, choice.data.desc)
            self.subviews.list.list.page_top = 0
            self:refresh_list()
        end
    else
        -- Single items toggle on click/Enter
        self:toggle_item_base(choice)
        self:refresh_list()
    end
end

function StockView:toggle_range(idx, choice)
    if not self.prev_list_idx then
        self:toggle_item(idx, choice, nil)
        return
    end
    local choices = self.subviews.list:getVisibleChoices()
    local list_idx = self.subviews.list.list:getSelected()
    local target_value
    for i = list_idx, self.prev_list_idx, list_idx < self.prev_list_idx and 1 or -1 do
        target_value = self:toggle_item_base(choices[i], target_value)
    end
    self.prev_list_idx = list_idx
end

function StockView:toggle_visible()
    local target_value
    for _, choice in ipairs(self.subviews.list:getVisibleChoices()) do
        target_value = self:toggle_item_base(choice, target_value)
    end
end

-- returns the list of items the actions should operate on: the pending
-- (selected) items, or the highlighted row if nothing is selected
function StockView:get_action_items()
    local items = {}
    local all_choices = self:cache_choices()
    for _, choice in ipairs(all_choices) do
        if choice.data.pending then
            table.insert(items, choice.data.item)
        end
    end
    if #items > 0 then return items end

    local _, choice = self.subviews.list:getSelected()
    if choice then
        if not choice.data.is_group then
            table.insert(items, choice.data.item)
        else
            for _, item_choice in ipairs(choice.data.items) do
                table.insert(items, item_choice.data.item)
            end
        end
    end
    return items
end

-- -------------------
-- actions
--

function StockView:act_dump()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do
        if not item.flags.dump then all = false break end
    end
    for _, item in ipairs(items) do item.flags.dump = not all end
    self:apply_status_changes(items)
end

function StockView:act_forbid()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do
        if not item.flags.forbid then all = false break end
    end
    for _, item in ipairs(items) do item.flags.forbid = not all end
    self:apply_status_changes(items)
end

function StockView:act_melt()
    local items = self:get_action_items()
    if #items == 0 then return end
    local all = true
    for _, item in ipairs(items) do
        if not item.flags.melt then all = false break end
    end
    for _, item in ipairs(items) do
        if all then
            dfhack.items.cancelMelting(item)
        elseif dfhack.items.canMelt(item) then
            dfhack.items.markForMelting(item)
        end
    end
    self:apply_status_changes(items)
end

function StockView:act_trade()
    local depot = get_active_depot()
    if not depot then return end
    local items = self:get_action_items()
    for _, item in ipairs(items) do
        if dfhack.items.canTrade(item) and not is_trade_marked(item) then
            dfhack.items.markForTrade(item, depot)
        end
    end
    self:apply_status_changes(items)
end

function StockView:act_zoom()
    local _, choice = self.subviews.list:getSelected()
    if not choice then return end
    local item
    if choice.item_id then
        item = choice.data.items[choice.item_id].item
    else
        item = (next(choice.data.items))
        item = item and choice.data.items[item].item
    end
    if not item then return end
    local x, y, z = dfhack.items.getPosition(item)
    if not x then return end
    self.parent_view:dismiss()
    -- center=true actually centers the view; highlight=true draws DF's pulsing
    -- recenter indicator on the tile so it's easy to spot
    dfhack.gui.revealInDwarfmodeMap(xyz2pos(x, y, z), true, true)
end

-- -------------------
-- settings persistence
--

function StockView:get_settings()
    local settings = {
        filters={},
        sliders={},
        sort={col=self.current_sort.col, dir=self.current_sort.dir},
        frame={w=self.frame.w, h=self.frame.h, l=self.frame.l, t=self.frame.t},
    }
    for _, f in ipairs(FILTERS) do
        settings.filters[f.id] = self.subviews['f_'..f.id]:getOptionValue()
    end
    for _, name in ipairs{'min_condition', 'max_condition', 'min_quality', 'max_quality'} do
        settings.sliders[name] = self.subviews[name]:getOptionValue()
    end
    settings.sliders.min_value = self.subviews.min_value:getOptionValue().index
    settings.sliders.max_value = self.subviews.max_value:getOptionValue().index
    return settings
end

function StockView:apply_settings(settings)
    if not settings then return end
    if settings.filters then
        for _, f in ipairs(FILTERS) do
            local v = settings.filters[f.id]
            -- migrate older saves (booleans / 'shown'/'hide') to include/exclude
            if v == true or v == 'hide' then v = 'exclude'
            elseif v == false or v == 'shown' then v = 'include' end
            if v ~= nil then self.subviews['f_'..f.id]:setOption(v) end
        end
    end
    if settings.sliders then
        for _, name in ipairs{'min_condition', 'max_condition', 'min_quality', 'max_quality',
                'min_value', 'max_value'} do
            if settings.sliders[name] ~= nil then
                self.subviews[name]:setOption(settings.sliders[name])
            end
        end
    end
    -- (type check tolerates older saves where sort was a numeric option index)
    if type(settings.sort) == 'table' then
        self:set_current_sort(settings.sort.col, settings.sort.dir)
    end
end

-- briefly show a confirmation message in-dialog, then auto-hide it. kept local
-- to the window so it never touches DF's announcement log
function StockView:flash_status(text, pen)
    local label = self.subviews.status_msg
    label:setText{{text=text, pen=pen or COLOR_GREEN}}
    label.visible = true
    local end_ms = dfhack.getTickCount() + 3000
    local function reset()
        if dfhack.getTickCount() < end_ms then
            dfhack.timeout(10, 'frames', reset)
        else
            label.visible = false
        end
    end
    reset()
end

function StockView:save_default()
    dfhack.persistent.saveSiteData('stockview/default', self:get_settings())
    self:flash_status('Saved as default')
end

function StockView:restore_default()
    self:apply_settings(dfhack.persistent.getSiteData('stockview/default') or self.baseline)
    self:refresh_list()
    self:flash_status('Restored default')
end

function StockView:save_last()
    dfhack.persistent.saveSiteData('stockview/last', self:get_settings())
end

-- -------------------
-- StockViewScreen
--

StockViewScreen = defclass(StockViewScreen, gui.ZScreenModal)
StockViewScreen.ATTRS{
    focus_path='stockview',
}

function StockViewScreen:init()
    self:addviews{StockView{view_id='stockview'}}
end

function StockViewScreen:onDismiss()
    self.subviews.stockview:save_last()
    view = nil
end

-- -------------------
-- StockViewLauncher (overlay on the vanilla stocks screen)
--

StockViewLauncher = defclass(StockViewLauncher, overlay.OverlayWidget)
StockViewLauncher.ATTRS{
    desc='Adds a hotkey to open the enhanced stockview item browser.',
    default_pos={x=-3, y=-12},
    default_enabled=true,
    viewscreens='dwarfmode/Stocks',
    frame={w=27, h=3},
    frame_style=gui.MEDIUM_FRAME,
    frame_background=gui.CLEAR_PEN,
}

function StockViewLauncher:init()
    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            label='enhanced view',
            key='CUSTOM_SHIFT_Z',
            on_activate=function()
                view = view and view:raise() or StockViewScreen{}:show()
            end,
        },
    }
end

OVERLAY_WIDGETS = {
    launcher=StockViewLauncher,
}

-- forget the persisted window size/position so it reverts to the screen-relative
-- default; also applies it immediately if the dialog is open
local function reset_window()
    for _, key in ipairs{'stockview/last', 'stockview/default'} do
        local s = dfhack.persistent.getSiteData(key)
        if s and s.frame then
            s.frame = nil
            dfhack.persistent.saveSiteData(key, s)
        end
    end
    if view and view.subviews.stockview then
        local win = view.subviews.stockview
        win.frame = get_default_frame()
        win:updateLayout()
    end
end

if dfhack_flags.module then
    return
end

if not dfhack.world.isFortressMode() then
    qerror('gui/stockview requires fortress mode')
end

local args = {...}
if args[1] == 'reset-window' then
    reset_window()
    print('stockview: window size and position reset to default')
    return
elseif args[1] then
    qerror('unknown command: '..args[1])
end

view = view and view:raise() or StockViewScreen{}:show()
