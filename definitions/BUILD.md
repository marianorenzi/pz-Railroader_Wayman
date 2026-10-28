# Tilesets y entidades

Las fuentes canónicas están en `tracks/`, `switches/`, `turns/` y `curves/`.
Los definitions contienen únicamente datos del contrato de entidades. Los
sprites editados de CrossingEdge se leen desde `art/sprites/`; todo archivo
de trabajo se escribe en `work/` o `output/`.

## Tracks y turnouts

```bash
python3 -B scripts/build_missing_entities.py
python3 -B scripts/build_missing_entities.py --apply
```

La primera orden prepara y verifica. `--apply` copia los resultados al mod de
este repositorio. Requiere Python/Pillow, `../pz-EntityGenerator` y
`../pz-tilesheet`; las rutas se pueden cambiar con `--generator` y
`--pz-tilesheet`. `--output` y `--work` cambian los directorios de salida.

El build toma los nombres e índices publicados de los scripts del mod.
Las caras existentes mantienen sus referencias. Las caras nuevas ocupan
slots transparentes sin referencias ni propiedades y luego agregan páginas.
Los IDs de tiledef se asignan entre los disponibles de 100 a 512: los números
de página y los IDs no tienen que ser consecutivos. `mod.info` conserva la
asignación explícita y evita colisiones en reconstrucciones posteriores.
Los packs que no cambian se conservan literalmente.

La referencia de compatibilidad es el release **1.0.0**, commit
`f8ccfff76fee0d67542eb178328275ffa4892aae`. Sus páginas conservan los IDs de
tiledef, nombres, índices, dimensiones y propiedades de los sprites usados.
Las correcciones gráficas pueden actualizar sus píxeles y los definitions
pueden cambiar la composición de las entidades. Las asignaciones posteriores
a ese release se pueden reorganizar.

```bash
python3 -B scripts/verify_release_assets.py
```

Las celdas eliminadas durante un retoque dejan slots transparentes y sin
propiedades; no se reutilizan durante esa misma reconstrucción. Las celdas
ocupadas mantienen sus índices y las celdas nuevas usan espacios disponibles.

Los nombres fuente `CrossingEdgeDiag`, `CrossingSegmentDiag` y `TrackSegmentDiag`
se publican como `DiagonalCrossingEdge`, `DiagonalCrossingSegment` y
`DiagonalTrackSegment`, respectivamente, conservando las entidades existentes.

La incorporación de las 17 caras pendientes utiliza 463 sprites nuevos:

| Página nueva | tiledef ID |
|---|---:|
| `railroader_wayman_tracks_02` | 484 |
| `railroader_wayman_switches_14` | 485 |
| `railroader_wayman_switches_15` | 486 |
| `railroader_wayman_switches_16` | 487 |
| `railroader_wayman_switches_17` | 488 |
| `railroader_wayman_switches_18` | 489 |
| `railroader_wayman_switches_19` | 492 |
| `railroader_wayman_switches_20` | 493 |

Los resultados por defecto incluyen:

- `output/definitions/railroader_wayman_{tracks,switches}/`: bindings generados.
- `output/entities/`: scripts de entidad y XUI.
- `output/texturepacks/`, `output/*.tiles` y `output/*.png`: packs y atlas.
- `output/render/entities/`: composiciones individuales y hojas de revisión.
- `output/lua/WaymanEntityGeometry.lua`: geometría de turns, turnouts y curvas.
- `output/entities-build-manifest.json`: hashes, asignaciones y caras agregadas.
- `work/entities-build/`: sprites individuales y copia previa a esta incorporación.

Se comprueban los píxeles y propiedades después de decodificar cada pack y
tiledef. También se conservan las recetas existentes. `Right90DegTurnout`
incorpora receta, XUI, icono y traducciones EN/ES/RU.

`Left90DegTurnout` tiene sus cuatro caras publicadas. S usa Curve90Deg:S con
`at (5,6,0)`, desvío hasta `(1,2,0)` y switch `(2,5,0)`. Las tres caras nuevas
de Wye conservan el remate de CrossingEdge en la curve para conectar
segmentos diagonales.

## Curvas

Se regeneran mediante `scripts/build_curves.py`; ver
[instrucciones de curvas](curves/README.md).

## Verificación

```bash
python3 -B -m unittest discover -s tests -p 'test_*generator.py' -v
```

Estas pruebas reconstruyen en directorios temporales, comprueban que no se
asignen otros IDs y contrastan cada sprite con sus fuentes. Los tests Lua
`WaymanEntityRuntime` y `WaymanComponents` cubren el registro de las caras
operativas simples y de las ocho caras compuestas.
