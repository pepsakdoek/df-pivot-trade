local gui = require('gui')
dfhack.printerr('loading pivot_trade_ui.lua')
local pivot_ui = reqscript('pivot_trade_ui')

function get_trade_items()
    local screen = dfhack.gui.getCurViewscreen()
    if not df.viewscreen_tradegoodsst:is_instance(screen) then
        return nil, nil
    end
    
    local fort_items = {}
    local caravan_items = {}
    
    -- In viewscreen_tradegoodsst:
    -- broker_items is usually the fort's items
    -- trader_items is the caravan's items
    for _, info in ipairs(screen.broker_items) do
        table.insert(fort_items, info.item)
    end
    for _, info in ipairs(screen.trader_items) do
        table.insert(caravan_items, info.item)
    end
    
    return fort_items, caravan_items
end

function get_all_fort_items()
    local items = {}
    for _, item in ipairs(df.global.world.items.all) do
        if dfhack.items.isOwnedByFortress(item) and not item.flags.trader then
            table.insert(items, item)
        end
    end
    return items
end

function main()
    dfhack.printerr("starting main()")
    local fort_items, caravan_items = get_trade_items()
    
    if fort_items then
        print("Depot has items")
        -- We are in the trade screen
        pivot_ui.PivotScreen{
            frame_title = "Pivot Trade",
            left_title = "Fortress Goods",
            left_items = fort_items,
            right_title = "Caravan Goods",
            right_items = caravan_items,
            is_trade = true
        }:show()
    else
        -- Not in trade screen, check if we should show stocks
        -- For testing, we'll just show all fort items
        print("Showing stocks screen")
        local all_items = get_all_fort_items()
        if #all_items == 0 then
            qerror("No items found to display!")
        end
        
        pivot_ui.PivotScreen{
            frame_title = "Pivot Stocks",
            left_title = "Fortress Stocks",
            left_items = all_items,
            is_trade = false
        }:show()
    end
end

if not dfhack_flags.module then
    main()
end
