--@ module = true
local M = {}

--------------------------------------------------------------------------
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

return M