-- pivot_trade_ui.lua
-- UI implementation for the DFHack Pivot UI
dfhack.printerr('inside pivot_trade_ui.lua')
local gui = require('gui')
local widgets = require('gui.widgets')
dfhack.printerr('loading item_classifier.lua')
local classifier = reqscript('item_classifier')


PivotPane = defclass(PivotPane, widgets.Panel)
PivotPane.ATTRS = {
    title = "Inventory",
    items = DEFAULT_NIL,
    on_submit = DEFAULT_NIL,
}

function PivotPane:init(args)
    self.hierarchy_data = self:process_items(args.items or {})
    self.view_mode = 'CLASS' -- 'CLASS', 'SUBCLASS', 'ITEMS'
    self.current_class_id = nil
    self.current_sub_id = nil

    self:add_views{
        widgets.Label{
            view_id = 'title_label',
            frame = {t=0, l=0},
            text = self.title,
            text_pen = gui.CYAN
        },
        widgets.Label{
            view_id = 'path_label',
            frame = {t=1, l=0},
            text = "Root"
        },
        widgets.List{
            view_id = 'item_list',
            frame = {t=3, l=0, r=0, b=0},
            on_submit = self:callback('on_list_submit'),
        }
    }
    self:refresh_list()
end

function PivotPane:process_items(items)
    local data = {}
    for _, item in ipairs(items) do
        local class_id, sub_id = classifier.classify_item(item)
        data[class_id] = data[class_id] or { count = 0, value = 0, subclasses = {} }
        data[class_id].subclasses[sub_id] = data[class_id].subclasses[sub_id] or { count = 0, value = 0, items = {} }
        
        local val = item:getTotalValue()
        data[class_id].count = data[class_id].count + 1
        data[class_id].value = data[class_id].value + val
        
        local sub = data[class_id].subclasses[sub_id]
        sub.count = sub.count + 1
        sub.value = sub.value + val
        table.insert(sub.items, item)
    end
    return data
end

local function format_value(val)
    if val >= 1000000 then return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then return string.format("%.1fk", val / 1000)
    else return tostring(val) end
end

function PivotPane:refresh_list()
    local list_widget = self.subviews.item_list
    local choices = {}
    
    if self.view_mode == 'CLASS' then
        self.subviews.path_label:setText("Whole Inventory")
        local sorted_classes = {}
        for id, _ in pairs(self.hierarchy_data) do table.insert(sorted_classes, id) end
        table.sort(sorted_classes)
        
        for _, id in ipairs(sorted_classes) do
            local info = self.hierarchy_data[id]
            table.insert(choices, {
                text = {
                    {text=string.format("%-15s", id), width=15},
                    {text=string.format(" %3d", info.count), width=4, pen=gui.CYAN},
                    {text=string.format(" %6s", format_value(info.value)), width=7, pen=gui.GOLD}
                },
                class_id = id
            })
        end
    elseif self.view_mode == 'SUBCLASS' then
        local class_id = self.current_class_id
        self.subviews.path_label:setText("> " .. class_id)
        local info = self.hierarchy_data[class_id]
        
        local sorted_subs = {}
        for id, _ in pairs(info.subclasses) do table.insert(sorted_subs, id) end
        table.sort(sorted_subs)
        
        for _, id in ipairs(sorted_subs) do
            local sub = info.subclasses[id]
            table.insert(choices, {
                text = {
                    {text=string.format("%-15s", id), width=15},
                    {text=string.format(" %3d", sub.count), width=4, pen=gui.CYAN},
                    {text=string.format(" %6s", format_value(sub.value)), width=7, pen=gui.GOLD}
                },
                sub_id = id
            })
        end
    elseif self.view_mode == 'ITEMS' then
        local class_id = self.current_class_id
        local sub_id = self.current_sub_id
        self.subviews.path_label:setText(">> " .. sub_id)
        local items = self.hierarchy_data[class_id].subclasses[sub_id].items
        
        for _, item in ipairs(items) do
            local desc = dfhack.items.getDescription(item, 0)
            table.insert(choices, {
                text = {
                    {text=string.format("%-20s", desc:sub(1,20)), width=20},
                    {text=string.format(" %6s", format_value(item:getTotalValue())), width=7, pen=gui.GOLD}
                },
                item = item
            })
        end
    end
    
    list_widget:setChoices(choices)
end

function PivotPane:on_list_submit(idx, choice)
    if self.view_mode == 'CLASS' then
        self.current_class_id = choice.class_id
        self.view_mode = 'SUBCLASS'
    elseif self.view_mode == 'SUBCLASS' then
        self.current_sub_id = choice.sub_id
        self.view_mode = 'ITEMS'
    elseif self.view_mode == 'ITEMS' then
        if self.on_submit then self.on_submit(choice.item) end
    end
    self:refresh_list()
end

function PivotPane:go_back()
    if self.view_mode == 'ITEMS' then
        self.view_mode = 'SUBCLASS'
        self:refresh_list()
        return true
    elseif self.view_mode == 'SUBCLASS' then
        self.view_mode = 'CLASS'
        self:refresh_list()
        return true
    end
    return false
end

PivotScreen = defclass(PivotScreen, gui.FramedScreen)
PivotScreen.ATTRS = {
    frame_title = "Pivot Inventory",
    left_title = "Fortress",
    left_items = DEFAULT_NIL,
    right_title = "Caravan",
    right_items = DEFAULT_NIL,
    is_trade = false
}

function PivotScreen:init(args)
    self:add_views{
        widgets.Panel{
            view_id = 'main_panel',
            subviews = {
                PivotPane{
                    view_id = 'left_pane',
                    title = self.left_title,
                    items = self.left_items,
                    frame = {t=0, l=0, w=35, b=2},
                    on_submit = function(item) self:toggle_item(item) end
                },
                PivotPane{
                    view_id = 'right_pane',
                    title = self.right_title,
                    items = self.right_items,
                    frame = {t=0, r=0, w=35, b=2},
                    on_submit = function(item) self:toggle_item(item) end,
                    visible = self.is_trade
                },
                widgets.Label{
                    view_id = 'footer',
                    frame = {b=0, l=0},
                    text = {
                        {key='SELECT', text=': Enter, '},
                        {key='BACK', text=': Esc/Backspace, '},
                        {text='Tab: Switch Pane'}
                    }
                }
            }
        }
    }
    self.active_pane = self.subviews.left_pane
    self.subviews.left_pane:setFocus(true)
end

function PivotScreen:toggle_item(item)
    if not self.is_trade then return end
    -- Real trade toggle logic would go here
    dfhack.gui.showAnnouncement("Toggled: " .. dfhack.items.getDescription(item, 0), COLOR_WHITE)
end

function PivotScreen:onInput(keys)
    if keys.LEAVESCREEN or keys.BACKSPACE then
        if not self.active_pane:go_back() then
            self:dismiss()
        end
        return true
    end
    if keys.STANDARDSCROLL_RIGHT or keys.STANDARDSCROLL_LEFT or keys.SELECT_ALL then -- Tab or Arrows
        if self.is_trade then
            self.active_pane:setFocus(false)
            if self.active_pane == self.subviews.left_pane then
                self.active_pane = self.subviews.right_pane
            else
                self.active_pane = self.subviews.left_pane
            end
            self.active_pane:setFocus(true)
            return true
        end
    end
    return PivotScreen.super.onInput(self, keys)
end

return {
    PivotPane = PivotPane,
    PivotScreen = PivotScreen
}