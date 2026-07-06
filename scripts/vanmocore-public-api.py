#!/usr/bin/env python3
"""Conservatively export VanmoCore API for SwiftPM."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ACCESS = ("private ", "fileprivate ", "public ", "internal ", "open ")


def is_type_line(stripped: str) -> bool:
    return bool(
        re.match(r"^(@Model\s*)?(public )?(final )?(class|enum|struct|protocol|actor) ", stripped)
        or stripped.startswith("@Model")
    )


def publicize_type_line(line: str) -> str:
    stripped = line.strip()
    if any(stripped.startswith(marker) for marker in ACCESS):
        return line
    if stripped.startswith("@Model"):
        return line
    return re.sub(
        r"^(final class|class|enum|struct|protocol|actor) ",
        r"public \1 ",
        line,
    )


def publicize_model_class(content: str) -> str:
    return content.replace("@Model\nfinal class", "@Model\npublic final class")


def publicize_members(content: str) -> str:
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    depth = 0
    in_public_type = False
    in_protocol = False
    protocol_depth = 0

    for line in lines:
        stripped = line.strip()
        if re.match(r"^(public |private )?protocol ", stripped):
            in_protocol = True
            protocol_depth = 0
            if in_public_type:
                in_public_type = False
                depth = 0
        elif not in_public_type and is_type_line(stripped):
            if "@Model" in stripped or re.match(r"^public (final )?(class|enum|struct|actor) ", stripped):
                in_public_type = True
                depth = 0

        if in_protocol:
            out.append(line)
            protocol_depth += line.count("{") - line.count("}")
            if protocol_depth <= 0 and "{" in line:
                in_protocol = False
            continue

        if in_public_type and line.startswith("    ") and not line.startswith("        "):
            inner = line.lstrip()
            if inner.startswith("private ") or inner.startswith("fileprivate "):
                out.append(line)
                depth += line.count("{") - line.count("}")
                if depth <= 0:
                    in_public_type = False
                continue
            if not any(inner.startswith(marker) for marker in ACCESS):
                if re.match(r"(static |)(var|let|func|init\()", inner):
                    line = "    public " + inner
                if inner.startswith("private(set) var"):
                    line = "    public " + inner

        out.append(line)
        if in_public_type:
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                in_public_type = False

    return "".join(out)


def strip_erroneous_public(content: str) -> str:
    """Remove public from local bindings inside nested scopes; keep type-level members."""
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    depth = 0
    for line in lines:
        stripped = line.strip()
        if depth >= 1 and (stripped.startswith("public let ") or stripped.startswith("public var ")):
            line = line.replace("public let ", "let ", 1).replace("public var ", "var ", 1)
        out.append(line)
        depth += line.count("{") - line.count("}")
        if depth < 0:
            depth = 0
    return "".join(out)


def transform_file(path: Path) -> None:
    content = path.read_text(encoding="utf-8")
    content = strip_erroneous_public(content)
    content = publicize_model_class(content)
    lines = []
    for line in content.splitlines(keepends=True):
        stripped = line.strip()
        if line and not line.startswith(" ") and is_type_line(stripped):
            line = publicize_type_line(line)
        lines.append(line)
    content = "".join(lines)
    content = publicize_members(content)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Packages/VanmoCore/Sources/VanmoCore")
    for path in sorted(root.rglob("*.swift")):
        transform_file(path)
        print(f"publicized {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
