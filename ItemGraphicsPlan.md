# Item Graphics Implementation Plan: Graphical Pivot UI

This plan outlines the steps required to transition the `df-pivot-trade` hierarchical UI from a text-only display to a rich, graphical interface using item sprites.

## 1. Technical Goals
- **Multi-Row Entries**: Refactor the list rendering to support rows that are 3 characters high.
- **Representative Icons**: Display 2-3 distinct item sprites per hierarchy row to visually represent the contents of that branch. It should be the Between the "Value" and "Class" columns and should drill down when clicked.  It will require about 12 tiles wide (for 3 3x3 icons with spacing)
- **Steam Graphic Integration**: Leverage DFHack's ability to render native game sprites (layered item graphics) within a `gui.widgets` context.
- **Performance**: Implement a caching layer for representative items to avoid scanning the entire inventory every frame.

---

## 2. UI Layout Change (3-Row Height)

Current row (1 row high): (same as header just the values)
`[X] [Cnt] [Value] [Class] [Subclass] [Grouped] [Description]`

Proposed row (3 rows high):
```
Header row: `[X] [Cnt] [Value] [*IMAGES*] [Class] [Subclass] [Grouped] [Description]`
Row 1 : Must be a frame:  so a top left corner, top horizontal frame, and then the top right corner
Row 2 : Vertical Frame [X] [Cnt] [Value] [*IMAGES*] [Class] [Subclass] [Grouped] [Description] Vertical frame
Row 3 : Must be the bottom of the frame : So bottom left corner, bottom horizontal frame, bottom right corner  
```

We will need to find the appropriate sprites for the items as well as the frames.

### Layout Logic:
- Column widths will remain consistent, but the vertical space will be utilized for larger text and sprites.
- Images will be rendered in a dedicated "Graphic Zone" (e.g., between the selection checkbox and the hierarchy labels).

---

## 3. Representative Item Selection

At higher levels of the hierarchy, we need to pick 2-3 items to represent the group.

- **Leaf Level (Item)**: Display the specific item sprite. If it's a stack, show the stack graphic.
- **Grouped Level**: Pick the 3 most valuable items in the group that have distinct `subtype`.
- **Subclass/Class Level**: 
    - Pick 1 item from the "Top" subclass.
    - Pick 1 item from the "Middle" subclass.
    - Pick 1 item from the "Bottom" subclass (or just the 3 most expensive overall).
- **Diversity Filter**: Ensure that if we have 100 "Iron Helmets", we only use 1 image slot for a helmet and use the others for different items in that branch (e.g., an Iron Breastplate).

---

## 4. Implementation Steps

### Phase 1: Custom List Widget
The standard `widgets.List` is optimized for 1-line rows.
1.  Extend `widgets.List` or create `PivotList` that overrides `onRenderItem`.
2.  Adjust `row_height` to 3.
3.  Update the scrollbar logic to handle the tripled height.

### Phase 2: Graphics Pipeline
1.  **Item Sprite Retrieval**: Use `dfhack.items.getGraphicTile` (or the internal layered graphic equivalent) to get the sprite IDs.
2.  **Sprite Rendering**: Use `dc:tile` or `dc:unit` (adapted for items) within the `onRenderItem` loop.
3.  **Color Handling**: Items like clothing/armor require material-based coloring. Ensure the rendering logic respects the item's `material_color`.

### Phase 3: Aggregation Refactor
1.  Update `aggregate_choices` in `pivot_trade.lua` to identify and store the `representative_item_ids` during the initial scan.
2.  Store these IDs in the `choice.data` object so the renderer doesn't have to re-calculate them.

### Phase 4: Styling & Polish
1.  Add "Selection Frames" around images when a row is selected.
2.  Ensure that images are centered within their 3-row vertical block.
3.  Add fallback ASCII characters if graphics are disabled.

---

## 5. Potential Challenges
- **Memory/Performance**: Drawing hundreds of layered sprites per second can be heavy.
    - *Solution*: Only draw sprites for visible list items.
- **Layered Items**: Some items (like decorated bins) have complex layered graphics.
    - *Solution*: Use the base item graphic for the representative slots to keep the UI clean.
- **Space Constraints**: 3 rows per item significantly reduces the "information density" (fewer items visible at once).
    - *Solution*: Ensure the "Collapse" and "Filter" features are easy to use to compensate for the reduced visibility.

---

## 6. Development Milestones
1.  **Milestone 1**: A working 3-row-high text-only list.
2.  **Milestone 2**: Single static image per row (e.g., always a generic crate).
3.  **Milestone 3**: Dynamic representative image selection.
4.  **Milestone 4**: Full layered item graphics with coloring.
