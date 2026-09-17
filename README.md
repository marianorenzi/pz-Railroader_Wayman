# Railroader Wayman

Work-in-progress Build 42 companion mod for Railroader. It currently provides
constructible visual railway pieces built from custom tilesets. It does not yet
store Wayman track data or integrate constructed pieces into Railroader's route
graph.

## Repository layout

- `RailroaderWayman/`: Workshop item copied to the Project Zomboid Workshop
  directory for testing.
- `RailroaderWayman/Contents/mods/RailroaderWayman/common/`: shared mod
  metadata.
- `RailroaderWayman/Contents/mods/RailroaderWayman/42/`: Build 42 mod files.
- `tilesets/definitions/`: source matrices grouped into tracks, turns and
  switches.

## Facing convention

`facing` describes the track entrance. Cardinal entrances use their own
direction. Diagonal entrances use the next cardinal direction clockwise:

- `NW` -> `N`
- `NE` -> `E`
- `SE` -> `S`
- `SW` -> `W`

For pieces with equivalent opposite orientations, `S` represents the `N/S`
axis and `W` represents the `E/W` axis.

## Track entities

- `TrackSegment`: straight track, `S/W`.
- `DiagonalTrackSegment`: diagonal track, `S/W`.
- `CrossingSegment`: cardinal crossing edge, `S/W`.
- `DiagonalCrossingSegment`: diagonal crossing segment, currently `N/E`.
- `DiagonalCrossingEdge`: diagonal crossing edge, `N/S` only. Suitable vanilla
  sprites for `E/W` are not currently available.

## Turn entities

- `Degree45LeftTurnSegment`: `N/E/S/W`.
- `Degree45RightTurnSegment`: `N/E/S/W`.

## Turnout entities

- `SymmetricalThreeWayTurnout`: `N/S/W`.
- `DiagonalRight45DegTurnout`: `N/S/W`.
- `WyeTurnout`: `S`.
- `SymmetricalCompactThreeWayTurnout`: `E/W`.
- `Right45DegTurnout`: `N/E/S/W`.
- `Left45DegTurnout`: `N/E/S/W`.
- `Left90DegTurnout`: `N`.
- `DiagonalLeft45DegTurnout`: `N/W`.

Missing orientations remain intentionally absent until their vanilla tile
compositions have been captured and verified.

## Current construction behavior

Construction recipes and material costs are provisional. Pieces are visual
entities only: they do not yet control trains, expose operational switches or
participate in Railroader routing. Generated custom sprites avoid duplicate
vanilla tile restrictions and persist normally with the world.
