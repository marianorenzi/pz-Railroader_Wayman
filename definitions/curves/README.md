# Curvas sin durmientes

Las tres definiciones canónicas se incorporan como entidades independientes:
`Left45DegCurve`, `Right45DegCurve` y `Curve90Deg`, cada una con caras N/E/S/W.
El historial de variantes está en `.codex-context/CURVES.md`; los definitions
contienen los tiles, dimensiones, nodos y sentidos de las piezas elegidas.
Left45DegCurve:E usa el mapa comprobado v3 de 6×3 y conserva el nodo `(4,2,0)`.
Right45DegCurve:S usa la captura corregida v2 de 5×3, con el nodo `(2,1,0)`
tomado de `destination.relative`. Right45DegCurve:E usa la captura corregida v2
de 5×4, con `(4,3,0)` como único nodo. Las referencias Wayman de esa captura se
resuelven a sprites vanilla en el definition fuente. Los tilesets incorporan
estas correcciones.
Left45DegCurve:S conserva su nodo `(5,4,0)`
fuera de la matriz visual de 6×3. Curve90Deg:S tiene su primer nodo en `(5,6,0)`,
fuera de su matriz de 6×5; se conserva en esa posición.

Las tres entidades usan el perfil de receta `turn` con multiplicador 1 de
`definitions/CostProfiles.json`. Sus sprites tienen las mismas propiedades de
desmontaje nativo que las otras piezas de Wayman: `CanScrap=true`, `Material=Wood`
y `CustomName=Wayman_<entidad>`.

## Regeneración

Desde la raíz de Railroader Wayman:

```bash
python3 -B scripts/build_curves.py
python3 -B scripts/build_curves.py --apply
```

La primera orden prepara y verifica; `--apply` copia los resultados al mod de
este repositorio. No actualiza ninguna instalación de Steam ni de Zomboid.
Requiere Python/Pillow y los repositorios vecinos `../pz-EntityGenerator` y
`../pz-tilesheet`; las rutas se pueden cambiar con `--generator` y
`--pz-tilesheet`. `--output` y `--work` permiten preparar en otros directorios.

El build solo genera esta familia. Las tres páginas usan estos nombres e IDs:

| Página | tiledef ID | Sprites usados |
|---|---:|---:|
| `railroader_wayman_curves_01` | 481 | 63 |
| `railroader_wayman_curves_02` | 482 | 56 |
| `railroader_wayman_curves_03` | 483 | 29 |

Cada página tiene una matriz de 8×8 slots de 128×256 px: 148 sprites activos y
44 slots vacíos. Los nueve sprites eliminados quedan transparentes y sin
propiedades para conservar los índices de todos los demás. Las asignaciones
permanentes están en `scripts/curves_sprite_layout.json`, una configuración del
build separada del contrato de definitions. Una celda nueva sin slot asignado
detiene el build hasta que se le asigne uno explícitamente.

Se comprueban las colisiones de IDs antes de aplicar. Ninguna
página de tracks/turns/switches se reempaca. Las posiciones dentro de una cara
pueden cambiar al corregir su matriz, conservando los nombres e índices de los
sprites desplazados. Right45DegCurve:E conserva sus siete sprites anteriores y
usa los slots nuevos `railroader_wayman_curves_03_24` a `_28` para los cinco tiles
agregados.

## Archivos para reutilizar en turnouts

Con las rutas por defecto, los resultados están en la raíz `output/`:

- `curve-sources/`: los tres atlas nuevos y las cinco hojas vanilla
  `industry_railroad_*.png`, reunidos como un único `--source-directory` para
  `build_tilesets.py`. Permite combinar tiles vanilla y
  `railroader_wayman_curves_01_0`, etc., en una nueva definición de turnout.
- `definitions/railroader_wayman_curves/*.json`: matrices generadas que asocian
  cada celda `(x,y)` con su sprite nuevo y conservan su geometría.
- `railroader_wayman_curves_0{1,2,3}.png`, `.tiles` y `.tiles.txt`: atlas completos
  a resolución nativa y definiciones binarias y legibles.
- `texturepacks/railroader_wayman_curves_0{1,2,3}.pack`: packs para el juego.
- `render/curves/<entidad>_<cara>.png`: las 12 composiciones transparentes a
  resolución nativa; son recortes visuales, por lo que las coordenadas de
  colocación deben tomarse del JSON, no del borde del PNG.
- `render/curves/<entidad>.png`: tres hojas de revisión con las cuatro caras.
- `entities/` y `render/icons/`: scripts, XUI e iconos de 48×48.
- `lua/WaymanEntityGeometry.lua`: catálogo publicado con la geometría de curvas
  actualizada; conserva los turns y switches publicados, sin incorporar caras
  de turnout que todavía están en preparación.
- `curves-build-manifest.json`: hashes, IDs, sprites retirados y nodos exteriores
  preservados.

Los sprites individuales de 128×256 quedan en
`work/railroader_wayman_curves/<página>/`. Las orientaciones faltantes de los
turnouts se construyen aparte; este build conserva sus definiciones actuales.

## Verificación

```bash
python3 -B -m unittest discover -s tests -p 'test_*generator.py' -v
```

Las pruebas reconstruyen en un directorio temporal y comparan los archivos
publicados, cada píxel de los packs, nombres/IDs, propiedades de desmontaje,
recetas, callbacks, iconos y traducciones. El test Lua `WaymanEntityRuntime`
incluye las 12 caras nuevas. La aceptación de colocación, menú de construcción
y apariencia dentro de PZ sigue siendo una comprobación en el juego.
