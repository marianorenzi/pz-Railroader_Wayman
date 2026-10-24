"""Source-to-generated-definition contracts for independent entity components."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = Path(os.environ.get("ENTITY_GENERATOR_ROOT", ROOT.parent / "pz-EntityGenerator"))
SCRIPTS = GENERATOR / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ComponentsGeneratorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.geometry = load("build_geometry")
        cls.entities = load("build_entities")
        cls.tilesets = load("build_tilesets")
        cls.definitions = [json.loads(path.read_text()) for path in sorted(
            (ROOT / "definitions/switches").glob("0[56]_*.json"))]

    def test_catalog_preserves_every_component_and_legacy_geometry(self):
        catalog = self.geometry.collect(ROOT / "definitions/switches", "turnout")
        for definition in self.definitions:
            for facing, face in definition["faces"].items():
                with self.subTest(entity=definition["entity"], facing=facing):
                    self.assertEqual(catalog[definition["entity"]][facing],
                                     {"components": face["components"]})
                    self.assertEqual(len(face["components"]), 3)
                    self.assertTrue(all(c["type"] == "turnout" for c in face["components"]))
        legacy = json.loads((ROOT / "definitions/switches/07_WyeTurnout.json").read_text())
        expected = {key: value for key, value in legacy["faces"]["S"].items()
                    if key in self.geometry.POINT_KEYS}
        self.assertEqual(catalog["WyeTurnout"]["S"], dict(expected, kind="turnout"))
        self.assertEqual(self.geometry.face_geometry({"nodes": [{"x": 1, "y": 2}]}),
                         {"kind": "turn", "nodes": [{"x": 1, "y": 2}]})

    def test_mixed_component_types_and_invalid_geometry(self):
        components = [{"type": "turn", "nodes": [{"x": 1, "y": 2, "z": 0}]},
                      {"type": "turnout", "at": {"x": 2, "y": 3},
                       "switch": {"x": 0, "y": 0}, "divergingNodes": []}]
        self.assertEqual(self.geometry.face_geometry({"components": components}),
                         {"components": components})
        for bad in [[], {}, [{"type": "unknown"}], [{"type": "turn", "nodes": []}],
                    [{"type": "turnout", "at": {"x": 0, "y": 0}}],
                    [{"type": "turn", "nodes": [{"x": float("inf"), "y": 0}]}]]:
            with self.subTest(components=bad), self.assertRaises(ValueError):
                self.geometry.face_geometry({"components": bad})

    def test_composition_and_entity_generation_preserve_metadata(self):
        originals = copy.deepcopy(self.definitions)
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            args = argparse.Namespace(name="components", work_directory=directory / "work",
                                      output=directory / "output", source_directory=directory)
            config = {"tileWidth": 2, "tileHeight": 256, "sourceColumns": 8}
            # Art is independent of the geometry contract; run the real composition
            # pipeline with small synthetic source sprites instead of installed art.
            sprite = Image.new("RGBA", (2, 256), (255, 255, 255, 255))
            with patch.object(self.tilesets, "crop_sprite", return_value=sprite):
                self.tilesets.generate_pngs(args, config, self.definitions)
            for source in self.definitions:
                path = args.output / "definitions/components" / f"{source['entity']}.json"
                generated = json.loads(path.read_text())
                self.assertEqual({k: v for k, v in generated.items() if k != "faces"},
                                 {k: v for k, v in source.items() if k != "faces"})
                for facing, face in source["faces"].items():
                    self.assertEqual({k: v for k, v in generated["faces"][facing].items() if k != "layers"},
                                     {k: v for k, v in face.items() if k != "layers"})
                subprocess.run([sys.executable, "-B", str(SCRIPTS / "build_entities.py"),
                                "--definition", str(path), "--cost-profiles",
                                str(ROOT / "definitions/CostProfiles.json"),
                                "--output", str(directory / "entities")], check=True, capture_output=True)
                script = (directory / "entities" / f"{source['entity']}.txt").read_text()
                self.assertEqual(script.count("OnCreate = RailroaderWaymanEntityRuntime.OnCreate,"), 1)
                self.assertEqual(script.count("component CraftRecipe"), 1)
            self.assertEqual(self.definitions, originals, "generation mutated source metadata")

    def test_runtime_catalog_cli(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "WaymanEntityGeometry.lua"
            subprocess.run([sys.executable, "-B", str(SCRIPTS / "build_geometry.py"),
                            "--turns", str(ROOT / "definitions/turns"),
                            "--turnouts", str(ROOT / "definitions/switches"),
                            "--output", str(output)], check=True, capture_output=True)
            self.assertEqual(output.read_bytes(), (ROOT / "RailroaderWayman/Contents/mods/"
                             "RailroaderWayman/42/media/lua/shared/Wayman/WaymanEntityGeometry.lua").read_bytes())


if __name__ == "__main__":
    unittest.main()
