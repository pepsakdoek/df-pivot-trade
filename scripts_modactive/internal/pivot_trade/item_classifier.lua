--@ module = true
-- local M = {}

--------------------------------------------------------------------------
-- Current Issues with Classifier (and the 'Other' category):
--
-- * Leather is not under Textiles & Leather when 'trade contents only' is selected
--  * It falls under 'containers' when Trade bin with contents is selected
--  * (Classifier correctly identifies leather; issue is in UI container/content separation)
-- * Some grouped tallow meals fall under other for some reason
--  * (GLOB -> Raw Materials; FOOD -> Food & Consumables; may need investigation)
--
-- RESOLVED ISSUES:
-- * Scrolls (completed works) -> Books & Writing (via hasWriting flag)
-- * Amulets, Bracelets, Rings, Earrings, Crowns, Sceptres -> Jewelry & Accessories
-- * Bodies (CORPSE/CORPSEPIECE/REMAINS) -> Corpses & Remains
-- * Catapult/ballista/bolt thrower parts + siege ammo -> Siege Equipment
-- * Bookcases -> Furniture (via bookcase subtype predicate)
-- * Coffins -> Furniture / Burial
-- * Grates/Windows/Statues -> already in Furniture
-- * Mechanisms (TRAPPARTS) + Trap components (TRAPCOMP) + Pipe sections -> Tools & Equipment / Traps & Mechanisms
-- * Totems & Figurines -> dedicated class
-- * Pots -> Containers
-- * Dyes -> Clothing & Textiles / Dyes
-- * Milk / food-related liquids -> Food & Consumables / Liquids & Pastes
---------------------------------------------------------------------------


--------------------------------------------------------------------------
-- PART 1: ITEM CLASSIFIER LOGIC
---------------------------------------------------------------------------
local function add_subtype_id(map, id)
    if id ~= nil then map[id] = true end
end

local writing_tool_subtypes = {}
add_subtype_id(writing_tool_subtypes, dfhack.items.findSubtype('TOOL:ITEM_TOOL_SCROLL'))
add_subtype_id(writing_tool_subtypes, dfhack.items.findSubtype('TOOL:ITEM_TOOL_SCROLL_ROLLERS'))
add_subtype_id(writing_tool_subtypes, dfhack.items.findSubtype('TOOL:ITEM_TOOL_QUIRE'))

local instrument_tool_uses = {
    'INSTRUMENT',
    'INSTRUMENT_PIECE',
    'MUSICAL_INSTRUMENT',
    'PLAY_INSTRUMENT',
    'PLAY_MUSIC',
}

local function tool_def_text(def)
    if not def then return nil end
    return def.id or def.subtype_name or def.name or def.name_plural
end

local function is_rough_gem(item)
    if df.item_roughst and df.item_roughst:is_instance(item) then
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_GEM and not mat.material.flags.IS_GLASS
    end
    if item:getType() ~= df.item_type.ROUGH then return false end
    local mat = dfhack.matinfo.decode(item)
    return mat and mat.material and mat.material.flags.IS_GEM and not mat.material.flags.IS_GLASS
