#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_PATH="Vanmo.xcodeproj"
CONFIGURATION="Debug"
EVIDENCE_ROOT="build/app-build-evidence"
SOURCE_PACKAGES_DIR="${EVIDENCE_ROOT}/SourcePackages"

usage() {
    cat <<'EOF'
Usage:
  scripts/check-app-build.sh ios-simulator
  scripts/check-app-build.sh macos
  scripts/check-app-build.sh all
  scripts/check-app-build.sh --help

Build Debug compile evidence for one or both application targets.
This command does not install, launch, test, archive, or regenerate the Xcode project.

This script uses isolated caches under build/app-build-evidence/, not Xcode's
Incremental Build cache. A first run often spends a long time on Resolve
Package Graph before it compiles Vanmo sources.

Do not start ios-simulator and macos as two concurrent processes; they share
SourcePackages. Use this script's all mode, or run the two platforms one after
the other. Do not point Xcode at build/app-build-evidence/SourcePackages.
EOF
}

die_usage() {
    printf 'ERROR: %s\n' "$*" >&2
    usage >&2
    exit 2
}

require_command() {
    local name="$1"
    if ! command -v "$name" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$name" >&2
        exit 1
    fi
}

selected_platforms() {
    case "$1" in
        ios-simulator)
            SELECTED_PLATFORMS=(ios-simulator)
            ;;
        macos)
            SELECTED_PLATFORMS=(macos)
            ;;
        all)
            SELECTED_PLATFORMS=(ios-simulator macos)
            ;;
        *)
            die_usage "unsupported platform: $1"
            ;;
    esac
}

platform_scheme() {
    case "$1" in
        ios-simulator) printf '%s\n' Vanmo ;;
        macos) printf '%s\n' Vanmo-macOS ;;
    esac
}

platform_destination() {
    case "$1" in
        ios-simulator) printf '%s\n' "generic/platform=iOS Simulator" ;;
        macos) printf '%s\n' "platform=macOS" ;;
    esac
}

platform_derived_data() {
    case "$1" in
        ios-simulator) printf '%s\n' "${EVIDENCE_ROOT}/DerivedData/ios-simulator" ;;
        macos) printf '%s\n' "${EVIDENCE_ROOT}/DerivedData/macos" ;;
    esac
}

platform_product_path() {
    case "$1" in
        ios-simulator) printf '%s\n' "${EVIDENCE_ROOT}/DerivedData/ios-simulator/Build/Products/Debug-iphonesimulator/Vanmo.app" ;;
        macos) printf '%s\n' "${EVIDENCE_ROOT}/DerivedData/macos/Build/Products/Debug/Vanmo-macOS.app" ;;
    esac
}

write_metadata() {
    local path="$1"
    local platform="$2"
    local scheme="$3"
    local destination="$4"
    local derived_data="$5"
    local product_path="$6"
    local command_line="$7"
    local started_at="$8"
    local finished_at="$9"
    local xcodebuild_status="${10}"
    local product_present="${11}"
    local status="${12}"
    local git_dirty=no

    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git_dirty=yes
    fi

    {
        printf 'platform=%s\n' "$platform"
        printf 'scheme=%s\n' "$scheme"
        printf 'configuration=%s\n' "$CONFIGURATION"
        printf 'destination=%s\n' "$destination"
        printf 'derived_data=%s\n' "$derived_data"
        printf 'product_path=%s\n' "$product_path"
        printf 'command=%s\n' "$command_line"
        printf 'xcode_version=%s\n' "$XCODE_VERSION"
        printf 'swift_version=%s\n' "$SWIFT_VERSION"
        printf 'git_head=%s\n' "$GIT_HEAD"
        printf 'git_dirty=%s\n' "$git_dirty"
        printf 'started_at=%s\n' "$started_at"
        printf 'finished_at=%s\n' "$finished_at"
        printf 'xcodebuild_exit=%s\n' "$xcodebuild_status"
        printf 'product_present=%s\n' "$product_present"
        printf 'status=%s\n' "$status"
    } >"$path"
}

