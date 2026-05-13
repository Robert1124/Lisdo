from __future__ import annotations

import importlib.util
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPO_ROOT / "script" / "generate_mac_appcast.py"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


spec = importlib.util.spec_from_file_location("generate_mac_appcast", GENERATOR_PATH)
assert spec is not None
generate_mac_appcast = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(generate_mac_appcast)


class GenerateMacAppcastTests(unittest.TestCase):
    def test_markdown_release_notes_file_marks_description_as_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            dmg_path = temp_path / "Lisdo.dmg"
            notes_path = temp_path / "v1.2.3.md"
            output_path = temp_path / "appcast.xml"

            dmg_path.write_bytes(b"test dmg")
            notes_path.write_text("### Changes\n\n- Fixed appcast notes\n", encoding="utf-8")

            result = generate_mac_appcast.main(
                [
                    "--version",
                    "1.2.3",
                    "--build",
                    "42",
                    "--release-url",
                    "https://example.com/releases/v1.2.3",
                    "--dmg-url",
                    "https://example.com/Lisdo.dmg",
                    "--dmg-path",
                    str(dmg_path),
                    "--output",
                    str(output_path),
                    "--release-notes-file",
                    str(notes_path),
                ]
            )

            self.assertEqual(result, 0)
            description = self._item_description(output_path)
            self.assertEqual(description.text, "### Changes\n\n- Fixed appcast notes")
            self.assertEqual(description.attrib, {f"{{{SPARKLE_NS}}}format": "markdown"})

    def test_inline_release_notes_do_not_mark_description_as_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            dmg_path = temp_path / "Lisdo.dmg"
            output_path = temp_path / "appcast.xml"

            dmg_path.write_bytes(b"test dmg")

            result = generate_mac_appcast.main(
                [
                    "--version",
                    "1.2.3",
                    "--build",
                    "42",
                    "--release-url",
                    "https://example.com/releases/v1.2.3",
                    "--dmg-url",
                    "https://example.com/Lisdo.dmg",
                    "--dmg-path",
                    str(dmg_path),
                    "--output",
                    str(output_path),
                    "--release-notes",
                    "### Inline notes",
                ]
            )

            self.assertEqual(result, 0)
            description = self._item_description(output_path)
            self.assertEqual(description.text, "### Inline notes")
            self.assertEqual(description.attrib, {})

    def _item_description(self, output_path: Path) -> ET.Element:
        root = ET.parse(output_path).getroot()
        item = root.find("./channel/item")
        self.assertIsNotNone(item)
        description = item.find("description") if item is not None else None
        self.assertIsNotNone(description)
        assert description is not None
        return description


if __name__ == "__main__":
    unittest.main()
