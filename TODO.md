# TODO

* Added "Elf friendly" flag for the stock screen
* Valuation differs from Trade view (file pivot_trade_ui.lua in 79dde33c43083f54e57ced4481c882668ea56e66)
 * Merchant appraisal skill? Or Deals in place
 * Common has a getPerceivedValue function which I am pretty sure I'm not using

```
local mer = trade.open and trade.mer or nil
common.get_perceived_value(item, mer) 
```