end

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
    material_is_glass = function(item)
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_GLASS
    end,
    material_is_leather = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isLeather() end,
    material_is_cloth = function(item) local mat = dfhack.matinfo.decode(item) return mat and mat:isCloth() end,
    material_is_bone_or_shell = function(item) 
        local mat = dfhack.matinfo.decode(item)
        return mat and (mat.material.flags.BONE or mat.material.flags.SHELL)
    end,
    material_is_gem = function(item)
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_GEM
    end,

    item_is_metal_bar = function(item)
        if item:getType() ~= df.item_type.BAR then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_METAL
    end,
    item_is_other_bar = function(item)
        if item:getType() ~= df.item_type.BAR then return false end
        local mat = dfhack.matinfo.decode(item)
        return not (mat and mat.material and mat.material.flags.IS_METAL)
    end,
    item_is_coal_bar = function(item)
        return item:getType() == df.item_type.BAR and item:getMaterial() == df.builtin_mats.COAL
    end,
    item_is_rough_gem = is_rough_gem,
    item_is_cut_gem = function(item)
        return (df.item_smallgemst and df.item_smallgemst:is_instance(item)) or
            item:getType() == df.item_type.SMALLGEM
    end,
    item_is_large_gem = function(item)
        return (df.item_gemst and df.item_gemst:is_instance(item)) or
            item:getType() == df.item_type.LARGE_GEM
    end,
    item_is_rough_glass = function(item)
        if df.item_roughst and df.item_roughst:is_instance(item) then
            local mat = dfhack.matinfo.decode(item)
            return mat and mat.material and mat.material.flags.IS_GLASS
        end
        if item:getType() ~= df.item_type.ROUGH then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_GLASS
    end,
    item_is_sheet = function(item)
        return (df.item_sheetst and df.item_sheetst:is_instance(item)) or
            item:getType() == df.item_type.SHEET
    end,
    item_is_gem_item = function(item)
        if df.item_gemst and df.item_gemst:is_instance(item) then return true end
        if df.item_smallgemst and df.item_smallgemst:is_instance(item) then return true end
        return is_rough_gem(item)
    end,
    item_is_textile_or_leather = function(item)
        local t = item:getType()
        return t == df.item_type.CLOTH or t == df.item_type.THREAD or
            t == df.item_type.LEATHER or t == df.item_type.SKIN_TANNED
    end,

    item_is_clothing = function(item)
        if not item:isArmor() then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and (item:isClothing())
    end,

    item_is_artifact = function(item) return item.flags.artifact end,
    item_is_forbidden = function(item) return item.flags.forbidden end,
    item_has_improvements = function(item) return #item.improvements > 0 end,
    item_is_writing_tool = function(item)
        if item:getType() ~= df.item_type.TOOL then return false end
        if df.item_toolst:is_instance(item) and item:hasToolUse(df.tool_uses.CONTAIN_WRITING) then
            return true
        end
        return writing_tool_subtypes[item:getSubtype()] == true
    end,
    item_is_instrument_tool = function(item)
        if item:getType() ~= df.item_type.TOOL then return false end
        if df.item_toolst:is_instance(item) then
            for _, name in ipairs(instrument_tool_uses) do
                local tool_use = df.tool_uses[name]
                if tool_use and item:hasToolUse(tool_use) then
                    return true
                end
            end
        end
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        local text = tool_def_text(def)
        if not text then return false end
        text = text:lower()
        return text:find('instrument', 1, true) ~= nil or text:find('music', 1, true) ~= nil
    end,

    item_has_writing = function(item)
        return item:hasWriting()
    end,

    item_scroll_type = function(item)
        if item:getType() == df.item_type.SCROLL then return true end
        return item:hasWriting()
    end,

    item_is_bookcase = function(item)
        if item:getType() ~= df.item_type.FURNITURE then return false end
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        local text = tool_def_text(def)
        return text and text:lower():find('bookcase', 1, true) ~= nil
    end,

    item_is_pot = function(item)
        if item:getType() ~= df.item_type.TOOL then return false end
        local def = dfhack.items.getSubtypeDef(item:getType(), item:getSubtype())
        local text = tool_def_text(def)
        return text and text:lower():find('pot', 1, true) ~= nil
    end,

    item_is_food_liquid = function(item)
        local t = item:getType()
        if t ~= df.item_type.LIQUID_MISC and t ~= df.item_type.GLOB then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and (mat.material.flags.EDIBLE_RAW or mat.material.flags.EDIBLE_COOKED)
    end,

    item_is_dye = function(item)
        if item:getType() ~= df.item_type.POWDER_MISC then return false end
        local mat = dfhack.matinfo.decode(item)
        return mat and mat.material and mat.material.flags.IS_DYE
    end,
}

