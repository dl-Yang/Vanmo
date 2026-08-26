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


WORD_NUMBERS = {
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
}

STAGE_CLAIM_RE = re.compile(
    r"\b(?:all\s+)?(one|two|three|four|five|six|seven|eight|nine|ten|\d+)"
    r"\s+(?:`[^`]+`\s+)?(?:baseline\s+)?stages?\b",
    re.IGNORECASE,
)
FRACTION_RE = re.compile(r"\b(\d+)/(\d+)\b")
COMMAND_RE = re.compile(
    r"(?<![A-Za-z0-9_/.-])(?:\./)?((?:init|run_device|build_ipa)\.sh|scripts/[A-Za-z0-9_./-]+\.sh)\b"
)
INDEX_ENTRY_RE = re.compile(
    r"\[`([^`]+\.md)`\]\(([^)]+)\)(?:\s+[—–-]\s+\*\*([^*]+)\*\*)?"
)
STATUS_LINE_RE = re.compile(r"^\*\*Status:\*\*\s*(.+)$", re.MULTILINE)
ACCEPTANCE_STATUS_RE = re.compile(
    r"^\*\*Current acceptance status:\*\*\s*(.+)$",
    re.MULTILINE,
)
RELATED_SPEC_RE = re.compile(r"^\*\*Related spec:\*\*\s*(.+)$", re.MULTILINE)


def heading_excerpt(text, heading):
    match = re.search(r"^" + re.escape(heading) + r"\s*$", text, re.MULTILINE)
    if not match:
        return None
    level = len(heading) - len(heading.lstrip("#"))
    rest = text[match.end() :]
    next_heading = re.search(r"^#{1," + str(level) + r"} ", rest, re.MULTILINE)
    return rest[: next_heading.start()] if next_heading else rest


def status_phrase(raw):
    if not raw:
        return None
    phrase = re.split(r"[.;]", raw, maxsplit=1)[0]
    words = re.findall(r"[A-Za-z]+", phrase)
    if not words:
        return None
    return " ".join(word.lower() for word in words)


def parse_init_fast_stages(text):
    stages = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("swift package resolve"):
            continue
        if line.startswith("swift test"):
            stages.append("swift_test")
            continue
        match = re.match(r"\./scripts/([A-Za-z0-9_.-]+\.sh)\b", line)
        if not match:
            continue
        name = match.group(1)
        if name == "check-app-build.sh":
            break
        stages.append(name)
    return stages


def stage_aliases(stage_key):
    aliases = {
        "swift_test": ("vanmocore",),
        "check-cloud-sync-multiplatform-scope.sh": (
            "cloudkit",
            "check-cloud-sync-multiplatform-scope",
        ),
        "check-harness-docs.sh": (
            "check-harness-docs",
            "harness documentation",
            "harness document",
        ),
        "check-ios-ui-cli.sh": (
            "check-ios-ui-cli",
            "ios ui",
        ),
    }
    if stage_key in aliases:
        return aliases[stage_key]
    stem = Path(stage_key).stem.replace("-", " ")
    return (stage_key, stem)


def stage_count_claims(excerpt):
    claims = []
    for match in STAGE_CLAIM_RE.finditer(excerpt):
        token = match.group(1).lower()
        value = WORD_NUMBERS[token] if token in WORD_NUMBERS else int(token)
        claims.append((value, match.group(0)))
    for match in FRACTION_RE.finditer(excerpt):
        left, right = int(match.group(1)), int(match.group(2))
        if left == right:
            claims.append((left, match.group(0)))
    return claims


def extract_commands(text):
    return {match.group(1) for match in COMMAND_RE.finditer(text)}


def listed_markdown_files(index_text):
    files = []
    for match in INDEX_ENTRY_RE.finditer(index_text):
        name = match.group(1)
        if name == "index.md":
            continue
        files.append((name, match.group(3)))
    return files


def plan_markdown_files(directory):
    return sorted(
        path.name for path in directory.glob("*.md") if path.name != "index.md"
    )


