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
-- PART 2: UI CLASSES (PivotPane and PivotScreen)
---------------------------------------------------------------------------
local function format_value(val)
    if val >= 1000000 then return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then return string.format("%.1fk", val / 1000)
    else return tostring(val) end
end

PivotPane = defclass(PivotPane, widgets.Panel)
PivotPane.ATTRS = { title = "Inventory", items = DEFAULT_NIL, on_submit = DEFAULT_NIL }

function PivotPane:init(args)
    self.hierarchy_data = self:process_items(args.items or {})
    self.view_mode = 'CLASS'
    
    -- We define the subviews directly as a table
    -- This avoids the need to call the add_views method
    self.subviews = {
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
            on_submit = self:callback('on_list_submit') 
        }
    }
    
    -- After manually setting subviews, we trigger the internal update
    -- if self.updateLayout then self:updateLayout() end
    -- self:refresh_list()
end

function PivotPane:process_items(items)
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

function PivotPane:refresh_list()
    local choices = {}
    if self.view_mode == 'CLASS' then
        self.subviews.path_label:setText("Whole Inventory")
        for id, info in pairs(self.hierarchy_data) do
            table.insert(choices, { text = {{text=id, width=15}, {text=tostring(info.count), pen=gui.CYAN}}, class_id = id })
        end
    elseif self.view_mode == 'SUBCLASS' then
        local info = self.hierarchy_data[self.current_class_id]
        for id, sub in pairs(info.subclasses) do
            table.insert(choices, { text = {{text=id, width=15}, {text=tostring(sub.count), pen=gui.CYAN}}, sub_id = id })
        end
    end
    self.subviews.item_list:setChoices(choices)
end

function PivotPane:on_list_submit(idx, choice)
    if self.view_mode == 'CLASS' then
        self.current_class_id = choice.class_id
        self.view_mode = 'SUBCLASS'
    elseif self.view_mode == 'SUBCLASS' then
        self.current_sub_id = choice.sub_id
        self.view_mode = 'ITEMS'
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
    return false -- Tells the screen we are at the top level
end


PivotScreen = defclass(PivotScreen, gui.FramedScreen)
PivotScreen.ATTRS = { frame_title = "Pivot Inventory", left_items = DEFAULT_NIL, is_trade = false }

function PivotScreen:init(args)
    self.subviews = {
        widgets.Panel{
            view_id = 'main_panel',
            subviews = {
                PivotPane{ 
                    view_id = 'left_pane', 
                    title = "Stocks", 
                    items = self.left_items, 
                    frame = {t=0, l=0, w=35, b=2} 
                },
                widgets.Label{ 
                    frame = {b=0, l=0}, 
                    text = "Esc: Back | Enter: Select" 
                }
            }
        }
    }
end

function PivotScreen:onInput(keys)
    -- This is the critical check for closing the window
    if keys.LEAVESCREEN or keys.BACKSPACE then
        -- First, try to let the pane go back a level (e.g., Items -> Subclass)
        if not self.subviews.left_pane:go_back() then
            -- If the pane is already at the Root level, close the whole screen
            self:dismiss()
        end
        return true -- Tell the game we handled the key
    end

    -- Send all other keys (like arrows/Enter) to the base FramedScreen logic
    -- This allows the List widget to scroll properly
    return PivotScreen.super.onInput(self, keys)
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
    print("Launching Pivot Trade...")
    local fort_items, caravan_items = get_trade_items()
    local items_to_show = fort_items or get_all_fort_items()
    
    if #items_to_show == 0 then
        qerror("No items found!")
    end

    PivotScreen{
        frame_title = fort_items and "Pivot Trade" or "Pivot Stocks",
        left_items = items_to_show,
        is_trade = (fort_items ~= nil)
    }:show()
end

main()