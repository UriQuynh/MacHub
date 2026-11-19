#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           MacHub — Build Script          ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Cấu hình phát hành (một nguồn duy nhất cho version, repo, khóa Sparkle) ──
cd "$(dirname "$0")"
# shellcheck source=config/release.env
source config/release.env
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
SPARKLE_PUBLIC_ED_KEY="$(tr -d '[:space:]' < config/sparkle_public_ed_key)"
FEED_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/appcast.xml"
REPO_URL="https://github.com/${GITHUB_REPO}"
case "$APP_VERSION" in
    ''|*[!0-9.]*) echo "❌ VERSION không hợp lệ: '$APP_VERSION'"; exit 1 ;;
esac
if [[ "$SPARKLE_PUBLIC_ED_KEY" == __* || "$GITHUB_REPO" == __* ]]; then
    echo "⚠️  Chưa cấu hình GITHUB_REPO hoặc khóa Sparkle → bản build này sẽ TẮT tự cập nhật."
    echo "   Chạy ./scripts/setup-sparkle-keys.sh và sửa config/release.env."
fi

# ── Step 0: Terminate existing instances ──
if [ "$CI" != "true" ] && [ "$1" != "--no-run" ]; then
    echo "🛑 Stopping any running instances..."
    pkill -9 MacHub 2>/dev/null || true
    sleep 0.5
fi

# ── Step 1: Build (Default: Apple Silicon chip M / Optional: --universal) ──
BUILD_UNIVERSAL=false
for arg in "$@"; do
    if [ "$arg" = "--universal" ]; then
        BUILD_UNIVERSAL=true
    fi
done

if [ "$BUILD_UNIVERSAL" = "true" ]; then
    echo "🔨 Building MacHub (Release - Universal 2: arm64 + x86_64)..."
    mkdir -p .build/bin_arm64 .build/bin_x86_64 .build/release
    echo "  -> Compiling arm64 (Apple Silicon)..."
    swift build -c release --triple arm64-apple-macosx >/dev/null 2>&1 || swift build -c release
    if [ -f ".build/out/Products/Release/MacHub" ]; then
        cp .build/out/Products/Release/MacHub .build/bin_arm64/MacHub
    elif [ -f ".build/release/MacHub" ]; then
        cp .build/release/MacHub .build/bin_arm64/MacHub
    fi

    echo "  -> Compiling x86_64 (Intel)..."
    swift build -c release --triple x86_64-apple-macosx >/dev/null 2>&1 || true
    if [ -f ".build/out/Products/Release/MacHub" ]; then
        cp .build/out/Products/Release/MacHub .build/bin_x86_64/MacHub
    fi

    BINARY=".build/release/MacHub"
    if [ -f ".build/bin_arm64/MacHub" ] && [ -f ".build/bin_x86_64/MacHub" ]; then
        echo "  -> Merging with lipo (Universal 2)..."
        lipo -create .build/bin_arm64/MacHub .build/bin_x86_64/MacHub -output "$BINARY"
    elif [ -f ".build/bin_arm64/MacHub" ]; then
        cp .build/bin_arm64/MacHub "$BINARY"
    fi
else
    echo "⚡ Building MacHub (Tốc độ cao - Chip M: M1/M2/M3/M4)..."
    swift build -c release
    BINARY=".build/release/MacHub"
fi

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed – binary not found."
    exit 1
fi
echo "✅ Build succeeded: $(file "$BINARY")"

# ── Step 2: Create .app bundle ──
APP_NAME="MacHub"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "📦 Creating app bundle..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "$BINARY" "${MACOS}/"
# Hook cho Claude Code (cùng thư mục build với binary chính).
HOOK_BIN="$(dirname "$BINARY")/machub-agent-hook"
if [ ! -f "$HOOK_BIN" ]; then HOOK_BIN=".build/release/machub-agent-hook"; fi
if [ -f "$HOOK_BIN" ]; then
    cp "$HOOK_BIN" "${MACOS}/machub-agent-hook"
else
    echo "❌ Không tìm thấy machub-agent-hook"
    exit 1
