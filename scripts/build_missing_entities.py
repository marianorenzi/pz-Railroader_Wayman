#!/usr/bin/env python3
"""Build tracks/turnouts against published sprite bindings, appending missing art."""
import argparse
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import shutil
import struct
import sys

from PIL import Image

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "RailroaderWayman/Contents/mods/RailroaderWayman/42"
CONFIG = {"tileWidth": 128, "tileHeight": 256, "sourceColumns": 8}
ALIASES = {"CrossingEdgeDiag": "DiagonalCrossingEdge",
           "CrossingSegmentDiag": "DiagonalCrossingSegment",
           "TrackSegmentDiag": "DiagonalTrackSegment"}


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def read_pack(path):
    stream = io.BytesIO(path.read_bytes())
    def integer():
        return struct.unpack("<I", stream.read(4))[0]
    def string():
        return stream.read(integer()).decode()
    if stream.read(4) != b"PZPK" or integer() != 1 or integer() != 1:
        raise ValueError(f"Unsupported pack header: {path}")
    page, count, flags = string(), integer(), integer()
    if (count, flags) != (64, 1):
        raise ValueError(f"Expected 64 untrimmed sprites: {path}")
    entries = {string(): struct.unpack("<8I", stream.read(32)) for _ in range(count)}
    atlas = Image.open(io.BytesIO(stream.read(integer()))).convert("RGBA")
    if stream.read() or atlas.size != (1024, 2048):
        raise ValueError(f"Invalid pack atlas: {path}")
    sprites = {}
    for name, (x, y, w, h, dx, dy, fw, fh) in entries.items():
        if (w, h, dx, dy, fw, fh) != (128, 256, 0, 0, 128, 256):
            raise ValueError(f"Unexpected sprite dimensions: {name}")
        sprites[name] = atlas.crop((x, y, x+w, y+h))
    return page, sprites


def read_tiles(path):
    stream = io.BytesIO(path.read_bytes())
    if stream.read(12) != b"tdef" + struct.pack("<II", 1, 1):
        raise ValueError(f"Unsupported tiledef header: {path}")
    sheet = stream.readline().decode().rstrip("\n")
    image = stream.readline().decode().rstrip("\n")
    columns, rows, tile_id, count = struct.unpack("<4I", stream.read(16))
    if image != sheet + ".png" or (columns, rows, count) != (8, 8, 64) or not 1 <= tile_id <= 512:
        raise ValueError(f"Invalid tiledef allocation: {path}")
    header = path.read_bytes()[:stream.tell()]
    properties = {}
    for index in range(count):
        values = {}
        for _ in range(struct.unpack("<I", stream.read(4))[0]):
            key = stream.readline().decode().rstrip("\n")
            values[key] = stream.readline().decode().rstrip("\n")
        properties[f"{sheet}_{index}"] = values
    if stream.read():
        raise ValueError(f"Trailing tiledef data: {path}")
    return tile_id, header, properties


def tiles_bytes(header, sheet, properties):
    result = io.BytesIO()
    result.write(header)
    for index in range(64):
        values = properties[f"{sheet}_{index}"]
        result.write(struct.pack("<I", len(values)))
        for key, value in values.items():
            result.write(f"{key}\n{value}\n".encode())
    return result.getvalue()


def script_faces(text):
    faces, facing = {}, None
    for line in text.splitlines():
        match = re.fullmatch(r"\s*face ([NESW])\s*", line)
        if match:
            facing = match[1]
            faces[facing] = []
        match = re.fullmatch(r"\s*row = (.*),\s*", line)
        if match:
            faces[facing].append([None if value == "false" else value for value in match[1].split()])
    return faces


def free_tiledef(ids):
    used = set(ids.values())
    for candidate in list(range(480, 513)) + list(range(479, 99, -1)):
        if candidate not in used:
            return candidate
    raise ValueError("No unallocated tiledef IDs remain between 100 and 512")


def retire_removed_cells(entity, facing, previous, current, sprites, properties):
    """Clear removed cells without moving or reusing any published sprite slot."""
    retired = []
    for y, row in enumerate(previous):
        for x, sprite in enumerate(row):
            if sprite is None:
                continue
            replacement = current[y][x] if y < len(current) and x < len(current[y]) else None
            if replacement == sprite:
                continue
            if replacement is not None or any(sprite in values for values in current):
                raise ValueError(f"A published sprite would move: {entity}:{facing}:{x},{y}")
            sprites[sprite] = Image.new("RGBA", (128, 256))
            properties[sprite] = {}
            retired.append({"entity": entity, "facing": facing, "x": x, "y": y, "sprite": sprite})
    return retired