def related_plan_paths(source, text):
    paths = []
    for _, raw_destination in markdown_destinations(text):
        target = destination_path(raw_destination, source)
        if target is None:
            continue
        try:
            relative = target.relative_to(root)
        except ValueError:
            continue
        parts = relative.parts
        if (
            len(parts) >= 4
            and parts[0] == "docs"
            and parts[1] == "exec-plans"
            and parts[2] in {"active", "completed"}
            and parts[-1] != "index.md"
        ):
            paths.append(target)
    return paths


init_path = root / "init.sh"
if init_path.is_file():
    init_stages = parse_init_fast_stages(init_path.read_text(encoding="utf-8"))
    expected_stage_count = len(init_stages)
    if expected_stage_count == 0:
        fail_check("init.sh fast baseline has no parsed verification stages")
    else:
        pass_check(
            f"init.sh fast baseline has {expected_stage_count} stage(s): "
            + ", ".join(init_stages)
        )
else:
    init_stages = []
    expected_stage_count = 0
    fail_check("init.sh missing; cannot derive fast baseline stage count")

reliability_path = root / "docs/RELIABILITY.md"
quality_path = root / "docs/QUALITY_SCORE.md"
architecture_path = root / "ARCHITECTURE.md"
reliability_text = (
    reliability_path.read_text(encoding="utf-8") if reliability_path.is_file() else ""
)
quality_text = quality_path.read_text(encoding="utf-8") if quality_path.is_file() else ""
architecture_text = (
    architecture_path.read_text(encoding="utf-8") if architecture_path.is_file() else ""
)

live_excerpts = []

bootstrap = heading_excerpt(reliability_text, "### Bootstrap")
if bootstrap is None:
    fail_check("docs/RELIABILITY.md is missing the Bootstrap section")
else:
    full_cut = re.search(
        r"^After the .+? succeed,",
        bootstrap,
        re.MULTILINE,
    )
    if full_cut:
        bootstrap = bootstrap[: full_cut.start()]
    live_excerpts.append(("docs/RELIABILITY.md Bootstrap", bootstrap))

quality_current = None
quality_match = re.search(r"\*\*Current baseline evidence:\*\*.*", quality_text)
if quality_match:
    quality_rest = quality_text[quality_match.start() :]
    quality_next = re.search(r"\n## ", quality_rest)
    quality_current = (
        quality_rest[: quality_next.start()] if quality_next else quality_rest
    )
    live_excerpts.append(("docs/QUALITY_SCORE.md current baseline", quality_current))
else:
    fail_check("docs/QUALITY_SCORE.md is missing Current baseline evidence")

architecture_excerpt = None
for line in architecture_text.splitlines():
    if "./init.sh" in line and re.search(r"baseline stages", line, re.IGNORECASE):
        architecture_excerpt = line
        break
if architecture_excerpt is None:
    fail_check(
        "ARCHITECTURE.md is missing a live ./init.sh baseline-stages paragraph"
    )
else:
    live_excerpts.append(("ARCHITECTURE.md baseline paragraph", architecture_excerpt))

for label, excerpt in live_excerpts:
    claims = stage_count_claims(excerpt)
    if not claims:
        fail_check(f"stage-count mismatch: {label} states no fast-baseline stage count")
        continue
    for value, raw in claims:
        if value != expected_stage_count:
            fail_check(
                f"stage-count mismatch: {label} claims {value} ({raw}), "
                f"init.sh fast baseline has {expected_stage_count}"
            )
        else:
            pass_check(f"{label} stage count {value} matches init.sh")
    lowered = excerpt.lower()
    for stage_key in init_stages:
        aliases = stage_aliases(stage_key)
        if any(alias in lowered for alias in aliases):
            pass_check(f"{label} mentions {stage_key}")
        else:
            fail_check(
                f"{label} does not mention stage {stage_key}; "
                f"expected one of {', '.join(aliases)}"
            )

