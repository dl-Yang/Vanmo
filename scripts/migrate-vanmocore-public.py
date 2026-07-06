#!/usr/bin/env python3
"""Add public access modifiers to VanmoCore Swift sources for SPM export."""

from __future__ import annotations

import re
import sys
from pathlib import Path

SKIP_FILES = {
    "Package.swift",
}

TYPE_PATTERNS = [
    (re.compile(r"^(@Model\s*\n)(final class \w+)"), r"\1public \2"),
    (re.compile(r"^(final class \w+)"), r"public \1"),
    (re.compile(r"^(class \w+)"), r"public \1"),
    (re.compile(r"^(enum \w+)"), r"public \1"),
    (re.compile(r"^(struct \w+)"), r"public \1"),
    (re.compile(r"^(protocol \w+)"), r"public \1"),
    (re.compile(r"^(actor \w+)"), r"public \1"),
    (re.compile(r"^(extension \w+)"), r"public \1"),
]

MEMBER_PATTERNS = [
    (re.compile(r"^    (static let \w+)"), r"    public \1"),
    (re.compile(r"^    (static var \w+)"), r"    public \1"),
    (re.compile(r"^    (static func \w+)"), r"    public \1"),
    (re.compile(r"^    (var \w+)"), r"    public \1"),
    (re.compile(r"^    (let \w+)"), r"    public \1"),
    (re.compile(r"^    (func \w+)"), r"    public \1"),
    (re.compile(r"^    (init\()"), r"    public \1"),
]

PRIVATE_MARKERS = ("private ", "fileprivate ", "public ", "internal ", "open ")


def already_public(line: str) -> bool:
    stripped = line.lstrip()
    return any(stripped.startswith(marker) for marker in PRIVATE_MARKERS)


def strip_erroneous_public(content: str) -> str:
    """Remove public from nested local bindings introduced by older migration runs."""
    return re.sub(r"(?m)^(\s+)public (let|var) ", r"\1\2 ", content)


def transform(content: str) -> str:
    content = strip_erroneous_public(content)
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    in_type = False
    brace_depth = 0

    for line in lines:
        raw = line.rstrip("\n")
        stripped = raw.strip()

        if not in_type:
            for pattern, repl in TYPE_PATTERNS:
                if pattern.match(stripped) and not already_public(stripped):
                    raw = pattern.sub(repl, raw)
                    break
            if re.match(r"^(public )?(final )?(class|enum|struct|protocol|actor) ", stripped) or stripped.startswith("@Model"):
                in_type = True
                brace_depth = raw.count("{") - raw.count("}")
        else:
            for pattern, repl in MEMBER_PATTERNS:
                if pattern.match(raw) and not already_public(raw.lstrip()):
                    raw = pattern.sub(repl, raw)
                    break
            brace_depth += raw.count("{") - raw.count("}")
            if brace_depth <= 0 and "{" in raw:
                in_type = False
                brace_depth = 0

        out.append(raw + ("\n" if line.endswith("\n") else ""))

    return "".join(out)


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Packages/VanmoCore/Sources/VanmoCore")
    for path in sorted(root.rglob("*.swift")):
        if path.name in SKIP_FILES:
            continue
        original = path.read_text(encoding="utf-8")
        transformed = transform(original)
        if transformed != original:
            path.write_text(transformed, encoding="utf-8")
            print(f"updated {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
