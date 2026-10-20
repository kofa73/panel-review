#!/usr/bin/env python3
"""Load user defaults and keep effective run settings in one place."""

import argparse
import json
import os
import re
import stat
import sys
from pathlib import Path

from panel_common import panel_atomic_write, panel_valid_id


PLUGIN_ROOT = Path(__file__).resolve().parent.parent
BUILTIN_PROFILE = PLUGIN_ROOT / "profiles" / "default.md"
DEFAULTS = {
    "issue_rounds": 2,
    "max_rounds": 4,
    "seat_timeout_seconds": 2400,
}
# The detached CLI barrier has a two-hour platform limit. Reserve time for the
# timeout command's kill grace, status writes, and sentinel publication.
MAX_BARRIER_BACKGROUND_SECONDS = 2 * 60 * 60
BARRIER_WAIT_MARGIN_SECONDS = 60
BARRIER_TOOL_HEADROOM_SECONDS = 30
MAX_SEAT_TIMEOUT_SECONDS = (
    MAX_BARRIER_BACKGROUND_SECONDS
    - BARRIER_WAIT_MARGIN_SECONDS
    - BARRIER_TOOL_HEADROOM_SECONDS
)
ALLOWED_ROOT_KEYS = {"version", "profiles", "defaults", "cleanup"}
ALLOWED_DEFAULT_KEYS = {
    "review_profile",
    "issue_rounds",
    "max_rounds",
    "seat_timeout_seconds",
}
LEGACY_ENVIRONMENT = {
    "PANEL_REVIEW_KEEP_TMP": "cleanup.keep_tmp in config.json",
    "PANEL_REVIEW_SEAT_TIMEOUT": "defaults.seat_timeout_seconds or --seat-timeout",
}


class ConfigError(Exception):
    pass


def config_path():
    """Return the XDG path without interpreting a relative XDG_CONFIG_HOME as cwd."""
    xdg_home = os.environ.get("XDG_CONFIG_HOME")
    if xdg_home:
        base = Path(xdg_home)
        if not base.is_absolute():
            raise ConfigError("XDG_CONFIG_HOME must be an absolute path")
    else:
        home = os.environ.get("HOME")
        if not home:
            raise ConfigError("HOME is required when XDG_CONFIG_HOME is unset")
        base = Path(home) / ".config"
    return base / "panel-review" / "config.json"


def _object_without_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ConfigError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _require_keys(value, allowed, label):
    unknown = sorted(set(value) - allowed)
    if unknown:
        raise ConfigError(f"unknown {label} key: {unknown[0]}")


def _positive_integer(value, label):
    if type(value) is not int or value < 1:
        raise ConfigError(f"{label} must be a positive integer")


def _parse_positive_override(value, label):
    if re.fullmatch(r"[0-9]+", value or "") is None:
        raise ConfigError(f"--{label.replace('_', '-')} must be a positive integer")
    return int(value, 10)


def _validate_seat_timeout(value, label):
    _positive_integer(value, label)
    if value > MAX_SEAT_TIMEOUT_SECONDS:
        raise ConfigError(
            f"{label} must not exceed {MAX_SEAT_TIMEOUT_SECONDS} seconds; "
            "the CLI barrier has a two-hour maximum wait"
        )


def _is_path_selector(selector):
    return (
        selector.startswith(("/", "./", "../", "~/"))
        or "/" in selector
    )


def _validate_selector(selector, profiles, label):
    if not isinstance(selector, str) or not selector or "\x00" in selector:
        raise ConfigError(f"{label} must be a non-empty profile selector")
    if selector == "builtin:generic" or _is_path_selector(selector):
        return
    if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", selector) is None:
        raise ConfigError(f"{label} must be a profile name or path")
    if selector not in profiles:
        raise ConfigError(f"unknown review profile name: {selector}")


def load_config():
    path = config_path()
    if not os.path.lexists(path):
        return {"profiles": {}, "defaults": {}, "keep_tmp": False}
    try:
        mode = os.stat(path).st_mode
        if not stat.S_ISREG(mode):
            raise ConfigError(f"{path} is not a regular file")
        raw = path.read_bytes()
        decoded = raw.decode("utf-8")
        value = json.loads(decoded, object_pairs_hook=_object_without_duplicates)
    except ConfigError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ConfigError(f"cannot read valid UTF-8 JSON from {path}: {error}") from error

    if not isinstance(value, dict):
        raise ConfigError("the config root must be a JSON object")
    _require_keys(value, ALLOWED_ROOT_KEYS, "config")
    if type(value.get("version")) is not int or value["version"] != 1:
        raise ConfigError("config version must be 1")

    profiles = value.get("profiles", {})
    if not isinstance(profiles, dict):
        raise ConfigError("profiles must be a JSON object")
    for name, source in profiles.items():
        if (
            not isinstance(name, str)
            or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name) is None
        ):
            raise ConfigError("profile names must contain only letters, digits, '.', '_' or '-'")
        if name == "builtin":
            raise ConfigError("profile name 'builtin' is reserved")
        if not isinstance(source, str) or not os.path.isabs(source) or "\x00" in source:
            raise ConfigError(f"profiles.{name} must be a full absolute source path")

    defaults = value.get("defaults", {})
    if not isinstance(defaults, dict):
        raise ConfigError("defaults must be a JSON object")
    _require_keys(defaults, ALLOWED_DEFAULT_KEYS, "defaults")
    if "review_profile" in defaults:
        _validate_selector(defaults["review_profile"], profiles, "defaults.review_profile")
    for field in ("issue_rounds", "max_rounds"):
        if field in defaults:
            _positive_integer(defaults[field], f"defaults.{field}")
    if "seat_timeout_seconds" in defaults:
        _validate_seat_timeout(
            defaults["seat_timeout_seconds"], "defaults.seat_timeout_seconds"
        )

    cleanup = value.get("cleanup", {})
    if not isinstance(cleanup, dict):
        raise ConfigError("cleanup must be a JSON object")
    _require_keys(cleanup, {"keep_tmp"}, "cleanup")
    keep_tmp = cleanup.get("keep_tmp", False)
    if type(keep_tmp) is not bool:
        raise ConfigError("cleanup.keep_tmp must be a boolean")

    return {"profiles": profiles, "defaults": defaults, "keep_tmp": keep_tmp}


