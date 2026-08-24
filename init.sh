#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

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

echo "==> 检查 CloudKit 与跨平台边界"
./scripts/check-cloud-sync-multiplatform-scope.sh

echo "==> 默认启动命令"
echo "    ./run_device.sh --macos"

if [[ "${RUN_START_COMMAND:-0}" == "1" ]]; then
    echo "==> 构建并启动 macOS 应用"
    exec ./run_device.sh --macos
fi

echo "设置 RUN_START_COMMAND=1 可在验证后构建并启动 macOS 应用。"
