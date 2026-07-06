#!/bin/bash
set -euo pipefail

PROJECT_NAME="Vanmo"
CONFIGURATION="Debug"
DERIVED_DATA="$(pwd)/build/DerivedData"

# ios-device | ios-simulator | macos
RUN_TARGET="ios-device"

INSTALL_ONLY=false
LAUNCH_ONLY=false
CLEAN=false
DEVICE=""
DEVICE_NAME=""

SCHEME=""
PRODUCT_NAME=""
BUNDLE_ID=""
SDK_SUFFIX=""
APP_PATH=""
DESTINATION=""

usage() {
    cat <<'EOF'
用法: ./run_device.sh [选项] [设备 UDID 或名称]

不打开 Xcode，构建并安装到真机、模拟器或本机 macOS，可选启动 App。

选项:
  -s, --simulator [名称|UDID]         在 iOS 模拟器上运行（默认选已启动或首个 iPhone 模拟器）
  -m, --macos                         构建并运行原生 macOS App（Vanmo-macOS）
  -c, --configuration Debug|Release   构建配置（默认 Debug）
  --clean                             清理 DerivedData 后再构建（SPM 卡住时用）
  --install-only                      只安装，不启动
  --launch-only                       只启动已安装的 App（跳过构建）
  -h, --help                          显示帮助

示例:
  ./run_device.sh                                    # iOS 真机（自动检测）
  ./run_device.sh --simulator                        # iOS 模拟器（自动检测）
  ./run_device.sh --simulator "iPhone 17 Pro"        # 指定模拟器
  ./run_device.sh 00008110-001E254A3A60401E          # 指定真机 UDID
  ./run_device.sh --macos                            # 本机 macOS App
  ./run_device.sh --macos --launch-only              # 仅启动已构建的 macOS App
  ./run_device.sh --configuration Release --simulator

查看设备:
  iOS 真机: xcrun xctrace list devices
  模拟器:   xcrun simctl list devices available
  构建目标: xcodebuild -project Vanmo.xcodeproj -scheme Vanmo -showdestinations
EOF
}

configure_target() {
    case "$RUN_TARGET" in
        ios-device)
            SCHEME="Vanmo"
            PRODUCT_NAME="Vanmo"
            BUNDLE_ID="com.vanmo.app"
            SDK_SUFFIX="iphoneos"
            ;;
        ios-simulator)
            SCHEME="Vanmo"
            PRODUCT_NAME="Vanmo"
            BUNDLE_ID="com.vanmo.app"
            SDK_SUFFIX="iphonesimulator"
            ;;
        macos)
            SCHEME="Vanmo-macOS"
            PRODUCT_NAME="Vanmo-macOS"
            BUNDLE_ID="com.vanmo.app.mac"
            SDK_SUFFIX=""
            ;;
        *)
            echo "❌ 未知运行目标: ${RUN_TARGET}" >&2
            exit 1
            ;;
    esac
}

update_app_path() {
    if [[ "$RUN_TARGET" == "macos" ]]; then
        APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${PRODUCT_NAME}.app"
    else
        APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-${SDK_SUFFIX}/${PRODUCT_NAME}.app"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--simulator)
            RUN_TARGET="ios-simulator"
            shift
            if [[ $# -gt 0 && "$1" != -* ]]; then
                DEVICE="$1"
                shift
            fi
            ;;
        -m|--macos)
            RUN_TARGET="macos"
            shift
            ;;
        -c|--configuration)
            CONFIGURATION="${2:?缺少 configuration 值}"
            shift 2
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --install-only)
            INSTALL_ONLY=true
            shift
            ;;
        --launch-only)
            LAUNCH_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "未知选项: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ "$RUN_TARGET" == "macos" ]]; then
                echo "❌ macOS 模式不支持指定设备参数: $1" >&2
                exit 1
            fi
            DEVICE="$1"
            shift
            ;;
    esac
done

configure_target
update_app_path

