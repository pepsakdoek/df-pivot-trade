-- pivot_trade.lua (Unified Version)
local gui = require('gui')
local widgets = require('gui.widgets')
local dfhack = require('dfhack')
local df = df

---------------------------------------------------------------------------
-- PART 1: ITEM CLASSIFIER LOGIC
---------------------------------------------------------------------------
local predicates = {
    weapon_skill_sword = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and df.job_skill[def.skill_melee] == 'FORMS_SWORD'
    end,
    weapon_skill_axe = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and df.job_skill[def.skill_melee] == 'FORMS_AXE'
    end,
    weapon_skill_polearm = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and (df.job_skill[def.skill_melee] == 'FORMS_SPEAR' or df.job_skill[def.skill_melee] == 'FORMS_PIKE')
    end,
    weapon_skill_blunt = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and (df.job_skill[def.skill_melee] == 'FORMS_MACE' or df.job_skill[def.skill_melee] == 'FORMS_HAMMER')
    end,
    weapon_skill_dagger = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and df.job_skill[def.skill_melee] == 'FORMS_DAGGER'
    end,
    weapon_skill_ranged = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        return def and (df.job_skill[def.skill_ranged] ~= 'NONE')
    end,
    weapon_skill_throwing = function(item)
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        if not def then return false end
        return df.job_skill[def.skill_melee] == 'THROW' or df.job_skill[def.skill_ranged] == 'THROW'
    end,
    
    material_is_metal = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isMetal() end,
    material_is_stone = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isStone() end,
    material_is_wood = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isWood() end,
    material_is_glass = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isGlass() end,
    material_is_leather = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isLeather() end,
    material_is_cloth = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isCloth() end,
    material_is_bone_or_shell = function(item) 
        local mat = dfhack.matinfo.decode(item)
        return mat and (mat.material.flags.BONE or mat.material.flags.SHELL)
    end,

    item_is_clothing = function(item)
        if not item:isArmor() then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and (item:isClothing())
    end,

    item_is_artifact = function(item) return item.flags.artifact end,
    item_is_forbidden = function(item) return item.flags.forbidden end,
    item_has_improvements = function(item) return #item.improvements > 0 end,
}