def reject_legacy_environment():
    for name, replacement in LEGACY_ENVIRONMENT.items():
        if name in os.environ:
            raise ConfigError(f"{name} is no longer supported; use {replacement}")


def resolve_selector(selector, profiles):
    _validate_selector(selector, profiles, "review profile")
    if selector == "builtin:generic":
        source = BUILTIN_PROFILE
    elif _is_path_selector(selector):
        source = Path(os.path.expanduser(selector))
        if not source.is_absolute():
            source = Path.cwd() / source
    else:
        source = Path(profiles[selector])
    return selector, str(source.absolute())


def resolve_start(args):
    reject_legacy_environment()
    config = load_config()
    selector = args.review_profile
    if selector is None:
        selector = config["defaults"].get("review_profile", "builtin:generic")
    selector, source_path = resolve_selector(selector, config["profiles"])
    limits = dict(DEFAULTS)
    limits.update(
        {
            key: config["defaults"][key]
            for key in DEFAULTS
            if key in config["defaults"]
        }
    )
    for key in DEFAULTS:
        override = getattr(args, key)
        if override is not None:
            limits[key] = _parse_positive_override(override, key)
    _validate_limits(limits)
    return {
        "review_profile": {"selector": selector, "source_path": source_path},
        "limits": limits,
    }


def _validate_limits(limits):
    _positive_integer(limits["issue_rounds"], "issue_rounds")
    _positive_integer(limits["max_rounds"], "max_rounds")
    _validate_seat_timeout(limits["seat_timeout_seconds"], "seat_timeout_seconds")
    if limits["issue_rounds"] > limits["max_rounds"]:
        raise ConfigError("issue_rounds must not exceed max_rounds")


def saved_limits(manifest):
    """Read persisted settings, using built-in values only for older manifests."""
    limits = manifest.get("limits") if isinstance(manifest, dict) else None
    if not isinstance(limits, dict):
        raise ConfigError("manifest limits are missing or invalid")
    effective = dict(DEFAULTS)
    effective.update({key: limits[key] for key in DEFAULTS if key in limits})
    _validate_limits(effective)
    return effective


def update_run(args):
    reject_legacy_environment()
    if not panel_valid_id(args.id):
        raise ConfigError(f"invalid run id: {args.id}")
    path = Path("/tmp") / args.id / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ConfigError(f"missing or invalid manifest for {args.id}") from error
    try:
        effective = saved_limits(manifest)
    except ConfigError as error:
        raise ConfigError(f"invalid limits in manifest for {args.id}: {error}") from error
    for key in DEFAULTS:
        override = getattr(args, key)
        if override is not None:
            effective[key] = _parse_positive_override(override, key)
    _validate_limits(effective)
    manifest["limits"] = effective
    panel_atomic_write(str(path), json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n")
    return effective


def read_run_settings(args):
    if not panel_valid_id(args.id):
        raise ConfigError(f"invalid run id: {args.id}")
    path = Path("/tmp") / args.id / "manifest.json"
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ConfigError(f"missing or invalid manifest for {args.id}") from error
    limits = saved_limits(manifest)
    profile = manifest.get("review_profile") if isinstance(manifest, dict) else None
    selector = profile.get("selector") if isinstance(profile, dict) else None
    if not isinstance(selector, str) or not selector:
        selector = profile.get("source_path", "") if isinstance(profile, dict) else ""
    return {"limits": limits, "review_profile_selector": selector}


def main(argv):
    parser = argparse.ArgumentParser(prog="user_config", allow_abbrev=False)
    subparsers = parser.add_subparsers(dest="command", required=True)
    start = subparsers.add_parser("resolve-start", allow_abbrev=False)
    start.add_argument("--review-profile")
    for key in ("issue_rounds", "max_rounds"):
        start.add_argument(f"--{key.replace('_', '-')}")
    start.add_argument("--seat-timeout", dest="seat_timeout_seconds")
    update = subparsers.add_parser("update-run", allow_abbrev=False)
    update.add_argument("--id", required=True)
    for key in ("issue_rounds", "max_rounds"):
        update.add_argument(f"--{key.replace('_', '-')}")
    update.add_argument("--seat-timeout", dest="seat_timeout_seconds")
    read = subparsers.add_parser("read-settings", allow_abbrev=False)
    read.add_argument("--id", required=True)
    subparsers.add_parser("cleanup-policy", allow_abbrev=False)
    args = parser.parse_args(argv[1:])
    try:
        if args.command == "resolve-start":
            result = resolve_start(args)
        elif args.command == "update-run":
            result = {"limits": update_run(args)}
        elif args.command == "read-settings":
            result = read_run_settings(args)
        else:
            reject_legacy_environment()
            result = {"keep_tmp": load_config()["keep_tmp"]}
    except ConfigError as error:
        print(f"user_config: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