if [[ "$RUN_TARGET" == "macos" && -n "$DEVICE" ]]; then
    echo "❌ macOS 模式不支持指定设备参数: ${DEVICE}" >&2
    exit 1
fi

if [[ "$INSTALL_ONLY" == true && "$LAUNCH_ONLY" == true ]]; then
    echo "❌ --install-only 与 --launch-only 不能同时使用" >&2
    exit 1
fi

is_udid() {
    [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$ ]] \
        || [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

parse_simctl_line() {
    local line="$1"
    local udid name

    udid=$(echo "$line" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
    name=$(echo "$line" | sed -E 's/^[[:space:]]+([^(]+)\(.*/\1/' | sed 's/[[:space:]]*$//')
    echo "${udid}|${name}"
}

parse_xcodebuild_destination() {
    local line="$1"
    local platform id name

    platform=$(echo "$line" | sed -nE 's/.*platform:([^,}]+).*/\1/p')
    id=$(echo "$line" | sed -nE 's/.*[[:space:]]id:([^,}]+).*/\1/p')
    name=$(echo "$line" | sed -nE 's/.*name:([^}]+).*/\1/p' | sed 's/[[:space:]]*$//')

    if [[ -z "$platform" || -z "$id" ]]; then
        return 1
    fi

    echo "${platform}|${id}|${name}"
}

list_xcodebuild_destinations() {
    xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME}" \
        -showdestinations 2>/dev/null \
        | grep -E '^\s+\{' || true
}

resolve_simulator() {
    local input="$1"
    local line udid name

    if is_udid "$input"; then
        line=$(xcrun simctl list devices available 2>/dev/null \
            | grep -F "$input" \
            | head -1 || true)
        if [[ -n "$line" ]]; then
            IFS='|' read -r udid name <<< "$(parse_simctl_line "$line")"
            echo "${udid}|${name}"
            return
        fi
        echo "❌ 找不到模拟器: ${input}" >&2
        echo "   可用命令: xcrun simctl list devices available" >&2
        exit 1
    fi

    line=$(xcrun simctl list devices available 2>/dev/null \
        | grep -F "$input" \
        | grep -Ei 'iphone|ipad' \
        | head -1 || true)
    if [[ -n "$line" ]]; then
        IFS='|' read -r udid name <<< "$(parse_simctl_line "$line")"
        echo "${udid}|${name}"
        return
    fi

    echo "❌ 找不到模拟器: ${input}" >&2
    echo "   可用命令: xcrun simctl list devices available" >&2
    exit 1
}

detect_simulator() {
    local line udid name

    line=$(xcrun simctl list devices booted 2>/dev/null \
        | grep -Ei 'iphone|ipad' \
        | head -1 || true)
    if [[ -n "$line" ]]; then
        IFS='|' read -r udid name <<< "$(parse_simctl_line "$line")"
        echo "${udid}|${name}"
        return
    fi

    line=$(xcrun simctl list devices available 2>/dev/null \
        | grep -Ei 'iphone' \
        | head -1 || true)
    if [[ -n "$line" ]]; then
        IFS='|' read -r udid name <<< "$(parse_simctl_line "$line")"
        echo "${udid}|${name}"
        return
    fi

    echo "❌ 未找到可用的 iOS 模拟器。" >&2
    echo "   可用命令: xcrun simctl list devices available" >&2
    exit 1
}

resolve_ios_device_from_xcodebuild() {
    local input="$1"
    local line platform id name

    while IFS= read -r line; do
        IFS='|' read -r platform id name <<< "$(parse_xcodebuild_destination "$line")" || continue
        [[ "$platform" == "iOS" ]] || continue
        [[ "$id" == *placeholder* ]] && continue

        if [[ -n "$input" ]]; then
            if is_udid "$input" && [[ "$id" == "$input" ]]; then
                echo "${id}|${name}"
                return
            fi
            if [[ -n "$name" && "$name" == *"$input"* ]]; then
                echo "${id}|${name}"
                return
            fi
        fi
    done < <(list_xcodebuild_destinations)

    return 1
}

detect_ios_device_from_xcodebuild() {
    local line platform id name

    while IFS= read -r line; do
        IFS='|' read -r platform id name <<< "$(parse_xcodebuild_destination "$line")" || continue
        [[ "$platform" == "iOS" ]] || continue
        [[ "$id" == *placeholder* ]] && continue
        echo "${id}|${name}"
        return
    done < <(list_xcodebuild_destinations)

    return 1
}

resolve_device_from_xctrace() {
    local input="$1"
    local line udid name

    if is_udid "$input"; then
        line=$(xcrun xctrace list devices 2>/dev/null \
            | sed -n '/^== Devices ==/,/^== Simulators ==/p' \
            | grep -F "$input" \
            | grep -E '\([0-9.]+\) \([0-9A-F-]+\)$' \
            | grep -vi 'macbook' \
            | head -1 || true)
        if [[ -n "$line" ]]; then
            udid=$(echo "$line" | sed -E 's/.*\(([0-9A-F-]+)\)$/\1/')
            name=$(echo "$line" | sed -E 's/ \([0-9.]+\) \([0-9A-F-]+\)$//')
            echo "${udid}|${name}"
            return
        fi
        return 1
    fi

    line=$(xcrun xctrace list devices 2>/dev/null \
        | sed -n '/^== Devices ==/,/^== Simulators ==/p' \
        | grep -F "$input" \
        | grep -E '\([0-9.]+\) \([0-9A-F-]+\)$' \
        | grep -vi 'macbook' \
        | head -1 || true)
    if [[ -n "$line" ]]; then
        udid=$(echo "$line" | sed -E 's/.*\(([0-9A-F-]+)\)$/\1/')
        name=$(echo "$line" | sed -E 's/ \([0-9.]+\) \([0-9A-F-]+\)$//')
        echo "${udid}|${name}"
        return
    fi

    return 1
}

detect_device_from_xctrace() {
    local line udid name

    line=$(xcrun xctrace list devices 2>/dev/null \
        | sed -n '/^== Devices ==/,/^== Simulators ==/p' \
        | grep -E '\([0-9.]+\) \([0-9A-F-]+\)$' \
        | grep -vi 'macbook' \
        | head -1 || true)

    if [[ -n "$line" ]]; then
        udid=$(echo "$line" | sed -E 's/.*\(([0-9A-F-]+)\)$/\1/')
        name=$(echo "$line" | sed -E 's/ \([0-9.]+\) \([0-9A-F-]+\)$//')
        echo "${udid}|${name}"
        return
    fi

    return 1
}

query_devicectl_devices() {
    local input="${1:-}"
    local tmp result

    tmp=$(mktemp "${TMPDIR:-/tmp}/vanmo-devicectl.XXXXXX")
    if ! xcrun devicectl list devices --json-output "$tmp" --quiet 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    result=$(INPUT="$input" python3 - "$tmp" <<'PY'
import json
import os
import sys

needle = os.environ.get("INPUT", "").casefold()
path = sys.argv[1]

with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)

devices = payload.get("result", {}).get("devices", [])
paired = []

for device in devices:
    if device.get("connectionProperties", {}).get("pairingState") != "paired":
        continue

    name = device.get("deviceProperties", {}).get("name", "")
    udid = device.get("hardwareProperties", {}).get("udid", "")
    identifier = device.get("identifier", "")
    candidates = [value for value in (udid, identifier, name) if value]

    if needle:
        haystacks = [value.casefold() for value in candidates]
        if not any(needle in haystack for haystack in haystacks):
            continue

    paired.append((udid or identifier, name))

if not paired:
    raise SystemExit(1)

udid, name = paired[0]
print(f"{udid}|{name}")
PY
) || result=""

    rm -f "$tmp"

    if [[ -n "$result" ]]; then
        echo "$result"
        return 0
    fi

    return 1
}