-- The Hierarchy Definition
HIERARCHY = {
    {
        id = "Weapons",
        engine_types = {df.item_type.WEAPON},
        subclasses = {
            { id = "Weapons", item_type = df.item_type.WEAPON },
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
        id = "Clothing & Textiles",
        engine_types = {df.item_type.ARMOR, df.item_type.HELM, df.item_type.PANTS, df.item_type.GLOVES, df.item_type.SHOES, df.item_type.CLOTH, df.item_type.THREAD, df.item_type.LEATHER, df.item_type.SKIN_TANNED},
        match_predicate = "item_is_dye",
        require = function(item)
            return predicates.item_is_clothing(item) or predicates.item_is_textile_or_leather(item) or predicates.item_is_dye(item)
        end,
        subclasses = {
            { id = "Body", item_type = df.item_type.ARMOR },
            { id = "Headwear", item_type = df.item_type.HELM },
            { id = "Legwear", item_type = df.item_type.PANTS },
            { id = "Handwear", item_type = df.item_type.GLOVES },
            { id = "Footwear", item_type = df.item_type.SHOES },
            { id = "Textiles & Leather", predicate = "item_is_textile_or_leather" },
            { id = "Dyes", predicate = "item_is_dye" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Jewelry & Accessories",
        engine_types = {df.item_type.AMULET, df.item_type.BRACELET, df.item_type.RING, df.item_type.EARRING, df.item_type.CROWN, df.item_type.SCEPTER},
        subclasses = {
            { id = "Amulets", item_type = df.item_type.AMULET },
            { id = "Bracelets", item_type = df.item_type.BRACELET },
            { id = "Rings", item_type = df.item_type.RING },
            { id = "Earrings", item_type = df.item_type.EARRING },
            { id = "Crowns", item_type = df.item_type.CROWN },
            { id = "Scepters", item_type = df.item_type.SCEPTER },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Ammunition",
        engine_types = {df.item_type.AMMO},
        subclasses = {
            { id = "Ammo", item_type = df.item_type.AMMO },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Siege Equipment",
        engine_types = {df.item_type.CATAPULTPARTS, df.item_type.BALLISTAPARTS, df.item_type.BOLT_THROWER_PARTS, df.item_type.SIEGEAMMO, df.item_type.BALLISTAARROWHEAD},
        subclasses = {
            { id = "Siege Engines", item_types = {df.item_type.CATAPULTPARTS, df.item_type.BALLISTAPARTS, df.item_type.BOLT_THROWER_PARTS} },
            { id = "Siege Ammo", item_types = {df.item_type.SIEGEAMMO, df.item_type.BALLISTAARROWHEAD} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Books & Writing",
        engine_types = {df.item_type.BOOK, df.item_type.SCROLL, df.item_type.SHEET, df.item_type.TOOL},
        match_predicate = "item_is_sheet",
        require = function(item)
            if item:getType() ~= df.item_type.TOOL then return true end
            return predicates.item_is_writing_tool(item) or predicates.item_has_writing(item)
        end,
        subclasses = {
            { id = "Books", item_type = df.item_type.BOOK },
            { id = "Scrolls", predicate = "item_scroll_type" },
            { id = "Sheets", predicate = "item_is_sheet" },
            { id = "Writing Tools", predicate = "item_is_writing_tool" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Instruments & Parts",
        engine_types = {df.item_type.INSTRUMENT, df.item_type.TOOL},
        require = function(item)
            return item:getType() == df.item_type.INSTRUMENT or predicates.item_is_instrument_tool(item)
        end,
        subclasses = {
            { id = "Instruments", item_type = df.item_type.INSTRUMENT },
            { id = "Parts", predicate = "item_is_instrument_tool" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Containers",
        engine_types = {df.item_type.BARREL, df.item_type.BIN, df.item_type.BOX, df.item_type.BAG, df.item_type.CAGE},
        match_predicate = "item_is_pot",
        subclasses = {
            { id = "Barrels", item_type = df.item_type.BARREL },
            { id = "Bins", item_type = df.item_type.BIN },
            { id = "Boxes", item_type = df.item_type.BOX },
            { id = "Bags", item_type = df.item_type.BAG },
            { id = "Cages", item_type = df.item_type.CAGE },
            { id = "Pots", predicate = "item_is_pot" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Tools & Equipment",
        engine_types = {df.item_type.TOOL, df.item_type.FLASK, df.item_type.GOBLET, df.item_type.BUCKET, df.item_type.CHAIN, df.item_type.QUIVER, df.item_type.BACKPACK, df.item_type.SPLINT, df.item_type.CRUTCH, df.item_type.ANVIL, df.item_type.TRAPCOMP, df.item_type.TRAPPARTS, df.item_type.PIPE_SECTION},
        subclasses = {
            { id = "Liquid Containers", item_types = {df.item_type.FLASK, df.item_type.GOBLET, df.item_type.BUCKET} },
            { id = "Restraints", item_type = df.item_type.CHAIN },
            { id = "Backpacks & Quivers", item_types = {df.item_type.BACKPACK, df.item_type.QUIVER} },
            { id = "Medical", item_types = {df.item_type.SPLINT, df.item_type.CRUTCH} },
            { id = "Anvils", item_type = df.item_type.ANVIL },
            { id = "Traps & Mechanisms", item_types = {df.item_type.TRAPCOMP, df.item_type.TRAPPARTS, df.item_type.PIPE_SECTION} },
            { id = "General Tools", item_type = df.item_type.TOOL },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Furniture",
        engine_types = {df.item_type.BED, df.item_type.CHAIR, df.item_type.TABLE, df.item_type.CABINET, df.item_type.DOOR, df.item_type.GRATE, df.item_type.HATCH_COVER, df.item_type.WINDOW, df.item_type.STATUE, df.item_type.SLAB, df.item_type.COFFIN, df.item_type.FLOODGATE, df.item_type.QUERN, df.item_type.MILLSTONE, df.item_type.ARMORSTAND, df.item_type.WEAPONRACK, df.item_type.FURNITURE, df.item_type.BARS},
        subclasses = {
            { id = "Beds", item_type = df.item_type.BED },
            { id = "Tables", item_type = df.item_type.TABLE },
            { id = "Chairs", item_type = df.item_type.CHAIR },
            { id = "Storage", item_types = {df.item_type.CABINET, df.item_type.ARMORSTAND, df.item_type.WEAPONRACK} },
            { id = "Barriers", item_types = {df.item_type.DOOR, df.item_type.GRATE, df.item_type.HATCH_COVER, df.item_type.BARS, df.item_type.WINDOW, df.item_type.FLOODGATE} },
            { id = "Workshop", item_types = {df.item_type.QUERN, df.item_type.MILLSTONE} },
            { id = "Burial", item_type = df.item_type.COFFIN },
            { id = "Bookcases", predicate = "item_is_bookcase" },
            { id = "Decorative", item_types = {df.item_type.STATUE, df.item_type.SLAB} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Finished Goods",
        engine_types = {df.item_type.CRAFTS},
        subclasses = {
            { id = "Crafts", item_type = df.item_type.CRAFTS },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Toys",
        engine_types = {df.item_type.TOY},
        subclasses = {
            { id = "Toys", item_type = df.item_type.TOY },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Totems & Figurines",
        engine_types = {df.item_type.TOTEM, df.item_type.FIGURINE},
        subclasses = {
            { id = "Totems", item_type = df.item_type.TOTEM },
            { id = "Figurines", item_type = df.item_type.FIGURINE },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Gems",
        engine_types = {df.item_type.SMALLGEM, df.item_type.ROUGH, df.item_type.LARGE_GEM},
        match_predicate = "item_is_gem_item",
        require = function(item) return not predicates.item_is_rough_glass(item) end,
        subclasses = {
            { id = "Cut Gems", predicate = "item_is_cut_gem" },
            { id = "Rough Gems", predicate = "item_is_rough_gem" },
            { id = "Large Gems", predicate = "item_is_large_gem" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Raw Materials",
        engine_types = {df.item_type.BAR, df.item_type.BLOCKS, df.item_type.BOULDER, df.item_type.WOOD, df.item_type.CLOTH, df.item_type.THREAD, df.item_type.LEATHER, df.item_type.SKIN_TANNED, df.item_type.ROUGH, df.item_type.GLOB, df.item_type.POWDER_MISC, df.item_type.LIQUID_MISC},
        match_predicate = "item_is_rough_glass",
        require = function(item)
            local t = item:getType()
            if t == df.item_type.GLOB or t == df.item_type.LIQUID_MISC then
                return not predicates.item_is_food_liquid(item)
            end
            if t == df.item_type.POWDER_MISC then
                return not predicates.item_is_dye(item)
            end
            return true
        end,
        subclasses = {
            { id = "Metal Bars", predicate = "item_is_metal_bar" },
            { id = "Other Bars", predicate = "item_is_other_bar" },
            { id = "Stone", item_types = {df.item_type.BLOCKS, df.item_type.BOULDER} },
            { id = "Wood", item_type = df.item_type.WOOD },
            { id = "Glass", predicate = "item_is_rough_glass" },
            { id = "Powders & Liquids", item_types = {df.item_type.POWDER_MISC, df.item_type.LIQUID_MISC, df.item_type.GLOB} },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Food & Consumables",
        engine_types = {df.item_type.FOOD, df.item_type.DRINK, df.item_type.PLANT, df.item_type.PLANT_GROWTH, df.item_type.SEEDS, df.item_type.MEAT, df.item_type.FISH, df.item_type.FISH_RAW, df.item_type.CHEESE, df.item_type.EGG, df.item_type.HONEYCOMB, df.item_type.GLOB, df.item_type.LIQUID_MISC},
        require = function(item)
            local t = item:getType()
            if t == df.item_type.GLOB or t == df.item_type.LIQUID_MISC then
                return predicates.item_is_food_liquid(item)
            end
            return true
        end,
        subclasses = {
            { id = "Prepared Food", item_type = df.item_type.FOOD },
            { id = "Drinks", item_type = df.item_type.DRINK },
            { id = "Plants", item_types = {df.item_type.PLANT, df.item_type.PLANT_GROWTH} },
            { id = "Meat & Fish", item_types = {df.item_type.MEAT, df.item_type.FISH, df.item_type.FISH_RAW} },
            { id = "Dairy & Eggs", item_types = {df.item_type.CHEESE, df.item_type.EGG} },
            { id = "Seeds", item_type = df.item_type.SEEDS },
            { id = "Liquids & Pastes", predicate = "item_is_food_liquid" },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Animals",
        engine_types = {df.item_type.ANIMAL},
        subclasses = {
            { id = "Caged Animals", item_type = df.item_type.ANIMAL },
            { id = "Other", fallback = true }
        }
    },
    {
        id = "Corpses & Remains",
        engine_types = {df.item_type.CORPSE, df.item_type.CORPSEPIECE, df.item_type.REMAINS},
        subclasses = {
            { id = "Corpses", item_type = df.item_type.CORPSE },
            { id = "Body Parts", item_type = df.item_type.CORPSEPIECE },
            { id = "Remains", item_type = df.item_type.REMAINS },
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

        if not match_class and class.match_predicate and predicates[class.match_predicate] then
            if predicates[class.match_predicate](item) then
                match_class = true
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

-- M.classify_item = classify_item
-- return M
