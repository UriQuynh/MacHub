#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  setup-sparkle-keys.sh — chạy MỘT LẦN trên Mac của người phát hành.
#
#  1. Tạo cặp khóa EdDSA của Sparkle (private key lưu trong Keychain đăng nhập).
#  2. Ghi khóa CÔNG KHAI vào config/sparkle_public_ed_key (commit được).
#  3. Đưa khóa RIÊNG vào GitHub secret MACHUB_SPARKLE_ED_PRIVATE_KEY qua `gh`
#     (không ghi ra đĩa), để CI ký file zip phát hành.
#
#  Mất private key = không phát hành được bản cập nhật cho người dùng hiện tại.
#  Hãy sao lưu: generate_keys -x <file>  (rồi cất file đó ở nơi an toàn, xóa bản trên máy).
# ─────────────────────────────────────────────────────────────
set -euo pipefail
cd "$(dirname "$0")/.."
source config/release.env

if [[ "$GITHUB_REPO" == __* ]]; then
    echo "❌ Sửa GITHUB_REPO trong config/release.env trước (vd. uri/MacHub)."
    exit 1
fi

echo "📦 Resolve Swift packages để lấy công cụ Sparkle..."
swift package resolve >/dev/null
swift build -c release --product MacHub >/dev/null 2>&1 || true
BIN=".build/artifacts/sparkle/Sparkle/bin"
if [ ! -x "$BIN/generate_keys" ]; then
    echo "❌ Không tìm thấy $BIN/generate_keys"
    exit 1
fi

# generate_keys không tạo khóa mới nếu Keychain đã có; chỉ in khóa công khai hiện có.
"$BIN/generate_keys" --account machub >/dev/null
PUB="$("$BIN/generate_keys" --account machub -p | tr -d '[:space:]')"
if [ -z "$PUB" ]; then
    echo "❌ Không đọc được khóa công khai."
    exit 1
fi
printf '%s\n' "$PUB" > config/sparkle_public_ed_key
echo "✅ Đã ghi khóa công khai vào config/sparkle_public_ed_key: $PUB"

if command -v gh >/dev/null 2>&1; then
    read -r -p "Đưa private key lên secret MACHUB_SPARKLE_ED_PRIVATE_KEY của ${GITHUB_REPO}? [y/N] " ans
    if [[ "$ans" == [yY] ]]; then
        umask 077
        # generate_keys -x từ chối ghi đè file có sẵn → xuất vào thư mục tạm riêng (0700).
        TMPDIR_KEY="$(mktemp -d)"
        trap 'rm -rf "$TMPDIR_KEY"' EXIT
        "$BIN/generate_keys" --account machub -x "$TMPDIR_KEY/key" >/dev/null
        gh secret set MACHUB_SPARKLE_ED_PRIVATE_KEY --repo "$GITHUB_REPO" < "$TMPDIR_KEY/key"
        rm -rf "$TMPDIR_KEY"
        echo "✅ Đã cập nhật secret."
    fi
else
    echo "ℹ️  Chưa có gh CLI. Tự xuất key: $BIN/generate_keys --account machub -x key.txt"
    echo "   rồi dán nội dung vào Settings → Secrets → Actions → MACHUB_SPARKLE_ED_PRIVATE_KEY, sau đó xóa key.txt."
fi

echo ""
echo "Tiếp theo: commit config/sparkle_public_ed_key, rồi ./build.sh để build bản có tự cập nhật."