resolve_device_from_devicectl() {
    local input="$1"
    query_devicectl_devices "$input"
}

resolve_device() {
    local input="$1"
    local result

    if result=$(resolve_ios_device_from_xcodebuild "$input"); then
        echo "$result"
        return
    fi

    if result=$(resolve_device_from_xctrace "$input"); then
        echo "$result"
        return
    fi

    if result=$(resolve_device_from_devicectl "$input"); then
        echo "$result"
        return
    fi

    echo "❌ 找不到设备: ${input}" >&2
    echo "   可用命令: xcodebuild -project ${PROJECT_NAME}.xcodeproj -scheme ${SCHEME} -showdestinations" >&2
    echo "            xcrun xctrace list devices" >&2
    exit 1
}

detect_device() {
    local result

    if result=$(detect_ios_device_from_xcodebuild); then
        echo "$result"
        return
    fi

    if result=$(detect_device_from_xctrace); then
        echo "$result"
        return
    fi

    if result=$(query_devicectl_devices ""); then
        echo "$result"
        return
    fi

    echo "❌ 未检测到已连接的真机。请用 USB 连接设备并信任此 Mac。" >&2
    echo "   可用命令: xcodebuild -project ${PROJECT_NAME}.xcodeproj -scheme ${SCHEME} -showdestinations" >&2
    echo "            xcrun xctrace list devices" >&2
    exit 1
}

