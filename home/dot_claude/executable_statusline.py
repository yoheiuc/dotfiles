#!/usr/bin/env python3

import json
import os
import sys


RESET = "\033[0m"
DIM = "\033[2m"
CYAN = "\033[36m"
YELLOW = "\033[33m"
MAGENTA = "\033[35m"


def shorten_dir(path: str) -> str:
    name = os.path.basename(path.rstrip("/"))
    return name or path or "-"


def format_duration(ms: int) -> str:
    if ms <= 0:
        return "0s"
    seconds = ms // 1000
    if seconds < 60:
        return f"{seconds}s"
    minutes, seconds = divmod(seconds, 60)
    if minutes < 60:
        return f"{minutes}m{seconds:02d}s"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h{minutes:02d}m"


def find_percentages(obj):
    found = []

    def walk(node):
        if isinstance(node, dict):
            lower = {str(k).lower(): v for k, v in node.items()}
            if "used_percent" in lower:
                label = (
                    lower.get("label")
                    or lower.get("name")
                    or lower.get("window")
                    or lower.get("period")
                    or lower.get("type")
                    or "usage"
                )
                try:
                    value = float(lower["used_percent"])
                    found.append((str(label), int(round(value))))
                except Exception:
                    pass
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(obj)
    return found


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("Claude", end="")
        return

    model = data.get("model", {}).get("display_name") or "Claude"
    current_dir = shorten_dir(data.get("workspace", {}).get("current_dir") or data.get("cwd") or "")

    total_duration_ms = int(data.get("cost", {}).get("total_duration_ms") or 0)

    parts = [
        f"{CYAN}{model}{RESET}",
        f"{DIM}{current_dir}{RESET}",
    ]

    if total_duration_ms > 0:
        parts.append(f"{YELLOW}{format_duration(total_duration_ms)}{RESET}")

    usage_parts = []
    seen = set()
    for label, used in find_percentages(data):
        normalized = label.lower()
        if normalized in seen:
            continue
        seen.add(normalized)

        compact = label
        for src, dst in (
            ("5 hour", "5h"),
            ("5hr", "5h"),
            ("weekly", "7d"),
            ("week", "7d"),
        ):
            compact = compact.replace(src, dst).replace(src.title(), dst)
        usage_parts.append(f"{compact}:{used}%")

    if usage_parts:
        parts.append(f"{MAGENTA}{' '.join(usage_parts[:2])}{RESET}")

    print(" | ".join(parts), end="")


if __name__ == "__main__":
    main()
