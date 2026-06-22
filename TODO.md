# TODO

* Zoom doesn't work on the stock view (and it does work on the old discord implementation)
-- That implementation
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

* Also create a function to open the 'item' page for the item. Lets call it Item Sheet
-- AI generated possible code for that feature (would need testing if it's at all possible to do)
local item = df.item.find(12345) -- Replace with your item ID
if item then
    dfhack.gui.showItemDescription(item)
else
    qerror("Item not found.")
end

* Remove pivot_trade_ui traces and only use the new pivot_trade_ui2