devicectl_ref() {
    if [[ -n "$DEVICE_NAME" ]]; then
        echo "$DEVICE_NAME"
    else
        echo "$DEVICE"
    fi
}

ensure_simulator_booted() {
    local udid="$1"
    local state

    state=$(xcrun simctl list devices 2>/dev/null | grep -F "$udid" | sed -E 's/.*\((Booted|Shutdown)\).*/\1/' || true)
    if [[ "$state" != "Booted" ]]; then
        echo "🚀 启动模拟器..."
        if ! xcrun simctl boot "$udid"; then
            echo "❌ 模拟器启动失败: ${udid}" >&2
            exit 1
        fi
        open -a Simulator
    fi
}

check_ios_signing() {
    local team

    team=$(xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -destination "${DESTINATION}" \
        -showBuildSettings 2>/dev/null \
        | awk -F ' = ' '/^[[:space:]]*DEVELOPMENT_TEAM = / {print $2; exit}')

    if [[ -z "$team" ]]; then
        echo "❌ iOS 真机构建需要 Development Team。" >&2
        echo "   请在 Xcode → Signing & Capabilities 中设置 Team，或执行 xcodegen generate 后重新配置。" >&2
        exit 1
    fi
}

select_destination() {
    case "$RUN_TARGET" in
        ios-simulator)
            DESTINATION="platform=iOS Simulator,id=${DEVICE}"
            ;;
        ios-device)
            DESTINATION="platform=iOS,id=${DEVICE}"
            ;;
        macos)
            DESTINATION="platform=macOS"
            ;;
    esac
}

if [[ "$RUN_TARGET" == "macos" ]]; then
    echo "💻 目标平台: macOS（${SCHEME}）"
elif [[ "$RUN_TARGET" == "ios-simulator" ]]; then
    if [[ -z "$DEVICE" ]]; then
        IFS='|' read -r DEVICE DEVICE_NAME <<< "$(detect_simulator)"
    else
        IFS='|' read -r DEVICE DEVICE_NAME <<< "$(resolve_simulator "$DEVICE")"
    fi
    echo "📱 目标模拟器: ${DEVICE_NAME:-$DEVICE} (${DEVICE})"
else
    if [[ -z "$DEVICE" ]]; then
        IFS='|' read -r DEVICE DEVICE_NAME <<< "$(detect_device)"
    else
        IFS='|' read -r DEVICE DEVICE_NAME <<< "$(resolve_device "$DEVICE")"
    fi
    echo "📱 目标真机: ${DEVICE_NAME:-$DEVICE} (${DEVICE})"
fi

select_destination

