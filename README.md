# Railroader Wayman

Build 42 companion mod for Railroader. The current prototype only declares
constructible visual track entities; it does not yet store Wayman track data or
integrate constructed pieces into Railroader's route graph.

## Development layout

Copy or link `mods/RailroaderWayman` directly into the Project Zomboid `mods`
directory. The resulting path must be `Zomboid/mods/RailroaderWayman`, not
`Zomboid/mods/pz-Railroader_Wayman/mods/RailroaderWayman`. Shared metadata is
under `common` and the game-facing Build 42 files are under `42`.

## Prototype entities

- `RailroaderWayman.BasicTrackSegment`: 3x1 or 1x3 straight track.
- `RailroaderWayman.DiagonalTrackSegment`: provisional diagonal artwork. Its
  supplied faces currently occupy 6x1 and 5x1 respectively and require visual
  verification in game.

The construction recipe is deliberately provisional: one hammer, three large
planks, two metal bars and six railroad spikes. Moving and dismantling are not
enabled because the vanilla railroad sprites do not carry the tile properties
required by the moveables/scrapping system.
