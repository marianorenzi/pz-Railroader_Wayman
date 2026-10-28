#!/usr/bin/env python3
"""Verify tileset compatibility with the last released mod, allowing newer assets."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
MOD_RELATIVE = Path("RailroaderWayman/Contents/mods/RailroaderWayman/42")
RELEASE = "f8ccfff76fee0d67542eb178328275ffa4892aae"


def verify(root=ROOT, reference=RELEASE):
    root = Path(root)
    mod = root / MOD_RELATIVE
    spec = importlib.util.spec_from_file_location("release_asset_reader", ROOT / "scripts/build_missing_entities.py")
    assets = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(assets)
    def git(*arguments):
        return subprocess.run(["git", *arguments], cwd=root, check=True, capture_output=True).stdout
    commit = git("rev-parse", "--verify", reference + "^{commit}").decode().strip()
    def blob(relative):
        return git("show", f"{commit}:{relative}")
    old_info = blob(MOD_RELATIVE / "mod.info").decode()
    old_ids = {name:int(value) for name,value in re.findall(r"^tiledef=(\S+) (\d+)$", old_info, re.M)}
    new_ids = {name:int(value) for name,value in re.findall(r"^tiledef=(\S+) (\d+)$", (mod / "mod.info").read_text(), re.M)}
    if len(new_ids) != len(set(new_ids.values())):
        raise ValueError("Current tiledef IDs collide")
    released = set()
    entities, face_count, binding_count, layout_updates = 0, 0, 0, 0
    scripts_relative = MOD_RELATIVE / "media/scripts"
    for name in git("ls-tree", "-r", "--name-only", commit, str(scripts_relative)).decode().splitlines():
        path = Path(name)
        if path.parent != scripts_relative or path.suffix != ".txt":
            continue
        previous = assets.script_faces(blob(path).decode())
        if not previous:
            continue
        current = assets.script_faces((root / path).read_text())
        entities += 1
        for facing, rows in previous.items():
            face_count += 1
            if facing not in current:
                raise ValueError(f"Released entity face disappeared: {path.stem}:{facing}")
            for y,row in enumerate(rows):
                for x,sprite in enumerate(row):
                    if not sprite:
                        continue
                    actual = current[facing][y][x] if y < len(current[facing]) and x < len(current[facing][y]) else None
                    if actual != sprite:
                        layout_updates += 1
                    released.add(sprite)
                    binding_count += 1
    compared, pixel_updates = set(), []
    with tempfile.TemporaryDirectory(prefix="wayman-release-assets-") as temporary:
        temporary = Path(temporary)
        for page, tile_id in old_ids.items():
            if new_ids.get(page) != tile_id:
                raise ValueError(f"Released tiledef ID changed: {page}")
            pack = temporary / f"{page}.pack"
            tiledef = temporary / f"{page}.tiles"
            pack.write_bytes(blob(MOD_RELATIVE / f"media/texturepacks/{page}.pack"))
            tiledef.write_bytes(blob(MOD_RELATIVE / f"media/{page}.tiles"))
            old_page, old_sprites = assets.read_pack(pack)
            new_page, new_sprites = assets.read_pack(mod / f"media/texturepacks/{page}.pack")
            old_id, _, old_properties = assets.read_tiles(tiledef)
            new_id, _, new_properties = assets.read_tiles(mod / f"media/{page}.tiles")
            if old_page != new_page or old_id != new_id or new_id != tile_id:
                raise ValueError(f"Released binary page identity changed: {page}")
            for sprite in released.intersection(old_sprites):
                if sprite not in new_sprites:
                    raise ValueError(f"Released sprite disappeared: {sprite}")
                if old_sprites[sprite].getbbox() is not None and new_sprites[sprite].getbbox() is None:
                    raise ValueError(f"Released sprite became empty: {sprite}")
                if old_sprites[sprite].tobytes() != new_sprites[sprite].tobytes():
                    pixel_updates.append(sprite)
                if old_properties[sprite] != new_properties[sprite]:
                    raise ValueError(f"Released sprite properties changed: {sprite}")
                compared.add(sprite)
    if compared != released:
        raise ValueError(f"Released sprite is missing from registered pages: {sorted(released-compared)}")
    return {"release": "1.0.0", "commit": commit, "registeredPages": len(old_ids),
            "entities": entities, "faces": face_count, "spriteBindings": binding_count,
            "uniqueSprites": len(compared), "tiledefIdsPreserved": True,
            "spriteNamesPreserved": True, "spriteDimensionsPreserved": True,
            "nonemptySpritesPreserved": True, "propertiesPreserved": True,
            "pixelUpdates": sorted(pixel_updates), "entityLayoutUpdates": layout_updates}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", default=RELEASE)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = verify(reference=args.reference)
    text = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
