"""Black-box tests for user config validation and saved execution settings."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
USER_CONFIG = ROOT / "scripts" / "user_config.py"


class UserConfigTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.config_home = self.base / "xdg"
        self.config_file = self.config_home / "panel-review" / "config.json"
        self.config_file.parent.mkdir(parents=True)
        self.env = os.environ.copy()
        self.env["HOME"] = str(self.base / "home")
        self.env["XDG_CONFIG_HOME"] = str(self.config_home)
        self.env.pop("PANEL_REVIEW_KEEP_TMP", None)
        self.env.pop("PANEL_REVIEW_SEAT_TIMEOUT", None)
        self.run_id = f"py-user-config-{uuid.uuid4().hex}"

    def tearDown(self):
        shutil.rmtree(Path("/tmp") / self.run_id, ignore_errors=True)
        self.temp.cleanup()

    def write_config(self, value):
        self.config_file.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(value, str):
            self.config_file.write_text(value, encoding="utf-8")
        else:
            self.config_file.write_text(json.dumps(value), encoding="utf-8")

    def run_config(self, *args, env=None, cwd=None):
        return subprocess.run(
            [str(USER_CONFIG), *args],
            cwd=cwd,
            env=self.env if env is None else env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_missing_config_uses_project_neutral_built_in_defaults(self):
        result = self.run_config("resolve-start")

        self.assertEqual(result.returncode, 0, result.stderr)
        settings = json.loads(result.stdout)
        self.assertEqual(settings["review_profile"]["selector"], "builtin:generic")
        self.assertEqual(
            settings["review_profile"]["source_path"],
            str((ROOT / "profiles/default.md").resolve()),
        )
        self.assertEqual(
            settings["limits"],
            {"issue_rounds": 2, "max_rounds": 4, "seat_timeout_seconds": 2400},
        )

    def test_configured_profile_and_defaults_merge_with_command_overrides(self):
        profile = self.base / "domain.md"
        profile.write_text("# Domain\n", encoding="utf-8")
        self.write_config(
            {
                "version": 1,
                "profiles": {"domain": str(profile)},
                "defaults": {
                    "review_profile": "domain",
                    "issue_rounds": 3,
                    "max_rounds": 5,
                    "seat_timeout_seconds": 1800,
                },
            }
        )

        configured = self.run_config("resolve-start")
        self.assertEqual(configured.returncode, 0, configured.stderr)
        self.assertEqual(
            json.loads(configured.stdout),
            {
                "review_profile": {"selector": "domain", "source_path": str(profile)},
                "limits": {"issue_rounds": 3, "max_rounds": 5, "seat_timeout_seconds": 1800},
            },
        )

        overridden = self.run_config(
            "resolve-start",
            "--review-profile",
            "builtin:generic",
            "--issue-rounds",
            "4",
            "--max-rounds",
            "6",
            "--seat-timeout",
            "900",
        )
        self.assertEqual(overridden.returncode, 0, overridden.stderr)
        settings = json.loads(overridden.stdout)
        self.assertEqual(settings["review_profile"]["selector"], "builtin:generic")
        self.assertEqual(settings["limits"], {"issue_rounds": 4, "max_rounds": 6, "seat_timeout_seconds": 900})

    def test_selector_syntax_distinguishes_bare_names_from_paths(self):
        workdir = self.base / "work"
        workdir.mkdir()
        profile = workdir / "local-profile"
        profile.write_text("# Local\n", encoding="utf-8")
        self.write_config({"version": 1})

        bare = self.run_config("resolve-start", "--review-profile", "local-profile", cwd=workdir)
        self.assertNotEqual(bare.returncode, 0)
        self.assertIn("unknown review profile name", bare.stderr)

        path = self.run_config("resolve-start", "--review-profile", "./local-profile", cwd=workdir)
        self.assertEqual(path.returncode, 0, path.stderr)
        self.assertEqual(
            json.loads(path.stdout)["review_profile"]["source_path"],
            str(profile),
        )

    def test_config_schema_rejects_invalid_json_versions_keys_types_and_paths(self):
        invalid_configs = (
            ("{bad json", "valid UTF-8 JSON"),
            ({"version": 2}, "version must be 1"),
            ({"version": 1, "extra": True}, "unknown config key"),
            ({"version": 1, "defaults": {"extra": True}}, "unknown defaults key"),
            ({"version": 1, "defaults": {"issue_rounds": True}}, "positive integer"),
            ({"version": 1, "defaults": {"max_rounds": 0}}, "positive integer"),
            ({"version": 1, "profiles": {"domain": "relative.md"}}, "full absolute source path"),
            ({"version": 1, "cleanup": {"keep_tmp": 1}}, "must be a boolean"),
            ({"version": 1, "defaults": {"review_profile": "missing"}}, "unknown review profile name"),
        )
        for config, message in invalid_configs:
            with self.subTest(config=config):
                self.write_config(config)
                result = self.run_config("resolve-start")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_round_limit_pair_is_checked_after_overrides_merge(self):
        self.write_config(
            {"version": 1, "defaults": {"issue_rounds": 5, "max_rounds": 4}}
        )
        invalid = self.run_config("resolve-start")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("issue_rounds must not exceed max_rounds", invalid.stderr)

        valid = self.run_config("resolve-start", "--max-rounds", "6")
        self.assertEqual(valid.returncode, 0, valid.stderr)
        self.assertEqual(json.loads(valid.stdout)["limits"]["max_rounds"], 6)

    def test_timeout_must_fit_the_dynamic_barrier_wait(self):
        over_limit = self.run_config("resolve-start", "--seat-timeout", "7111")
        self.assertNotEqual(over_limit.returncode, 0)
        self.assertIn("must not exceed 7110 seconds", over_limit.stderr)
        zero = self.run_config("resolve-start", "--seat-timeout", "0")
        self.assertNotEqual(zero.returncode, 0)
        self.assertIn("positive integer", zero.stderr)

        obsolete_spelling = self.run_config(
            "resolve-start", "--seat-timeout-seconds", "900"
        )
        self.assertNotEqual(obsolete_spelling.returncode, 0)

    def test_saved_run_updates_ignore_changed_config_defaults(self):
        run_dir = Path("/tmp") / self.run_id
        run_dir.mkdir()
        manifest_path = run_dir / "manifest.json"
        manifest_path.write_text(
            json.dumps(
                {
                    "id": self.run_id,
                    "limits": {"issue_rounds": 3, "max_rounds": 7, "seat_timeout_seconds": 900},
                }
            ),
            encoding="utf-8",
        )
        self.write_config({"version": 1, "defaults": {"issue_rounds": 1, "max_rounds": 2}})

        result = self.run_config(
            "update-run", "--id", self.run_id, "--issue-rounds", "4"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(manifest_path.read_text(encoding="utf-8"))["limits"],
            {"issue_rounds": 4, "max_rounds": 7, "seat_timeout_seconds": 900},
        )

    def test_legacy_environment_variables_are_rejected_with_migration_guidance(self):
        for name, value, replacement in (
            ("PANEL_REVIEW_KEEP_TMP", "true", "cleanup.keep_tmp"),
            ("PANEL_REVIEW_SEAT_TIMEOUT", "300", "--seat-timeout"),
        ):
            with self.subTest(name=name):
                env = self.env.copy()
                env[name] = value
                result = self.run_config("cleanup-policy", env=env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(name, result.stderr)
                self.assertIn(replacement, result.stderr)

    def test_cleanup_policy_is_action_time_and_rejects_invalid_config(self):
        default = self.run_config("cleanup-policy")
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertEqual(json.loads(default.stdout), {"keep_tmp": False})

        self.write_config({"version": 1, "cleanup": {"keep_tmp": True}})
        keep = self.run_config("cleanup-policy")
        self.assertEqual(keep.returncode, 0, keep.stderr)
        self.assertEqual(json.loads(keep.stdout), {"keep_tmp": True})

        self.write_config("not json")
        invalid = self.run_config("cleanup-policy")
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn("valid UTF-8 JSON", invalid.stderr)


if __name__ == "__main__":
    unittest.main()
