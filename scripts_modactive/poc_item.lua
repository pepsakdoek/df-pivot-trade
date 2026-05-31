local gui = require('gui')
local widgets = require('gui.widgets')

-------------------------------------------------------
-- Helpers
-------------------------------------------------------

local function log_debug(msg)
    local f = io.open('poc_item_debug.log', 'a')
    if f then
        f:write(os.date('%H:%M:%S ') .. tostring(msg) .. '\n')
        f:close()
    end
end

-- Clear log on start
local f = io.open('poc_item_debug.log', 'w')
if f then f:close() end

local function get_items()
	return df.global.world.items.all
end

local function item_label(item)
	if not item then return 'nil' end

	local t = df.item_type[item:getType()]
	local sub = item:getSubtype() or -1

	return string.format('#%d %s:%d', item.id, t or 'UNKNOWN', sub)
end

local function item_glyph(item)
	local t = df.item_type[item:getType()]

	if t == 'WEAPON' then return 247 end
	if t == 'ARMOR' then return 5 end
	if t == 'TOOL' then return 42 end

	return 249
end

local function item_color(item)
	local mat = dfhack.matinfo.decode(item)
	if mat and mat.material then
		return mat.material.state_color or COLOR_WHITE
	end
	return COLOR_WHITE
end

local function item_graphics(item)
    if not item then return nil end
    local tile = -1
    
    -- Try virtual method first (v50+)
    local ok, res = pcall(function() return item:getGraphicsTile() end)
    if ok and res and res > 0 then return res end

    -- Fallback to items module
    ok, res = pcall(dfhack.items.getGraphicsInfo, item)
    if ok and res and res.tile and res.tile > 0 then
        return res.tile
    end

    return nil
end

-------------------------------------------------------
-- Main screen
-------------------------------------------------------

ItemInspector = defclass(ItemInspector, gui.ZScreen)
ItemInspector.ATTRS{
	focus_path = 'item_inspector',
}

function ItemInspector:init()
	self.items = get_items()
	self.selected_item = nil
    self.dirty = true

    -- Pre-create widgets for direct access
    self.glyph_label = widgets.Label{
        view_id = 'glyph',
        frame = {l = 0, t = 0, w = 4, h = 4},
    }

    self.meta_label = widgets.Label{
        view_id='meta_label',
        frame={l=0, t=0},
        text='Select an item',
    }

    self.desc_label = widgets.WrappedLabel{
        view_id='desc',
        frame={l=42, t=18, r=1, b=1},
        text='',
    }

    self.list_widget = widgets.List{
        view_id = 'list',
        frame = {l = 1, t = 1, w = 39, b = 1},
        choices = self:make_choices(),
        on_select = function(idx, choice)
            if not choice then 
                self.selected_item = nil
            else
                self.selected_item = choice.item
            end
            self.dirty = true
        end,
    }

	self:addviews{
		widgets.Window{
            view_id = 'main_window',
			frame = {w = 110, h = 40, align = gui.ALIGN_CENTER},
			frame_title = 'Fortress Item Inspector',

			subviews = {
                -- SOLID BACKGROUND FILL
                widgets.Panel{
                    frame = {l=0, r=0, t=0, b=0},
                    on_render = function(dc)
                        dc:fill(0, 0, dc.width-1, dc.height-1, dfhack.pen.parse{ch=32, bg=COLOR_BLACK})
                    end
                },

				------------------------------------------------
				-- LEFT: LIST
				------------------------------------------------
				self.list_widget,

                -- Vertical divider
                widgets.Panel{
                    frame = {l = 40, t = 0, w = 1, b = 0},
                    frame_style = gui.FRAME_INTERIOR,
                },

				------------------------------------------------
				-- CENTER: GLYPH BORDER
				------------------------------------------------
                widgets.Panel{
                    frame = {l = 41, t = 1, w = 6, h = 6},
                    frame_style = gui.FRAME_INTERIOR,
                    subviews = {
                        self.glyph_label,
                    }
                },

				------------------------------------------------
				-- RIGHT: META
				------------------------------------------------
                widgets.Panel{
                    frame = {l = 48, t = 1, r = 1, h = 16},
                    frame_style = gui.FRAME_INTERIOR,
                    subviews = {
                        self.meta_label,
                    }
                },

				------------------------------------------------
				-- BOTTOM: DESCRIPTION
				------------------------------------------------
                self.desc_label,
			},
		},
	}

    log_debug('ItemInspector initialized. Items found: ' .. #self.items)
end

function ItemInspector:update_ui()
    local item = self.selected_item
    if not item then return end

    log_debug('Updating UI for item: ' .. item.id)

    -- Update Graphics
    local tile = item_graphics(item)
    local glyph = item_glyph(item)
    local fg = item_color(item)

    if tile then
        log_debug('Setting tile: ' .. tile)
        self.glyph_label:setText({{tile=tile, text=string.char(glyph), pen={fg=fg, bg=COLOR_BLACK}}})
    else
        log_debug('Setting glyph: ' .. glyph)
        self.glyph_label:setText({{text=string.char(glyph), pen={fg=fg, bg=COLOR_BLACK}}})
    end

    -- Update Meta
	local mat = dfhack.matinfo.decode(item)
	local meta = {
		'ID: ' .. item.id,
		'Type: ' .. df.item_type[item:getType()],
		'Subtype: ' .. tostring(item:getSubtype()),
	}
	if mat then
		table.insert(meta, 'Material: ' .. mat:getToken())
	end
    self.meta_label:setText(table.concat(meta, '\n'))

    -- Update Desc
    self.desc_label:setText(dfhack.items.getReadableDescription(item))
end

function ItemInspector:onRenderFrame()
    if self.dirty then
        self:update_ui()
        self.dirty = false
    end
end

-------------------------------------------------------
-- Run
-------------------------------------------------------

view = ItemInspector{}
view:show()