build_platform() {
    local platform="$1"
    local run_dir="$2"
    local scheme destination derived_data product_path platform_dir log_path metadata_path
    local started_at finished_at
    local xcodebuild_status=1
    local product_present=no
    local status=fail
    local -a xcodebuild_args
    local -a pipeline_status
    local command_line

    scheme="$(platform_scheme "$platform")"
    destination="$(platform_destination "$platform")"
    derived_data="$(platform_derived_data "$platform")"
    product_path="$(platform_product_path "$platform")"
    platform_dir="${run_dir}/${platform}"
    log_path="${platform_dir}/xcodebuild.log"
    metadata_path="${platform_dir}/metadata.txt"

    mkdir -p "$platform_dir" "$derived_data" "$SOURCE_PACKAGES_DIR"
    : >"$log_path"

    xcodebuild_args=(
        xcodebuild
        -project "$PROJECT_PATH"
        -scheme "$scheme"
        -configuration "$CONFIGURATION"
        -destination "$destination"
        -derivedDataPath "$derived_data"
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR"
        -hideShellScriptEnvironment
        build
    )
    if [[ "$platform" == macos ]]; then
        xcodebuild_args+=(
            CODE_SIGNING_ALLOWED=NO
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGN_IDENTITY=
            DEVELOPMENT_TEAM=
        )
    fi
    command_line="${xcodebuild_args[*]}"
    started_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    printf '==> Building %s (%s / %s)\n' "$platform" "$scheme" "$CONFIGURATION"
    set +e
    "${xcodebuild_args[@]}" 2>&1 | tee "$log_path"
    pipeline_status=("${PIPESTATUS[@]}")
    xcodebuild_status="${pipeline_status[0]}"
    set -e
    finished_at="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    if [[ -d "$product_path" ]]; then
        product_present=yes
    fi
    if [[ "$xcodebuild_status" -eq 0 && "$product_present" == yes ]]; then
        status=pass
    fi

    write_metadata \
        "$metadata_path" \
        "$platform" \
        "$scheme" \
        "$destination" \
        "$derived_data" \
        "$product_path" \
        "$command_line" \
        "$started_at" \
        "$finished_at" \
        "$xcodebuild_status" \
        "$product_present" \
        "$status"

    printf 'platform=%s status=%s xcodebuild_exit=%s product=%s evidence=%s\n' \
        "$platform" \
        "$status" \
        "$xcodebuild_status" \
        "$product_present" \
        "$platform_dir"

    if [[ "$status" == pass ]]; then
        return 0
    fi
    return 1
}

PLATFORM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        ios-simulator|macos|all)
            if [[ -n "$PLATFORM" ]]; then
                die_usage "conflicting platform argument: $1"
            fi
            PLATFORM="$1"
            shift
            ;;
        *)
            die_usage "unknown argument: $1"
            ;;
    esac
done

if [[ -z "$PLATFORM" ]]; then
    die_usage "missing platform argument"
fi

require_command xcodebuild
require_command swift
require_command git
require_command tee

XCODE_VERSION="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
SWIFT_VERSION="$(swift --version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
GIT_HEAD="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"

if [[ ! -d "$PROJECT_PATH" ]]; then
    printf 'ERROR: committed Xcode project not found: %s\n' "$PROJECT_PATH" >&2
    exit 1
fi

SELECTED_PLATFORMS=()
selected_platforms "$PLATFORM"
RUN_ID="$(date '+%Y%m%d-%H%M%S')-$$"
RUN_DIR="${EVIDENCE_ROOT}/runs/${RUN_ID}"
SUMMARY_PATH="${RUN_DIR}/summary.txt"
AGGREGATE=pass
FAILED_COUNT=0

mkdir -p "$RUN_DIR" "$EVIDENCE_ROOT"

SOURCE_PACKAGES_LOCK_DIR="${EVIDENCE_ROOT}/SourcePackages.lockdir"
SOURCE_PACKAGES_LOCK_PID="${SOURCE_PACKAGES_LOCK_DIR}/pid"

acquire_source_packages_lock() {
    if mkdir "$SOURCE_PACKAGES_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" >"$SOURCE_PACKAGES_LOCK_PID"
        return 0
    fi

    local owner_pid=""
    if [[ -f "$SOURCE_PACKAGES_LOCK_PID" ]]; then
        owner_pid="$(tr -d '[:space:]' <"$SOURCE_PACKAGES_LOCK_PID" || true)"
    fi
    if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
        rm -rf "$SOURCE_PACKAGES_LOCK_DIR"
        if mkdir "$SOURCE_PACKAGES_LOCK_DIR" 2>/dev/null; then
            printf '%s\n' "$$" >"$SOURCE_PACKAGES_LOCK_PID"
            return 0
        fi
    fi

    printf 'ERROR: another check-app-build.sh is using %s\n' "$SOURCE_PACKAGES_DIR" >&2
    printf 'ERROR: run ios-simulator and macos serially, or use this script'\''s all mode.\n' >&2
    printf 'ERROR: do not start this script while another instance still holds the evidence package cache.\n' >&2
    if [[ -n "$owner_pid" ]]; then
        printf 'ERROR: lock owner pid=%s\n' "$owner_pid" >&2
    fi
    return 1
}

acquire_source_packages_lock || exit 1
cleanup_source_packages_lock() {
    rm -rf "$SOURCE_PACKAGES_LOCK_DIR"
}
trap cleanup_source_packages_lock EXIT

{
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'selection=%s\n' "$PLATFORM"
} >"$SUMMARY_PATH"

for selected in "${SELECTED_PLATFORMS[@]}"; do
    if build_platform "$selected" "$RUN_DIR"; then
        printf 'platform=%s status=pass evidence=%s/%s\n' "$selected" "$RUN_DIR" "$selected" >>"$SUMMARY_PATH"
    else
        AGGREGATE=fail
        FAILED_COUNT=$((FAILED_COUNT + 1))
        printf 'platform=%s status=fail evidence=%s/%s\n' "$selected" "$RUN_DIR" "$selected" >>"$SUMMARY_PATH"
    fi
done

printf 'aggregate=%s failed_count=%s evidence=%s\n' "$AGGREGATE" "$FAILED_COUNT" "$RUN_DIR" | tee -a "$SUMMARY_PATH"

if [[ "$AGGREGATE" == pass ]]; then
    exit 0
fi
exit 1
