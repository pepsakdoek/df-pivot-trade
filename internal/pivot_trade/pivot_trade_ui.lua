--@ module = true
local M = {}
local gui = require('gui')
local widgets = require('gui.widgets')

-- This is crucial: the UI needs to know how to classify items internally
local item_classifier = reqscript('internal/pivot_trade/item_classifier')

---------------------------------------------------------------------------
-- PART 2: MODERN UI CLASSES (v50+)
---------------------------------------------------------------------------

local function ui_format_value(val)
    if val >= 1000000 then return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then return string.format("%.1fk", val / 1000)
    else return tostring(val) end
end

local function get_generic_description(item)
    local desc = dfhack.items.getReadableDescription(item)

    -- Pattern: ≡, -, +, *, #, (, ), {, }, [, ], <, >, «, »
    desc = desc:gsub("[%-%+%*#≡%(%){}%[%]<>%z\174\175\240]", "")
    
    -- Strip "left" and "right" specifically for shoes/gloves
    desc = desc:gsub("%f[%a][Ll]eft%f[%A]", "")
    desc = desc:gsub("%f[%a][Rr]ight%f[%A]", "")
    
    -- Clean up double spaces from the removals
    return desc:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

-- We define PivotWindow as a local class used only inside this module
local PivotWindow = defclass(nil, widgets.Window)
PivotWindow.ATTRS {
    frame_title = "Pivot Inventory Explorer",
    resizable = true,
    resize_min = {w=8, h=30},
    frame = {w=70, h=40},
}

function PivotWindow:init(args)
    self.items = args.items
    self.hierarchy_data = self:process_items(args.items or {})
    self.view_mode = 'CLASS' 
    self.current_class_id = nil
    self.current_sub_id = nil
    self.current_group_name = nil

    self:addviews{
        widgets.Label{
            view_id = 'path_label',
            frame = {t=0, l=0},
            text = "Root",
            text_pen = gui.YELLOW
        },
        widgets.Divider{frame={t=1, h=1}},
        widgets.List{
            view_id = 'main_list',
            frame = {t=2, l=0, r=0, b=2},
            on_submit = self:callback('on_list_submit'),
            scroll_keys = widgets.SECOND_SCROLL_KEYS,
        },
        widgets.Divider{frame={b=1, h=1}},
        widgets.HotkeyLabel{
            frame = {b=0, l=0},
            label = "Go Back",
            key = "LEAVESCREEN",
            on_activate = function() self:go_back() end
        },
    }
    self:refresh_list()
end

function PivotWindow:process_items(items)
    local data = {}
    for _, item in ipairs(items) do
        -- Call the classifier function from the required module
        local class_id, sub_id = item_classifier.classify_item(item)
        data[class_id] = data[class_id] or { count = 0, value = 0, subclasses = {} }
        data[class_id].subclasses[sub_id] = data[class_id].subclasses[sub_id] or { count = 0, value = 0, items = {} }
        
        local val = item:getCurrencyValue(nil)
        data[class_id].count = data[class_id].count + 1
        data[class_id].value = data[class_id].value + val
        
        local sub = data[class_id].subclasses[sub_id]
        sub.count = sub.count + 1
        sub.value = sub.value + val
        table.insert(sub.items, item)
    end
    return data
end

