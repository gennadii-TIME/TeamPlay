#!/usr/bin/env python3
"""Cloud/CI smoke test mirroring TeamPlay M3UParser archive gating rules."""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Entry:
    name: str
    url: str
    group: str | None = None
    catchup: str | None = None
    catchup_days: int | None = None


ATTR = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')


def parse_extinf(line: str) -> dict[str, str]:
    return dict(ATTR.findall(line))


def parse_m3u(text: str) -> list[Entry]:
    entries: list[Entry] = []
    pending: dict[str, str] | None = None
    pending_name = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTINF:"):
            pending = parse_extinf(line)
            if '"' in line:
                after = line.rsplit('"', 1)[-1]
            else:
                after = line
            pending_name = after.split(",", 1)[-1].strip() if "," in after else ""
            continue
        if line.startswith("#"):
            continue
        attrs = pending or {}
        days = None
        for key in ("catchup-days", "timeshift", "tvg-rec"):
            if key in attrs and attrs[key].isdigit() and int(attrs[key]) > 0:
                days = int(attrs[key])
                break
        entries.append(
            Entry(
                name=pending_name or line,
                url=line,
                group=attrs.get("group-title"),
                catchup=attrs.get("catchup") or attrs.get("catchup-type"),
                catchup_days=days,
            )
        )
        pending = None
        pending_name = ""
    return entries


def archive_capability(entry: Entry) -> tuple[bool, int]:
    days = entry.catchup_days or 0
    marker = (entry.catchup or "").lower()
    has_marker = bool(marker) and marker not in {"0", "none", "false"}
    supported = (has_marker or days > 0) and days > 0
    return supported, (days * 24 if supported else 0)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    fixture = root / "Fixtures" / "sample_archive.m3u"
    text = fixture.read_text(encoding="utf-8")
    entries = parse_m3u(text)
    assert len(entries) >= 2, entries

    plain = next(e for e in entries if e.name == "Plain News")
    archived = next(e for e in entries if e.name == "News With Archive")
    assert archive_capability(plain) == (False, 0), plain
    assert archive_capability(archived) == (True, 72), archived

    print("verify_m3u_parser: OK")
    print(f"  fixture entries: {len(entries)}")
    print("  archive gating: source-advertised only")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"verify_m3u_parser: FAIL {exc}", file=sys.stderr)
        raise SystemExit(1)