for location in ("active", "completed"):
    directory = root / "docs/exec-plans" / location
    index_path = directory / "index.md"
    if not directory.is_dir() or not index_path.is_file():
        fail_check(f"docs/exec-plans/{location}/index.md is missing")
        continue

    index_text = index_path.read_text(encoding="utf-8")
    listed = listed_markdown_files(index_text)
    listed_names = [name for name, _ in listed]
    on_disk = plan_markdown_files(directory)

    for name in on_disk:
        if name in listed_names:
            pass_check(f"docs/exec-plans/{location}/index.md lists {name}")
        else:
            fail_check(
                f"docs/exec-plans/{location}/index.md does not list {name}"
            )
    for name, status in listed:
        if name in on_disk:
            pass_check(f"docs/exec-plans/{location}/{name} exists for index entry")
        else:
            fail_check(
                f"docs/exec-plans/{location}/index.md lists missing {name}"
            )
        if not status:
            fail_check(
                f"docs/exec-plans/{location}/index.md is missing a bold status "
                f"for {name}"
            )
            continue
        plan_path = directory / name
        if not plan_path.is_file():
            continue
        plan_text = plan_path.read_text(encoding="utf-8")
        status_match = STATUS_LINE_RE.search(plan_text)
        if not status_match:
            fail_check(f"docs/exec-plans/{location}/{name} is missing **Status:**")
            continue
        index_word = status_phrase(status)
        plan_word = status_phrase(status_match.group(1))
        if index_word is None or plan_word is None:
            fail_check(
                f"index/plan Status mismatch: docs/exec-plans/{location}/index.md "
                f"lists {name} as '{status.strip()}', plan Status is "
                f"'{status_match.group(1).strip()}'"
            )
        elif index_word == plan_word:
            pass_check(
                f"docs/exec-plans/{location}/index.md status {index_word} "
                f"matches {name}"
            )
        else:
            fail_check(
                f"index/plan Status mismatch: docs/exec-plans/{location}/index.md "
                f"lists {name} as '{status.strip()}', plan Status is "
                f"'{status_match.group(1).strip()}'"
            )
        if location == "active" and plan_word == "completed":
            fail_check(
                f"docs/exec-plans/active/{name} Status is completed; "
                "move it to completed/"
            )
        if location == "completed" and plan_word != "completed":
            fail_check(
                f"docs/exec-plans/completed/{name} Status is "
                f"'{status_match.group(1).strip()}', expected completed"
            )

active_names = set(
    plan_markdown_files(root / "docs/exec-plans/active")
)
completed_names = set(
    plan_markdown_files(root / "docs/exec-plans/completed")
)
overlap = sorted(active_names & completed_names)
if overlap:
    fail_check(
        "plan listed in both active/ and completed/: " + ", ".join(overlap)
    )
else:
    pass_check("active and completed plan filenames do not overlap")

