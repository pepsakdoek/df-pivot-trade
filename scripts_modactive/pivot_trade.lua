--@ module = true

local ui = reqscript('internal/pivot_trade/pivot_trade_ui')

-- Keep the overlay registration at the top level so DFHack can hook into them
PivotTradeBannerOverlay = ui.PivotTradeBannerOverlay
TradeEthicsWarningOverlay = ui.TradeEthicsWarningOverlay
PivotTradeOverlay = ui.PivotTradeOverlay

OVERLAY_WIDGETS = {
    banner = PivotTradeBannerOverlay,
    ethics_warning = TradeEthicsWarningOverlay,
}

function main()
    ui.show_trade_view()
end