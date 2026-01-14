# DFHack Pivot UI: Trade & Stocks

## Overview
This mod provides a pivot-style, keyboard-driven interface for managing items in Dwarf Fortress. It replaces the flat lists of the Trading and Stocks screens with a hierarchical, MECE (Mutually Exclusive, Cumulatively Exhaustive) view.

## Features
- **Dual-Pane Trading**: When opened from the Trade screen, it shows Fortress goods on the left and Caravan goods on the right.
- **Stocks View**: When opened from the main map or Stocks screen, it provides a searchable, hierarchical view of all fortress-owned items.
- **MECE Hierarchy**: Items are grouped by Class (e.g., Weapons, Armor) and Subclass (e.g., Swords, Helms).
- **Value Aggregation**: Instantly see the total count and value of entire categories.
- **Keyboard Optimized**: Navigate with arrows/Enter, switch panes with Tab, and go back with Esc/Backspace.

## Installation
1. Place the following files in your `/Dwarf Fortress/dfhack-config/scripts/` folder:
   - `pivot_trade.lua`
   - `pivot_trade_ui.lua`
   - `item_classifier.lua`

## Usage
### In the Trade Screen
1. Open the Trade Depot and start trading with a caravan.
2. Once the standard trade screen is visible, open the DFHack console (`Ctrl+Shift+P` or `Ctrl+P`).
3. Type `pivot_trade` and press Enter.
4. Use **Tab** to switch between your goods and the caravan's goods.

### For General Stocks
1. While on the main map or in the Stocks screen, open the DFHack console.
2. Type `pivot_trade` and press Enter.
3. This will show all items owned by your fortress, perfect for testing or inventory audits.

## Controls
- **Arrows**: Navigate list.
- **Enter**: Drill down into Class -> Subclass -> Items.
- **Esc / Backspace**: Go up one level or close the mod.
- **Tab**: Switch between Fortress and Caravan panes (Trade mode only).
- **Enter (on Item)**: Toggles the item for trade (Trade mode only).

## Technical Notes
- **No `mkmodule`**: Uses standard Lua tables for better compatibility.
- **Direct Integration**: Pulls data directly from `viewscreen_tradegoodsst` when available.
- **Mod Friendly**: Automatically classifies modded items into "Other" if they don't match standard definitions.
