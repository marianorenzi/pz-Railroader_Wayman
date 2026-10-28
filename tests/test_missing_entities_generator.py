"""Verify appended asset pages, source pixels and complete entity bindings."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "RailroaderWayman/Contents/mods/RailroaderWayman/42"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class MissingEntitiesGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="wayman-entities-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.output = Path(cls.temp.name) / "output"
        subprocess.run([sys.executable, "-B", str(ROOT / "scripts/build_missing_entities.py"),
                        "--output", str(cls.output), "--work", str(Path(cls.temp.name) / "work")],
                       check=True, capture_output=True, text=True)
        cls.manifest = json.loads((cls.output / "entities-build-manifest.json").read_text())
        cls.builder = load("missing_test_builder", ROOT / "scripts/build_missing_entities.py")
        generator = ROOT.parent / "pz-EntityGenerator/scripts"
        sys.path.insert(0, str(generator))
        cls.tiles = load("missing_test_tiles", generator / "build_tilesets.py")
        cls.entities = load("missing_test_entities", generator / "build_entities.py")

    def test_rebuild_is_idempotent_and_all_registered_artifacts_match(self):
        self.assertEqual((len(self.manifest["entities"]), self.manifest["faces"]), (14, 48))
        self.assertEqual(self.manifest["addedFaces"], [])
        self.assertEqual(self.manifest["allocatedSprites"], [])
        self.assertEqual(self.manifest["changedExistingSprites"], [])
        self.assertEqual(self.manifest["retiredSprites"], [])
        self.assertEqual(self.manifest["newPages"], {})
        for relative, digest in self.manifest["files"].items():
            with self.subTest(file=relative):
                self.assertEqual(hashlib.sha256((MOD / relative).read_bytes()).hexdigest(), digest)
        info = (MOD / "mod.info").read_text()
        ids = re.findall(r"^tiledef=(\S+) (\d+)$", info, re.M)
        self.assertEqual(len(ids), len({value for _, value in ids}))
        self.assertTrue(all(100 <= int(value) <= 512 for _, value in ids))
        self.assertEqual({name for name, _ in ids}, set(re.findall(r"^pack=(\S+)$", info, re.M)))

    def test_tilesets_preserve_the_last_released_version(self):
        verifier = load("release_compatibility_test", ROOT / "scripts/verify_release_assets.py")
        report = verifier.verify()
        self.assertEqual(report["commit"], "f8ccfff76fee0d67542eb178328275ffa4892aae")
        self.assertEqual(report["registeredPages"], 16)
        self.assertTrue(report["tiledefIdsPreserved"] and report["spriteNamesPreserved"])
        self.assertTrue(report["spriteDimensionsPreserved"] and report["nonemptySpritesPreserved"])
        self.assertTrue(report["propertiesPreserved"])

    def test_every_source_cell_matches_packed_pixels_properties_and_entity_rows(self):
        sprites, props, cache, seen = {}, {}, {}, set()
        for page in self.manifest["tiledefs"]:
            sprites.update(self.builder.read_pack(MOD / "media/texturepacks" / f"{page}.pack")[1])
            props.update(self.builder.read_tiles(MOD / "media" / f"{page}.tiles")[2])
        original_crop = self.tiles.crop_sprite
        def crop(directory, name, config, cache):
            path = ROOT / "art/sprites" / f"{name}.png"
            if path.is_file():
                with Image.open(path) as image:
                    return image.convert("RGBA")
            return original_crop(directory, name, config, cache)
        self.tiles.crop_sprite = crop
        self.addCleanup(setattr, self.tiles, "crop_sprite", original_crop)
        for family in ("tracks", "switches"):
            for path in sorted((ROOT / "definitions" / family).glob("*.json")):
                source = json.loads(path.read_text())
                name = self.builder.ALIASES.get(source["entity"], source["entity"])
                built = json.loads((self.output / "definitions" / ("railroader_wayman_" + family) /
                                    path.name.split("_", 1)[1]).read_text())
                self.assertEqual(built["entity"], name)
                self.assertEqual(set(built), set(source))
                script = self.builder.script_faces((MOD / "media/scripts" / f"{name}.txt").read_text())
                sizes = self.entities.normalized_sizes(built["faces"])
                for facing, face in source["faces"].items():
                    generated = built["faces"][facing]
                    self.assertEqual({k:v for k,v in generated.items() if k != "layers"},
                                     {k:v for k,v in face.items() if k != "layers"})
                    self.assertEqual(script[facing], self.entities.padded_rows(generated, *sizes[facing]))
                    for y,row in enumerate(generated["layers"][0]["tiles"]):
                        for x,sprite in enumerate(row):
                            expected, inputs = self.tiles.compose_cell(face["layers"], x, y,
                                ROOT.parent / "pz-EntityGenerator/sources", self.builder.CONFIG, cache)
                            self.assertEqual(bool(sprite), bool(inputs))
                            if sprite:
                                self.assertNotIn(sprite, seen)
                                seen.add(sprite)
                                self.assertEqual(sprites[sprite].tobytes(), expected.tobytes(), (name,facing,x,y))
                                self.assertEqual(props[sprite], {"CanScrap":"true", "Material":"Wood", "CustomName":"Wayman_"+name})

    def test_crossing_faces_and_new_turnout_are_constructible_and_translated(self):
        scripts = MOD / "media/scripts"
        crossing = self.builder.script_faces((scripts / "DiagonalCrossingEdge.txt").read_text())
        self.assertEqual(set(crossing), set("NESW"))
        for name in ("Right90DegTurnout", "Left90DegTurnout", "WyeTurnout"):
            script = (scripts / f"{name}.txt").read_text()
            self.assertEqual(set(self.builder.script_faces(script)), set("NESW"))
            self.assertEqual(script.count("OnCreate = RailroaderWaymanEntityRuntime.OnCreate,"), 1)
            self.assertEqual(script.count("component CraftRecipe"), 1)
            xui = (scripts / "xui/defaultskin" / f"{name}_xuiSkin.txt").read_text()
            self.assertIn(f"Icon = {name}Icon,", xui)
            with Image.open(MOD / "media/textures" / f"{name}Icon.png") as image:
                self.assertEqual(image.size, (48, 48))
                self.assertIsNotNone(image.getbbox())
            for language in ("EN", "ES", "RU"):
                directory = MOD / "media/lua/shared/Translate" / language
                self.assertTrue(json.loads((directory / "Recipes.json").read_text())[f"WaymanEntityName_{name}"])
                self.assertTrue(json.loads((directory / "Moveables.json").read_text())[f"Wayman_{name}"])


class SpriteRetirementTest(unittest.TestCase):
    def test_removed_sprite_becomes_empty_and_new_cell_uses_a_different_slot(self):
        builder = load("retirement_builder", ROOT / "scripts/build_missing_entities.py")
        generator = ROOT.parent / "pz-EntityGenerator"
        sys.path.insert(0, str(generator / "scripts"))
        tiles = load("retirement_tiles", generator / "scripts/build_tilesets.py")
        entities = load("retirement_entities", generator / "scripts/build_entities.py")
        packer = load("retirement_packer", ROOT.parent / "pz-tilesheet/pz_tilesheet.py")
        profiles = entities.load_profiles(ROOT / "definitions/CostProfiles.json")
        with tempfile.TemporaryDirectory(prefix="wayman-retirement-test-") as directory:
            root = Path(directory)
            mod = root / "mod"
            media = mod / "media"
            builder.ROOT, builder.MOD = root, mod
            def save(path, value):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
            save(root / "definitions/CostProfiles.json", (ROOT / "definitions/CostProfiles.json").read_text())
            save(mod / "mod.info", "pack=railroader_wayman_tracks_01\ntiledef=railroader_wayman_tracks_01 480\n"
                 "pack=railroader_wayman_switches_01\ntiledef=railroader_wayman_switches_01 500\n")
            cache = {}
            for family, tile_id, name, profile, cells in (
                ("tracks", 480, "TestTrack", "track", 1),
                ("switches", 500, "TestTurnout", "turnout", 3),
            ):
                page = f"railroader_wayman_{family}_01"
                properties, images = {}, []
                for index in range(64):
                    sprite = f"{page}_{index}"
                    image = Image.new("RGBA", (128, 256))
                    properties[sprite] = {}
                    if index < cells:
                        image, _ = tiles.compose_cell([{"index": 0, "tiles": [[f"industry_railroad_01_{index}"]]}],
                                                     0, 0, generator / "sources", builder.CONFIG, cache)
                        properties[sprite] = {"CanScrap": "true", "Material": "Wood", "CustomName": "Wayman_"+name}
                    images.append({"path": str(index), "name": str(index), "image": image})
                atlas, entries, rows = packer.build_atlas(images, 128, 256, 8)
                media.mkdir(parents=True, exist_ok=True)
                packer.write_pack(str(media), page, atlas, entries, 128, 256)
                packer.write_tiles_bin(str(media), page, tile_id, entries, 8, rows, properties)
                face = {"width": cells + (family == "switches"), "height": 1,
                        "layers": [{"index": 0, "tiles": [[f"{page}_{i}" for i in range(cells)] +
                                   ([None] if family == "switches" else [])]}]}
                if family == "switches":
                    face.update(at={"x": 1, "y": 0, "z": 0}, switch={"x": 2, "y": 0, "z": 0})
                definition = {"entity": name, "costProfile": profile, "costMultiplier": 1, "iconFace": "N",
                              "faces": {"N": face}}
                save(media / "scripts" / f"{name}.txt", entities.entity_script(
                    definition, "RailroaderWayman", f"ES_Wayman{name}", profiles[profile]))
                face["layers"][0]["tiles"] = [["industry_railroad_01_0"]] if family == "tracks" else [[
                    None, "industry_railroad_01_1", "industry_railroad_01_2", "industry_railroad_01_3"]]
                save(root / "definitions" / family / f"00_{name}.json", json.dumps(definition))
            for language in ("EN", "ES", "RU"):
                for filename in ("Recipes.json", "Moveables.json"):
                    save(media / "lua/shared/Translate" / language / filename, "{}\n")
            output = root / "output"
            args = SimpleNamespace(generator=generator, pz_tilesheet=ROOT.parent / "pz-tilesheet",
                                   output=output, work=root / "work", apply=False)
            with patch("sys.stdout", new=io.StringIO()):
                builder.build(args)
            manifest = json.loads((output / "entities-build-manifest.json").read_text())
            self.assertEqual(manifest["retiredSprites"], ["railroader_wayman_switches_01_0"])
            self.assertEqual([item["sprite"] for item in manifest["allocatedSprites"]],
                             ["railroader_wayman_switches_01_3"])
            sprites = builder.read_pack(output / "texturepacks/railroader_wayman_switches_01.pack")[1]
            properties = builder.read_tiles(output / "railroader_wayman_switches_01.tiles")[2]
            self.assertIsNone(sprites["railroader_wayman_switches_01_0"].getbbox())
            self.assertEqual(properties["railroader_wayman_switches_01_0"], {})
            published = builder.script_faces((output / "entities/TestTurnout.txt").read_text())["N"][0]
            self.assertEqual(published, [None, "railroader_wayman_switches_01_1",
                                        "railroader_wayman_switches_01_2", "railroader_wayman_switches_01_3"])


if __name__ == "__main__":
    unittest.main()
