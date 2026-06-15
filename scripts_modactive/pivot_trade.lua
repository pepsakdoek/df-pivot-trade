--@ module = true

local gui = require('gui')
local overlay = require('plugins.overlay')
local tradeoverlay = reqscript('internal/pivot_trade/tradeoverlay')
local ethics = reqscript('internal/pivot_trade/ethics')

local main_gui = reqscript('internal/pivot_trade/pivot_trade_ui')

-- Overlay definitions must be at the top level for DFHack to register them
TradeEthicsWarningOverlay = ethics.TradeEthicsWarningOverlay
PivotTradeOverlay = tradeoverlay.TradeOverlay

PivotTradeBannerOverlay = defclass(PivotTradeBannerOverlay, overlay.OverlayWidget)
PivotTradeBannerOverlay.ATTRS{
    desc='Adds link to the trade screen to launch the DFHack trade UI.',
    default_pos={x=-31,y=-5},
    default_enabled=true,
    viewscreens={'dwarfmode/Trade/Default', 'dwarfmode/Stocks', 'dfhack/lua/caravan/trade'},
    frame={w=25, h=1},
    frame_background=gui.CLEAR_PEN,
}

function PivotTradeBannerOverlay:init()
    local function get_label()
        local focus = dfhack.gui.getCurFocus()
        -- Robust check for Stocks screen
        local stocks_open = (df.viewscreen_stocksst and df.viewscreen_stocksst:is_instance(focus)) or
                            (type(focus) == 'string' and focus:find('Stocks'))
        if stocks_open then
            return 'Pivot Stocks UI'
        end
        return 'Pivot trade UI'
    end

    self:addviews{
        widgets.TextButton{
            frame={t=0, l=0},
            label=get_label,
            key='CUSTOM_CTRL_P',
            enabled=true,
            on_activate=function() main_gui.show_trade_view() end,
        },
    }
end

function PivotTradeBannerOverlay:onInput(keys)
    if PivotTradeBannerOverlay.super.onInput(self, keys) then return true end

    if keys._MOUSE_R or keys.LEAVESCREEN then
        if main_gui.trade_view then
            main_gui.trade_view:dismiss()
        end
    end
end

OVERLAY_WIDGETS = {
    banner = PivotTradeBannerOverlay,
    trade_overlay = PivotTradeOverlay,
    ethics_warning = TradeEthicsWarningOverlay,
}

if not dfhack_flags.module then
    -- Pass the first argument to main
    main_gui.main(...)
end
