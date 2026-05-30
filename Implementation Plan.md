# Migrate Caravan Methodology into df-pivot-trade

The `caravan` repo contains a significantly more advanced version of the same idea: a hierarchical, filterable, sortable trade UI. The goal is to transplant all of its logic and UI into `df-pivot-trade` while keeping the project structured as a DFHack Steam Mod (using `scripts_modactive/` and the DFHack overlay system).

---

## What We Are Migrating

The `caravan` repo is organized as a set of flat files that override internal DFHack game files. We are converting it into a proper mod-scoped module layout under `scripts_modactive/internal/pivot_trade/`, renaming the namespace from `caravan` to `pivot_trade` throughout.

### Key differences between the two repos

| Feature | df-pivot-trade (current) | caravan (source) |
|---|---|---|
| Entry UI | Basic `PivotScreen` window | Full `LuaTrade` + overlay banner + `TradeScreen` |
| Trade data source | Custom `get_trade_items()` hack | Native `df.global.game.main_interface.trade` |
| Item hierarchy | 3-level (Class > Subclass > Item) | 4-level (Class > Subclass > Grouped > Item) |
| Sorting | None | 8 sort modes with column-click cycling |
| Filtering | None | Sliders for quality, condition, value + provenance, ethics, mandates |
| Bins | Not handled | Bin-aware with separate bin/contents toggle |
| Ethics | None | Animal/tree ethics warning overlay |
| Trade overlay | None | `TradeOverlay` (shift/ctrl click on vanilla UI) |
| Broker skill | Not used | Obfuscates values based on broker appraisal skill |

---

## Proposed Changes

### New Module Layout

The mod will use a `pivot_trade` namespace under `scripts_modactive/internal/pivot_trade/`. All `reqscript('internal/caravan/...')` calls in the source become `reqscript('internal/pivot_trade/...')`.

---

### Module: `internal/pivot_trade/`

#### [MODIFY] [item_classifier.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/item_classifier.lua)
- **Replace entirely** with the version from `d:/P/caravan/item_classifier.lua`.
- The caravan version is strictly superior: more item types, glass/gem disambiguation, predicate-based classification, the `HIERARCHY` table, and exports `classify_item` properly.
- Only change: remove the `--@ module = true` line (not needed in mod scripts) and keep the `M.classify_item = classify_item; return M` pattern so `reqscript` works correctly.

#### [NEW] [common.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/common.lua)
- Copy from `d:/P/caravan/common.lua`.
- Update all `reqscript('internal/caravan/...')` → `reqscript('internal/pivot_trade/...')`.
- Contains: broker skill obfuscation, search key building, slider widgets (quality/condition/value range sliders), info panel widgets (ethics/mandates/provenance), `get_banned_items`, `get_risky_items`, `has_wood`, `scan_banned`, constants (`CH_UP`, `CH_DN`, `ALL_PEN`, `SOME_PEN`).

#### [NEW] [sorting.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/sorting.lua)
- Copy from `d:/P/caravan/sorting.lua`.
- Update all `reqscript` paths.
- Contains: all sort functions (`sort_by_status_desc`, `sort_by_value_desc`, `sort_by_class_desc`, etc.), `get_sort_level`, `get_entry_icon`, `sort_noop`.

#### [NEW] [ethics.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/ethics.lua)
- Copy from `d:/P/caravan/ethics.lua`.
- Update all `reqscript` paths and the `focus_path` strings from `caravan/...` → `pivot_trade/...`.
- Contains: `is_ethical_product`, `has_ethics_violation`, the `Ethics` window, `EthicsScreen` ZScreen, and `TradeEthicsWarningOverlay`.

#### [NEW] [predicates.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/predicates.lua)
- Copy from `d:/P/caravan/predicates.lua`.
- No path changes needed (no internal `reqscript` calls).
- Contains: `PREDICATE_LIBRARY`, `pass_predicates`, `init_context_predicates`, `make_predicate_str`.

#### [NEW] [tradeoverlay.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/tradeoverlay.lua)
- Copy from `d:/P/caravan/tradeoverlay.lua`.
- No internal `reqscript` calls.
- Contains: `TradeOverlay` OverlayWidget (shift/ctrl click helpers, collapse bins/types hotkeys).

#### [DELETE] [pivot_trade_ui.lua](file:///d:/P/df-pivot-trade/scripts_modactive/internal/pivot_trade/pivot_trade_ui.lua)
- The old basic UI (`PivotScreen`) is fully superseded by the new `LuaTrade` + `TradeScreen` + overlay approach. This file will be removed.

