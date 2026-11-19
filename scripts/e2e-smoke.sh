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
check "Có machub-agent-hook trong bundle"  test -x "$APP/Contents/MacOS/machub-agent-hook"
check "machub-agent-hook đã được ký"        codesign --verify "$APP/Contents/MacOS/machub-agent-hook"
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

echo "▶ 3. Render UI (tab 0–2 + tab Agent với dữ liệu mẫu)"
for TAB in 0 1 2 4; do
    PNG="$OUT/ui-tab$TAB.png"
    rm -f "$PNG"
    MACHUB_PREVIEW=1 MACHUB_PREVIEW_TAB=$TAB MACHUB_PREVIEW_OUT="$PNG" MACHUB_AGENT_FIXTURES=1 MACHUB_PREVIEW_WAIT=1 \
        "$BIN" >"$OUT/preview-tab$TAB.log" 2>&1 &
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
DUMP="$OUT/agent-dump.json"
rm -f "$DUMP"
MACHUB_AGENT_DUMP="$DUMP" "$BIN" >"$OUT/app-stdout.log" 2>&1 &
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

echo "▶ 4b. Theo dõi agent qua hook thật"
HOOK="$APP/Contents/MacOS/machub-agent-hook"
check "Socket agent quyền 0600" test "$(stat -f %Lp "$SUPPORT/agent.sock" 2>/dev/null)" = "600"
mkdir -p "$OUT/fake-repo/.git"; echo "ref: refs/heads/feature-x" > "$OUT/fake-repo/.git/HEAD"
CWD="$(cd "$OUT/fake-repo" && pwd)"
printf '{"hook_event_name":"SessionStart","session_id":"e2e-1","cwd":"%s","source":"startup","model":"claude-sonnet-5-5"}' "$CWD" | "$HOOK" claude
printf '{"hook_event_name":"UserPromptSubmit","session_id":"e2e-1","cwd":"%s","prompt":"chạy test e2e"}' "$CWD" | "$HOOK" claude
printf '{"model":{"id":"claude-sonnet-5-5","display_name":"Sonnet"},"session_id":"e2e-1","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":%s}}}' "$(( $(date +%s) + 3600 ))" \
    | "$HOOK" statusline > "$OUT/statusline.txt"
sleep 2
check "Phiên Claude hiện trong MacHub"   bash -c "grep -q '\"id\":\"claude:e2e-1\"' '$DUMP'"
check "Trạng thái 'running' sau prompt"  bash -c "grep -q '\"state\":\"running\"' '$DUMP'"
check "Đọc repo + nhánh từ .git"         bash -c "grep -q '\"branch\":\"feature-x\"' '$DUMP' && grep -q '\"repo\":\"fake-repo\"' '$DUMP'"
check "Hạn mức 5H từ statusLine"         bash -c "grep -q '\"five_hour\"' '$DUMP'"
check "statusLine in dòng trạng thái"    grep -q "5H 12%" "$OUT/statusline.txt"
printf '{"hook_event_name":"Stop","session_id":"e2e-1","cwd":"%s","last_assistant_message":"xong"}' "$CWD" | "$HOOK" claude
sleep 1
check "Trạng thái 'finished' sau Stop"   bash -c "grep -q '\"state\":\"finished\"' '$DUMP'"
# Yêu cầu quyền khi không ai bấm: hook phải trả về rỗng (để terminal hỏi), không bao giờ tự cho phép.
START=$(date +%s)
PERM_OUT=$(printf '{"hook_event_name":"PermissionRequest","session_id":"e2e-1","cwd":"%s","tool_name":"Bash","tool_input":{"command":"echo hi"}}' "$CWD" \
    | MACHUB_AGENT_SUPPORT_DIR="$OUT/no-machub" "$HOOK" claude)
check "Không có MacHub → không tự cho phép" test -z "$PERM_OUT"
check "…và trả về ngay"                    test $(( $(date +%s) - START )) -le 3

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
