#!/usr/bin/env bash
# P1-3 云同步与多端：静态范围检查（不执行 xcodebuild）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

echo "== P1-3 Cloud Sync / Multi-platform static checks =="

# 1) CloudKit entitlements (Debug and Release use *-Cloud.entitlements;
# personal-team fallback files omit iCloud)
if [[ -f Vanmo/Vanmo-Cloud.entitlements ]] && \
   rg -q 'com.apple.developer.icloud-services' Vanmo/Vanmo-Cloud.entitlements && \
   rg -q 'CloudKit' Vanmo/Vanmo-Cloud.entitlements && \
   rg -q 'iCloud.com.vanmo.app' Vanmo/Vanmo-Cloud.entitlements; then
  pass "iOS Cloud entitlements include CloudKit container"
else
  fail "Vanmo-Cloud.entitlements missing CloudKit configuration"
fi

if ! rg -q 'com.apple.developer.icloud-services' Vanmo/Vanmo.entitlements 2>/dev/null; then
  pass "iOS personal-team fallback entitlements omit iCloud"
else
  fail "Vanmo.entitlements still declares iCloud — personal-team signing would fail"
fi

if [[ -f VanmoMac/Vanmo-Mac-Cloud.entitlements ]] && \
   rg -q 'CloudKit' VanmoMac/Vanmo-Mac-Cloud.entitlements; then
  pass "macOS Cloud entitlements present"
else
  fail "VanmoMac/Vanmo-Mac-Cloud.entitlements missing or incomplete"
fi

if [[ -f VanmoMac/Vanmo-Mac.entitlements ]] && \
   ! rg -q 'CloudKit' VanmoMac/Vanmo-Mac.entitlements 2>/dev/null; then
  pass "macOS personal-team fallback entitlements omit CloudKit"
else
  fail "VanmoMac/Vanmo-Mac.entitlements should not include CloudKit"
fi

ios_cloud=$(rg -c 'CODE_SIGN_ENTITLEMENTS = "?Vanmo/Vanmo-Cloud.entitlements"?' Vanmo.xcodeproj/project.pbxproj || true)
mac_cloud=$(rg -c 'CODE_SIGN_ENTITLEMENTS = "?VanmoMac/Vanmo-Mac-Cloud.entitlements"?' Vanmo.xcodeproj/project.pbxproj || true)
ios_local=$(rg -c 'CODE_SIGN_ENTITLEMENTS = "?Vanmo/Vanmo.entitlements"?' Vanmo.xcodeproj/project.pbxproj || true)
mac_local=$(rg -c 'CODE_SIGN_ENTITLEMENTS = "?VanmoMac/Vanmo-Mac.entitlements"?' Vanmo.xcodeproj/project.pbxproj || true)
if [[ "${ios_cloud:-0}" -ge 2 && "${mac_cloud:-0}" -ge 2 && "${ios_local:-0}" -eq 0 && "${mac_local:-0}" -eq 0 ]] && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' Vanmo.xcodeproj/project.pbxproj; then
  pass "Xcode Debug and Release use Cloud entitlements + CLOUDKIT_SYNC_ENABLED"
else
  fail "project.pbxproj Debug/Release must both use Cloud entitlements (found iOS Cloud=$ios_cloud local=$ios_local, macOS Cloud=$mac_cloud local=$mac_local)"
fi

if [[ -f project.yml ]] && \
   rg -q 'Vanmo/Vanmo-Cloud.entitlements' project.yml && \
   rg -q 'VanmoMac/Vanmo-Mac-Cloud.entitlements' project.yml && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' project.yml && \
   ! rg -q 'CODE_SIGN_ENTITLEMENTS: Vanmo/Vanmo.entitlements' project.yml && \
   ! rg -q 'CODE_SIGN_ENTITLEMENTS: VanmoMac/Vanmo-Mac.entitlements' project.yml; then
  pass "project.yml enables CloudKit for Debug and Release"
else
  fail "project.yml missing CloudKit configuration or still points a config at non-cloud entitlements"
fi

if rg -q '\.define\("CLOUDKIT_SYNC_ENABLED"\)' Packages/VanmoCore/Package.swift; then
  pass "VanmoCore defines CLOUDKIT_SYNC_ENABLED for all package configurations"
else
  fail "Packages/VanmoCore/Package.swift missing CLOUDKIT_SYNC_ENABLED"
fi

if rg -q 'CloudSyncAvailability' Packages/VanmoCore/Sources/VanmoCore/Storage/CloudSyncPreferences.swift && \
   rg -q 'CloudSyncAvailability.isCloudKitEnabled' Vanmo/Features/Settings/Views/SettingsView.swift; then
  pass "Settings reflects CloudKit build availability"
else
  fail "Settings missing CloudSyncAvailability guard"
fi

# 2) SwiftData CloudKit container wiring (VanmoCore + 双端 App 入口)
if rg -q 'cloudKitDatabase' Packages/VanmoCore/Sources/VanmoCore/Storage/ModelContainerFactory.swift && \
   rg -q 'CloudMediaState' Packages/VanmoCore/Sources/VanmoCore/Storage/ModelContainerFactory.swift && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' Packages/VanmoCore/Sources/VanmoCore/Storage/ModelContainerFactory.swift && \
   rg -q 'resolvedCloudKitDatabase' Packages/VanmoCore/Sources/VanmoCore/Storage/ModelContainerFactory.swift && \
   rg -q 'ModelContainerFactory.makeSharedContainer' Vanmo/App/VanmoApp.swift VanmoMac/App/VanmoMacApp.swift; then
  pass "CloudKit-backed SwiftData container wired with local/cloud split"
