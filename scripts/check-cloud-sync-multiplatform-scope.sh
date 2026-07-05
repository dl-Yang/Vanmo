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

# 1) CloudKit entitlements (Debug 无 iCloud；Release 使用 *-Cloud.entitlements)
if [[ -f Vanmo/Vanmo-Cloud.entitlements ]] && \
   rg -q 'com.apple.developer.icloud-services' Vanmo/Vanmo-Cloud.entitlements && \
   rg -q 'CloudKit' Vanmo/Vanmo-Cloud.entitlements && \
   rg -q 'iCloud.com.vanmo.app' Vanmo/Vanmo-Cloud.entitlements; then
  pass "iOS Release entitlements include CloudKit container"
else
  fail "Vanmo-Cloud.entitlements missing CloudKit configuration"
fi

if ! rg -q 'com.apple.developer.icloud-services' Vanmo/Vanmo.entitlements 2>/dev/null; then
  pass "iOS Debug entitlements omit iCloud (personal team compatible)"
else
  fail "Vanmo.entitlements still declares iCloud — Debug signing will fail on personal teams"
fi

if [[ -f Vanmo/Vanmo-Mac-Cloud.entitlements ]] && \
   rg -q 'CloudKit' Vanmo/Vanmo-Mac-Cloud.entitlements; then
  pass "macOS Release Cloud entitlements present"
else
  fail "Vanmo-Mac-Cloud.entitlements missing or incomplete"
fi

if [[ -f Vanmo/Vanmo-Mac.entitlements ]] && \
   ! rg -q 'CloudKit' Vanmo/Vanmo-Mac.entitlements 2>/dev/null; then
  pass "macOS Debug entitlements omit CloudKit"
else
  fail "Vanmo-Mac.entitlements should not include CloudKit for Debug builds"
fi

if rg -q 'Vanmo-Cloud.entitlements' Vanmo.xcodeproj/project.pbxproj && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' Vanmo.xcodeproj/project.pbxproj; then
  pass "Xcode Release config uses Cloud entitlements + CLOUDKIT_SYNC_ENABLED"
else
  fail "project.pbxproj missing Release CloudKit build settings"
fi

if [[ -f project.yml ]] && \
   rg -q 'Vanmo-Cloud.entitlements' project.yml && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' project.yml && \
   rg -q 'Vanmo/Vanmo.entitlements' project.yml; then
  pass "project.yml preserves Debug/Release CloudKit split"
else
  fail "project.yml missing Debug/Release CloudKit configuration"
fi

if rg -q 'CloudSyncAvailability' Vanmo/Core/Storage/CloudSyncPreferences.swift && \
   rg -q 'CloudSyncAvailability.isCloudKitEnabled' Vanmo/Features/Settings/Views/SettingsView.swift; then
  pass "Settings reflects CloudKit build availability"
else
  fail "Settings missing CloudSyncAvailability guard"
fi

# 2) SwiftData CloudKit container wiring
if rg -q 'cloudKitDatabase' Vanmo/Core/Storage/ModelContainerFactory.swift && \
   rg -q 'CloudMediaState' Vanmo/Core/Storage/ModelContainerFactory.swift && \
   rg -q 'CLOUDKIT_SYNC_ENABLED' Vanmo/Core/Storage/ModelContainerFactory.swift && \
   rg -q 'ModelContainerFactory.makeSharedContainer' Vanmo/App/VanmoApp.swift Vanmo/App/VanmoMacApp.swift; then
  pass "CloudKit-backed SwiftData container wired with local/cloud split"
else
  fail "ModelContainerFactory / app entry not wired for CloudKit split"
fi

# 3) Sensitive fields must not appear in @Model sync entities
model_files=(
  Vanmo/Features/Browser/Models/ConnectionModels.swift
  Vanmo/Features/Library/Models/MediaItem.swift
  Vanmo/Features/Library/Models/FolderBookmark.swift
)
model_hits=""
for file in "${model_files[@]}"; do
  # 仅检查 @Model class 块内的字段，忽略辅助 struct（如 MediaServerConnectionSnapshot）
  block_hits="$(python3 - "$file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
pattern = re.compile(r'@Model\s*\n(?:final\s+)?class\s+\w+\s*\{.*?\n\}', re.S)
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
   rg -q 'isProgressCloudSynced = false|isFavoriteCloudSynced = false' Vanmo/Features/Library/Models/MediaItem.swift && \
   rg -q 'func upsertProgress' Vanmo/Core/Storage/CloudMediaState.swift; then
  pass "Media server progress/favorite exclusion hooks present"
else
  fail "Missing media server exclusion in sync write paths"
fi

# 5) Sync coordinator + conflict resolver
for f in \
  Vanmo/Core/Storage/CloudSyncCoordinator.swift \
  Vanmo/Core/Storage/CloudSyncConflictResolver.swift \
  Vanmo/Core/Storage/CloudSyncPreferences.swift \
  Vanmo/Core/Storage/CloudMediaState.swift; do
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

# 8) macOS skeleton markers
if [[ -f Vanmo/App/VanmoMacApp.swift ]] && rg -q '#if os\(macOS\)' Vanmo/App/VanmoMacApp.swift; then
  pass "VanmoMacApp macOS entry exists"
else
  fail "VanmoMacApp.swift missing or not guarded"
fi

if rg -q '#if os\(macOS\)|#if os\(iOS\)' Vanmo/App/ContentView.swift; then
  pass "ContentView has platform presentation guards"
else
  fail "ContentView missing platform guards"
fi

if rg -q 'VanmoMac' Vanmo.xcodeproj/project.pbxproj; then
  pass "Xcode project references VanmoMac target"
else
  fail "VanmoMac target not found in project.pbxproj"
fi

# 10) pbxproj 源文件路径与磁盘一致（PlatformCompatibility 曾误挂在 Prefetch）
if python3 - <<'PY'
import re
from pathlib import Path
text = Path("Vanmo.xcodeproj/project.pbxproj").read_text()
prefetch = re.search(r'9814B17DA901EBFF609E8477 /\* Prefetch \*/ = \{.*?children = \((.*?)\);', text, re.S)
utilities = re.search(r'B0D12706C0A3FA280DE62831 /\* Utilities \*/ = \{.*?children = \((.*?)\);', text, re.S)
assert prefetch and 'PlatformCompatibility' not in prefetch.group(1), 'PlatformCompatibility still under Prefetch'
assert utilities and 'PlatformCompatibility' in utilities.group(1), 'PlatformCompatibility missing from Utilities'
assert Path('Vanmo/Shared/Utilities/PlatformCompatibility.swift').is_file(), 'PlatformCompatibility.swift missing on disk'
PY
then
  pass "PlatformCompatibility.swift grouped under Shared/Utilities"
else
  fail "PlatformCompatibility.swift pbxproj path/group mismatch"
fi

echo "== Summary: $failures failure(s) =="
exit "$failures"
