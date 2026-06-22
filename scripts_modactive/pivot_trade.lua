--@ module = true

local ui = reqscript('internal/pivot_trade/pivot_trade_ui')
local ui2 = reqscript('internal/pivot_trade/pivot_trade_ui2')

-- Keep the overlay registration at the top level so DFHack can hook into them
PivotTradeBannerOverlay = ui.PivotTradeBannerOverlay
TradeEthicsWarningOverlay = ui.TradeEthicsWarningOverlay
PivotTradeOverlay = ui.PivotTradeOverlay
DrillDownTrade = ui2.DrillDownTrade
DrillDownTradeLauncher = ui2.DrillDownTradeLauncher

OVERLAY_WIDGETS = {
    banner = PivotTradeBannerOverlay,
    ethics_warning = TradeEthicsWarningOverlay,
    drill_down = PivotTradeOverlay,
    trade_browser = DrillDownTradeLauncher,
 }

function main()
    ui.show_trade_view()
end