if [[ "$RUN_TARGET" == "ios-simulator" && "$LAUNCH_ONLY" == false ]]; then
    ensure_simulator_booted "$DEVICE"
fi

if [[ "$LAUNCH_ONLY" == false ]]; then
    if [[ "$CLEAN" == true ]]; then
        echo "🧹 清理 DerivedData: ${DERIVED_DATA}"
        rm -rf "${DERIVED_DATA}"
    fi

    if [[ "$RUN_TARGET" == "ios-device" ]]; then
        check_ios_signing
    fi

    echo ""
    echo "[1/3] 构建 ${CONFIGURATION} (${SCHEME})..."

    XCODEBUILD_ARGS=(
        -project "${PROJECT_NAME}.xcodeproj"
        -scheme "${SCHEME}"
        -configuration "${CONFIGURATION}"
        -destination "${DESTINATION}"
        -derivedDataPath "${DERIVED_DATA}"
    )

    if [[ "$RUN_TARGET" == "ios-device" ]]; then
        xcodebuild "${XCODEBUILD_ARGS[@]}" -allowProvisioningUpdates build
    else
        xcodebuild "${XCODEBUILD_ARGS[@]}" build
    fi

    if [[ ! -d "${APP_PATH}" ]]; then
        echo "❌ 未找到构建产物: ${APP_PATH}" >&2
        exit 1
    fi

    echo ""
    case "$RUN_TARGET" in
        ios-simulator)
            echo "[2/3] 安装到模拟器..."
            xcrun simctl install "$DEVICE" "${APP_PATH}"
            ;;
        ios-device)
            echo "[2/3] 安装到真机..."
            xcrun devicectl device install app --device "$(devicectl_ref)" "${APP_PATH}"
            ;;
        macos)
            echo "[2/3] 注册本机 App..."
            /usr/bin/open -R "${APP_PATH}" >/dev/null 2>&1 || true
            ;;
    esac
fi

if [[ "$INSTALL_ONLY" == false ]]; then
    echo ""
    echo "[3/3] 启动 App..."
    case "$RUN_TARGET" in
        ios-simulator)
            if [[ "$LAUNCH_ONLY" == true ]]; then
                ensure_simulator_booted "$DEVICE"
            fi
            xcrun simctl launch "$DEVICE" "${BUNDLE_ID}"
            ;;
        ios-device)
            xcrun devicectl device process launch --device "$(devicectl_ref)" "${BUNDLE_ID}"
            ;;
        macos)
            if [[ "$LAUNCH_ONLY" == true && ! -d "${APP_PATH}" ]]; then
                echo "❌ 未找到已构建的 App: ${APP_PATH}" >&2
                echo "   请先执行 ./run_device.sh --macos，或去掉 --launch-only。" >&2
                exit 1
            fi
            /usr/bin/open "${APP_PATH}"
            ;;
    esac
fi

echo ""
echo "✅ 完成"
if [[ "$INSTALL_ONLY" == false ]]; then
    echo ""
    echo "查看日志:"
    case "$RUN_TARGET" in
        ios-simulator)
            echo "  xcrun simctl spawn ${DEVICE} log stream --predicate 'processImagePath CONTAINS \"Vanmo\"'"
            ;;
        ios-device)
            echo "  推荐: 打开 Console.app，左侧选中设备，搜索 Vanmo（或 [Debug] 前缀）"
            echo "  也可: Xcode → Window → Devices and Simulators → 选中设备 → Open Console"
            echo "  说明: macOS 26 的 log stream 不支持 --device；CLI 采集需 sudo："
            echo "    sudo log collect --device-udid ${DEVICE} --last 5m --output /tmp/vanmo.logarchive"
            echo "    log show /tmp/vanmo.logarchive --style compact --predicate 'processImagePath CONTAINS \"Vanmo\"'"
            ;;
        macos)
            echo "  log stream --predicate 'processImagePath CONTAINS \"Vanmo\"'"
            echo "  或打开 Console.app，搜索 Vanmo / [Debug]"
            ;;
    esac
fi
