#!/usr/bin/env python3
"""Shared persistence and schema helpers for migrated panel-review scripts."""

import os
import re
import stat
import sys
import tempfile


CATEGORIES = {"security", "correctness", "performance", "maintainability", "style"}
SEVERITIES = {"critical", "high", "medium", "low", "style"}
STATES = {"open", "accepted", "rejected", "contested", "unresolved", "merged"}


def panel_valid_id(value):
    """Reject path-like IDs before they can escape their /tmp namespace."""
    return (
        isinstance(value, str)
        and bool(value)
        and value not in {".", ".."}
        and all(char.isascii() and (char.isalnum() or char in "._-") for char in value)
    )


def panel_require_id(value):
    """Exit with the shell helper's public validation error for an unsafe ID."""
    if not panel_valid_id(value):
        print(f"panel: invalid run id: '{value if value is not None else ''}'", file=sys.stderr)
        raise SystemExit(2)


def _write_temp(directory, data):
    fd, path = tempfile.mkstemp(prefix=".panel.", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        return path
    except BaseException:
        try:
            os.unlink(path)
        except OSError:
            pass
        raise


def _rotate_backup(dest, directory):
    """Best-effort backup that never follows a dest or dest.bak symlink to write."""
    try:
        source_fd = os.open(dest, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        try:
            if not stat.S_ISREG(os.fstat(source_fd).st_mode):
                return
            chunks = []
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                chunks.append(chunk)
        finally:
            os.close(source_fd)
        backup_tmp = _write_temp(directory, b"".join(chunks))
        try:
            # replace(2) replaces a symlink itself; it never opens it for writing.
            os.replace(backup_tmp, dest + ".bak")
        except OSError:
            try:
                os.unlink(backup_tmp)
            except OSError:
                pass
    except OSError:
        # A backup is diagnostic only. Its failure must not block the new state.
        pass


def panel_atomic_write(dest, data):
    """Durably replace *dest* via a same-directory rename and safe .bak rotation.

    The temp file shares dest's filesystem, so replace is atomic. A previous regular
    file is copied through a private temp and renamed to .bak: this avoids writing
    through a pre-planted symlink in world-writable /tmp.
    """
    if isinstance(data, str):
        data = data.encode()
    elif not isinstance(data, bytes):
        raise TypeError("data must be bytes or str")
    directory = os.path.dirname(dest) or "."
    os.makedirs(directory, exist_ok=True)
    _rotate_backup(dest, directory)
    tmp = _write_temp(directory, data)
    try:
        # This replaces a symlink at dest instead of ever opening it for writing.
        os.replace(tmp, dest)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def valid_location(value):
    """Match the evidence-location schema shared by parser and index validation."""
    return (type(value) is str and bool(value)) or (
        type(value) is list
        and bool(value)
        and all(type(item) is str and bool(item) for item in value)
    )


def valid_point(value):
    """Require enough structured evidence to project a review card safely."""
    return (
        type(value) is dict
        and type(value.get("assertion")) is str
        and "location" in value
        and valid_location(value["location"])
        and ("precondition" not in value or type(value["precondition"]) is str)
        and ("impact" not in value or type(value["impact"]) is str)
    )


def extract_fenced_block(text, tag):
    """Return whether a tagged fence exists and concatenate every matching body."""
    opening = re.compile(rf"```{re.escape(tag)}[ \t\r]*")
    closing = re.compile(r"```[ \t\r]*")
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()

    present = False
    inside = False
    content = []
    for line in lines:
        if opening.fullmatch(line):
            present = True
            inside = True
        elif inside and closing.fullmatch(line):
            inside = False
        elif inside:
            content.append(line[:-1] if line.endswith("\r") else line)

    return present, "".join(f"{line}\n" for line in content)


def stance_integrity_problems(index, stances, engaged, configured, deduplicate_unknown_sources):
    """Find shared debate-input errors while leaving each caller's diagnostics stable.

    Normal rounds report one unknown-source error per distinct value; degraded rounds report one
    per offending stance. The flag keeps that existing difference at the shared validation point.
    """
    problems = [
        ("unconfigured_seat", seat)
        for seat in engaged
        if seat not in configured
    ]
    sources = [stance.get("_source") for stance in stances]
    if deduplicate_unknown_sources:
        unique_sources = []
        for source in sources:
            if source not in unique_sources:
                unique_sources.append(source)
        sources = unique_sources
    problems.extend(
        ("unknown_source", source)
        for source in sources
        if source not in engaged
    )

    open_ids = [
        issue.get("id")
        for issue in index.get("issues", [])
        if issue.get("state") == "open"
    ]
    for seat in engaged:
        for issue_id in open_ids:
            count = sum(
                stance.get("_source") == seat and stance.get("id") == issue_id
                for stance in stances
            )
            if count != 1:
                problems.append(("stance_count", (seat, issue_id, count)))
    return problems