else
  fail "ModelContainerFactory / app entry not wired for CloudKit split"
fi

# 3) Sensitive fields must not appear in @Model sync entities (VanmoCore)
model_files=(
  Packages/VanmoCore/Sources/VanmoCore/Models/ConnectionModels.swift
  Packages/VanmoCore/Sources/VanmoCore/Models/MediaItem.swift
  Packages/VanmoCore/Sources/VanmoCore/Models/FolderBookmark.swift
)
model_hits=""
for file in "${model_files[@]}"; do
  block_hits="$(python3 - "$file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
pattern = re.compile(r'@Model\s*\n(?:public\s+)?(?:final\s+)?class\s+\w+\s*\{.*?\n\}', re.S)
blocks = pattern.findall(text)
joined = '\n'.join(blocks)
hits = []
for token in ('password', 'accessToken', 'refreshToken'):
    if re.search(rf'\bvar\s+{token}\b', joined):
        hits.append(token)
if hits:
    print(f"{sys.argv[1]}: " + ", ".join(hits))
PY
)" || true
  if [[ -n "$block_hits" ]]; then
    model_hits+="${block_hits}"$'\n'
  fi
done
if [[ -z "$model_hits" ]]; then
  pass "Sync @Model types contain no password/token fields"
else
  fail "Sensitive fields found in sync @Model blocks:\n$model_hits"
fi

# 4) Media server exclusion in progress/favorite write paths
if rg -q 'markMediaProgressChanged' Vanmo/Features/Player/ViewModels/PlayerViewModel.swift && \
   rg -q 'markMediaFavoriteChanged' Vanmo/Features/Library/ViewModels/LibraryViewModel.swift && \
   rg -q 'isProgressCloudSynced = false|isFavoriteCloudSynced = false' \
     Packages/VanmoCore/Sources/VanmoCore/Models/MediaItem.swift \
     Packages/VanmoCore/Sources/VanmoCore/Mappers/ServerMediaItemMapper.swift && \
   rg -q 'func upsertProgress' Packages/VanmoCore/Sources/VanmoCore/Storage/CloudMediaState.swift; then
  pass "Media server progress/favorite exclusion hooks present"
else
  fail "Missing media server exclusion in sync write paths"
fi

# 5) Sync coordinator + conflict resolver (VanmoCore)
for f in \
  Packages/VanmoCore/Sources/VanmoCore/Storage/CloudSyncCoordinator.swift \
  Packages/VanmoCore/Sources/VanmoCore/Storage/CloudSyncConflictResolver.swift \
  Packages/VanmoCore/Sources/VanmoCore/Storage/CloudSyncPreferences.swift \
  Packages/VanmoCore/Sources/VanmoCore/Storage/CloudMediaState.swift; do
  if [[ -f "$f" ]]; then
    pass "Found $(basename "$f")"
  else
    fail "Missing $f"
  fi
done

# 6) Write-path sync triggers
if rg -q 'requestSync' Vanmo/Features/Browser/ViewModels/BrowserViewModel.swift \
  Vanmo/Features/Player/ViewModels/PlayerViewModel.swift \
  Vanmo/Features/Library/ViewModels/LibraryViewModel.swift \
  Vanmo/App/ContentView.swift; then
  pass "Sync triggers attached to write paths / lifecycle"
else
  fail "Sync triggers missing from expected ViewModels"
fi

# 7) Settings cloud sync UI
if rg -q 'cloudSyncSection|iCloud 同步' Vanmo/Features/Settings/Views/SettingsView.swift; then
  pass "Settings includes iCloud sync section"
else
  fail "Settings missing iCloud sync section"
fi

# 8) macOS 独立 target（VanmoMac/，不再依赖 iOS 工程内的 VanmoMacApp）
if [[ -f VanmoMac/App/VanmoMacApp.swift ]] && \
   ! [[ -f Vanmo/App/VanmoMacApp.swift ]]; then
  pass "VanmoMacApp lives in VanmoMac/ and removed from Vanmo/"
else
  fail "VanmoMacApp should be VanmoMac-only (VanmoMac/App/VanmoMacApp.swift)"
fi

if rg -q 'Vanmo-macOS' Vanmo.xcodeproj/project.pbxproj project.yml; then
  pass "Xcode project references Vanmo-macOS target"
else
  fail "Vanmo-macOS target not found in project"
fi

if ! rg -q '#if os\(macOS\)' Vanmo/App/ContentView.swift; then
  pass "iOS ContentView no longer carries macOS presentation patches"
else
  fail "ContentView still contains #if os(macOS) — macOS UI should live in VanmoMac/"
fi

# 9) XcodeGen drift, target source whitelist, VanmoCore UI imports
if "$ROOT/scripts/check-architecture-guards.sh"; then
  pass "Architecture structure guards passed"
else
  fail "Architecture structure guards failed"
fi

echo "== Summary: $failures failure(s) =="
exit "$failures"
