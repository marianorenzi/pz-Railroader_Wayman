# Changelog

## 0.2.1

### New

- Added explicit external-edge references for turnout legs, allowing them to target Railroader edges not managed by Wayman.

## 0.2.0

### New

- Added support for extending Railroader's existing `main` network. Wayman edges and switches are merged into a preserved copy of the original Railroader graph.
- Added an Origin tab to the Graph Editor for selecting an edge, travel direction, and optional route offset.
- Added interactive World Map selection:
    - Clicking an edge selects it in the Graph Editor.
    - Clicking an available node selects its node block.
    - Clicking a node on the selected edge selects its edge block.
- Added graph snapshots to `console.txt` before and after Railroader export for diagnostics.

### Changed

- The World Map now keeps the Graph Editor on top during map interaction.
- Selected edge blocks are highlighted independently from available blocks, with improved marker layering and tooltips for overlapping nodes.
- Programmatic node-block selections now scroll their tables to the selected row.
- Switch interaction-place metadata is preserved and exported to Railroader.
- The node-count column now accounts for the list scrollbar when the Default column is hidden.

### Fixed

- Fixed selected edge nodes being rendered with the same color as the rest of the edge.

## 0.1.1

- Fixed the Graph Editor's Move Up and Move Down actions not reordering the selected node block.

## 0.1.0

Changes since last release.

### New

- Added an Entity Node Editor UI accessible from the world context menu.
    - Added Node Blocks (entity-based, like "at", "switch", "through", "diverge", etc...) and Nodes tables with controls to add, remove, reorder, and restore geometry overrides to their defaults.
    - Added **Edit node** mode to relocate a selected node by clicking a world square, including cursor hover previews, highlighted selection, and Escape cancellation.
    - Added colored world highlights for `nodes`, `at`, `switch`, `through`, and `diverging` nodes while editing an entity.
    - Implemented Reload and Apply flows backed by the entity's current `modData` and the authoritative `updateRailEntity` server operation (for multiplayer support).
- Added English, Spanish, and Russian translations (AI generated) for the Node Editor, crafting category, and entity recipe names.

### Changed

- Reworked the graph editor layout and controls for clearer edge, switch, and node-block editing.
- Updated XUI display names to use translatable `WaymanEntityName_*` keys.
- Corrected generated turn and turnout geometry definitions used by the editor and runtime.

### Fixed

- Fixed custom turnout overrides being rejected with `static turnout geometry was not found` when their branch nodes no longer matched a built-in template.
- Fixed entity updates so graph placement, block inversion, and configured switch legs are preserved while geometry is rebuilt.
- Fixed node highlights and table coordinates after applying or reloading entity overrides.
- Fixed stale highlights remaining after the node editor closes or node relocation is cancelled.
- Fixed untranslated crafting categories and recipe names appearing as raw XUI text.

### Compatibility

- Existing absolute-coordinate graph records remain readable when no origin is present.
- Existing turnout records without an explicit interaction place continue to use static-geometry inference. Updating the entity once stores the explicit place required by custom geometry.
