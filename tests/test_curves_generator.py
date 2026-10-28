"""Rebuild curves and verify shipped art, tile identities, recipes and geometry."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "RailroaderWayman/Contents/mods/RailroaderWayman/42"
GENERATOR = Path(os.environ.get("ENTITY_GENERATOR_ROOT", ROOT.parent / "pz-EntityGenerator"))
PACKER = Path(os.environ.get("PZ_TILESHEET_ROOT", ROOT.parent / "pz-tilesheet"))
FAMILY = "railroader_wayman_curves"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_pack(path):
    stream = io.BytesIO(path.read_bytes())
    def integer():
        return struct.unpack("<I", stream.read(4))[0]
    def string():
        return stream.read(integer()).decode()
    assert stream.read(4) == b"PZPK" and integer() == 1 and integer() == 1
    page = string()
    count, flags = integer(), integer()
    assert count == 64 and flags == 1
    entries = {string(): struct.unpack("<8I", stream.read(32)) for _ in range(count)}
    atlas = Image.open(io.BytesIO(stream.read(integer()))).convert("RGBA")
    assert not stream.read() and atlas.size == (1024, 2048)
    sprites = {}
    for name, (x, y, w, h, dx, dy, fw, fh) in entries.items():
        assert (w, h, dx, dy, fw, fh) == (128, 256, 0, 0, 128, 256)
        sprites[name] = atlas.crop((x, y, x+w, y+h))
    return page, sprites


def read_tiles(path):
    stream = io.BytesIO(path.read_bytes())
    assert stream.read(12) == b"tdef" + struct.pack("<II", 1, 1)
    name = stream.readline().decode().rstrip("\n")
    assert stream.readline().decode().rstrip("\n") == name + ".png"
    columns, rows, tile_id, count = struct.unpack("<4I", stream.read(16))
    assert (columns, rows, count) == (8, 8, 64)
    props = {}
    for index in range(count):
        values = {}
        for _ in range(struct.unpack("<I", stream.read(4))[0]):
            key = stream.readline().decode().rstrip("\n")
            values[key] = stream.readline().decode().rstrip("\n")
        props[f"{name}_{index}"] = values
    assert not stream.read()
    return name, tile_id, props


class CurvesGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="wayman-curves-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.output, cls.work = Path(cls.temp.name) / "output", Path(cls.temp.name) / "work"
        subprocess.run([sys.executable, "-B", str(ROOT / "scripts/build_curves.py"),
                        "--generator", str(GENERATOR), "--pz-tilesheet", str(PACKER),
                        "--output", str(cls.output), "--work", str(cls.work)],
                       check=True, capture_output=True, text=True)
        cls.manifest = json.loads((cls.output / "curves-build-manifest.json").read_text())
        cls.builder = load("curves_builder", ROOT / "scripts/build_curves.py")
        sys.path.insert(0, str(GENERATOR / "scripts"))
        cls.tiles = load("curve_source_tiles", GENERATOR / "scripts/build_tilesets.py")
        cls.entities = load("curve_source_entities", GENERATOR / "scripts/build_entities.py")
        cls.definitions = [json.loads(path.read_text()) for path in sorted((ROOT / "definitions/curves").glob("*.json"))]

    def test_rebuild_matches_shipped_artifacts_and_keeps_tiledefs_unique(self):
        self.assertEqual((self.manifest["faces"], self.manifest["sprites"]), (12, 148))
        for relative, expected in self.manifest["files"].items():
            with self.subTest(file=relative):
                self.assertEqual(hashlib.sha256((MOD / relative).read_bytes()).hexdigest(), expected)
        info = (MOD / "mod.info").read_text()
        ids = re.findall(r"^tiledef=(\S+) (\d+)$", info, re.M)
        self.assertEqual(len(ids), len({value for _, value in ids}))
        self.assertEqual(len(ids), len({name for name, _ in ids}))
        for name, value in self.manifest["tiledefs"].items():
            self.assertIn((name, str(value)), ids)
            self.assertTrue(100 <= value <= 512)

    def test_every_shipped_pixel_and_native_scrap_property_matches_its_source(self):
        sprites, properties = {}, {}
        for name, value in self.manifest["tiledefs"].items():
            page, packed = read_pack(MOD / "media/texturepacks" / f"{name}.pack")
            self.assertEqual(page, name + "0")
            actual_name, actual_id, props = read_tiles(MOD / "media" / f"{name}.tiles")
            self.assertEqual((actual_name, actual_id), (name, value))
            sprites.update(packed)
            properties.update(props)
        cache, used = {}, set()
        for source in self.definitions:
            built = json.loads((self.output / "definitions" / FAMILY / f"{source['entity']}.json").read_text())
            self.assertEqual({k: v for k, v in built.items() if k != "faces"},
                             {k: v for k, v in source.items() if k != "faces"})
            for facing, face in source["faces"].items():
                generated = built["faces"][facing]
                self.assertEqual({k: v for k, v in generated.items() if k != "layers"},
                                 {k: v for k, v in face.items() if k != "layers"})
                for y, row in enumerate(generated["layers"][0]["tiles"]):
                    for x, sprite in enumerate(row):
                        expected, layers = self.tiles.compose_cell(face["layers"], x, y, GENERATOR / "sources", self.builder.CONFIG, cache)
                        self.assertEqual(bool(sprite), bool(layers))
                        if sprite:
                            self.assertNotIn(sprite, used)
                            used.add(sprite)
                            self.assertEqual(sprites[sprite].tobytes(), expected.tobytes(), (source["entity"], facing, x, y))
                            self.assertEqual(properties[sprite], {"CanScrap": "true", "Material": "Wood",
                                                               "CustomName": "Wayman_" + source["entity"]})
        self.assertEqual(len(used), 148)
        for sprite in set(sprites) - used:
            self.assertIsNone(sprites[sprite].getbbox())
            self.assertEqual(properties[sprite], {})

    def test_entity_bindings_callbacks_costs_icons_and_translations(self):
        profiles = self.entities.load_profiles(ROOT / "definitions/CostProfiles.json")
        for definition in self.definitions:
            name = definition["entity"]
            built = json.loads((self.output / "definitions" / FAMILY / f"{name}.json").read_text())
            text = (MOD / "media/scripts" / f"{name}.txt").read_text()
            self.assertEqual(text.count("OnCreate = RailroaderWaymanEntityRuntime.OnCreate,"), 1)
            faces = self.builder.script_faces(text)
            for facing, size in self.entities.normalized_sizes(built["faces"]).items():
                expected = [[v or "false" for v in row] for row in self.entities.padded_rows(built["faces"][facing], *size)]
                self.assertEqual(faces[facing], expected)
            recipe = "\n".join(self.entities.EntityGenerator.recipe_lines(definition, profiles["turn"]))
            self.assertIn(recipe, text)
            xui = (MOD / "media/scripts/xui/defaultskin" / f"{name}_xuiSkin.txt").read_text()
            self.assertIn(f"Icon = {name}Icon,", xui)
            self.assertIn(f"DisplayName = WaymanEntityName_{name},", xui)
            with Image.open(MOD / "media/textures" / f"{name}Icon.png") as icon:
                self.assertEqual(icon.size, (48, 48))
                self.assertIsNotNone(icon.getbbox())
            for language in ("EN", "ES", "RU"):
                directory = MOD / "media/lua/shared/Translate" / language
                self.assertTrue(json.loads((directory / "Recipes.json").read_text())[f"WaymanEntityName_{name}"])
                self.assertTrue(json.loads((directory / "Moveables.json").read_text())[f"Wayman_{name}"])
        self.assertEqual(self.manifest["outsideNodesPreserved"], [
            {"entity": "Left45DegCurve", "facing": "S", "node": {"x": 5, "y": 4, "z": 0}},
            {"entity": "Curve90Deg", "facing": "S", "node": {"x": 5, "y": 6, "z": 0}}])

    def test_exported_source_directory_can_mix_curves_with_vanilla_tiles(self):
        sources = self.output / "curve-sources"
        self.assertEqual(len(list(sources.glob("*.png"))), 8)
        _, packed = read_pack(MOD / "media/texturepacks/railroader_wayman_curves_01.pack")
        curve = self.tiles.crop_sprite(sources, FAMILY + "_01_0", self.builder.CONFIG, {})
        self.assertEqual(curve.tobytes(), packed[FAMILY + "_01_0"].tobytes())
        name = "industry_railroad_01_7"
        vanilla = self.tiles.crop_sprite(GENERATOR / "sources", name, self.builder.CONFIG, {})
        layers = [{"index": 0, "tiles": [[FAMILY + "_01_0"]]}, {"index": 1, "tiles": [[name]]}]
        combined, used = self.tiles.compose_cell(layers, 0, 0, sources, self.builder.CONFIG, {})
        self.assertEqual(used, [FAMILY + "_01_0", name])
        self.assertEqual(combined.tobytes(), Image.alpha_composite(curve, vanilla).tobytes())


class CurveLayoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = load("curve_layout_builder", ROOT / "scripts/build_curves.py")
        sys.path.insert(0, str(GENERATOR / "scripts"))
        cls.tiles = load("curve_layout_tiles", GENERATOR / "scripts/build_tilesets.py")
        cls.geometry = load("curve_layout_geometry", GENERATOR / "scripts/build_geometry.py")

    def generate(self, source_row, references):
        directory = tempfile.TemporaryDirectory(prefix="wayman-curve-layout-")
        self.addCleanup(directory.cleanup)
        directory = Path(directory.name)
        args = SimpleNamespace(work_directory=directory / "work", output=directory / "output",
                               source_directory=GENERATOR / "sources")
        source = {"entity": "TestCurve", "faces": {"E": {
            "width": len(source_row), "height": 1,
            "layers": [{"index": 0, "tiles": [source_row]}]}}}
        layout = {"tiledefs": {FAMILY + "_01": 481},
                  "entities": {"TestCurve": {"E": [references]}}}
        result = self.builder.generate_stable_pngs(args, self.builder.CONFIG, [source], layout, self.tiles)
        return args, result

    def test_deleted_cell_is_transparent_without_reallocating_later_sprites(self):
        names = [FAMILY + "_01_" + str(index) for index in (7, 12, 31)]
        args, (generated, retired) = self.generate(
            ["industry_railroad_01_10", None, "industry_railroad_01_11"], names)
        self.assertEqual(generated["TestCurve"]["faces"]["E"]["layers"][0]["tiles"],
                         [[names[0], None, names[2]]])
        self.assertEqual(retired, [names[1]])
        sprites = args.work_directory / FAMILY / (FAMILY + "_01")
        self.assertEqual(len(list(sprites.glob("*.png"))), 64)
        with Image.open(sprites / "12__padding.png") as image:
            self.assertIsNone(image.getbbox())
        for index, x in ((7, 0), (31, 2)):
            with Image.open(sprites / f"{index:02d}__TestCurve__E_0_{x}.png") as image:
                self.assertIsNotNone(image.getbbox())

    def test_new_cell_requires_an_explicit_slot(self):
        with self.assertRaisesRegex(ValueError, "No assigned sprite for TestCurve:E:0,0"):
            self.generate(["industry_railroad_01_10"], [None])

    def test_curve_geometry_update_preserves_unpublished_turnout_faces(self):
        previous = ("RailroaderWaymanEntityGeometry = {\n"
                    "    Left45DegCurve = {\n        E = {old = true},\n    },\n"
                    "    Left90DegTurnout = {\n        N = {published = true},\n    },\n}\n")
        face = {"kind": "turn", "nodes": [{"x": 4, "y": 2, "z": 0}], "nodesFacing": "E,SW"}
        result = self.builder.merge_curve_geometry(previous, {"Left45DegCurve": {"E": face}}, self.geometry)
        self.assertEqual(result, previous.replace("{old = true}", self.geometry.lua_value(face)))


if __name__ == "__main__":
    unittest.main()
