#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Vanmo.xcodeproj"
SCHEME="Vanmo"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="${ROOT_DIR}/build/DerivedData-UITests"
RUNS_DIR="${ROOT_DIR}/build/ui-cli/runs"
ONLY_TESTING="VanmoUITests/VanmoDeviceInteractionTests/testExecuteCommand"
BUNDLE_ID="com.vanmo.app"

MODE=""
ACTION=""
DEVICE_SELECTOR=""
TEAM="${VANMO_DEVELOPMENT_TEAM:-}"
TEAM_OPTION_SET=false
OUTPUT_PATH=""
SELECTOR_KIND=""
SELECTOR_VALUE=""
TEXT_VALUE=""
EXPECTED_STATE=""
TIMEOUT=""
DIRECTION=""

usage() {
    cat <<'EOF'
[VanmoUI] 用法:
  scripts/ios-ui.sh device screenshot [--device UDID|名称] [--team TEAM] [--output PATH]
  scripts/ios-ui.sh device tree [--device UDID|名称] [--team TEAM] [--output PATH]
  scripts/ios-ui.sh device tap|type|wait|assert (--identifier VALUE | --label VALUE) [选项]
  scripts/ios-ui.sh device swipe --direction up|down|left|right [--device UDID|名称] [--team TEAM]
  scripts/ios-ui.sh simulator screenshot --output PATH [--device UDID|名称]
  scripts/ios-ui.sh simulator launch|terminate [--device UDID|名称]

[VanmoUI] 真机选项:
  --device UDID|名称       指定真机；默认使用首个真实 iOS destination
  --team TEAM              Development Team；默认读取 VANMO_DEVELOPMENT_TEAM
  --output PATH            screenshot/tree 输出路径
  --identifier VALUE       按 accessibility identifier 选择元素
  --label VALUE            按 accessibility label 选择元素
  --text VALUE             type 输入内容（必填；不会输出到日志）
  --state exists|absent    wait/assert 期望状态（必填）
  --timeout SECONDS        tap/type/wait/assert 超时，范围 0.1...60，默认 10
  --direction DIRECTION    swipe 方向：up、down、left、right

[VanmoUI] 默认真机输出:
  screenshot: ./vanmo-ui-screenshot.png
  tree:       ./vanmo-ui-tree.json

[VanmoUI] 示例:
  scripts/ios-ui.sh device screenshot --output /tmp/vanmo.png
  scripts/ios-ui.sh device tap --identifier play-button --timeout 5
  scripts/ios-ui.sh device type --label Search --text "example"
  scripts/ios-ui.sh device wait --identifier player --state exists
  scripts/ios-ui.sh simulator screenshot --output /tmp/simulator.png
  scripts/ios-ui.sh simulator launch --device "iPhone 17 Pro"
EOF
}

log() {
    printf '[VanmoUI] %s\n' "$*"
}

warn() {
    printf '[VanmoUI] 警告: %s\n' "$*" >&2
}

die() {
    printf '[VanmoUI] 错误: %s\n' "$*" >&2
    exit 1
}

require_option_value() {
    local option="$1"
    local count="$2"
    local value="${3:-}"

    if [[ "$count" -lt 2 || -z "$value" ]]; then
        die "${option} 缺少非空值"
    fi
}

set_selector() {
    local kind="$1"
    local value="$2"

    if [[ -n "$SELECTOR_KIND" ]]; then
        die "--identifier 与 --label 必须且只能提供一个"
    fi
    SELECTOR_KIND="$kind"
    SELECTOR_VALUE="$value"
}

validate_timeout() {
    python3 - "$TIMEOUT" <<'PY'
import math
import sys

raw = sys.argv[1]
try:
    value = float(raw)
except ValueError:
    raise SystemExit(1)

if not math.isfinite(value) or value < 0.1 or value > 60:
    raise SystemExit(1)
PY
}

parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --device)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$DEVICE_SELECTOR" ]] || die "--device 不能重复"
                DEVICE_SELECTOR="$2"
                shift 2
                ;;
            --team)
                require_option_value "$1" "$#" "${2:-}"
                [[ "$TEAM_OPTION_SET" == false ]] || die "--team 不能重复"
                TEAM="$2"
                TEAM_OPTION_SET=true
                shift 2
                ;;
            --output)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$OUTPUT_PATH" ]] || die "--output 不能重复"
                OUTPUT_PATH="$2"
                shift 2
                ;;
            --identifier)
                require_option_value "$1" "$#" "${2:-}"
                set_selector "identifier" "$2"
                shift 2
                ;;
            --label)
                require_option_value "$1" "$#" "${2:-}"
                set_selector "label" "$2"
                shift 2
                ;;
            --text)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$TEXT_VALUE" ]] || die "--text 不能重复"
                TEXT_VALUE="$2"
                shift 2
                ;;
            --state)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$EXPECTED_STATE" ]] || die "--state 不能重复"
                EXPECTED_STATE="$2"
                shift 2
                ;;
            --timeout)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$TIMEOUT" ]] || die "--timeout 不能重复"
                TIMEOUT="$2"
                shift 2
                ;;
            --direction)
                require_option_value "$1" "$#" "${2:-}"
                [[ -z "$DIRECTION" ]] || die "--direction 不能重复"
                DIRECTION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "未知参数: $1"
                ;;
        esac
    done
}

validate_no_selector() {
    [[ -z "$SELECTOR_KIND" ]] || die "${ACTION} 不支持 --identifier 或 --label"
}

validate_no_text() {
    [[ -z "$TEXT_VALUE" ]] || die "${ACTION} 不支持 --text"
}

validate_no_state() {
    [[ -z "$EXPECTED_STATE" ]] || die "${ACTION} 不支持 --state"
}

validate_no_timeout() {
    [[ -z "$TIMEOUT" ]] || die "${ACTION} 不支持 --timeout"
}

validate_no_direction() {
    [[ -z "$DIRECTION" ]] || die "${ACTION} 不支持 --direction"
}

validate_device_command() {
    case "$ACTION" in
        screenshot)
            [[ -n "$OUTPUT_PATH" ]] || OUTPUT_PATH="${PWD}/vanmo-ui-screenshot.png"
            validate_no_selector
            validate_no_text
            validate_no_state
            validate_no_timeout
            validate_no_direction
            ;;
        tree)
            [[ -n "$OUTPUT_PATH" ]] || OUTPUT_PATH="${PWD}/vanmo-ui-tree.json"
            validate_no_selector
            validate_no_text
            validate_no_state
            validate_no_timeout
            validate_no_direction
            ;;
        tap)
            [[ -n "$SELECTOR_KIND" ]] || die "tap 必须提供 --identifier 或 --label"
            [[ -z "$OUTPUT_PATH" ]] || die "tap 不支持 --output"
            validate_no_text
            validate_no_state
            validate_no_direction
            ;;
        type)
            [[ -n "$SELECTOR_KIND" ]] || die "type 必须提供 --identifier 或 --label"
            [[ -n "$TEXT_VALUE" ]] || die "type 必须提供非空 --text"
            [[ -z "$OUTPUT_PATH" ]] || die "type 不支持 --output"
            validate_no_state
            validate_no_direction
            ;;
        wait|assert)
            [[ -n "$SELECTOR_KIND" ]] || die "${ACTION} 必须提供 --identifier 或 --label"
            case "$EXPECTED_STATE" in
                exists|absent) ;;
                "") die "${ACTION} 必须提供 --state exists|absent" ;;
                *) die "--state 仅支持 exists 或 absent" ;;
            esac
            [[ -z "$OUTPUT_PATH" ]] || die "${ACTION} 不支持 --output"
            validate_no_text
            validate_no_direction
            ;;
        swipe)
            case "$DIRECTION" in
                up|down|left|right) ;;
                "") die "swipe 必须提供 --direction up|down|left|right" ;;
                *) die "--direction 仅支持 up、down、left 或 right" ;;
            esac
            [[ -z "$OUTPUT_PATH" ]] || die "swipe 不支持 --output"
            validate_no_selector
            validate_no_text
            validate_no_state
            validate_no_timeout
            ;;
        *)
            die "真机不支持命令: ${ACTION}"
            ;;
    esac

    if [[ -n "$TIMEOUT" ]] && ! validate_timeout; then
        die "--timeout 必须是 0.1 到 60 之间的有限数值"
    fi
    if [[ -n "$TEAM" && ! "$TEAM" =~ ^[A-Za-z0-9]{10}$ ]]; then
        die "--team 必须是 10 位字母数字 Apple Team ID"
    fi
}

