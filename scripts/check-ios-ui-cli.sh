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
scripts/ios-ui.sh --help >/dev/null

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
