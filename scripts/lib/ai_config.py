#!/usr/bin/env python3
"""
ai_config.py — JSON manipulation helpers for dotfiles AI config scripts.

Called from scripts/lib/ai-config.sh as the single Python backend for mutation
and read helpers. All write paths go through atomic_write_* so a crash mid-write
cannot leave ~/.claude.json corrupted.

Subcommands:
  json-read <file> <expr>
  json-upsert-mcp <file> <name> <json_value>
  json-remove-mcp <file> <name>
  json-upsert-key <file> <key> <json_value>
  json-upsert-nested-key <file> <dotted_key> <json_value>
"""

from __future__ import annotations

import json
import os
import sys
import tempfile


# ---------------------------------------------------------------------------
# Atomic write primitives
# ---------------------------------------------------------------------------

def atomic_write_text(path: str, content: str) -> None:
    """Write `content` to `path` atomically (tempfile in same dir + os.replace)."""
    path = os.fspath(path)
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-ai-config.", suffix=".new")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def atomic_write_json(path: str, obj) -> None:
    atomic_write_text(path, json.dumps(obj, indent=2) + "\n")


# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------

def json_read(file: str, expr: str) -> int:
    if not os.path.isfile(file):
        return 1
    try:
        with open(file) as f:
            d = json.load(f)  # noqa: F841 — used by eval(expr)
        v = eval(expr, {}, {"d": d})  # noqa: S307 — internal callers only
        if v is None or v == "":
            return 1
        print(v)
        return 0
    except Exception:
        return 1


def json_upsert_mcp(file: str, name: str, value_json: str) -> int:
    value = json.loads(value_json)
    d = _load_json_or_empty(file)
    d.setdefault("mcpServers", {})[name] = value
    atomic_write_json(file, d)
    return 0


def json_remove_mcp(file: str, name: str) -> int:
    if not os.path.isfile(file):
        print("absent")
        return 0
    with open(file) as f:
        d = json.load(f)
    servers = d.get("mcpServers", {})
    if name in servers:
        del servers[name]
        atomic_write_json(file, d)
        print("removed")
    else:
        print("absent")
    return 0


def json_upsert_key(file: str, key: str, value_json: str) -> int:
    value = json.loads(value_json)
    d = _load_json_or_empty(file)
    d[key] = value
    atomic_write_json(file, d)
    return 0


def json_upsert_nested_key(file: str, dotted: str, value_json: str) -> int:
    value = json.loads(value_json)
    parts = dotted.split(".")
    d = _load_json_or_empty(file)
    node = d
    for p in parts[:-1]:
        if not isinstance(node.get(p), dict):
            node[p] = {}
        node = node[p]
    node[parts[-1]] = value
    atomic_write_json(file, d)
    return 0


def _load_json_or_empty(file: str) -> dict:
    if os.path.isfile(file):
        with open(file) as f:
            return json.load(f)
    return {}


# ---------------------------------------------------------------------------
# CLI dispatcher
# ---------------------------------------------------------------------------

COMMANDS = {
    "json-read": (json_read, 2),
    "json-upsert-mcp": (json_upsert_mcp, 3),
    "json-remove-mcp": (json_remove_mcp, 2),
    "json-upsert-key": (json_upsert_key, 3),
    "json-upsert-nested-key": (json_upsert_nested_key, 3),
}


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv[1]
    spec = COMMANDS.get(cmd)
    if spec is None:
        print(f"ai_config.py: unknown subcommand: {cmd}", file=sys.stderr)
        return 2
    fn, n_args = spec
    args = argv[2:]
    if len(args) != n_args:
        print(
            f"ai_config.py: {cmd} expects {n_args} args, got {len(args)}",
            file=sys.stderr,
        )
        return 2
    return fn(*args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
