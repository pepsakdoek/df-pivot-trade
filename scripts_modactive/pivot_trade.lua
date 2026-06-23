--@ module = true

local ethics = reqscript('internal/pivot_trade/ethics')
local tradeoverlay = reqscript('internal/pivot_trade/tradeoverlay')
local ui2 = reqscript('internal/pivot_trade/pivot_trade_ui2')

TradeEthicsWarningOverlay = ethics.TradeEthicsWarningOverlay
PivotTradeOverlay = tradeoverlay.TradeOverlay
DrillDownTrade = ui2.DrillDownTrade
DrillDownTradeLauncher = ui2.DrillDownTradeLauncher

OVERLAY_WIDGETS = {
    ethics_warning = TradeEthicsWarningOverlay,
    drill_down = PivotTradeOverlay,
    trade_browser = DrillDownTradeLauncher,
}

function main()
    view = view and view:raise() or ui2.DrillDownTradeScreen{}:show()
end