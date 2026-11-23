import json
import tempfile
import unittest
from pathlib import Path

import vendor_specs


def write(root: Path, name: str, text: str) -> None:
    path = root / f"{name}.js"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class VendorSpecsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.build, self.out = root / "build", root / "out"
        write(self.build, "git", 'var a={name:"git",subcommands:[{name:"flow",loadSpec:"git-flow"}]};export{a as default,b as gitGenerators};')
        write(self.build, "git-flow", 'var f={name:"git-flow"};export{f as default};')
        write(self.build, "cd", 'var c={name:"cd"};export{c as default};')
        write(self.build, "aws/s3", 'var s={name:"s3"};export{s as default};')

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_rewrites_default_export(self) -> None:
        vendor_specs.vendor(self.build, self.out, ["cd"])

        text = (self.out / "cd.js").read_text()
        self.assertIn("globalThis.__smaltiSpec=c;", text)
        self.assertNotIn("export{", text)

    def test_rewrites_named_exports(self) -> None:
        vendor_specs.vendor(self.build, self.out, ["git"])

        text = (self.out / "git.js").read_text()
        self.assertIn("globalThis.__smaltiSpec=a;", text)
        self.assertIn("globalThis.__smaltiExports={gitGenerators:b};", text)

    def test_resolves_loadspec_transitively(self) -> None:
        vendor_specs.vendor(self.build, self.out, ["git"])

        manifest = json.loads((self.out / "manifest.json").read_text())
        self.assertEqual(manifest["specs"], {"git": "git.js", "git-flow": "git-flow.js"})
        self.assertEqual(manifest["commands"], ["git"])

    def test_nested_spec_keeps_its_folder(self) -> None:
        write(self.build, "aws", 'var w={name:"aws",subcommands:[{name:"s3",loadSpec:"aws/s3"}]};export{w as default};')

        vendor_specs.vendor(self.build, self.out, ["aws"])

        self.assertTrue((self.out / "aws/s3.js").exists())

    def test_refuses_to_replace_a_folder_it_did_not_create(self) -> None:
        self.out.mkdir(parents=True)
        (self.out / "precious.txt").write_text("keep")

        with self.assertRaises(vendor_specs.VendorError):
            vendor_specs.vendor(self.build, self.out, ["cd"])
        self.assertTrue((self.out / "precious.txt").exists())

    def test_replaces_its_own_output(self) -> None:
        vendor_specs.vendor(self.build, self.out, ["cd"])

        vendor_specs.vendor(self.build, self.out, ["git"])

        self.assertFalse((self.out / "cd.js").exists())

    def test_missing_command_fails(self) -> None:
        with self.assertRaises(vendor_specs.VendorError):
            vendor_specs.vendor(self.build, self.out, ["claude"])

    def test_missing_dependency_fails(self) -> None:
        write(self.build, "broken", 'var x={name:"broken",subcommands:[{name:"y",loadSpec:"nope"}]};export{x as default};')

        with self.assertRaises(vendor_specs.VendorError):
            vendor_specs.vendor(self.build, self.out, ["broken"])


if __name__ == "__main__":
    unittest.main()
