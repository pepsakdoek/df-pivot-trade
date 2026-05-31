--@ module = true
local gui = require('gui')
local widgets = require('gui.widgets')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local common = reqscript('internal/pivot_trade/common')

local function get_selected_item()
    -- Standard DFHack way to get selected item in most lists (Stocks, etc.)
    local item = dfhack.gui.getSelectedItem(true)
    if item then return item end

    -- Fallback: check if an item is being inspected in the UI (Steam version)
    if df.global.game.main_interface.view_sheets.viewing_item then
        return df.global.game.main_interface.view_sheets.viewing_item
    end

    -- Fallback: check if the map cursor is over an item
    local item_id = df.global.world.selected_item_id
    if item_id >= 0 then
        return df.item.find(item_id)
    end

    return nil
end
-- ... Keep your top imports and get_selected_item / debug helper functions completely the same ...

local ClassifyPopup = defclass(ClassifyPopup, gui.ZScreenModal)
ClassifyPopup.ATTRS {
    focus_path = 'classify_item_poc',
}

function ClassifyPopup:init(args)
    local item = args.item
    local name = dfhack.items.getReadableDescription(item)
    local value = common.get_perceived_value(item, nil)
    local class, subclass = classifier.classify_item(item)

    -- [Keep your local get_methods, get_pages, and get_mat_gfx logic functions right here]

    self:addviews{
        widgets.Window{
            frame_title = 'Item Classification POC',
            frame = {w = 80, h = 32}, 
            resizable = true,          -- Makes the main UI window drag-resizable by mouse!
            resize_min = {w = 50, h = 20},
            subviews = {
                -- Explicit Layout Wrapper to split Left and Right columns cleanly
                widgets.Panel{
                    frame = {t = 0, l = 0, r = 0, b = 2},
                    subviews = {
                        -- LEFT SIDE: Left column dedicated cleanly to text data
                        widgets.Label{
                            view_id = 'details_label',
                            frame = {t = 0, l = 0, w = 45}, -- Locks text to the left 45 text-columns
                            text = {
                                {text = 'Name:  ', pen = COLOR_GREY}, {text = name, pen = COLOR_WHITE}, NEWLINE,
                                {text = 'Value: ', pen = COLOR_GREY}, {text = dfhack.formatInt(value), pen = COLOR_GREEN}, NEWLINE,
                                {text = 'Class: ', pen = COLOR_GREY}, {text = class, pen = COLOR_CYAN}, NEWLINE,
                                {text = 'Sub:   ', pen = COLOR_GREY}, {text = subclass, pen = COLOR_BLUE}, NEWLINE,
                                NEWLINE,
                                {text = 'Debug Info:', pen = COLOR_YELLOW}, NEWLINE,
                                {text = 'Type:    ', pen = COLOR_GREY}, 
                                {text = function() return tostring(df.item_type[args.item:getType()]) end, pen = COLOR_WHITE}, NEWLINE,
                                {text = 'Basic Ch:', pen = COLOR_GREY},
                                {text = function() 
                                    local ok, res = pcall(function() return args.item:getBasicSprite() end)
                                    if ok then return tostring(res) end
                                    ok, res = pcall(dfhack.items.getItemBasicSprite, args.item)
                                    return ok and tostring(res) or 'err'
                                end, pen = COLOR_WHITE}, 
                                {gap = 2, text = 'findGraphicsTile: ', pen = COLOR_GREY},
                                {text = function() return tostring(dfhack.screen.findGraphicsTile ~= nil) end, pen = COLOR_WHITE}, NEWLINE,
                                {text = 'Mat Gfx: ', pen = COLOR_GREY},
                                --{text = get_mat_gfx(args.item)}, NEWLINE,
                                NEWLINE,
                                {text = 'Loaded Pages:', pen = COLOR_YELLOW}, NEWLINE,
                                --{text = get_pages(), w = 43}, NEWLINE,
                            }
                        },
                        
                        -- RIGHT SIDE: Graphic display box anchored to the right side wall
                        widgets.Panel{
                            view_id = 'graphic_area',
                            frame = {t = 0, r = 2, w = 25, h = 10}, -- Anchored via 'r = 2' (Right side)
                            on_render_body = function(dc)
                                -- Define visual canvas frame variables
                                local box_w, box_h = 7, 5
                                
                                -- Clear out a dark visual backdrop context block
                                for y = 0, box_h - 1 do
                                    for x = 0, box_w - 1 do
                                        dc:seek(x, y):char(32, {bg = COLOR_BLACK})
                                    end
                                end

                                -- Draw explicit text box borders (+-----+)
                                for x = 0, box_w - 1 do
                                    dc:seek(x, 0):char(string.byte('-'), COLOR_GREY)
                                    dc:seek(x, box_h - 1):char(string.byte('-'), COLOR_GREY)
                                end
                                for y = 0, box_h - 1 do
                                    dc:seek(0, y):char(string.byte('|'), COLOR_GREY)
                                    dc:seek(box_w - 1, y):char(string.byte('|'), COLOR_GREY)
                                end
                                dc:seek(0, 0):char(string.byte('+'), COLOR_GREY)
                                dc:seek(box_w - 1, 0):char(string.byte('+'), COLOR_GREY)
                                dc:seek(0, box_h - 1):char(string.byte('+'), COLOR_GREY)
                                dc:seek(box_w - 1, box_h - 1):char(string.byte('+'), COLOR_GREY)

                                -- Asset Cascade lookup
                                local texpos = nil
                                local src_lbl = "None"

                                local item_type = args.item:getType()
                                local item_subtype = args.item:getSubtype()
                                texpos = dfhack.items.getSubtypeTile(item_type, item_subtype)
                                if texpos and texpos > 0 then src_lbl = "Subtype" end

                                if not texpos or texpos <= 0 then
                                    texpos = dfhack.screen.findGraphicsTile('ITEMS', 0, 0)
                                    if texpos and texpos > 0 then src_lbl = "ITEMS" end
                                end

                                if not texpos or texpos <= 0 then
                                    texpos = dfhack.screen.findGraphicsTile('CURSORS', 0, 0)
                                    if texpos and texpos > 0 then src_lbl = "CURSORS" end
                                end

                                -- Blit standard output string inside the box boundaries
                                if texpos and texpos > 0 then
                                    dc:seek(2, 2):string(' ', {
                                        ch = 32,
                                        tile = texpos,
                                        fg = args.item:getColor(),
                                        bg = 0,
                                        use_tile = true
                                    })
                                    dc:seek(0, box_h):string(src_lbl, COLOR_YELLOW)
                                else
                                    dc:seek(3, 2):char(args.item:getChar(), {fg = args.item:getColor(), bg = 0})
                                    dc:seek(0, box_h):string("ASCII", COLOR_RED)
                                end
                            end
                        },
                    }
                },
                
                -- Bottom Window actions strip
                widgets.HotkeyLabel{
                    frame = {b = 0, r = 0},
                    label = 'Close',
                    key = 'LEAVESCREEN',
                    on_activate = function() self:dismiss() end,
                }
            }
        }
    }
end

-- Command Entry Point
if not dfhack_flags or not dfhack_flags.module then
    local item = get_selected_item()
    if not item then
        qerror('Please select an item in the game UI first (e.g., in Stocks or an inventory list).')
    end
    ClassifyPopup{item = item}:show()
end
