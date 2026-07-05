#!/bin/bash
set -euo pipefail

PROJECT_NAME="Vanmo"
SCHEME="Vanmo"
BUNDLE_ID="com.vanmo.app"
CONFIGURATION="Debug"
DERIVED_DATA="$(pwd)/build/DerivedData"

USE_SIMULATOR=false
INSTALL_ONLY=false
LAUNCH_ONLY=false
CLEAN=false
DEVICE=""

SDK_SUFFIX="iphoneos"
APP_PATH=""

usage() {
    cat <<'EOF'
用法: ./run_device.sh [选项] [设备 UDID 或名称]

不打开 Xcode，构建并安装到真机或模拟器，可选启动 App。

选项:
  -s, --simulator [名称|UDID]         在 iOS 模拟器上运行（默认选已启动或首个 iPhone 模拟器）
  -c, --configuration Debug|Release   构建配置（默认 Debug）
  --clean                             清理 DerivedData 后再构建（SPM 卡住时用）
  --install-only                      只安装，不启动
  --launch-only                       只启动已安装的 App（跳过构建）
  -h, --help                          显示帮助

示例:
  ./run_device.sh                                    # 真机（自动检测）
  ./run_device.sh --simulator                        # 模拟器（自动检测）
  ./run_device.sh --simulator "iPhone 17 Pro"        # 指定模拟器
  ./run_device.sh 00008110-001E254A3A60401E          # 指定真机 UDID
  ./run_device.sh --simulator --launch-only          # 模拟器须带 -s
  ./run_device.sh --configuration Release --simulator

查看设备:
  真机:   xcrun xctrace list devices
  模拟器: xcrun simctl list devices available
EOF
}

update_app_path() {
    SDK_SUFFIX=$([[ "$USE_SIMULATOR" == true ]] && echo "iphonesimulator" || echo "iphoneos")
    APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-${SDK_SUFFIX}/${PROJECT_NAME}.app"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--simulator)
            USE_SIMULATOR=true
            shift
            if [[ $# -gt 0 && "$1" != -* ]]; then
                DEVICE="$1"
                shift
            fi
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
            DEVICE="$1"
            shift
            ;;
    esac
done

update_app_path

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

resolve_device() {
    local input="$1"
    local line udid name

    if is_udid "$input"; then
        echo "${input}|"
        return
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

    line=$(xcrun devicectl list devices 2>/dev/null \
        | grep -F "$input" \
        | awk '/available \(paired\)/ {print; exit}' || true)
    if [[ -n "$line" ]]; then
        name=$(echo "$line" | awk '{print $1}')
        udid=$(echo "$line" | awk '{print $3}')
        echo "${udid}|${name}"
        return
    fi

    echo "❌ 找不到设备: ${input}" >&2
    echo "   可用命令: xcrun xctrace list devices" >&2
    exit 1
}

detect_device() {
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

    line=$(xcrun devicectl list devices 2>/dev/null \
        | awk '/available \(paired\)/ {print; exit}' || true)
    if [[ -n "$line" ]]; then
        name=$(echo "$line" | awk '{print $1}')
        udid=$(echo "$line" | awk '{print $3}')
        echo "${udid}|${name}"
        return
    fi

    echo "❌ 未检测到已连接的真机。请用 USB 连接设备并信任此 Mac。" >&2
    echo "   可用命令: xcrun xctrace list devices" >&2
    exit 1
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

if [[ "$USE_SIMULATOR" == true ]]; then
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

if [[ "$USE_SIMULATOR" == true && "$LAUNCH_ONLY" == false ]]; then
    ensure_simulator_booted "$DEVICE"
fi

if [[ "$LAUNCH_ONLY" == false ]]; then
    if [[ "$CLEAN" == true ]]; then
        echo "🧹 清理 DerivedData: ${DERIVED_DATA}"
        rm -rf "${DERIVED_DATA}"
    fi

    if [[ "$USE_SIMULATOR" == true ]]; then
        DESTINATION="platform=iOS Simulator,id=${DEVICE}"
    else
        DESTINATION="platform=iOS,id=${DEVICE}"
    fi

    echo ""
    echo "[1/3] 构建 ${CONFIGURATION}..."
    if [[ "$USE_SIMULATOR" == true ]]; then
        xcodebuild \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme "${SCHEME}" \
            -configuration "${CONFIGURATION}" \
            -destination "${DESTINATION}" \
            -derivedDataPath "${DERIVED_DATA}" \
            build
    else
        xcodebuild \
            -project "${PROJECT_NAME}.xcodeproj" \
            -scheme "${SCHEME}" \
            -configuration "${CONFIGURATION}" \
            -destination "${DESTINATION}" \
            -derivedDataPath "${DERIVED_DATA}" \
            -allowProvisioningUpdates \
            build
    fi

    if [[ ! -d "${APP_PATH}" ]]; then
        echo "❌ 未找到构建产物: ${APP_PATH}" >&2
        exit 1
    fi

    echo ""
    if [[ "$USE_SIMULATOR" == true ]]; then
        echo "[2/3] 安装到模拟器..."
        xcrun simctl install "$DEVICE" "${APP_PATH}"
    else
        echo "[2/3] 安装到真机..."
        xcrun devicectl device install app --device "${DEVICE}" "${APP_PATH}"
    fi
fi

if [[ "$INSTALL_ONLY" == false ]]; then
    echo ""
    echo "[3/3] 启动 App..."
    if [[ "$USE_SIMULATOR" == true ]]; then
        if [[ "$LAUNCH_ONLY" == true ]]; then
            ensure_simulator_booted "$DEVICE"
        fi
        xcrun simctl launch "$DEVICE" "${BUNDLE_ID}"
    else
        xcrun devicectl device process launch --device "${DEVICE}" "${BUNDLE_ID}"
    fi
fi

echo ""
echo "✅ 完成"
if [[ "$INSTALL_ONLY" == false ]]; then
    echo ""
    echo "查看日志:"
    if [[ "$USE_SIMULATOR" == true ]]; then
        echo "  xcrun simctl spawn ${DEVICE} log stream --predicate 'processImagePath CONTAINS \"Vanmo\"'"
    else
        echo "  推荐: 打开 Console.app，左侧选中设备，搜索 Vanmo（或 [Debug] 前缀）"
        echo "  也可: Xcode → Window → Devices and Simulators → 选中设备 → Open Console"
        echo "  说明: macOS 26 的 log stream 不支持 --device；CLI 采集需 sudo："
        echo "    sudo log collect --device-udid ${DEVICE} --last 5m --output /tmp/vanmo.logarchive"
        echo "    log show /tmp/vanmo.logarchive --style compact --predicate 'processImagePath CONTAINS \"Vanmo\"'"
    fi
fi
