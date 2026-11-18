# Chính sách bảo mật

MacHub chạy với quyền Trợ năng, Ghi màn hình và có helper chạy bằng root (khóa sạc, quạt),
nên lỗi bảo mật được ưu tiên xử lý trước mọi tính năng.

## Báo lỗi
Vui lòng **không** mở issue công khai. Dùng *Security → Report a vulnerability* (GitHub private
vulnerability reporting) của repo này, kèm phiên bản, macOS, các bước tái hiện và ảnh hưởng.

## Phạm vi đặc biệt quan tâm
- `Resources/machub-power`, `Resources/install-helper.sh`, rule `/etc/sudoers.d/machub_power`.
- Chuỗi cập nhật: `Sources/UpdateManager.swift`, `.github/workflows/release.yml`, appcast.
- Dữ liệu clipboard (`Sources/ClipboardManager.swift`, `Sources/SecureStore.swift`).
- Mọi chỗ gọi `shell()` với dữ liệu không phải hằng số.

## Khóa phát hành
- Chứng chỉ ký code `MacHub Self-Signed` và khóa EdDSA của Sparkle chỉ nằm ở máy người phát hành và trong
  GitHub Secrets. Nếu lộ: thu hồi secret, tạo khóa mới và phát hành bản chuyển khóa theo hướng dẫn của Sparkle
  (*key rotation*), đồng thời thông báo người dùng.