validate_simulator_command() {
    [[ "$TEAM_OPTION_SET" == false ]] || die "模拟器命令不支持 --team"

    case "$ACTION" in
        tap|type|swipe|wait|assert|tree)
            die "模拟器 ${ACTION} 不受 simctl 支持；本工具按用户要求不在模拟器启用 XCUITest"
            ;;
        screenshot)
            [[ -n "$OUTPUT_PATH" ]] || die "模拟器 screenshot 必须提供 --output PATH"
            ;;
        launch|terminate)
            [[ -z "$OUTPUT_PATH" ]] || die "模拟器 ${ACTION} 不支持 --output"
            ;;
        *)
            die "模拟器不支持命令: ${ACTION}"
            ;;
    esac

    validate_no_selector
    validate_no_text
    validate_no_state
    validate_no_timeout
    validate_no_direction
}

list_ios_destinations() {
    local raw
    local line
    local platform
    local identifier
    local name
    local lowered_identifier

    if ! raw=$(xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -showdestinations 2>/dev/null); then
        die "无法读取 Xcode destinations；请确认工程和 Xcode 可用"
    fi

    while IFS= read -r line; do
        platform=$(printf '%s\n' "$line" \
            | sed -nE 's/.*platform:[[:space:]]*([^,}]+).*/\1/p' \
            | sed 's/[[:space:]]*$//')
        [[ "$platform" == "iOS" ]] || continue

        identifier=$(printf '%s\n' "$line" \
            | sed -nE 's/.*[[:space:]]id:[[:space:]]*([^,}]+).*/\1/p' \
            | sed 's/[[:space:]]*$//')
        name=$(printf '%s\n' "$line" \
            | sed -nE 's/.*name:[[:space:]]*([^}]+).*/\1/p' \
            | sed 's/[[:space:]]*$//')
        [[ -n "$identifier" && -n "$name" ]] || continue

        lowered_identifier=$(printf '%s' "$identifier" | tr '[:upper:]' '[:lower:]')
        [[ "$lowered_identifier" != *placeholder* ]] || continue
        printf '%s|%s\n' "$identifier" "$name"
    done < <(printf '%s\n' "$raw")
}

resolve_ios_device() {
    local destinations
    local identifier
    local name
    local first_result=""
    local exact_result=""
    local exact_count=0
    local partial_result=""
    local partial_count=0

    destinations=$(list_ios_destinations)
    [[ -n "$destinations" ]] || die "未检测到真实 iOS destination；请连接并信任设备"

    while IFS='|' read -r identifier name; do
        [[ -n "$identifier" ]] || continue
        [[ -n "$first_result" ]] || first_result="${identifier}|${name}"

        if [[ -n "$DEVICE_SELECTOR" ]]; then
            if [[ "$identifier" == "$DEVICE_SELECTOR" || "$name" == "$DEVICE_SELECTOR" ]]; then
                exact_result="${identifier}|${name}"
                exact_count=$((exact_count + 1))
            elif [[ "$name" == *"$DEVICE_SELECTOR"* ]]; then
                partial_result="${identifier}|${name}"
                partial_count=$((partial_count + 1))
            fi
        fi
    done < <(printf '%s\n' "$destinations")

    if [[ -z "$DEVICE_SELECTOR" ]]; then
        printf '%s\n' "$first_result"
    elif [[ "$exact_count" -eq 1 ]]; then
        printf '%s\n' "$exact_result"
    elif [[ "$exact_count" -gt 1 ]]; then
        die "设备名称匹配多个真机，请改用 UDID: ${DEVICE_SELECTOR}"
    elif [[ "$partial_count" -eq 1 ]]; then
        printf '%s\n' "$partial_result"
    elif [[ "$partial_count" -gt 1 ]]; then
        die "设备名称片段匹配多个真机，请提供完整名称或 UDID: ${DEVICE_SELECTOR}"
    else
        die "找不到真机: ${DEVICE_SELECTOR}"
    fi
}

