#!/usr/bin/env python3
"""Wrap exact user-visible literals that exist in L10nTable with L10n.tr()."""
import ast
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "Packages/VanmoCore/Sources/VanmoCore/Localization/generate_l10n.py"
TABLE = ROOT / "Packages/VanmoCore/Sources/VanmoCore/Localization/L10nTable.swift"

# Load keys from the Python generator source.
src = GEN.read_text(encoding="utf-8")
start = src.index("EN = {")
end = src.index("\n}", start)
mapping = ast.literal_eval(src[start + len("EN = "):end + 2])
keys = {key for key in mapping if any("\u4e00" <= ch <= "\u9fff" for ch in key)}

SKIP_DIRS = {"#Preview",}
SKIP_FILES = {
    "L10nTable.swift",
    "L10n.swift",
    "AppLanguage.swift",
    "LocalizedFormat.swift",
}

CALL_PREFIXES = (
    "Text(",
    "Label(",
    "Button(",
    "Toggle(",
    "Picker(",
    "Section(",
    "TextField(",
    "SecureField(",
    "navigationTitle(",
    "alert(",
    "help(",
    "accessibilityLabel(",
    "LabeledContent(",
)

# Match `"...."` including escapes.
STRING = r'"((?:\\.|[^"\\])*)"'


def should_skip_file(path: Path) -> bool:
    if path.name in SKIP_FILES:
        return True
    if "Localization" in path.parts:
        return True
    return False


def wrap_line(line: str) -> str:
    if "L10n.tr(" in line and line.count('"') <= 2:
        return line

    def repl(match: re.Match[str]) -> str:
        raw = match.group(0)
        value = ast.literal_eval(raw)
        if value not in keys:
            return raw
        # Don't wrap already wrapped.
        start = match.start()
        before = line[:start]
        if before.rstrip().endswith("L10n.tr("):
            return raw
        # Don't wrap identifier / systemImage / tag string literals in same
        # argument position when the previous token is a keyword we don't want.
        if re.search(r'(systemImage|identifier|tag|accessibilityIdentifier)\s*:\s*$', before):
            return raw
        return f"L10n.tr({raw})"

    return re.sub(STRING, repl, line)


def process(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    in_preview = False
    out_lines = []
    changed = False
    for line in original.splitlines(keepends=True):
        stripped = line.lstrip()
        if stripped.startswith("#Preview"):
            in_preview = True
        if in_preview:
            out_lines.append(line)
            if stripped.startswith("}") and stripped.count("{") == 0:
                # naive: keep preview untouched; reset on a lone closing at col 0
                if line.startswith("}"):
                    in_preview = False
            continue
        new_line = wrap_line(line)
        if new_line != line:
            changed = True
        out_lines.append(new_line)
    if changed:
        path.write_text("".join(out_lines), encoding="utf-8")
    return changed


def main() -> None:
    roots = [ROOT / "Vanmo", ROOT / "VanmoMac"]
    updated = []
    for root in roots:
        for path in root.rglob("*.swift"):
            if should_skip_file(path):
                continue
            if process(path):
                updated.append(str(path.relative_to(ROOT)))
    print(f"updated {len(updated)} files")
    for item in updated:
        print(item)


if __name__ == "__main__":
    main()
