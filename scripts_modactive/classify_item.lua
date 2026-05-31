--@ module = true
local gui = require('gui')
local widgets = require('gui.widgets')
local textures = require('gui.textures')
local classifier = reqscript('internal/pivot_trade/item_classifier')
local common = reqscript('internal/pivot_trade/common')

-------------------------------------------------------------------------------
-- Crash-Proofed Selection Logic
-------------------------------------------------------------------------------
local function get_selected_item()
    -- 1. Check modern UI Sheets safely via pcall to prevent structure-mismatch crashes
    local ok, item = pcall(function()
        local interface = df.global.game.main_interface
        
        -- Check generic item sheet (boulders, logs, rocks)
        if interface.item_sheet and interface.item_sheet.item then
            return interface.item_sheet.item
        end
        
        -- Check view_sheets interface (weapons, armor, trade goods)
        if interface.view_sheets and interface.view_sheets.viewing_item and interface.view_sheets.item then
            return interface.view_sheets.item
        end
        
        return nil
    end)
    if ok and item then return item end

    -- 2. Standard DFHack UI helper (Stocks, lists, trade depot screens, etc.)
    local dfhack_item = dfhack.gui.getSelectedItem(true)
    if dfhack_item then return dfhack_item end

    -- 3. Check hover/look interface
    if df.global.ui_look_target and df.global.ui_look_target.item then
        return df.global.ui_look_target.item
    end

    -- 4. Classic Map Cursor fallback
    if dfhack.gui.getCursorPos() then
        local item_id = df.global.world.selected_item_id
        if item_id and item_id >= 0 then
            return df.item.find(item_id)
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- UI Popup Component
-------------------------------------------------------------------------------
local ClassifyPopup = defclass(ClassifyPopup, gui.ZScreenModal)
ClassifyPopup.ATTRS {
    focus_path = 'classify_item_poc',
}

function ClassifyPopup:init(args)
    local item = args.item
    local name = dfhack.items.getReadableDescription(item)
    local value = common.get_perceived_value(item, nil)
    local class, subclass = classifier.classify_item(item)

    self:addviews{
        widgets.Window{
            frame_title = 'Item Classification POC',
            frame = {w = 80, h = 32}, 
            resizable = true,
            resize_min = {w = 50, h = 22},
            subviews = {
                widgets.Panel{
                    frame = {t = 0, l = 0, r = 0, b = 2},
                    subviews = {
                        
                        -- 1. TOP SECTION: Dynamic Graphics Area (Lines 0 to 4)
                        widgets.Panel{
                            view_id = 'graphic_area',
                            frame = {t = 0, l = 0, r = 0, h = 4},
                            on_render_body = function(dc)
                                -- Background backdrop fill
                                for x = 0, dc.width - 1 do
                                    for y = 0, 2 do
                                        dc:seek(x, y):char(32, {bg = COLOR_BLACK})
                                    end
                                end

                                -- Draw horizontal boundary strip below the sprite canvas
                                for x = 0, dc.width - 1 do
                                    dc:seek(x, 3):char(string.byte('-'), COLOR_GREY)
                                end

                                -- Get the actual premium engine texture 
                                local texpos = textures.getItemTexpos(item)
                                dc:seek(2, 1) -- Position the item preview on the canvas

                                if texpos and texpos >= 0 then
                                    -- Correct drawing logic for modern graphics engine
                                    dc:char(32) -- Clear character mask first
                                    dc:tile(32, texpos, true) -- Blit premium graphics asset
                                    
                                    dc:seek(5, 1):string("[Premium Graphics Engine]", COLOR_YELLOW)
                                else
                                    -- Text-mode character fallback
                                    dc:char(item:getChar(), {fg = item:getColor(), bg = 0})
                                    dc:seek(5, 1):string("[ASCII Text Fallback]", COLOR_RED)
                                end
                            end
                        },

                        -- 2. BOTTOM SECTION: Data text fields (Pushed to start at Line 5)
                        widgets.Label{
                            view_id = 'details_label',
                            frame = {t = 5, l = 0, r = 0}, -- Starts clean from line 5 down
                            text = {
                                {text = 'Name:  ', pen = COLOR_GREY}, {text = name, pen = COLOR_WHITE}, NEWLINE,
                                {text = 'Value: ', pen = COLOR_GREY}, {text = dfhack.formatInt(value), pen = COLOR_GREEN}, NEWLINE,
                                {text = 'Class: ', pen = COLOR_GREY}, {text = class, pen = COLOR_CYAN}, NEWLINE,
                                {text = 'Sub:   ', pen = COLOR_GREY}, {text = subclass, pen = COLOR_BLUE}, NEWLINE,
                                NEWLINE,
                                {text = 'Debug Info:', pen = COLOR_YELLOW}, NEWLINE,
                                {text = 'Type:    ', pen = COLOR_GREY}, 
                                {text = function() return tostring(df.item_type[item:getType()]) end, pen = COLOR_WHITE}, NEWLINE,
                                {text = 'Basic Ch:', pen = COLOR_GREY},
                                {text = function() 
                                    local ok, res = pcall(function() return item:getBasicSprite() end)
                                    if ok then return tostring(res) end
                                    ok, res = pcall(dfhack.items.getItemBasicSprite, item)
                                    return ok and tostring(res) or 'err'
                                end, pen = COLOR_WHITE}, 
                            }
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