function PivotWindow:refresh_list()
    local choices = {}
    local list = self.subviews.main_list
    
    if self.view_mode == 'CLASS' then
        local total_count, total_value = 0, 0
        for _, info in pairs(self.hierarchy_data) do
            total_count = total_count + info.count
            total_value = total_value + info.value
        end
        
        self.subviews.path_label:setText({
            {text=" All Items | ", pen=gui.YELLOW},
            {text=tostring(total_count), pen=gui.CYAN},
            {text=" items | Value: " .. ui_format_value(total_value), pen=gui.GREEN}
        })

        local keys = {}
        for k in pairs(self.hierarchy_data) do table.insert(keys, k) end
        table.sort(keys)
        for _, id in ipairs(keys) do
            local info = self.hierarchy_data[id]
            table.insert(choices, {
                text = {{text=string.format("%-25s", id)}, 
                    {text=string.format("%8d", info.count), pen=gui.CYAN}, 
                    {text=string.format(" (%s)", ui_format_value(info.value)), pen=gui.GREEN}},
                class_id = id
            })
        end

    elseif self.view_mode == 'SUBCLASS' then
        local info = self.hierarchy_data[self.current_class_id]
        self.subviews.path_label:setText({
            {text=self.current_class_id .. " | ", pen=gui.YELLOW},
            {text=tostring(info.count), pen=gui.CYAN},
            {text=" items (" .. ui_format_value(info.value) .. ")", pen=gui.GREEN}
        })

        local keys = {}
        for k in pairs(info.subclasses) do table.insert(keys, k) end
        table.sort(keys)
        for _, id in ipairs(keys) do
            local sub = info.subclasses[id]
            table.insert(choices, {
                text = {{text=string.format("%-25s", id)}, 
                {text=string.format("%8d", sub.count), pen=gui.CYAN}, 
                {text=string.format(" (%s)", ui_format_value(sub.value)), pen=gui.GREEN}},
                sub_id = id
            })
        end

    elseif self.view_mode == 'GROUPED' then
        local sub = self.hierarchy_data[self.current_class_id].subclasses[self.current_sub_id]
        
        self.subviews.path_label:setText({
            {text=self.current_class_id .. " > " .. self.current_sub_id .. " | ", pen=gui.YELLOW},
            {text=tostring(sub.count), pen=gui.CYAN},
            {text=" items (" .. ui_format_value(sub.value) .. ")", pen=gui.GREEN}
        })

        local groups = {}
        for _, item in ipairs(sub.items) do
            local name = get_generic_description(item)
            groups[name] = groups[name] or { count = 0, value = 0, items = {} }
            groups[name].count = groups[name].count + 1
            groups[name].value = groups[name].value + item:getCurrencyValue(nil)
            table.insert(groups[name].items, item)
        end

        local keys = {}
        for k in pairs(groups) do table.insert(keys, k) end
        table.sort(keys)

        for _, name in ipairs(keys) do
            local g = groups[name]
            table.insert(choices, {
                text = {
                    {text=string.format("%-35s", name)}, 
                    {text=string.format("%8d", g.count), pen=gui.CYAN}, 
                    {text=string.format(" (%s)", ui_format_value(g.value)), pen=gui.GREEN}
                },
                group_name = name,
                group_items = g.items
            })
        end

    elseif self.view_mode == 'ITEMS' then
        self.subviews.path_label:setText({
            {text="Items in Group: " .. self.current_group_name .. " | ", pen=gui.YELLOW},
            {text=tostring(#self.current_group_items), pen=gui.CYAN},
            {text=" items", pen=gui.GREEN}
        })

        for _, item in ipairs(self.current_group_items) do
            table.insert(choices, {
                text = {
                    {text=string.format("%-45s", dfhack.items.getReadableDescription(item))}, 
                    {text=string.format("%8d", item:getCurrencyValue(nil)), pen=gui.GREEN}
                },
                item = item
            })
        end
    end
    list:setChoices(choices)
end

function PivotWindow:on_list_submit(idx, choice)
    if self.view_mode == 'CLASS' then
        self.current_class_id = choice.class_id
        self.view_mode = 'SUBCLASS'
    elseif self.view_mode == 'SUBCLASS' then
        self.current_sub_id = choice.sub_id
        self.view_mode = 'GROUPED'
    elseif self.view_mode == 'GROUPED' then
        self.current_group_name = choice.group_name
        self.current_group_items = choice.group_items
        self.view_mode = 'ITEMS'
    end
    self:refresh_list()
end

function PivotWindow:go_back()
    if self.view_mode == 'ITEMS' then
        self.view_mode = 'GROUPED'
    elseif self.view_mode == 'GROUPED' then
        self.view_mode = 'SUBCLASS'
    elseif self.view_mode == 'SUBCLASS' then
        self.view_mode = 'CLASS'
    else
        self.parent_view:dismiss()
        return
    end
    self:refresh_list()
end

-- EXPORT: Attach the Screen wrapper to the M table
local PivotScreen = defclass(nil, gui.ZScreen)
PivotScreen.ATTRS {
    focus_path = 'pivot-inventory',
    items = DEFAULT_NIL,
}

function PivotScreen:init()
    self:addviews{
        PivotWindow{
            items = self.items
        }
    }
end

M.PivotScreen = PivotScreen
return M