---

### Entry Point

#### [MODIFY] [pivot_trade.lua](file:///d:/P/df-pivot-trade/scripts_modactive/pivot_trade.lua)
- **Replace entirely** with an adapted version of `d:/P/caravan/pivottrade.lua`.
- Key adaptations:
  - All `reqscript('internal/caravan/...')` → `reqscript('internal/pivot_trade/...')`.
  - `focus_path` strings: `'caravan/trade'` → `'pivot_trade/trade'`, `'caravan/trade/ethics'` → `'pivot_trade/trade/ethics'`.
  - `TradeScreen:onRenderFrame` guard: `dfhack.gui.matchFocusString('dfhack/lua/caravan/trade')` → `dfhack.gui.matchFocusString('dfhack/lua/pivot_trade/trade')`.
  - Keep the `TradeBannerOverlay` (the in-game overlay button) — this is the main activation mechanism for players.
  - **Remove** the old `main()` call at the end (the overlay drives everything now).
  - Add a DFHack overlay registration block at the bottom so the overlays are auto-registered when the mod is active (standard DFHack mod pattern).

---

## Overlay Registration

DFHack mods that want to register overlays need to include the `DFHACK_OVERLAY_ENABLE` block. This is done by adding to `pivot_trade.lua`:

```lua
if dfhack_flags and dfhack_flags.module then
    return
end

-- Register overlays (called by DFHack when the script is loaded as a mod)
local overlay = require('plugins.overlay')
overlay.register_handler{
    name='pivot_trade/banner',
    overlay=TradeBannerOverlay,
}
overlay.register_handler{
    name='pivot_trade/trade_overlay',
    overlay=TradeOverlay,
}
overlay.register_handler{
    name='pivot_trade/ethics_warning',
    overlay=TradeEthicsWarningOverlay,
}
```

> [!IMPORTANT]
> The exact overlay registration pattern must match what DFHack expects from mod scripts. I will verify the exact pattern used by `df-herald` (the working reference mod) before writing the final code.

---

## Open Questions

> [!IMPORTANT]
> **Overlay registration pattern**: The `caravan` repo never registers overlays itself (it relies on being part of the main DFHack install). I need to use the correct registration call for a mod script. The `df-herald` reference will be checked to confirm the exact API.

> [!NOTE]
> **`--@ module = true`**: This directive is used in the `caravan` repo files. In the context of a mod's `internal/` scripts, `reqscript` works correctly without it, but it does no harm to keep it. We will keep it as-is to stay close to the source.

> [!NOTE]
> **`pivot_trade_ui.lua` deletion**: The file will be deleted (or left as a stub that errors with a helpful message). Since it is no longer `reqscript`'d by anything, it is safe to delete.

---

## Verification Plan

### Manual in-game check (user must verify)
1. Launch DF with DFHack.
2. Go to the Mods screen → enable `DFHack Pivot UI - Trade and Stocks`.
3. Start a fortress and open a trade session.
4. Verify the **"Pivot trade UI"** button appears on the vanilla trade screen (bottom-right overlay).
5. Click the button and verify the `LuaTrade` window opens with:
   - **Tabs**: Caravan goods / Fort goods
   - **Sort columns**: X, Cnt, Value, Class, Subclass, Grouped, Item Description
   - **Filter panel** toggle (`Shift+F`)
   - **Search** (`Alt+S`)
   - **Total value** display at the bottom
6. Verify the **TradeOverlay** panel appears (shift/ctrl click helpers, collapse hotkeys).
7. Verify the **Ethics warning** overlay appears if elven merchants are present and you select animal products.

### Script-level check (can be run from DFHack console)
```lua
reqscript('pivot_trade')
```
Should not produce any errors.

---

## File Summary

```
scripts_modactive/
  pivot_trade.lua                          ← MODIFY (replace with caravan pivottrade.lua, adapted)
  internal/pivot_trade/
    item_classifier.lua                    ← MODIFY (replace with caravan version)
    common.lua                             ← NEW (from caravan)
    sorting.lua                            ← NEW (from caravan)
    ethics.lua                             ← NEW (from caravan)
    predicates.lua                         ← NEW (from caravan)
    tradeoverlay.lua                       ← NEW (from caravan)
    pivot_trade_ui.lua                     ← DELETE (superseded)
```
