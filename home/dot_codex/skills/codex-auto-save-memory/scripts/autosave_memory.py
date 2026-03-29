#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile


@dataclass
class TokenUsage:
    input_tokens: int
    context_window: int

    @property
    def ratio(self) -> float:
        if self.context_window <= 0:
            return 0.0
        return self.input_tokens / self.context_window


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hook-stop", action="store_true")
    parser.add_argument("--transcript-path")
    parser.add_argument("--cwd")
    parser.add_argument("--session-id")
    parser.add_argument("--turn-id")
    parser.add_argument("--last-assistant-message")
    parser.add_argument(
        "--threshold",
        type=float,
        default=float(os.environ.get("CODEX_MEMORY_AUTOSAVE_THRESHOLD", "0.75")),
    )
    parser.add_argument(
        "--memory-root",
        default=os.environ.get(
            "CODEX_MEMORY_AUTOSAVE_ROOT",
            str(Path.home() / ".codex" / "memories" / "auto-save"),
        ),
    )
    parser.add_argument(
        "--max-snippet-chars",
        type=int,
        default=int(os.environ.get("CODEX_MEMORY_AUTOSAVE_MAX_SNIPPET_CHARS", "1200")),
    )
    return parser.parse_args()


def read_hook_payload() -> dict:
    raw = sys.stdin.read().strip()
    if not raw:
        return {}
    return json.loads(raw)


def extract_text(content: list) -> str:
    parts = []
    for item in content or []:
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if isinstance(text, str) and text.strip():
            parts.append(text.strip())
    return "\n\n".join(parts).strip()


def normalize_text(text: str, max_chars: int) -> str:
    cleaned = re.sub(r"\s+", " ", (text or "").strip())
    if len(cleaned) <= max_chars:
        return cleaned
    return cleaned[: max_chars - 1].rstrip() + "…"


def load_transcript_lines(path: Path) -> list[dict]:
    items = []
    for line in path.read_text().splitlines():
        try:
            items.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return items


def latest_token_usage(items: list[dict]) -> TokenUsage | None:
    for obj in reversed(items):
        if obj.get("type") != "event_msg":
            continue
        payload = obj.get("payload", {})
        if payload.get("type") != "token_count":
            continue
        info = payload.get("info", {})
        last = info.get("last_token_usage", {})
        input_tokens = last.get("input_tokens")
        context_window = info.get("model_context_window")
        if isinstance(input_tokens, int) and isinstance(context_window, int):
            return TokenUsage(input_tokens=input_tokens, context_window=context_window)
    return None


def latest_user_message(items: list[dict]) -> str:
    for obj in reversed(items):
        if obj.get("type") != "response_item":
            continue
        payload = obj.get("payload", {})
        if payload.get("type") == "message" and payload.get("role") == "user":
            return extract_text(payload.get("content", []))
    return ""


def slugify_project(cwd: str) -> str:
    base = Path(cwd).name or "root"
    slug = re.sub(r"[^a-z0-9]+", "-", base.lower()).strip("-")
    if not slug:
        slug = "root"
    digest = hashlib.sha1(cwd.encode("utf-8")).hexdigest()[:8]
    return f"{slug}-{digest}"


def render_memory(
    *,
    cwd: str,
    session_id: str,
    turn_id: str,
    transcript_path: str,
    usage: TokenUsage,
    threshold: float,
    user_message: str,
    assistant_message: str,
    max_chars: int,
) -> str:
    now = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    user_excerpt = normalize_text(user_message or "(none)", max_chars)
    assistant_excerpt = normalize_text(assistant_message or "(none)", max_chars)
    return f"""# Codex Auto-Saved Memory

- Updated: {now}
- CWD: `{cwd}`
- Session: `{session_id or 'unknown'}`
- Turn: `{turn_id or 'unknown'}`
- Context usage: {usage.ratio:.1%} ({usage.input_tokens} / {usage.context_window} input tokens)
- Threshold: {threshold:.0%}
- Transcript: `{transcript_path}`

## Latest User Prompt

{user_excerpt}

## Latest Assistant Message

{assistant_excerpt}
"""


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as tmp:
        tmp.write(content)
        tmp_path = Path(tmp.name)
    tmp_path.replace(path)


def run(args: argparse.Namespace) -> dict:
    payload = read_hook_payload() if args.hook_stop else {}
    transcript_path = Path(args.transcript_path or payload.get("transcript_path") or "")
    cwd = args.cwd or payload.get("cwd") or str(Path.cwd())
    session_id = args.session_id or payload.get("session_id") or ""
    turn_id = args.turn_id or payload.get("turn_id") or ""
    assistant_message = args.last_assistant_message or payload.get("last_assistant_message") or ""

    if not transcript_path or not transcript_path.exists():
        return {"saved": False, "reason": "transcript-missing"}

    items = load_transcript_lines(transcript_path)
    usage = latest_token_usage(items)
    if usage is None:
        return {"saved": False, "reason": "token-usage-missing"}

    if usage.ratio < args.threshold:
        return {
            "saved": False,
            "reason": "below-threshold",
            "ratio": usage.ratio,
            "threshold": args.threshold,
        }

    memory_path = Path(args.memory_root) / f"{slugify_project(cwd)}.md"
    content = render_memory(
        cwd=cwd,
        session_id=session_id,
        turn_id=turn_id,
        transcript_path=str(transcript_path),
        usage=usage,
        threshold=args.threshold,
        user_message=latest_user_message(items),
        assistant_message=assistant_message,
        max_chars=args.max_snippet_chars,
    )
    atomic_write(memory_path, content)
    return {
        "saved": True,
        "path": str(memory_path),
        "ratio": usage.ratio,
        "threshold": args.threshold,
    }


def main() -> int:
    args = parse_args()
    result = run(args)

    if args.hook_stop:
        if result.get("saved"):
            print(
                json.dumps(
                    {
                        "continue": True,
                        "systemMessage": (
                            f"Auto-saved memory at {result['path']} "
                            f"({result['ratio']:.1%} context usage)"
                        ),
                    }
                )
            )
        else:
            print(json.dumps({}))
        return 0

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
