#!/bin/bash
set -euo pipefail

FFMPEG_VERSION="7.1"
MIN_IOS_VERSION="17.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/ffmpeg"
OUTPUT_DIR="$PROJECT_DIR/Vanmo/Frameworks/FFmpeg"
SOURCE_DIR="$BUILD_DIR/ffmpeg-$FFMPEG_VERSION"

NCPU=$(sysctl -n hw.ncpu)

echo "========================================"
echo " FFmpeg $FFMPEG_VERSION iOS Build Script"
echo "========================================"
echo "Build dir:  $BUILD_DIR"
echo "Output dir: $OUTPUT_DIR"
echo "CPU cores:  $NCPU"
echo ""

download_source() {
    mkdir -p "$BUILD_DIR"
    if [ -d "$SOURCE_DIR" ]; then
        echo "[skip] Source already downloaded."
        return
    fi

    local TARBALL="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    echo "[1/4] Downloading FFmpeg $FFMPEG_VERSION ..."
    curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "$TARBALL"
    echo "[1/4] Extracting ..."
    tar xf "$TARBALL" -C "$BUILD_DIR"
    echo "[1/4] Done."
}

build_arch() {
    local PLATFORM=$1   # iphoneos | iphonesimulator
    local ARCH="arm64"

    echo ""
    echo "----------------------------------------"
    echo " Building for $PLATFORM ($ARCH)"
    echo "----------------------------------------"

    local SDK_PATH
    SDK_PATH=$(xcrun --sdk "$PLATFORM" --show-sdk-path)
    local CC
    CC=$(xcrun --sdk "$PLATFORM" --find clang)
    local AS
    AS=$(xcrun --sdk "$PLATFORM" --find clang)

    local INSTALL_DIR="$BUILD_DIR/install-$PLATFORM"

    local EXTRA_CFLAGS="-arch $ARCH -isysroot $SDK_PATH -fembed-bitcode"
    local EXTRA_LDFLAGS="-arch $ARCH -isysroot $SDK_PATH"

    if [ "$PLATFORM" = "iphonesimulator" ]; then
        EXTRA_CFLAGS="$EXTRA_CFLAGS --target=arm64-apple-ios${MIN_IOS_VERSION}-simulator"
        EXTRA_LDFLAGS="$EXTRA_LDFLAGS --target=arm64-apple-ios${MIN_IOS_VERSION}-simulator"
    else
        EXTRA_CFLAGS="$EXTRA_CFLAGS --target=arm64-apple-ios${MIN_IOS_VERSION}"
        EXTRA_LDFLAGS="$EXTRA_LDFLAGS --target=arm64-apple-ios${MIN_IOS_VERSION}"
    fi

    cd "$SOURCE_DIR"
    make distclean 2>/dev/null || true

    ./configure \
        --prefix="$INSTALL_DIR" \
        --enable-cross-compile \
        --target-os=darwin \
        --arch="$ARCH" \
        --cc="$CC" \
        --as="$AS" \
        --sysroot="$SDK_PATH" \
        --extra-cflags="$EXTRA_CFLAGS" \
        --extra-ldflags="$EXTRA_LDFLAGS" \
        --enable-pic \
        --enable-static \
        --disable-shared \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-avdevice \
        --disable-postproc \
        --disable-avfilter \
        --enable-network \
        --enable-protocol=file \
        --enable-protocol=http \
        --enable-protocol=https \
        --enable-protocol=httpproxy \
        --enable-protocol=tcp \
        --enable-protocol=tls \
        --enable-securetransport \
        --enable-demuxer=dash \
        --enable-videotoolbox \
        --enable-audiotoolbox \
        --disable-encoders \
        --disable-muxers \
        --disable-bsfs \
        --disable-devices \
        --disable-x86asm \
        --enable-neon

    echo "Compiling ($NCPU parallel jobs) ..."
    make -j"$NCPU"
    make install

    echo "[OK] $PLATFORM build complete -> $INSTALL_DIR"
}

install_output() {
    echo ""
    echo "----------------------------------------"
    echo " Installing to project"
    echo "----------------------------------------"

    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/include"
    mkdir -p "$OUTPUT_DIR/lib/iphoneos"
    mkdir -p "$OUTPUT_DIR/lib/iphonesimulator"

    cp -R "$BUILD_DIR/install-iphoneos/include/"* "$OUTPUT_DIR/include/"

    cp "$BUILD_DIR/install-iphoneos/lib/"*.a "$OUTPUT_DIR/lib/iphoneos/"
    cp "$BUILD_DIR/install-iphonesimulator/lib/"*.a "$OUTPUT_DIR/lib/iphonesimulator/"

    echo ""
    echo "========================================"
    echo " Build complete!"
    echo "========================================"
    echo "Headers:       $OUTPUT_DIR/include/"
    echo "Device libs:   $OUTPUT_DIR/lib/iphoneos/"
    echo "Sim libs:      $OUTPUT_DIR/lib/iphonesimulator/"
    echo ""
    echo "Libraries built:"
    ls -lh "$OUTPUT_DIR/lib/iphoneos/"*.a 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
    echo ""
}

download_source
build_arch "iphoneos"
build_arch "iphonesimulator"
install_output
