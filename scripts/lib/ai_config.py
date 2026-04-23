#!/usr/bin/env python3
"""
ai_config.py — JSON / TOML manipulation helpers for dotfiles AI config scripts.

Called from scripts/lib/ai-config.sh as the single Python backend for mutation
and read helpers. All write paths go through atomic_write_* so a crash mid-write
cannot leave ~/.claude.json or ~/.codex/config.toml corrupted.

Subcommands:
  json-read <file> <expr>
  json-upsert-mcp <file> <name> <json_value>
  json-remove-mcp <file> <name>
  json-upsert-key <file> <key> <json_value>
  json-upsert-nested-key <file> <dotted_key> <json_value>
  toml-read <file> <expr>
  toml-remove-mcp-section <file> <name>
  toml-upsert-top-level <file> <key> <raw_value>
  toml-upsert-section-block <file> <section_header> <body>
  codex-upsert-mcp <file> <name> <command> <arg>
"""

from __future__ import annotations

import json
import os
import pathlib
import re
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
# TOML
# ---------------------------------------------------------------------------

def toml_read(file: str, expr: str) -> int:
    if not os.path.isfile(file):
        return 1
    try:
        import tomllib
    except ModuleNotFoundError:
        return 1
    try:
        with open(file, "rb") as f:
            d = tomllib.load(f)  # noqa: F841
        v = eval(expr, {}, {"d": d})  # noqa: S307
        if v is None or v == "":
            return 1
        print(v)
        return 0
    except Exception:
        return 1


def toml_remove_mcp_section(file: str, name: str) -> int:
    p = pathlib.Path(file).expanduser()
    if not p.is_file():
        print("absent")
        return 0
    content = p.read_text()
    pattern = re.compile(
        r"(?m)^\[mcp_servers\." + re.escape(name) + r"(?:\..*)?\]\s*\n(?:^(?!\[).*(?:\n|$))*"
    )
    new_content, count = pattern.subn("", content)
    if count == 0:
        print("absent")
        return 0
    new_content = re.sub(r"\n{3,}", "\n\n", new_content)
    atomic_write_text(str(p), new_content.rstrip("\n") + "\n")
    print("removed")
    return 0


def toml_upsert_top_level(file: str, key: str, value: str) -> int:
    p = pathlib.Path(file).expanduser()
    content = p.read_text() if p.exists() else ""
    section_match = re.search(r"(?m)^\[", content)
    prefix_end = section_match.start() if section_match else len(content)
    prefix = content[:prefix_end]
    suffix = content[prefix_end:]
    line = f"{key} = {value}"

    pattern = re.compile(rf"(?m)^{re.escape(key)}\s*=.*$")
    if pattern.search(prefix):
        prefix = pattern.sub(line, prefix, count=1)
    else:
        stripped = prefix.rstrip("\n")
        prefix = (stripped + "\n" + line + "\n\n") if stripped else (line + "\n\n")

    atomic_write_text(str(p), prefix + suffix.lstrip("\n"))
    return 0


def toml_upsert_section_block(file: str, section_header: str, body: str) -> int:
    p = pathlib.Path(file).expanduser()
    body = body.rstrip("\n")
    content = p.read_text() if p.exists() else ""
    new_block = f"{section_header}\n{body}\n"
    pattern = re.compile(
        rf"(?m)^{re.escape(section_header)}\s*\n(?:^(?!\[).*(?:\n|$))*"
    )
    if pattern.search(content):
        content = pattern.sub(new_block, content, count=1)
    else:
        stripped = content.rstrip("\n")
        content = (stripped + "\n\n" + new_block) if stripped else new_block

    atomic_write_text(str(p), content.rstrip("\n") + "\n")
    return 0


def codex_upsert_mcp(file: str, name: str, command: str, arg: str) -> int:
    section_header = f"[mcp_servers.{name}]"
    new_block = f'{section_header}\ncommand = "{command}"\nargs = ["{arg}"]\n'
    content = open(file).read() if os.path.isfile(file) else ""
    pattern = re.compile(
        r"^\[mcp_servers\." + re.escape(name) + r"\]\s*\n(?:(?!\[).*\n)*",
        re.MULTILINE,
    )
    if pattern.search(content):
        content = pattern.sub(new_block, content)
    else:
        content = content.rstrip("\n") + "\n\n" + new_block
    atomic_write_text(file, content)
    return 0


# ---------------------------------------------------------------------------
# CLI dispatcher
# ---------------------------------------------------------------------------

COMMANDS = {
    "json-read": (json_read, 2),
    "json-upsert-mcp": (json_upsert_mcp, 3),
    "json-remove-mcp": (json_remove_mcp, 2),
    "json-upsert-key": (json_upsert_key, 3),
    "json-upsert-nested-key": (json_upsert_nested_key, 3),
    "toml-read": (toml_read, 2),
    "toml-remove-mcp-section": (toml_remove_mcp_section, 2),
    "toml-upsert-top-level": (toml_upsert_top_level, 3),
    "toml-upsert-section-block": (toml_upsert_section_block, 3),
    "codex-upsert-mcp": (codex_upsert_mcp, 4),
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
