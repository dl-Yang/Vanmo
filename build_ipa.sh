#!/bin/bash
set -euo pipefail

PROJECT_NAME="Vanmo"
SCHEME="Vanmo"
CONFIGURATION="Release"
EXPORT_OPTIONS="ExportOptions.plist"

BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
IPA_DIR="${BUILD_DIR}/ipa"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "============================================"
echo "  Vanmo iOS 打包脚本"
echo "  $(date)"
echo "============================================"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${IPA_DIR}"

echo ""
echo "[1/3] 清理项目..."
xcodebuild clean \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -quiet

echo ""
echo "[2/3] 归档项目..."
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=iOS" \
    -quiet

if [ ! -d "${ARCHIVE_PATH}" ]; then
    echo "❌ 归档失败，未找到 .xcarchive 文件"
    exit 1
fi

echo ""
echo "[3/3] 导出 IPA..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${IPA_DIR}" \
    -exportOptionsPlist "${EXPORT_OPTIONS}" \
    -quiet

IPA_FILE=$(find "${IPA_DIR}" -name "*.ipa" -type f | head -1)
if [ -z "${IPA_FILE}" ]; then
    echo "❌ 导出失败，未找到 .ipa 文件"
    exit 1
fi

IPA_SIZE=$(du -h "${IPA_FILE}" | cut -f1)

echo ""
echo "============================================"
echo "  ✅ 打包成功！"
echo "  IPA 文件: ${IPA_FILE}"
echo "  文件大小: ${IPA_SIZE}"
echo "============================================"
echo ""
echo "后续步骤："
echo "  蒲公英上传: curl -F 'file=@${IPA_FILE}' -F '_api_key=YOUR_API_KEY' https://www.pgyer.com/apiv2/app/upload"
echo "  fir.im 上传: fir publish '${IPA_FILE}' -T YOUR_API_TOKEN"
echo ""
