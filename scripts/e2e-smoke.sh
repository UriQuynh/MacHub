#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  e2e-smoke.sh — kiểm thử đầu-cuối bản build/MacHub.app trên macOS thật.
#
#  Chạy sau `./build.sh --no-run`. Dùng được cả trên máy dev lẫn GitHub Actions.
#  Không cần quyền Trợ năng / Ghi màn hình; không cài helper root.
#
#  Kiểm tra:
#   1. Cấu trúc bundle, Info.plist, Sparkle nhúng đúng, chữ ký code hợp lệ.
#   2. smc được biên dịch từ nguồn (Mach-O arm64) và helper script hợp lệ.
#   3. Render 3 tab UI ra PNG (app thật khởi động, dyld nạp được Sparkle).
#   4. Chạy app ở chế độ thường: sống ổn định, ghi log đúng chỗ, không crash.
#   5. Clipboard: copy một chuỗi → lịch sử được lưu MÃ HÓA trên đĩa.
#
#  Kết quả (ảnh, log) ở build/e2e/.
# ─────────────────────────────────────────────────────────────
set -uo pipefail
cd "$(dirname "$0")/.."

APP="build/MacHub.app"
BIN="$APP/Contents/MacOS/MacHub"
OUT="build/e2e"
SUPPORT="$HOME/Library/Application Support/MacHub"
LOG="$HOME/Library/Logs/MacHub/machub.log"
VERSION="$(tr -d '[:space:]' < VERSION)"
mkdir -p "$OUT"

PASS=0
FAIL=0
pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }

[ -x "$BIN" ] || { echo "❌ Chưa có $BIN — chạy ./build.sh --no-run trước."; exit 1; }

echo "▶ 1. Bundle & chữ ký"
check "Info.plist hợp lệ"                 plutil -lint "$APP/Contents/Info.plist"
check "Bundle ID = com.machub.app"        test "$(plist CFBundleIdentifier)" = "com.machub.app"
check "Phiên bản = VERSION ($VERSION)"     test "$(plist CFBundleShortVersionString)" = "$VERSION"
check "SUFeedURL là https"                bash -c "[[ '$(plist SUFeedURL)' == https://* ]]"
check "Có SUPublicEDKey"                  test -n "$(plist SUPublicEDKey)"
check "LSUIElement (ẩn Dock)"             test "$(plist LSUIElement)" = "true"
check "Sparkle.framework được nhúng"      test -d "$APP/Contents/Frameworks/Sparkle.framework"
check "Binary link @rpath/Sparkle"        bash -c "otool -L '$BIN' | grep -q '@rpath/Sparkle.framework'"
check "rpath trỏ tới ../Frameworks"       bash -c "otool -l '$BIN' | grep -q '@executable_path/../Frameworks'"
check "Chữ ký code hợp lệ (strict)"       codesign --verify --deep --strict "$APP"
check "Không còn tài nguyên donate/zalo"  bash -c "! ls '$APP/Contents/Resources' | grep -qiE 'donate|zalo'"

echo "▶ 2. smc & helper"
SMC="$APP/Contents/Resources/smc"
check "smc là Mach-O arm64"               bash -c "file '$SMC' | grep -q 'Mach-O.*arm64'"
check "smc đã được ký"                    codesign --verify "$SMC"
"$SMC" -h >"$OUT/smc-help.txt" 2>&1 || true
check "smc chạy được (in usage)"          grep -qi "usage" "$OUT/smc-help.txt"
check "machub-power cú pháp hợp lệ"       bash -n "$APP/Contents/Resources/machub-power"
check "install-helper.sh cú pháp hợp lệ"  bash -n "$APP/Contents/Resources/install-helper.sh"
check "Helper không tìm smc theo PATH"    grep -q '^export PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$APP/Contents/Resources/machub-power"

echo "▶ 3. Render UI (3 tab)"
for TAB in 0 1 2; do
    PNG="$OUT/ui-tab$TAB.png"
    rm -f "$PNG"
    MACHUB_PREVIEW=1 MACHUB_PREVIEW_TAB=$TAB MACHUB_PREVIEW_OUT="$PNG" "$BIN" >"$OUT/preview-tab$TAB.log" 2>&1 &
    PID=$!
    for _ in $(seq 1 60); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$PID" 2>/dev/null; then kill -9 "$PID" 2>/dev/null; fi
    SIZE=$(stat -f %z "$PNG" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 10000 ]; then pass "Tab $TAB render ra PNG (${SIZE} bytes)"; else fail "Tab $TAB không render được (xem $OUT/preview-tab$TAB.log)"; fi
done

echo "▶ 4. Chạy app ở chế độ thường"
pkill -x MacHub 2>/dev/null || true
CRASH_BEFORE=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^MacHub' || true)
LOG_BEFORE=$( [ -f "$LOG" ] && wc -c < "$LOG" || echo 0 )
"$BIN" >"$OUT/app-stdout.log" 2>&1 &
APP_PID=$!
sleep 12
check "App vẫn chạy sau 12 giây"          kill -0 "$APP_PID"
check "Log ở ~/Library/Logs/MacHub"       test -f "$LOG"
check "Log có quyền 0600"                 test "$(stat -f %Lp "$LOG" 2>/dev/null)" = "600"
check "Không còn ghi /tmp/displaycontrol.log" bash -c "[ ! -f /tmp/displaycontrol.log ] || [ \$(stat -f %m /tmp/displaycontrol.log) -lt \$(( \$(date +%s) - 60 )) ]"
tail -c +$((LOG_BEFORE + 1)) "$LOG" > "$OUT/app-run.log" 2>/dev/null || true
if [ "$(plist SUPublicEDKey)" = "__SPARKLE_PUBLIC_ED_KEY__" ]; then
    check "Bản chưa có khóa → tắt tự cập nhật" grep -q "tự cập nhật bị tắt" "$OUT/app-run.log"
fi

echo "▶ 5. Clipboard được lưu mã hóa"
MARKER="MACHUB_E2E_$(date +%s)_$RANDOM"
printf '%s' "$MARKER" | pbcopy
CLIP="$SUPPORT/clipboard.json"
FOUND=0
for _ in $(seq 1 20); do
    sleep 1
    if [ -f "$CLIP" ] && [ "$(stat -f %m "$CLIP")" -ge "$(( $(date +%s) - 25 ))" ]; then FOUND=1; break; fi
done
if [ "$FOUND" = 1 ]; then
    pass "clipboard.json được ghi sau khi copy"
    check "File có header MHE1"           bash -c "head -c 4 '$CLIP' | grep -q MHE1"
    check "Chuỗi vừa copy KHÔNG nằm dạng rõ" bash -c "! grep -qa '$MARKER' '$CLIP'"
    check "clipboard.json quyền 0600"     test "$(stat -f %Lp "$CLIP")" = "600"
    check "Thư mục dữ liệu quyền 0700"    test "$(stat -f %Lp "$SUPPORT")" = "700"
else
    fail "clipboard.json không được ghi trong 20 giây (xem $OUT/app-run.log)"
fi

kill "$APP_PID" 2>/dev/null; sleep 2; kill -9 "$APP_PID" 2>/dev/null || true
CRASH_AFTER=$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -c '^MacHub' || true)
check "Không có crash report mới"         test "$CRASH_AFTER" -le "$CRASH_BEFORE"
tail -c +$((LOG_BEFORE + 1)) "$LOG" > "$OUT/app-run.log" 2>/dev/null || true

echo ""
echo "Kết quả E2E: $PASS đạt, $FAIL lỗi. Ảnh & log: $OUT/"
[ "$FAIL" -eq 0 ]
