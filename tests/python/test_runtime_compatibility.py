"""Manifest coverage for the Claude Code runtime compatibility release."""

from pathlib import Path
import json
import unittest


ROOT = Path(__file__).resolve().parents[2]


class RuntimeCompatibilityTest(unittest.TestCase):
    def test_plugin_manifest_matches_marketplace_release_metadata(self):
        plugin = json.loads((ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
        marketplace = json.loads(
            (ROOT / ".claude-plugin" / "marketplace.json").read_text(encoding="utf-8")
        )
        marketplace_plugin = next(
            entry for entry in marketplace["plugins"] if entry["name"] == plugin["name"]
        )

        self.assertEqual(plugin.get("author"), marketplace_plugin["author"])
        self.assertEqual(plugin["version"], marketplace_plugin["version"])


if __name__ == "__main__":
    unittest.main()
