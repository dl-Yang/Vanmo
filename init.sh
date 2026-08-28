#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

usage() {
    cat <<'EOF'
Usage:
  ./init.sh
  ./init.sh --full
  ./init.sh --help

Default mode runs the fast repository baseline and does not compile either application.
--full runs that baseline first, then Debug compile evidence for the iOS Simulator and macOS apps.
EOF
}

FULL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --full)
            if [[ "$FULL" -eq 1 ]]; then
                echo "❌ repeated argument: --full" >&2
                usage >&2
                exit 2
            fi
            FULL=1
            shift
            ;;
        *)
            echo "❌ unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

echo "==> 仓库目录: $PWD"

for command in swift xcodebuild; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "❌ 缺少必需命令: $command" >&2
        exit 1
    fi
done

echo "==> 解析 VanmoCore 依赖"
swift package resolve --package-path Packages/VanmoCore

echo "==> 运行 VanmoCore 基线测试"
swift test --package-path Packages/VanmoCore

echo "==> 检查 CloudKit、跨平台边界与结构守卫"
./scripts/check-cloud-sync-multiplatform-scope.sh

echo "==> 检查 Advanced Harness 文档守卫"
./scripts/check-harness-docs.sh

echo "==> 检查 iOS UI 交互 CLI"
./scripts/check-ios-ui-cli.sh

if [[ "$FULL" -eq 1 ]]; then
    echo "==> 编译 iOS Simulator 与 macOS Debug 应用"
    ./scripts/check-app-build.sh all
fi

echo "==> 默认启动命令"
echo "    ./run_device.sh --macos"

if [[ "${RUN_START_COMMAND:-0}" == "1" ]]; then
    echo "==> 构建并启动 macOS 应用"
    exec ./run_device.sh --macos
fi

echo "设置 RUN_START_COMMAND=1 可在验证后构建并启动 macOS 应用。"
