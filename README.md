# Railroader Wayman

**Version 1.0.0 · Project Zomboid Build 42 · Requires Railroader 3.0**

Build tracks, crossings, curves and turnouts, then connect them into routes for
Railroader trains. Wayman extends the existing railway network and includes a
Graph Editor, an interactive World Map overlay and construction guides.

## Requirements

- Project Zomboid Build 42.
- [Railroader 3.0](https://steamcommunity.com/sharedfiles/filedetails/?id=3774360904), enabled alongside Wayman.
- Supports singleplayer, hosted multiplayer and dedicated servers.

Wayman Mod ID: `RailroaderWayman`. Workshop ID: `3802731633`.

## Getting started

1. Build your railway pieces. Use the construction guides to align curves and turnouts with existing connections.
2. Open the Graph Editor with **.** or the **G** button on the World Map. The shortcut can be changed in the game's **Key Bindings** menu.
3. Create routes (called **edges** in the editor) and assign their node blocks in travel order.
4. Configure turnout connections using the edge selectors and start/end directions. Selectors include your draft routes and Railroader's existing routes.
5. Press **Accept**. Railroader validates the layout before it becomes available to trains; a rejected edit keeps the last accepted routes and your draft.

Placing track pieces alone does not create a drivable route. The Graph Editor
connects their route nodes and configures the turnouts. Incomplete turnouts can
remain in the draft until their connections are configured.

## Construction guides

During placement of a curve or turnout, guides show its connection directions.
Green indicates a compatible, free connection on an available node or route
endpoint. Red indicates an incompatible connection or no target. Labels identify
the target, its route and distance, and explain incompatible connections.

Guides look along each exit direction and stop searching at the first position
containing a node. Their visible length is eight tiles by default, but targets
can be farther away. Distances are measured in grid steps; a diagonal step counts
as one tile. Guides are visual aids and do not prevent construction.

## Construction and material recovery

Recipes vary by piece type and size. All railway construction requires a hammer.

| Piece type | Materials | Required skills |
| --- | --- | --- |
| Straight track and crossings | 1–3 planks and 1–3 nails, depending on the piece | Woodwork 2 |
| Curves | 4 planks, 2 railroad spikes, 1 Steel Rod | Woodwork 6, MetalWelding 4 |
| Turnouts | 6 planks, 4 railroad spikes, 2 Steel Rods | Woodwork 7, MetalWelding 5 |
| Three-way turnouts | 18 planks, 12 railroad spikes, 6 Steel Rods | Woodwork 7, MetalWelding 5 |

Railroad spikes can be forged from an Iron Chunk or cast using iron in a crucible.
Both recipes require Blacksmith 2 and the appropriate tools and charcoal.

Use the game's **Disassemble** action on a built piece to recover materials.
Recovery follows the game's tools, action duration and recovery chance. Materials
are returned once for the complete piece and left on the floor at the clicked
tile; destroying a piece does not return materials.

## World Map and editing drafts

The World Map displays Wayman routes, available node blocks and the selected
route's nodes. Click a route or node to select it in the Graph Editor. Its display
options control map layers and world highlights.

Unfinished graph and node edits are saved locally for each world or server and
player. Closing the Graph Editor or pressing **Cancel** keeps the draft; its
**Reload** action discards local changes and returns to the confirmed state.
Incoming changes are merged with local work, with conflicts presented for review
before publishing.

Accepted routes are saved and restored when the world loads. In multiplayer, the
server validates and publishes changes and synchronizes them with clients.

## Available pieces

| Entity | Available facings |
| --- | --- |
| `TrackSegment` | S, W |
| `DiagonalTrackSegment` | N, W |
| `CrossingSegment` | S, W |
| `DiagonalCrossingSegment` | N, E |
| `DiagonalCrossingEdge` | N, S |
| `Left45DegTurn` | N, E, S, W |
| `Right45DegTurn` | N, E, S, W |
| `Left45DegTurnout` | N, E, S, W |
| `Right45DegTurnout` | N, E, S, W |
| `Left45DegTurnoutDiag` | N, W |
| `Right45DegTurnoutDiag` | N, S, W |
| `Left90DegTurnout` | N |
| `WyeTurnout` | S |
| `SymmetricalThreeWayTurnout` | E, S, W |
| `SymmetricalCompactThreeWayTurnout` | E, W |

Facing describes the track entrance. Cardinal entrances use their own direction;
diagonal entrances use the next cardinal direction clockwise: NW → N, NE → E,
SE → S and SW → W. Pieces with equivalent opposite orientations use S for the
N/S axis and W for the E/W axis.

## Development tools

The Entity Node Editor is available in debug mode by right-clicking any tile of a
supported curve or turnout. It can move, add, remove and reorder supported nodes.
Use **Stage** to add geometry changes to the draft, then **Accept** in the Graph
Editor to publish them with the route connections. Multiplayer geometry changes
require an administrator or server debug mode.

Automatic graph diagnostics are limited to debug mode. The Graph Editor's
**Export** action remains available normally.

Wayman uses Railroader 3.0's public track-registration API. Pre-1.0 save
compatibility is not guaranteed.

## Repository layout

- `RailroaderWayman/`: packaged Workshop item, including its description and preview.
- `RailroaderWayman/Contents/mods/RailroaderWayman/42/`: Build 42 mod metadata, scripts, Lua code and assets.
- `definitions/`: source definitions for railway pieces and construction costs.
- `tests/`: automated Lua and Python checks.

Release history is in [CHANGELOG.md](CHANGELOG.md).