-- The Hierarchy Definition
HIERARCHY = {
    {
        id = "Weapons",
        engine_types = {df.item_type.WEAPON},
        subclasses = {
            { id = "Swords", predicate = "weapon_skill_sword" },
            { id = "Axes", predicate = "weapon_skill_axe" },
            { id = "Polearms", predicate = "weapon_skill_polearm" },
            { id = "Blunt", predicate = "weapon_skill_blunt" },
            { id = "Daggers", predicate = "weapon_skill_dagger" },
            { id = "Ranged", predicate = "weapon_skill_ranged" },
            { id = "Thrown", predicate = "weapon_skill_throwing" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Armor",
        engine_types = {df.item_type.ARMOR, df.item_type.HELM, df.item_type.PANTS, df.item_type.GLOVES, df.item_type.SHOES, df.item_type.SHIELD},
        require = function(item) return not predicates.item_is_clothing(item) end,
        subclasses = {
            { id = "Body", item_type = df.item_type.ARMOR },
            { id = "Helms", item_type = df.item_type.HELM },
            { id = "Legwear", item_type = df.item_type.PANTS },
            { id = "Handwear", item_type = df.item_type.GLOVES },
            { id = "Footwear", item_type = df.item_type.SHOES },
            { id = "Shields", item_type = df.item_type.SHIELD },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Clothing",
        engine_types = {df.item_type.ARMOR, df.item_type.HELM, df.item_type.PANTS, df.item_type.GLOVES, df.item_type.SHOES},
        require = function(item) return predicates.item_is_clothing(item) end,
        subclasses = {
            { id = "Body", item_type = df.item_type.ARMOR },
            { id = "Headwear", item_type = df.item_type.HELM },
            { id = "Legwear", item_type = df.item_type.PANTS },
            { id = "Handwear", item_type = df.item_type.GLOVES },
            { id = "Footwear", item_type = df.item_type.SHOES },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "AmmoAndTraps",
        engine_types = {df.item_type.AMMO, df.item_type.TRAPCOMP},
        subclasses = {
            { id = "Ammo", item_type = df.item_type.AMMO },
            { id = "TrapComponents", item_type = df.item_type.TRAPCOMP },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "ToolsAndEquipment",
        engine_types = {df.item_type.TOOL, df.item_type.FLASK, df.item_type.GOBLET, df.item_type.BUCKET, df.item_type.CHAIN, df.item_type.QUIVER},
        subclasses = {
            { id = "LiquidContainers", item_types = {df.item_type.FLASK, df.item_type.GOBLET, df.item_type.BUCKET} },
            { id = "Restraints", item_type = df.item_type.CHAIN },
            { id = "Quivers", item_type = df.item_type.QUIVER },
            { id = "GeneralTools", item_type = df.item_type.TOOL },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Furniture",
        engine_types = {df.item_type.FURNITURE, df.item_type.BED, df.item_type.CHAIR, df.item_type.TABLE, df.item_type.CABINET, df.item_type.DOOR, df.item_type.GRATE, df.item_type.HATCH_COVER, df.item_type.BARS, df.item_type.WINDOW, df.item_type.STATUE, df.item_type.SLAB},
        subclasses = {
            { id = "Beds", item_type = df.item_type.BED },
            { id = "Tables", item_type = df.item_type.TABLE },
            { id = "Chairs", item_type = df.item_type.CHAIR },
            { id = "Storage", item_type = df.item_type.CABINET },
            { id = "Barriers", item_types = {df.item_type.DOOR, df.item_type.GRATE, df.item_type.HATCH_COVER, df.item_type.BARS, df.item_type.WINDOW} },
            { id = "Decorative", item_types = {df.item_type.STATUE, df.item_type.SLAB} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Containers",
        engine_types = {df.item_type.BARREL, df.item_type.BIN, df.item_type.BOX, df.item_type.BAG, df.item_type.CAGE},
        subclasses = {
            { id = "Barrels", item_type = df.item_type.BARREL },
            { id = "Bins", item_type = df.item_type.BIN },
            { id = "Boxes", item_type = df.item_type.BOX },
            { id = "Bags", item_type = df.item_type.BAG },
            { id = "Cages", item_type = df.item_type.CAGE },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "FinishedGoods",
        engine_types = {df.item_type.CRAFTS, df.item_type.TOY, df.item_type.INSTRUMENT, df.item_type.BOOK, df.item_type.SCROLL, df.item_type.SHEET},
        subclasses = {
            { id = "Crafts", item_type = df.item_type.CRAFTS },
            { id = "Toys", item_type = df.item_type.TOY },
            { id = "Instruments", item_type = df.item_type.INSTRUMENT },
            { id = "BooksAndWriting", item_types = {df.item_type.BOOK, df.item_type.SCROLL, df.item_type.SHEET} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "RawMaterials",
        engine_types = {df.item_type.BAR, df.item_type.BLOCKS, df.item_type.BOULDER, df.item_type.WOOD, df.item_type.CLOTH, df.item_type.THREAD, df.item_type.LEATHER, df.item_type.SKIN_TANNED, df.item_type.GLOB, df.item_type.POWDER_MISC, df.item_type.LIQUID_MISC},
        subclasses = {
            { id = "MetalBars", item_type = df.item_type.BAR },
            { id = "Stone", item_types = {df.item_type.BLOCKS, df.item_type.BOULDER} },
            { id = "Wood", item_type = df.item_type.WOOD },
            { id = "Textiles", item_types = {df.item_type.CLOTH, df.item_type.THREAD} },
            { id = "LeatherAndSkins", item_types = {df.item_type.LEATHER, df.item_type.SKIN_TANNED} },
            { id = "PowdersAndLiquids", item_types = {df.item_type.POWDER_MISC, df.item_type.LIQUID_MISC, df.item_type.GLOB} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "FoodAndConsumables",
        engine_types = {df.item_type.FOOD, df.item_type.DRINK, df.item_type.PLANT, df.item_type.SEEDS, df.item_type.MEAT, df.item_type.FISH, df.item_type.FISH_RAW, df.item_type.CHEESE, df.item_type.EGG, df.item_type.HONEYCOMB},
        subclasses = {
            { id = "PreparedFood", item_type = df.item_type.FOOD },
            { id = "Drinks", item_type = df.item_type.DRINK },
            { id = "Plants", item_type = df.item_type.PLANT },
            { id = "MeatAndFish", item_types = {df.item_type.MEAT, df.item_type.FISH, df.item_type.FISH_RAW} },
            { id = "DairyAndEggs", item_types = {df.item_type.CHEESE, df.item_type.EGG} },
            { id = "Seeds", item_type = df.item_type.SEEDS },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Animals",
        engine_types = {df.item_type.ANIMAL},
        subclasses = {
            { id = "CagedAnimals", item_type = df.item_type.ANIMAL },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Other",
        fallback = true,
        subclasses = {
            { id = "Miscellaneous", fallback = true }
        }
    }
}

function classify_item(item)
    if not item then return "Other", "Miscellaneous" end
    local item_type = item:getType()
    
    for _, class in ipairs(HIERARCHY) do
        local match_class = false
        if class.fallback then
            match_class = true
        elseif class.engine_types then
            for _, et in ipairs(class.engine_types) do
                if et == item_type then
                    match_class = true
                    break
                end
            end
        end
        
        if match_class and class.require then
            if not class.require(item) then
                match_class = false
            end
        end
        
        if match_class then
            for _, sub in ipairs(class.subclasses or {}) do
                local match_sub = false
                if sub.fallback then
                    match_sub = true
                elseif sub.item_type and sub.item_type == item_type then
                    match_sub = true
                elseif sub.item_types then
                    for _, et in ipairs(sub.item_types) do
                        if et == item_type then
                            match_sub = true
                            break
                        end
                    end
                elseif sub.predicate and predicates[sub.predicate] then
                    if predicates[sub.predicate](item) then
                        match_sub = true
                    end
                end
                
                if match_sub then
                    return class.id, sub.id
                end
            end
            return class.id, "Other"
        end
    end
    
    return "Other", "Miscellaneous"
end


---------------------------------------------------------------------------
-- PART 2: MODERN UI CLASSES (v50+)
---------------------------------------------------------------------------

local function ui_format_value(val)
    if val >= 1000000 then return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then return string.format("%.1fk", val / 1000)
    else return tostring(val) end
end

-- The main logic container, now a widgets.Window
PivotWindow = defclass(PivotWindow, widgets.Window)
PivotWindow.ATTRS {
    frame_title = "Pivot Inventory Explorer",
    resizable = true,
    resize_min = {w=8, h=30},
    frame = {w=70, h=40},
    -- autoarrange_subviews = true,
}

function PivotWindow:init(args)
    self.items = args.items
    self.hierarchy_data = self:process_items(args.items or {})
    self.view_mode = 'CLASS' -- 'CLASS', 'SUBCLASS', 'ITEMS'
    self.current_class_id = nil
    self.current_sub_id = nil

    self:addviews{
        widgets.Label{
            view_id = 'path_label',
            text = "Root",
            text_pen = gui.YELLOW
        },
        widgets.List{
            view_id = 'main_list',
            frame = {t=2, l=0, r=0, b=2}, -- Leave room for hotkeys at bottom
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
        local class_id, sub_id = classify_item(item)
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
    local total_count = 0
    local total_value = 0

    if self.view_mode == 'CLASS' then
        -- Calculate Grand Totals
        for _, info in pairs(self.hierarchy_data) do
            total_count = total_count + info.count
            total_value = total_value + info.value
        end
        self.subviews.path_label:setText({
            {text="Root Selection | Total: "},
            {text=tostring(total_count), pen=gui.CYAN},
            {text=" items (" .. ui_format_value(total_value) .. ")", pen=gui.GREEN}
        })
        local keys = {}
        for k in pairs(self.hierarchy_data) do table.insert(keys, k) end
        table.sort(keys)

        for _, id in ipairs(keys) do
            local info = self.hierarchy_data[id]
            table.insert(choices, {
                text = {{text=string.format("%-20s", id)}, {text=string.format("%6d", info.count), pen=gui.CYAN}, {text=string.format(" (%s)", ui_format_value(info.value)), pen=gui.GREEN}},
                class_id = id
            })
        end
    elseif self.view_mode == 'SUBCLASS' then
        local info = self.hierarchy_data[self.current_class_id]
        self.subviews.path_label:setText({
            {text="Category: " .. self.current_class_id .. " | Subtotal: "},
            {text=tostring(info.count), pen=gui.CYAN},
            {text=" items (" .. ui_format_value(info.value) .. ")", pen=gui.GREEN}
        })
        local keys = {}
        for k in pairs(info.subclasses) do table.insert(keys, k) end
        table.sort(keys)

        for _, id in ipairs(keys) do
            local sub = info.subclasses[id]
            table.insert(choices, {
                text = {{text=string.format("%-20s", id)}, {text=string.format("%6d", sub.count), pen=gui.CYAN}, {text=string.format(" (%s)", ui_format_value(sub.value)), pen=gui.GREEN}},
                sub_id = id
            })
        end
    elseif self.view_mode == 'ITEMS' then
        local sub = self.hierarchy_data[self.current_class_id].subclasses[self.current_sub_id]
        self.subviews.path_label:setText({
            {text=self.current_class_id .. " > " .. self.current_sub_id .. " | Count: "},
            {text=tostring(sub.count), pen=gui.CYAN},
            {text=" (" .. ui_format_value(sub.value) .. ")", pen=gui.GREEN}
        })

        for _, item in ipairs(sub.items) do
            table.insert(choices, {
                text = {{text=string.format("%-40s", dfhack.items.getReadableDescription(item))}, {text=string.format("%8d", item:getCurrencyValue(nil)), pen=gui.GREEN}},
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
        self.view_mode = 'ITEMS'
    end
    self:refresh_list()
end

function PivotWindow:go_back()
    if self.view_mode == 'ITEMS' then
        self.view_mode = 'SUBCLASS'
    elseif self.view_mode == 'SUBCLASS' then
        self.view_mode = 'CLASS'
    else
        self.parent_view:dismiss() -- Closes the ZScreen
        return
    end
    self:refresh_list()
end

-- The Screen Wrapper, inheriting from gui.ZScreen
PivotScreen = defclass(PivotScreen, gui.ZScreen)
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

---------------------------------------------------------------------------
-- PART 3: MAIN DATA GETTERS AND ENTRY POINT
---------------------------------------------------------------------------
function get_trade_items()
    local screen = dfhack.gui.getCurViewscreen()
   
    local is_trade = false
    if df.viewscreen_layer_trade_itemsst and df.viewscreen_layer_trade_itemsst:is_instance(screen) then
        is_trade = true
    elseif df.viewscreen_tradegoodsst and df.viewscreen_tradegoodsst:is_instance(screen) then
        is_trade = true
    end

    if not is_trade then 
        return nil, nil 
    end

    -- For v50+, grabbing items from the trade screen is actually easier 
    -- using a built-in DFHack helper that finds what's on screen
    local fort_items = {}
    local caravan_items = {}

    -- This helper looks at the lists currently visible in the UI
    for _, item in ipairs(dfhack.gui.getTradeItems()) do
        -- We can separate them by checking if the fortress owns them
        if dfhack.items.isOwnedByFortress(item) then
            table.insert(fort_items, item)
        else
            table.insert(caravan_items, item)
        end
    end

    return fort_items, caravan_items
end

function get_all_fort_items()
    local items = {}
    for _, item in ipairs(df.global.world.items.other.IN_PLAY) do
        table.insert(items, item)
    end
    return items
end

function main()
    -- test_pivot("FoodAndConsumables", nil)

    print("Launching Pivot Trade...")
    local fort_items, caravan_items = get_trade_items()
    local items_to_show = fort_items or get_all_fort_items()
    
    if #items_to_show == 0 then
        qerror("No items found!")
    end
    -- Modern ZScreen show logic
    PivotScreen{items = items_to_show}:show()
end


---------------------------------------------------------------------------
-- PART 4: TEST UTILITIES (CLI VERSION)
---------------------------------------------------------------------------

-- Formats currency for the console
function format_val(val)
    if val >= 1000000 then return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then return string.format("%.1fk", val / 1000)
    else return tostring(val) end
end

function test_pivot(target_class, target_subclass)
    local items = df.global.world.items.other.IN_PLAY
    local results = {}

    for _, item in ipairs(items) do
        local class_id, sub_id = classify_item(item)
        
        results[class_id] = results[class_id] or { count = 0, value = 0, subclasses = {} }
        results[class_id].subclasses[sub_id] = results[class_id].subclasses[sub_id] or { count = 0, value = 0, items = {} }
        
        local val = item:getCurrencyValue(nil)
        
        results[class_id].count = results[class_id].count + 1
        results[class_id].value = results[class_id].value + val
        
        local sub = results[class_id].subclasses[sub_id]
        sub.count = sub.count + 1
        sub.value = sub.value + val
        -- Store the item reference for Level 3 detail
        table.insert(sub.items, item)
    end

    -- DISPLAY LOGIC
    if not target_class then
        -- Level 1: Root
        print("\nLevel: ROOT (Categories)")
        for id, data in pairs(results) do
            print(string.format("  %-20s | Count: %-6d | Value: %s", id, data.count, format_val(data.value)))
        end
    
    elseif target_class and not target_subclass then
        -- Level 2: Subclasses
        local data = results[target_class]
        if not data then print("Category not found.") return end
        
        print("\nLevel: " .. target_class)
        for sub_id, sub_data in pairs(data.subclasses) do
            print(string.format("  %-20s | Count: %-6d | Value: %s", sub_id, sub_data.count, format_val(sub_data.value)))
        end

    elseif target_class and target_subclass then
        -- Level 3: Individual Item Detail
        local class_data = results[target_class]
        local sub_data = class_data and class_data.subclasses[target_subclass]
        
        if not sub_data then 
            print(string.format("No items found for %s > %s", target_class, target_subclass))
            return 
        end
        
        print(string.format("\nLevel: %s > %s", target_class, target_subclass))
        for _, item in ipairs(sub_data.items) do
            local name = dfhack.items.getReadableDescription(item)
            local val = item:getCurrencyValue(nil)
            print(string.format("  %-40s | Value: %d", name, val))
        end
        print(string.format("\nTotal for %s: %d items, %s value", target_subclass, sub_data.count, format_val(sub_data.value)))
    end
end

main()