def build(args):
    generator = args.generator.resolve()
    sys.path.insert(0, str(generator / "scripts"))
    tiles = module("missing_tiles", generator / "scripts/build_tilesets.py")
    entities = module("missing_entities", generator / "scripts/build_entities.py")
    geometry = module("missing_geometry", generator / "scripts/build_geometry.py")
    renderer = module("missing_renderer", generator / "scripts/render_entity.py")
    packer = module("missing_packer", args.pz_tilesheet / "pz_tilesheet.py")
    output, work = args.output.resolve(), args.work.resolve()
    media = MOD / "media"
    info = (MOD / "mod.info").read_text()
    ids = {name: int(value) for name, value in re.findall(r"^tiledef=(\S+) (\d+)$", info, re.M)}
    if len(ids) != len(set(ids.values())) or set(ids) != set(re.findall(r"^pack=(\S+)$", info, re.M)):
        raise ValueError("Duplicate or inconsistent pack/tiledef registrations")
    families = ["railroader_wayman_tracks", "railroader_wayman_switches"]
    pages = {page for page in ids if any(page.startswith(family + "_") for family in families)}
    original_pages = set(pages)
    sprites, properties, headers, original_pixels = {}, {}, {}, {}
    for page in sorted(pages):
        _, decoded = read_pack(media / "texturepacks" / f"{page}.pack")
        actual_id, header, values = read_tiles(media / f"{page}.tiles")
        if actual_id != ids[page]:
            raise ValueError(f"Tiledef ID differs from mod.info: {page}")
        sprites.update(decoded)
        properties.update(values)
        headers[page] = header
        original_pixels.update({name: image.tobytes() for name, image in decoded.items()})
    bindings, original_refs = {}, set()
    for path in (media / "scripts").glob("*.txt"):
        bindings[path.stem] = script_faces(path.read_text())
        original_refs.update(sprite for rows in bindings[path.stem].values() for row in rows for sprite in row if sprite)
    free = {family: sorted((name for name, image in sprites.items()
                           if name.startswith(family + "_") and name not in original_refs
                           and image.getbbox() is None and not properties[name]),
                          key=lambda name: tuple(map(int, name.rsplit("_", 2)[1:])))
            for family in families}
    allocated = []
    def allocate(family):
        if not free[family]:
            number = max(int(page.rsplit("_", 1)[1]) for page in pages if page.startswith(family + "_")) + 1
            page = f"{family}_{number:02d}"
            ids[page] = free_tiledef(ids)
            pages.add(page)
            for index in range(64):
                name = f"{page}_{index}"
                sprites[name] = Image.new("RGBA", (128, 256))
                properties[name] = {}
                free[family].append(name)
        return free[family].pop(0)
    vanilla_crop = tiles.crop_sprite
    custom_sources = set()
    def crop(source_dir, name, config, cache):
        local = ROOT / "art/sprites" / f"{name}.png"
        if not local.is_file():
            return vanilla_crop(source_dir, name, config, cache)
        custom_sources.add(local)
        if name not in cache:
            with Image.open(local) as image:
                if image.size != (128, 256):
                    raise ValueError(f"Expected a 128x256 custom sprite: {local}")
                cache[name] = image.convert("RGBA")
        return cache[name]
    tiles.crop_sprite = crop
    profiles = entities.load_profiles(ROOT / "definitions/CostProfiles.json")
    generated, sources, claimed, missing, retired = {}, {}, set(), [], []
    cache, source_paths = {}, []
    for directory, family in zip(("tracks", "switches"), families):
        for path in sorted((ROOT / "definitions" / directory).glob("*.json")):
            source_paths.append(path)
            source = json.loads(path.read_text())
            tiles.validate_definition(path, source)
            name = ALIASES.get(source["entity"], source["entity"])
            result = copy.deepcopy(source)
            result["entity"] = name
            old_faces = bindings.get(name, {})
            for facing, face in source["faces"].items():
                if facing not in old_faces:
                    missing.append({"entity": source["entity"], "facing": facing})
                old_rows, rows = old_faces.get(facing, []), []
                for y in range(face["height"]):
                    row = []
                    for x in range(face["width"]):
                        image, inputs = tiles.compose_cell(face["layers"], x, y, generator / "sources", CONFIG, cache)
                        if not inputs:
                            row.append(None)
                            continue
                        sprite = old_rows[y][x] if y < len(old_rows) and x < len(old_rows[y]) else None
                        if sprite is None:
                            sprite = allocate(family)
                            allocated.append({"entity": source["entity"], "facing": facing, "x": x, "y": y, "sprite": sprite})
                        if sprite not in sprites or sprite in claimed:
                            raise ValueError(f"Missing or reused sprite binding: {name}:{facing}:{x},{y}:{sprite}")
                        claimed.add(sprite)
                        sprites[sprite] = image
                        properties[sprite].update(CanScrap="true", Material="Wood", CustomName=f"Wayman_{name}")
                        row.append(sprite)
                    rows.append(row)
                result["faces"][facing]["layers"] = [{"index": 0, "tiles": rows}]
            for facing, rows in old_faces.items():
                new_rows = result["faces"][facing]["layers"][0]["tiles"]
                retired.extend(retire_removed_cells(name, facing, rows, new_rows, sprites, properties))
            generated[name], sources[name] = result, source
            write(output / "definitions" / family / path.name.split("_", 1)[1], json_text(result))
    installs = {}
    def install(source, relative):
        installs[relative] = source
    changed_pixels = {name for name in sprites if name not in original_pixels or sprites[name].tobytes() != original_pixels[name]}
    for page in sorted(pages):
        family = page.rsplit("_", 1)[0]
        directory = work / family / page
        if directory.exists():
            shutil.rmtree(directory)
        directory.mkdir(parents=True)
        for index in range(64):
            sprites[f"{page}_{index}"].save(directory / f"{index:02d}__slot.png")
        atlas, entries, rows = packer.build_atlas([
            {"path": str(index), "name": str(index), "image": sprites[f"{page}_{index}"]}
            for index in range(64)], 128, 256, 8)
        output.mkdir(parents=True, exist_ok=True)
        pack_path = output / "texturepacks" / f"{page}.pack"
        if page not in original_pages or any(name.startswith(page + "_") for name in changed_pixels):
            packer.write_pack(str(output), page, atlas, entries, 128, 256)
        else:
            pack_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(media / "texturepacks" / f"{page}.pack", pack_path)
        tile_path = output / f"{page}.tiles"
        if page in original_pages:
            tile_path.write_bytes(tiles_bytes(headers[page], page, properties))
        else:
            packer.write_tiles_bin(str(output), page, ids[page], entries, 8, rows, properties)
        packer.write_tiles_txt(str(output), page, ids[page], entries, 8, rows, properties)
        atlas.save(output / f"{page}.png")
        actual_page, decoded = read_pack(pack_path)
        actual_id, _, actual_props = read_tiles(tile_path)
        if actual_page != page + "0" or actual_id != ids[page]:
            raise ValueError(f"Repacked identity differs: {page}")
        for sprite, image in decoded.items():
            if image.tobytes() != sprites[sprite].tobytes() or actual_props[sprite] != properties[sprite]:
                raise ValueError(f"Packed pixels/properties differ: {sprite}")
        install(pack_path, f"media/texturepacks/{page}.pack")
        install(tile_path, f"media/{page}.tiles")
    class Loader:
        tile_width, tile_height = 128, 256
        def get(self, name):
            return sprites[name] if name in sprites else crop(generator / "sources", name, CONFIG, cache)
    loader = Loader()
    for name, built in generated.items():
        source = sources[name]
        text = entities.entity_script(built, "RailroaderWayman", f"ES_Wayman{name}", profiles[source["costProfile"]])
        old = media / "scripts" / f"{name}.txt"
        if old.exists() and text.split("        component CraftRecipe", 1)[1] != old.read_text().split("        component CraftRecipe", 1)[1]:
            raise ValueError(f"Published recipe would change: {name}")
        target = output / "entities" / f"{name}.txt"
        write(target, text)
        install(target, f"media/scripts/{name}.txt")
        xui = output / "entities" / f"{name}_xuiSkin.txt"
        write(xui, entities.xui_script(name, f"ES_Wayman{name}", f"WaymanEntityName_{name}", f"{name}Icon"))
        install(xui, f"media/scripts/xui/defaultskin/{name}_xuiSkin.txt")
        render_dir = output / "render/entities"
        render_dir.mkdir(parents=True, exist_ok=True)
        for facing, face in built["faces"].items():
            renderer.render_face(face, loader, 0).save(render_dir / f"{source['entity']}_{facing}.png")
        renderer.contact_sheet(built, loader, 24, 24).save(render_dir / f"{source['entity']}.png")
        if not (media / "textures" / f"{name}Icon.png").exists():
            icon_path = output / "render/icons" / f"{name}Icon.png"
            icon_path.parent.mkdir(parents=True, exist_ok=True)
            renderer.fit_canvas(renderer.render_face(built["faces"][built["iconFace"]], loader, 0), (48, 48)).save(icon_path)
            install(icon_path, f"media/textures/{name}Icon.png")
    catalog = geometry.collect(ROOT / "definitions/turns", "turn")
    catalog.update(geometry.collect(ROOT / "definitions/switches", "turnout"))
    catalog.update(geometry.collect(ROOT / "definitions/curves", "turn"))
    lines = ["-- Generated by tilesets/build_geometry.py. Do not edit by hand.", "RailroaderWaymanEntityGeometry = {"]
    for name, faces in catalog.items():
        lines.append(f"    {name} = {{")
        lines.extend(f"        {facing} = {geometry.lua_value(face)}," for facing, face in faces.items())
        lines.append("    },")
    geo_path = output / "lua/WaymanEntityGeometry.lua"
    write(geo_path, "\n".join(lines + ["}", ""]))
    install(geo_path, "media/lua/shared/Wayman/WaymanEntityGeometry.lua")
    for language, label in (("EN", "Right 90-degree turnout"), ("ES", "Desvío derecho de 90 grados"), ("RU", "Правый стрелочный перевод на 90°")):
        for filename, prefix in (("Recipes.json", "WaymanEntityName_"), ("Moveables.json", "Wayman_")):
            relative = f"media/lua/shared/Translate/{language}/{filename}"
            values = json.loads((MOD / relative).read_text())
            values.setdefault(prefix + "Right90DegTurnout", label)
            target = output / "translations" / language / filename
            write(target, json.dumps(values, ensure_ascii=False, indent=4) + "\n")
            install(target, relative)
    for family in families:
        added = sorted(page for page in pages - original_pages if page.startswith(family + "_"))
        if added:
            matches = list(re.finditer(rf"^tiledef={family}_\d+ \d+\n", info, re.M))
            if not matches:
                raise ValueError(f"Missing registration anchor: {family}")
            offset = matches[-1].end()
            registrations = "".join(f"pack={page}\ntiledef={page} {ids[page]}\n" for page in added)
            info = info[:offset] + registrations + info[offset:]
    info_path = output / "entities-mod.info"
    write(info_path, info)
    install(info_path, "mod.info")
    source_paths += list((ROOT / "definitions/turns").glob("*.json")) + list((ROOT / "definitions/curves").glob("*.json"))
    source_paths += [ROOT / "definitions/CostProfiles.json"] + sorted(custom_sources)
    manifest = {"entities": list(generated), "faces": sum(len(d["faces"]) for d in generated.values()),
                "addedFaces": missing, "allocatedSprites": allocated,
                "retiredSprites": sorted(entry["sprite"] for entry in retired),
                "retiredBindings": retired,
                "changedExistingSprites": sorted(name for name in changed_pixels if name in original_refs),
                "tiledefs": {page: ids[page] for page in sorted(pages)},
                "newPages": {page: ids[page] for page in sorted(pages-original_pages)},
                "sourceHashes": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths},
                "files": {relative: hashlib.sha256(path.read_bytes()).hexdigest() for relative, path in installs.items()}}
    write(output / "entities-build-manifest.json", json_text(manifest))
    if args.apply:
        for relative, source in installs.items():
            target = MOD / relative
            if not target.exists() or target.read_bytes() != source.read_bytes():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
    print(f"VERIFIED: {len(generated)} entities, {manifest['faces']} faces; {len(missing)} new faces, {len(allocated)} new sprites, {len(retired)} retired")
    print(f"{'APPLIED' if args.apply else 'PREPARED'}: {len(pages-original_pages)} new pages; existing sprite IDs preserved")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generator", type=Path, default=ROOT.parent / "pz-EntityGenerator")
    parser.add_argument("--pz-tilesheet", type=Path, default=ROOT.parent / "pz-tilesheet")
    parser.add_argument("--work", type=Path, default=ROOT / "work/entities-build")
    parser.add_argument("--output", type=Path, default=ROOT / "output")
    parser.add_argument("--apply", action="store_true")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
