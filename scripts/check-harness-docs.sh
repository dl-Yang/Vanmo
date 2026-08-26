#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Advanced Harness documentation checks =="

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: required command not found: python3" >&2
    echo "== Summary: 1 failure(s) =="
    exit 1
fi

python3 - "$ROOT_DIR" <<'PY'
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

root = Path(sys.argv[1]).resolve()
failures = 0


def pass_check(message):
    print(f"PASS: {message}")


def fail_check(message):
    global failures
    failures += 1
    print(f"FAIL: {message}", file=sys.stderr)


def markdown_destinations(text):
    destinations = []

    for match in re.finditer(r"\]\(", text):
        start = match.end()
        index = start
        depth = 1
        escaped = False

        while index < len(text):
            character = text[index]
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    destinations.append((match.start(), text[start:index]))
                    break
            index += 1

    definition_pattern = re.compile(
        r"^[ \t]{0,3}\[[^\]\n]+\]:[ \t]*(?:<([^>\n]+)>|(\S+))",
        re.MULTILINE,
    )
    for match in definition_pattern.finditer(text):
        destinations.append((match.start(), match.group(1) or match.group(2)))

    return destinations


def destination_path(raw_destination, source):
    destination = raw_destination.strip()
    if not destination:
        return None

    if destination.startswith("<"):
        closing = destination.find(">")
        if closing == -1:
            return None
        destination = destination[1:closing]
    else:
        result = []
        depth = 0
        escaped = False
        for character in destination:
            if escaped:
                result.append(character)
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == "(":
                depth += 1
                result.append(character)
            elif character == ")":
                depth = max(0, depth - 1)
                result.append(character)
            elif character.isspace() and depth == 0:
                break
            else:
                result.append(character)
        destination = "".join(result)

    if not destination or destination.startswith("#"):
        return None

    lowered = destination.lower()
    if lowered.startswith(("http://", "https://", "mailto:", "//")):
        return None

    parsed = urlsplit(destination)
    if parsed.scheme:
        return Path("__unsupported_scheme__") / destination

    local_path = unquote(destination.split("#", 1)[0].split("?", 1)[0])
    if not local_path:
        return source

    if local_path.startswith("/"):
        return (root / local_path.lstrip("/")).resolve()
    return (source.parent / local_path).resolve()


required_files = [
    "AGENTS.md",
    "ARCHITECTURE.md",
    "README.md",
    "docs/PLANS.md",
    "docs/DESIGN.md",
    "docs/PRODUCT_SENSE.md",
    "docs/QUALITY_SCORE.md",
    "docs/RELIABILITY.md",
    "docs/SECURITY.md",
    "docs/FRONTEND.md",
    "docs/design-docs/index.md",
    "docs/product-specs/index.md",
    "docs/exec-plans/active/index.md",
    "docs/exec-plans/completed/index.md",
    "docs/exec-plans/tech-debt-tracker.md",
    "docs/references/index.md",
    "docs/generated/index.md",
    "docs/sops/index.md",
]

for relative_path in required_files:
    if (root / relative_path).is_file():
        pass_check(f"required file exists: {relative_path}")
    else:
        fail_check(f"required file missing: {relative_path}")

agents_path = root / "AGENTS.md"
required_routes = [
    "docs/QUALITY_SCORE.md",
    "docs/PLANS.md",
    "docs/exec-plans/active/index.md",
    "docs/product-specs/index.md",
    "docs/RELIABILITY.md",
    "docs/SECURITY.md",
    "docs/FRONTEND.md",
]

if agents_path.is_file():
    agents_text = agents_path.read_text(encoding="utf-8")
    agents_targets = {
        destination_path(destination, agents_path)
        for _, destination in markdown_destinations(agents_text)
    }
    for relative_path in required_routes:
        if (root / relative_path).resolve() in agents_targets:
            pass_check(f"AGENTS.md routes to {relative_path}")
        else:
            fail_check(f"AGENTS.md does not route to {relative_path}")
else:
    for relative_path in required_routes:
        fail_check(f"AGENTS.md does not route to {relative_path}")

markdown_files = [
    root / "AGENTS.md",
    root / "ARCHITECTURE.md",
    root / "README.md",
    root / ".cursor/rules/agents.mdc",
]
markdown_files.extend(sorted((root / "docs").rglob("*.md")))

for source in markdown_files:
    if not source.is_file():
        continue

    text = source.read_text(encoding="utf-8")
    source_relative = source.relative_to(root)
    for offset, raw_destination in markdown_destinations(text):
        target = destination_path(raw_destination, source)
        if target is None:
            continue

        line_number = text.count("\n", 0, offset) + 1
        label = f"{source_relative}:{line_number} -> {raw_destination.strip()}"

        try:
            inside_repository = os.path.commonpath((root, target)) == str(root)
        except (TypeError, ValueError):
            inside_repository = False

        if not inside_repository:
            fail_check(f"local Markdown link escapes repository: {label}")
        elif target.exists():
            pass_check(f"local Markdown link exists: {label}")
        else:
            fail_check(f"broken local Markdown link: {label}")

print(f"== Summary: {failures} failure(s) ==")
sys.exit(1 if failures else 0)
PY
