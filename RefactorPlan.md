# Refactoring Plan: Modularize Shared Functions

## Overview
This project aims to reduce code duplication and improve maintainability by moving shared utility functions into a common module.

## Target Files
- `scripts_modactive/stockview.lua`
- `scripts_modactive/internal/pivot_trade/pivot_trade_ui.lua`

## Shared Functions to Move
The following functions are identical in both files and will be moved to `scripts_modactive/internal/pivot_trade/common.lua`:

1. **get_generic_description**
   - *Purpose*: Cleans up item descriptions by removing special characters and specific labels (e.g., "left", "right").
2. **path_contains**
   - *Purpose*: Checks if a value exists within a path level (array of strings).
3. **path_level_str**
   - *Purpose*: Formats a path level for breadcrumb display, with a length check.

## Implementation Steps
1. Move the three functions into `scripts_modactive/internal/pivot_trade/common.ua`.
2. Update both `stockview.lua` and `pivot_trade_ui.lua` to import these functions from `common.lua`.
3. Verify that functionality remains identical in both modules after refactoring.

4. Then go through both target files again, and check if you can also move a lot of the UI functionality also to common.lua. Very big parts of the UI logic etc. can also be ported, but it might need a lot of work. Also the variable names are also not always aligned try to fix and align them too. 