resolve_simulator() {
    local devices_json
    local selection

    if ! devices_json=$(xcrun simctl list devices available -j); then
        die "无法读取可用模拟器；请确认 CoreSimulatorService 正常"
    fi

    if ! selection=$(SIMULATOR_SELECTOR="$DEVICE_SELECTOR" python3 -c '
import json
import os
import sys

payload = json.load(sys.stdin)
selector = os.environ.get("SIMULATOR_SELECTOR", "")
devices = []

for runtime_devices in payload.get("devices", {}).values():
    for device in runtime_devices:
        if device.get("isAvailable") is False:
            continue
        name = device.get("name", "")
        if not (name.startswith("iPhone") or name.startswith("iPad")):
            continue
        udid = device.get("udid", "")
        if udid:
            devices.append((udid, name, device.get("state", "")))

if not devices:
    print("[VanmoUI] 错误: 未找到 available iPhone/iPad 模拟器", file=sys.stderr)
    raise SystemExit(1)

if not selector:
    chosen = next((device for device in devices if device[2] == "Booted"), devices[0])
else:
    exact = [
        device for device in devices
        if device[0] == selector or device[1] == selector
    ]
    partial = [
        device for device in devices
        if selector.casefold() in device[1].casefold()
    ]
    if len(exact) == 1:
        chosen = exact[0]
    elif len(exact) > 1:
        print(
            "[VanmoUI] 错误: 模拟器名称匹配多个设备，请改用 UDID: " + selector,
            file=sys.stderr,
        )
        raise SystemExit(1)
    elif len(partial) == 1:
        chosen = partial[0]
    elif len(partial) > 1:
        print(
            "[VanmoUI] 错误: 模拟器名称片段匹配多个设备，请提供完整名称或 UDID: "
            + selector,
            file=sys.stderr,
        )
        raise SystemExit(1)
    else:
        print("[VanmoUI] 错误: 找不到模拟器: " + selector, file=sys.stderr)
        raise SystemExit(1)

print("|".join(chosen))
' <<< "$devices_json"); then
        exit 1
    fi

    printf '%s\n' "$selection"
}

ensure_simulator_booted() {
    local udid="$1"
    local state="$2"

    if [[ "$state" != "Booted" ]]; then
        log "正在启动模拟器 ${udid}"
        xcrun simctl boot "$udid"
    fi
    xcrun simctl bootstatus "$udid" -b
}

export_attachments() {
    local result_bundle="$1"
    local attachments_dir="$2"
    local export_log="$3"
    local export_status

    mkdir -p "$attachments_dir"
    set +e
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$attachments_dir" \
        >"$export_log" 2>&1
    export_status=$?
    set -e

    if [[ "$export_status" -ne 0 ]]; then
        warn "附件导出失败；详情见 ${export_log}"
    fi
}

find_exported_attachment() {
    local attachments_dir="$1"
    local attachment_name="$2"
    local manifest_path="${attachments_dir}/manifest.json"

    [[ -f "$manifest_path" ]] || return 1

    python3 - "$manifest_path" "$attachments_dir" "$attachment_name" <<'PY'
import json
import os
import sys

manifest_path, attachments_dir, wanted_name = sys.argv[1:]
with open(manifest_path, encoding="utf-8") as handle:
    payload = json.load(handle)

exported_names = []

def visit(value):
    if isinstance(value, dict):
        if value.get("suggestedHumanReadableName") == wanted_name:
            exported_name = value.get("exportedFileName")
            if isinstance(exported_name, str) and exported_name:
                exported_names.append(exported_name)
        for child in value.values():
            visit(child)
    elif isinstance(value, list):
        for child in value:
            visit(child)

visit(payload)
root = os.path.abspath(attachments_dir)
for exported_name in exported_names:
    candidate = os.path.abspath(os.path.join(root, exported_name))
    try:
        is_inside_root = os.path.commonpath((root, candidate)) == root
    except ValueError:
        is_inside_root = False
    if is_inside_root and os.path.isfile(candidate):
        print(candidate)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

copy_requested_attachment() {
    local attachments_dir="$1"
    local attachment_name="$2"
    local source_path

    if ! source_path=$(find_exported_attachment "$attachments_dir" "$attachment_name"); then
        warn "未在附件 manifest 中找到 ${attachment_name}"
        return 1
    fi

    mkdir -p "$(dirname "$OUTPUT_PATH")"
    if ! cp "$source_path" "$OUTPUT_PATH"; then
        warn "无法复制附件到 ${OUTPUT_PATH}"
        return 1
    fi
    log "输出已保存: ${OUTPUT_PATH}"
}

run_device_command() {
    local resolved
    local device_udid
    local device_name
    local run_id
    local run_dir
    local result_bundle
    local attachments_dir
    local xcodebuild_log
    local export_log
    local team_xcconfig=""
    local test_status
    local post_status=0
    local attachment_name=""
    local -a environment_args
    local -a xcodebuild_args
    local -a pipeline_status

    resolved=$(resolve_ios_device)
    IFS='|' read -r device_udid device_name <<< "$resolved"
    log "目标真机: ${device_name} (${device_udid})"

    run_id="$(date '+%Y%m%d-%H%M%S')-$$"
    run_dir="${RUNS_DIR}/${run_id}"
    result_bundle="${run_dir}/result.xcresult"
    attachments_dir="${run_dir}/attachments"
    xcodebuild_log="${run_dir}/xcodebuild.log"
    export_log="${run_dir}/attachments-export.log"
    mkdir -p "$run_dir"
    : >"$xcodebuild_log"
    log "运行目录: ${run_dir}"
    log "执行真机命令: ${ACTION}"

    environment_args=("TEST_RUNNER_VANMO_UI_ACTION=${ACTION}")
    [[ -z "$SELECTOR_KIND" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_SELECTOR_KIND=${SELECTOR_KIND}")
    [[ -z "$SELECTOR_VALUE" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_SELECTOR=${SELECTOR_VALUE}")
    [[ -z "$TEXT_VALUE" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_TEXT=${TEXT_VALUE}")
    [[ -z "$EXPECTED_STATE" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_EXPECTED=${EXPECTED_STATE}")
    [[ -z "$TIMEOUT" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_TIMEOUT=${TIMEOUT}")
    [[ -z "$DIRECTION" ]] \
        || environment_args+=("TEST_RUNNER_VANMO_UI_DIRECTION=${DIRECTION}")

    xcodebuild_args=(
        -project "$PROJECT_PATH"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -destination "platform=iOS,id=${device_udid}"
        -derivedDataPath "$DERIVED_DATA_PATH"
        -resultBundlePath "$result_bundle"
        "-only-testing:${ONLY_TESTING}"
        -parallel-testing-enabled NO
        -maximum-concurrent-test-device-destinations 1
        -hideShellScriptEnvironment
        -allowProvisioningUpdates
        test
    )
    if [[ -n "$TEAM" ]]; then
        team_xcconfig="${run_dir}/signing.xcconfig"
        printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM" >"$team_xcconfig"
        chmod 600 "$team_xcconfig"
        xcodebuild_args=(-xcconfig "$team_xcconfig" "${xcodebuild_args[@]}")
    fi

    set +e
    env "${environment_args[@]}" \
        xcodebuild "${xcodebuild_args[@]}" 2>&1 \
        | tee "$xcodebuild_log"
    pipeline_status=("${PIPESTATUS[@]}")
    test_status="${pipeline_status[0]}"
    set -e
    [[ -z "$team_xcconfig" ]] || rm -f "$team_xcconfig"

    export_attachments "$result_bundle" "$attachments_dir" "$export_log"

    case "$ACTION" in
        screenshot)
            attachment_name="vanmo-ui-screenshot.png"
            ;;
        tree)
            attachment_name="vanmo-ui-tree.json"
            ;;
    esac

    if [[ -n "$attachment_name" ]]; then
        copy_requested_attachment "$attachments_dir" "$attachment_name" || post_status=1
    fi

    if [[ "$test_status" -ne 0 ]]; then
        warn "XCUITest 失败，退出码 ${test_status}；运行目录: ${run_dir}"
        return "$test_status"
    fi
    if [[ "$post_status" -ne 0 ]]; then
        warn "测试成功但请求的附件不可用；运行目录: ${run_dir}"
        return "$post_status"
    fi

    log "真机命令完成；运行目录: ${run_dir}"
}

run_simulator_command() {
    local resolved
    local simulator_udid
    local simulator_name
    local simulator_state

    resolved=$(resolve_simulator)
    IFS='|' read -r simulator_udid simulator_name simulator_state <<< "$resolved"
    log "目标模拟器: ${simulator_name} (${simulator_udid})"

    case "$ACTION" in
        screenshot)
            ensure_simulator_booted "$simulator_udid" "$simulator_state"
            mkdir -p "$(dirname "$OUTPUT_PATH")"
            xcrun simctl io "$simulator_udid" screenshot "$OUTPUT_PATH"
            log "输出已保存: ${OUTPUT_PATH}"
            ;;
        launch)
            ensure_simulator_booted "$simulator_udid" "$simulator_state"
            xcrun simctl launch "$simulator_udid" "$BUNDLE_ID"
            log "模拟器 App 已启动"
            ;;
        terminate)
            xcrun simctl terminate "$simulator_udid" "$BUNDLE_ID"
            log "模拟器 App 已终止"
            ;;
    esac
}

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    usage
    exit 0
fi
if [[ $# -lt 2 ]]; then
    usage >&2
    die "必须提供平台和命令"
fi

MODE="$1"
ACTION="$2"
shift 2
parse_options "$@"

case "$MODE" in
    device)
        validate_device_command
        run_device_command
        ;;
    simulator)
        validate_simulator_command
        run_simulator_command
        ;;
    *)
        die "平台仅支持 device 或 simulator: ${MODE}"
        ;;
esac