spec_dir = root / "docs/product-specs"
spec_index = spec_dir / "index.md"
if spec_dir.is_dir() and spec_index.is_file():
    spec_index_text = spec_index.read_text(encoding="utf-8")
    listed_specs = [name for name, _ in listed_markdown_files(spec_index_text)]
    on_disk_specs = plan_markdown_files(spec_dir)
    for name in on_disk_specs:
        if name in listed_specs:
            pass_check(f"docs/product-specs/index.md lists {name}")
        else:
            fail_check(f"docs/product-specs/index.md does not list {name}")
    for name in listed_specs:
        if name in on_disk_specs:
            pass_check(f"docs/product-specs/{name} exists for index entry")
        else:
            fail_check(f"docs/product-specs/index.md lists missing {name}")

    for spec_name in on_disk_specs:
        spec_path = spec_dir / spec_name
        spec_text = spec_path.read_text(encoding="utf-8")
        spec_status = ACCEPTANCE_STATUS_RE.search(spec_text) or STATUS_LINE_RE.search(
            spec_text
        )
        related_plans = related_plan_paths(spec_path, spec_text)
        if related_plans and not spec_status:
            fail_check(
                f"docs/product-specs/{spec_name} links a plan but has no "
                "Current acceptance status or Status"
            )
        spec_word = status_phrase(spec_status.group(1)) if spec_status else None
        for plan_path in related_plans:
            plan_status = STATUS_LINE_RE.search(plan_path.read_text(encoding="utf-8"))
            if not plan_status:
                fail_check(
                    f"{plan_path.relative_to(root)} is missing **Status:** "
                    f"for spec {spec_name}"
                )
                continue
            plan_word = status_phrase(plan_status.group(1))
            spec_raw = spec_status.group(1).strip() if spec_status else "<missing>"
            if spec_word is None or plan_word is None or spec_word != plan_word:
                fail_check(
                    f"spec/plan Status mismatch: docs/product-specs/{spec_name} "
                    f"is '{spec_raw}', "
                    f"{plan_path.relative_to(root)} Status is "
                    f"'{plan_status.group(1).strip()}'"
                )
            else:
                pass_check(
                    f"docs/product-specs/{spec_name} status {spec_word} "
                    f"matches {plan_path.relative_to(root)}"
                )

    for location in ("active", "completed"):
        for plan_name in plan_markdown_files(root / "docs/exec-plans" / location):
            plan_path = root / "docs/exec-plans" / location / plan_name
            plan_text = plan_path.read_text(encoding="utf-8")
            related = RELATED_SPEC_RE.search(plan_text)
            if not related:
                continue
            destinations = markdown_destinations(related.group(1))
            if not destinations:
                raw = related.group(1).strip()
                destinations = [(0, raw)] if raw else []
            for _, raw_destination in destinations:
                spec_path = destination_path(raw_destination, plan_path)
                if spec_path is None or not spec_path.is_file():
                    continue
                spec_text = spec_path.read_text(encoding="utf-8")
                spec_status = ACCEPTANCE_STATUS_RE.search(
                    spec_text
                ) or STATUS_LINE_RE.search(spec_text)
                plan_status = STATUS_LINE_RE.search(plan_text)
                if not spec_status or not plan_status:
                    continue
                spec_word = status_phrase(spec_status.group(1))
                plan_word = status_phrase(plan_status.group(1))
                if spec_word is None or plan_word is None or spec_word != plan_word:
                    fail_check(
                        f"spec/plan Status mismatch: {plan_path.relative_to(root)} "
                        f"Status is '{plan_status.group(1).strip()}', "
                        f"{spec_path.relative_to(root)} is "
                        f"'{spec_status.group(1).strip()}'"
                    )

command_sources = [
    ("docs/RELIABILITY.md", reliability_text),
    ("AGENTS.md", agents_path.read_text(encoding="utf-8") if agents_path.is_file() else ""),
    ("README.md", (root / "README.md").read_text(encoding="utf-8") if (root / "README.md").is_file() else ""),
    (
        "docs/QUALITY_SCORE.md current baseline",
        quality_current or "",
    ),
]
reliability_standard = heading_excerpt(reliability_text, "## Standard Paths") or ""
reliability_commands = extract_commands(reliability_standard)
quality_commands = extract_commands(quality_current or "")

for label, text in command_sources:
    for command in sorted(extract_commands(text)):
        target = root / command
        if target.is_file():
            pass_check(f"{label} command exists: {command}")
        else:
            fail_check(f"{label} command does not exist: {command}")

if quality_current is None:
    pass
elif not quality_commands:
    fail_check(
        "docs/QUALITY_SCORE.md current baseline mentions no repository command paths"
    )
else:
    for command in sorted(quality_commands):
        if command in reliability_commands:
            pass_check(
                f"QUALITY current baseline command {command} is defined in "
                "RELIABILITY Standard Paths"
            )
        else:
            fail_check(
                f"QUALITY current baseline command {command} is not defined in "
                "docs/RELIABILITY.md Standard Paths"
            )

print(f"== Summary: {failures} failure(s) ==")
sys.exit(1 if failures else 0)
PY
