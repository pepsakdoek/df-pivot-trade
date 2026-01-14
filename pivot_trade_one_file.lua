-- pivot_trade.lua (Unified Version)
local gui = require('gui')
local widgets = require('gui.widgets')
local dfhack = require('dfhack')
local df = df

local item_classifier = reqscript('item_classifier')
local pivot_ui = reqscript('pivot_trade_ui')


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