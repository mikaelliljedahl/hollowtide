#!/usr/bin/env python3
"""Check local Markdown links and whitespace without modifying documentation."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    files = [
        ROOT / "README.md",
        ROOT / "AGENTS.md",
        *sorted((ROOT / "docs").rglob("*.md")),
    ]
    errors = []
    links = 0
    for path in files:
        text = path.read_text()
        relative = path.relative_to(ROOT)
        for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
            if "://" in target or target.startswith("#"):
                continue
            target = target.split("#")[0]
            if target:
                links += 1
                if not (path.parent / target).exists():
                    errors.append(f"{relative}: missing link {target}")
        if text.count("```") % 2:
            errors.append(f"{relative}: unbalanced code fence")
        for number, line in enumerate(text.splitlines(), 1):
            if line != line.rstrip() or "\ufeff" in line:
                errors.append(f"{relative}:{number}: trailing whitespace/BOM")
    for error in errors:
        print(error)
    print(f"Markdown: {len(files)} files, {links} local links, {len(errors)} errors")
    return bool(errors)


if __name__ == "__main__":
    raise SystemExit(main())
