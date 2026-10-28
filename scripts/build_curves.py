#!/usr/bin/env python3
"""Build the canonical bare-rail curves without reallocating existing tilesets."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import sys
from types import SimpleNamespace

from PIL import Image, ImageChops

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "RailroaderWayman/Contents/mods/RailroaderWayman/42"
FAMILY = "railroader_wayman_curves"
FIRST_ID = 481
CONFIG = {"tileWidth": 128, "tileHeight": 256, "sourceColumns": 8}
LAYOUT = ROOT / "scripts/curves_sprite_layout.json"


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def script_faces(text):
    faces, facing = {}, None
    for line in text.splitlines():
        match = re.fullmatch(r"\s*face ([NESW])\s*", line)
        if match:
            facing = match[1]
            faces[facing] = []
        match = re.fullmatch(r"\s*row = (.*),\s*", line)
        if match:
            faces[facing].append(match[1].split())
    return faces


def generate_stable_pngs(args, config, definitions, layout, tiles):
    """Keep every assigned sprite slot, including cells removed by later edits."""
    pages = sorted(layout["tiledefs"])
    slots = {f"{page}_{index}": None for page in pages for index in range(64)}
    assigned = {}
    for entity, faces in layout["entities"].items():
        for facing, rows in faces.items():
            for y, row in enumerate(rows):
                for x, name in enumerate(row):
                    if name:
                        if name not in slots or name in assigned:
                            raise ValueError(f"Invalid or duplicated assigned curve slot: {name}")
                        assigned[name] = (entity, facing, x, y)
    generated, cache = {}, {}
    for source in definitions:
        entity = source["entity"]
        built = {key: copy.deepcopy(value) for key, value in source.items() if key != "faces"}
        built["faces"] = {}
        for facing, face in source["faces"].items():
            references = layout["entities"].get(entity, {}).get(facing, [])
            rows = []
            for y in range(face["height"]):
                row = []
                for x in range(face["width"]):
                    sprite, inputs = tiles.compose_cell(face["layers"], x, y, args.source_directory, config, cache)
                    if not inputs:
                        row.append(None)
                        continue
                    name = references[y][x] if y < len(references) and x < len(references[y]) else None
                    if not name:
                        raise ValueError(f"No assigned sprite for {entity}:{facing}:{x},{y}; allocate its layout slot explicitly")
                    slots[name] = (entity, facing, x, y, sprite)
                    row.append(name)
                rows.append(row)
            built["faces"][facing] = {key: copy.deepcopy(value) for key, value in face.items() if key != "layers"}
            built["faces"][facing]["layers"] = [{"index": 0, "tiles": rows}]
        generated[entity] = built
    directory = args.work_directory / FAMILY
    if directory.exists():
        shutil.rmtree(directory)
    directory.mkdir(parents=True)
    definitions_dir = args.output / "definitions" / FAMILY
    definitions_dir.mkdir(parents=True, exist_ok=True)
    for name, built in generated.items():
        write(definitions_dir / f"{name}.json", json_text(built))
    transparent = Image.new("RGBA", (config["tileWidth"], config["tileHeight"]))
    for name, cell in slots.items():
        page, index = name.rsplit("_", 1)
        target = directory / page
        target.mkdir(exist_ok=True)
        if cell:
            entity, facing, x, y, sprite = cell
            sprite.save(target / f"{int(index):02d}__{entity}__{facing}_{y}_{x}.png")
        else:
            transparent.save(target / f"{int(index):02d}__padding.png")
    return generated, sorted(name for name in assigned if slots[name] is None)


def merge_curve_geometry(previous, catalog, generator):
    """Replace only curves; source turnout drafts must not be published here."""
    result = previous
    for name, faces in catalog.items():
        block = f"    {name} = {{\n"
        block += "".join(f"        {facing} = {generator.lua_value(face)},\n" for facing, face in faces.items())
        block += "    },\n"
        pattern = rf"^    {re.escape(name)} = \{{\n.*?^    \}},\n"
        matches = list(re.finditer(pattern, result, re.M | re.S))
        if len(matches) > 1:
            raise ValueError(f"Duplicate runtime curve geometry: {name}")
        if matches:
            result = re.sub(pattern, lambda _: block, result, count=1, flags=re.M | re.S)
        else:
            if not result.endswith("}\n"):
                raise ValueError("Cannot locate the runtime geometry catalog closing brace")
            result = result[:-2] + block + "}\n"
    return result


def build(args):
    generator = args.generator.resolve()
    sys.path.insert(0, str(generator / "scripts"))
    tiles = module("curve_tiles", generator / "scripts/build_tilesets.py")
    entities = module("curve_entities", generator / "scripts/build_entities.py")
    geometry = module("curve_geometry", generator / "scripts/build_geometry.py")
    renderer = module("curve_renderer", generator / "scripts/render_entity.py")
    packer = module("curve_packer", args.pz_tilesheet / "pz_tilesheet.py")
    sources = generator / "sources"
    output = args.output.resolve()
    definitions = tiles.load_definitions(ROOT / "definitions/curves")
    profiles = entities.load_profiles(ROOT / "definitions/CostProfiles.json")
    for definition in definitions:
        entities.EntityGenerator.recipe(definition, profiles[definition["costProfile"]])
    build_args = SimpleNamespace(name=FAMILY, work_directory=args.work.resolve(),
                                 output=output, source_directory=sources)
    layout = json.loads(LAYOUT.read_text())
    generated, retired = generate_stable_pngs(build_args, CONFIG, definitions, layout, tiles)
    properties, sprite_count, outside_nodes = {}, 0, []
    for definition in definitions:
        name = definition["entity"]
        for facing, face in definition["faces"].items():
            for node in face.get("nodes", []):
                if not (0 <= node["x"] < face["width"] and 0 <= node["y"] < face["height"]):
                    outside_nodes.append({"entity": name, "facing": facing, "node": node})
            for row in generated[name]["faces"][facing]["layers"][0]["tiles"]:
                for sprite in row:
                    if sprite:
                        properties[sprite] = {"CanScrap": "true", "Material": "Wood", "CustomName": f"Wayman_{name}"}
                        sprite_count += 1
    write(output / "curves-tile-properties.json", json_text(properties))
    sheets = sorted((build_args.work_directory / FAMILY).iterdir())
    info = (MOD / "mod.info").read_text()
    used_ids = {int(value): name for name, value in re.findall(r"^tiledef=(\S+) (\d+)$", info, re.M)
                if not name.startswith(FAMILY + "_")}
    for index in range(len(sheets)):
        tile_id = FIRST_ID + index
        if layout["tiledefs"][sheets[index].name] != tile_id:
            raise ValueError(f"Curve tiledef changed in the sprite layout: {sheets[index].name}")
        if not 100 <= tile_id <= 512 or tile_id in used_ids:
            raise ValueError(f"Curve tiledef {tile_id} is unavailable: {used_ids.get(tile_id)}")
    installs = []
    registrations = []
    reuse_sources = output / "curve-sources"
    reuse_sources.mkdir(parents=True, exist_ok=True)
    for path in sources.glob("industry_railroad_*.png"):
        shutil.copyfile(path, reuse_sources / path.name)
    for index, directory in enumerate(sheets):
        sprites = [{"path": str(path), "name": path.stem, "image": Image.open(path).convert("RGBA")}
                   for path in sorted(directory.glob("*.png"))]
        atlas, entries, rows = packer.build_atlas(sprites, 128, 256, 8)
        name, tile_id = directory.name, FIRST_ID + index
        packer.write_pack(str(output), name, atlas, entries, 128, 256)
        packer.write_tiles_bin(str(output), name, tile_id, entries, 8, rows, properties)
        packer.write_tiles_txt(str(output), name, tile_id, entries, 8, rows, properties)
        atlas.save(output / f"{name}.png")
        atlas.save(reuse_sources / f"{name}.png")
        installs += [(output / "texturepacks" / f"{name}.pack", MOD / "media/texturepacks" / f"{name}.pack"),
                     (output / f"{name}.tiles", MOD / "media" / f"{name}.tiles")]
        registrations += [f"pack={name}", f"tiledef={name} {tile_id}"]
    loader = renderer.SpriteLoader(sources, build_args.work_directory, 128, 256, 8)
    render_dir = output / "render/curves"
    render_dir.mkdir(parents=True, exist_ok=True)
    icon_dir = output / "render/icons"
    icon_dir.mkdir(parents=True, exist_ok=True)
    for definition in definitions:
        name = definition["entity"]
        built = generated[name]
        text = entities.entity_script(built, "RailroaderWayman", f"ES_Wayman{name}", profiles[definition["costProfile"]])
        old_script = MOD / "media/scripts" / f"{name}.txt"
        if old_script.exists():
            new_faces = script_faces(text)
            for facing, rows in script_faces(old_script.read_text()).items():
                face_sprites = {sprite for row in new_faces.get(facing, []) for sprite in row}
                for y, row in enumerate(rows):
                    for x, sprite in enumerate(row):
                        replacement = (new_faces[facing][y][x] if facing in new_faces and y < len(new_faces[facing])
                                       and x < len(new_faces[facing][y]) else "false")
                        # A corrected matrix can move an existing sprite while
                        # retaining its assigned slot and identity in this face.
                        if sprite != "false" and replacement not in ("false", sprite) and sprite not in face_sprites:
                            raise ValueError(f"Rebuild would reallocate a shipped sprite at {name}:{facing}:{x},{y}")
        entity_path = output / "entities" / f"{name}.txt"
        xui_path = output / "entities" / f"{name}_xuiSkin.txt"
        write(entity_path, text)
        write(xui_path, entities.xui_script(name, f"ES_Wayman{name}", f"WaymanEntityName_{name}", f"{name}Icon"))
        installs += [(entity_path, old_script), (xui_path, MOD / "media/scripts/xui/defaultskin" / xui_path.name)]
        for facing, face in definition["faces"].items():
            source_image = renderer.render_face(face, loader, 0)
            packed_image = renderer.render_face(built["faces"][facing], loader, 0)
            if source_image.size != packed_image.size or any(high for _, high in ImageChops.difference(source_image, packed_image).getextrema()):
                raise ValueError(f"Composed curve changed pixels: {name}:{facing}")
            packed_image.save(render_dir / f"{name}_{facing}.png")
        renderer.contact_sheet(built, loader, 24, 24).save(render_dir / f"{name}.png")
        icon = renderer.fit_canvas(renderer.render_face(built["faces"][built["iconFace"]], loader, 0), (48, 48))
        icon_path = icon_dir / f"{name}Icon.png"
        icon.save(icon_path)
        installs.append((icon_path, MOD / "media/textures" / icon_path.name))
    catalog = geometry.collect(ROOT / "definitions/curves", "turn")
    shipped_geometry = MOD / "media/lua/shared/Wayman/WaymanEntityGeometry.lua"
    previous = shipped_geometry.read_text()
    geometry_path = output / "lua/WaymanEntityGeometry.lua"
    write(geometry_path, merge_curve_geometry(previous, catalog, geometry))
    installs.append((geometry_path, shipped_geometry))
    current_ids = {name: int(value) for name, value in re.findall(rf"^tiledef=({FAMILY}_\d+) (\d+)$", info, re.M)}
    curve_packs = re.findall(rf"^pack=({FAMILY}_\d+)$", info, re.M)
    expected_ids = {path.name: FIRST_ID+i for i, path in enumerate(sheets)}
    if current_ids != expected_ids or sorted(curve_packs) != sorted(expected_ids):
        cleaned_info = re.sub(rf"^(?:pack|tiledef)={FAMILY}_\d+[^\n]*\n?", "", info, flags=re.M)
        anchors = list(re.finditer(r"^tiledef=railroader_wayman_tracks_\d+ \d+\n", cleaned_info, re.M))
        if not anchors:
            raise ValueError("Cannot locate tracks registration in mod.info")
        offset = anchors[-1].end()
        info = cleaned_info[:offset] + "\n".join(registrations) + "\n" + cleaned_info[offset:]
    info_path = output / "curves-mod.info"
    write(info_path, info)
    installs.append((info_path, MOD / "mod.info"))
    manifest = {"entities": list(generated), "faces": sum(len(d["faces"]) for d in definitions),
                "sprites": sprite_count, "tiledefs": {path.name: FIRST_ID+i for i, path in enumerate(sheets)},
                "outsideNodesPreserved": outside_nodes,
                "retiredSprites": retired,
                "spriteLayoutSha256": hashlib.sha256(LAYOUT.read_bytes()).hexdigest(),
                "sourceHashes": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in sorted((ROOT / "definitions/curves").glob("*.json"))},
                "files": {str(target.relative_to(MOD)): hashlib.sha256(path.read_bytes()).hexdigest()
                          for path, target in installs}}
    write(output / "curves-build-manifest.json", json_text(manifest))
    shutil.copyfile(ROOT / "definitions/curves/README.md", output / "README-curves.md")
    if args.apply:
        for source, target in installs:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    print(f"VERIFIED: {len(generated)} entities, {manifest['faces']} faces, {sprite_count} sprites; tiledefs {FIRST_ID}-{FIRST_ID+len(sheets)-1}")
    print(f"{'APPLIED' if args.apply else 'PREPARED'}: {len(installs)} mod files; reusable PNGs/definitions in {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generator", type=Path, default=ROOT.parent / "pz-EntityGenerator")
    parser.add_argument("--pz-tilesheet", type=Path, default=ROOT.parent / "pz-tilesheet")
    parser.add_argument("--work", type=Path, default=ROOT / "work")
    parser.add_argument("--output", type=Path, default=ROOT / "output")
    parser.add_argument("--apply", action="store_true", help="Copy the verified curve artifacts into this repository's mod")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