fi

# Copy Resources (AppIcon.icns, cover.jpg, helper scripts)
if [ -d "Resources" ]; then
    echo "🎨 Copying app resources (icons, cover image, helper scripts)..."
    cp -R Resources/* "${RESOURCES}/"
    chmod +x "${RESOURCES}/machub-power" "${RESOURCES}/install-helper.sh" 2>/dev/null || true
fi

# smc chạy bằng root qua helper → luôn biên dịch từ mã nguồn trong Vendor/, không dùng binary dựng sẵn.
echo "🔧 Compiling smc from Vendor/smc-command..."
SMC_ARCH_ARGS=(-arch arm64)
if [ "$BUILD_UNIVERSAL" = "true" ]; then
    SMC_ARCH_ARGS=(-arch arm64 -arch x86_64)
fi
clang "${SMC_ARCH_ARGS[@]}" -O2 -Wall -DCMD_TOOL_BUILD -mmacosx-version-min=14.0 \
    -framework IOKit -o "${RESOURCES}/smc" Vendor/smc-command/smc.c
chmod 755 "${RESOURCES}/smc"
echo "   smc sha256: $(shasum -a 256 "${RESOURCES}/smc" | cut -d' ' -f1)"

# Sparkle.framework (cập nhật có chữ ký EdDSA) → Contents/Frameworks
FRAMEWORKS="${CONTENTS}/Frameworks"
SPARKLE_FW=""
for candidate in \
    ".build/release/Sparkle.framework" \
    ".build/arm64-apple-macosx/release/Sparkle.framework" \
    ".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"; do
    if [ -d "$candidate" ]; then SPARKLE_FW="$candidate"; break; fi
done
if [ -z "$SPARKLE_FW" ]; then
    echo "❌ Không tìm thấy Sparkle.framework (swift build đã resolve package chưa?)"
    exit 1
fi
mkdir -p "${FRAMEWORKS}"
ditto "$SPARKLE_FW" "${FRAMEWORKS}/Sparkle.framework"
if ! otool -l "${MACOS}/MacHub" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS}/MacHub"
fi
if [ -f "LICENSE" ]; then
    cp "LICENSE" "${RESOURCES}/LICENSE"
fi

# Info.plist — LSUIElement hides dock icon (menu-bar only)
cat > "${CONTENTS}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacHub</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>MacHub</string>
    <key>CFBundleDisplayName</key>
    <string>MacHub</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MacHub — dựa trên HyperMac © 2026 Nguyễn Khắc Đại. GNU GPLv3.</string>
    <key>MHRepositoryURL</key>
    <string>${REPO_URL}</string>
    <key>SUFeedURL</key>
    <string>${FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>${SPARKLE_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MacHub sử dụng Bluetooth để tự động ngắt kết nối khi gập nắp máy (Sleep Guard), giúp chống tụt pin và chống nóng máy khi ngủ.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>MacHub quản lý nguồn Bluetooth khi máy Mac vào chế độ ngủ để tiết kiệm pin.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>MacHub cần quyền ghi màn hình để hiển thị ảnh xem trước các cửa sổ trong trình chuyển đổi Alt+Tab.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>MacHub sử dụng AppleEvents để điều khiển các ứng dụng và màn hình.</string>
</dict>
</plist>
PLIST

# ── Step 3: Code sign ──
# Dùng chứng chỉ self-signed cố định nếu có (scripts/setup-signing-identity.sh).
# Ký ad-hoc tạo cdhash mới mỗi lần build → macOS thu hồi quyền Accessibility
# sau mỗi lần rebuild. Identity cố định giữ nguyên Designated Requirement.
SIGN_IDENTITY="${MACHUB_SIGN_IDENTITY:-MacHub Self-Signed}"
SIGN_KEYCHAIN="${MACHUB_SIGN_KEYCHAIN:-}"
FIND_ARGS=()
if [[ -n "${SIGN_KEYCHAIN}" ]]; then
    FIND_ARGS=("${SIGN_KEYCHAIN}")
fi
# Không dùng -v: trên runner CI, cert tự ký không được trust nên -v (valid only)
# sẽ báo 0 identity dù vẫn ký được. codesign chỉ cần identity + private key.
if security find-identity -p codesigning "${FIND_ARGS[@]}" 2>/dev/null | grep -qF "${SIGN_IDENTITY}"; then
    echo "🔏 Code signing (${SIGN_IDENTITY})..."
    KC_ARGS=()
    if [[ -n "${SIGN_KEYCHAIN}" ]]; then
        KC_ARGS=(--keychain "${SIGN_KEYCHAIN}")
    fi
    # Ký từ trong ra ngoài: Sparkle (giữ identifier riêng của nó) → smc → app.
    # Không dùng --identifier kèm --deep vì sẽ ghi đè identifier của code lồng bên trong.
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${KC_ARGS[@]}" "${FRAMEWORKS}/Sparkle.framework"
    codesign --force --sign "${SIGN_IDENTITY}" "${KC_ARGS[@]}" "${RESOURCES}/smc"
    codesign --force --sign "${SIGN_IDENTITY}" "${KC_ARGS[@]}" --identifier "com.machub.app.agent-hook" "${MACOS}/machub-agent-hook"
    codesign --force --sign "${SIGN_IDENTITY}" "${KC_ARGS[@]}" --identifier "${BUNDLE_ID}" "${APP_DIR}"
else
    echo "🔏 Code signing (ad-hoc — quyền Accessibility sẽ mất sau mỗi lần build)..."
    echo "   → Chạy ./scripts/setup-signing-identity.sh một lần để hết bị."
    codesign --force --deep --sign - "${FRAMEWORKS}/Sparkle.framework" 2>/dev/null || true
    codesign --force --sign - "${RESOURCES}/smc" 2>/dev/null || true
    codesign --force --sign - --identifier "com.machub.app.agent-hook" "${MACOS}/machub-agent-hook" 2>/dev/null || true
    codesign --force --sign - --identifier "${BUNDLE_ID}" "${APP_DIR}" 2>/dev/null || true
fi

# ── Step 3.1: Create release zip package ──
echo "📦 Packaging ${BUILD_DIR}/MacHub.zip for distribution..."
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "${APP_DIR}" "${BUILD_DIR}/MacHub.zip"
echo "✅ Package created: ${BUILD_DIR}/MacHub.zip"

# ── Step 3.2: Create release DMG package ──
echo "📀 Packaging ${BUILD_DIR}/MacHub.dmg for distribution..."
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}" "${BUILD_DIR}/MacHub.dmg"
mkdir -p "${DMG_TEMP}"
cp -R "${APP_DIR}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"
hdiutil create -volname "MacHub" -srcfolder "${DMG_TEMP}" -ov -format UDZO "${BUILD_DIR}/MacHub.dmg" >/dev/null 2>&1 || true
rm -rf "${DMG_TEMP}"
if [ -f "${BUILD_DIR}/MacHub.dmg" ]; then
    echo "✅ Package created: ${BUILD_DIR}/MacHub.dmg"
fi

if [ "$CI" = "true" ] || [ "$1" = "--no-run" ]; then
    echo "📦 CI build completed. Artifacts are ready at: ${BUILD_DIR}/MacHub.zip & ${BUILD_DIR}/MacHub.dmg"
    exit 0
fi

# ── Step 4: Install to /Applications/ ──
echo "🚀 Installing to /Applications/MacHub.app..."
pkill -9 MacHub 2>/dev/null || true
sleep 0.3
rm -rf /Applications/MacHub.app
cp -R "${APP_DIR}" /Applications/MacHub.app

# ── Step 5: Launch ──
echo "▶️ Launching /Applications/MacHub.app..."
open /Applications/MacHub.app

sleep 1
PID=$(pgrep -x MacHub || true)
if [ -n "$PID" ]; then
    echo "✅ MacHub is running with PID: $PID"
else
    echo "⚠️ MacHub not detected yet, please check Console."
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✅  MacHub updated & running!"
echo "══════════════════════════════════════════"
echo ""
