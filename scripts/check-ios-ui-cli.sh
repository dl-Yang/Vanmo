#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== iOS UI interaction CLI static checks =="

for command in python3 xcrun; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "FAIL: required command not found: $command" >&2
        exit 1
    fi
done

test -x scripts/ios-ui.sh
bash -n scripts/ios-ui.sh

HELP_OUTPUT="$(scripts/ios-ui.sh --help)"
printf '%s\n' "$HELP_OUTPUT" | grep -q 'simulator journey --name tab-navigation' \
    || { echo "FAIL: help must document simulator journey tab-navigation" >&2; exit 1; }
printf '%s\n' "$HELP_OUTPUT" | grep -q 'simulator tree' \
    || { echo "FAIL: help must document simulator tree" >&2; exit 1; }
printf '%s\n' "$HELP_OUTPUT" | grep -q '走 XCUITest' \
    || { echo "FAIL: help must state that UI commands use XCUITest" >&2; exit 1; }

if TAP_OUTPUT="$(scripts/ios-ui.sh simulator tap 2>&1)"; then
    echo "FAIL: simulator tap without a selector should fail" >&2
    exit 1
fi
printf '%s\n' "$TAP_OUTPUT" | grep -q '必须提供 --identifier' \
    || { echo "FAIL: simulator tap should require a selector" >&2; exit 1; }
printf '%s\n' "$TAP_OUTPUT" | grep -q '不在模拟器启用 XCUITest' \
    && { echo "FAIL: simulator tap must not reject XCUITest" >&2; exit 1; }

if JOURNEY_OUTPUT="$(scripts/ios-ui.sh simulator journey 2>&1)"; then
    echo "FAIL: simulator journey without --name should fail" >&2
    exit 1
fi
printf '%s\n' "$JOURNEY_OUTPUT" | grep -q 'tab-navigation' \
    || { echo "FAIL: simulator journey should require --name tab-navigation" >&2; exit 1; }

python3 <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET

project = Path("project.yml").read_text(encoding="utf-8")
generated = Path("Vanmo.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
scheme_path = Path("Vanmo.xcodeproj/xcshareddata/xcschemes/Vanmo.xcscheme")

required_project_entries = (
    "VanmoUITests:",
    "type: bundle.ui-testing",
    "TEST_TARGET_NAME: Vanmo",
    "VanmoUITests: [test]",
)
for entry in required_project_entries:
    if entry not in project:
        raise SystemExit(f"FAIL: project.yml missing {entry}")

if "VanmoUITests" not in generated:
    raise SystemExit("FAIL: generated Xcode project is missing VanmoUITests")

scheme = ET.parse(scheme_path)
test_targets = {
    reference.attrib.get("BlueprintName")
    for reference in scheme.findall("./TestAction/Testables/TestableReference/BuildableReference")
}
if "VanmoUITests" not in test_targets:
    raise SystemExit("FAIL: generated Vanmo scheme does not test VanmoUITests")
PY

SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
PLATFORM_PATH="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)"
xcrun swiftc \
    -typecheck \
    -suppress-warnings \
    -swift-version 5 \
    -target arm64-apple-ios17.0-simulator \
    -sdk "$SDK_PATH" \
    -F "${PLATFORM_PATH}/Developer/Library/Frameworks" \
    VanmoUITests/VanmoDeviceInteractionTests.swift

echo "PASS: iOS UI interaction CLI static checks"
