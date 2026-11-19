# MacHub cho Windows

**Tải về:** [MacHub-Windows-Setup.exe](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub-Windows-Setup.exe)
(Windows 10/11 x64, cài cho tài khoản hiện tại). Bộ cài chưa ký số: SmartScreen → **More info → Run anyway**.

Bản Windows 10/11 của MacHub, viết bằng **Tauri 2 (Rust + React/TypeScript)**. App nằm ở khay hệ thống;
bấm icon (hoặc `Ctrl+Alt+M`) để mở bảng điều khiển nổi, mất focus thì tự ẩn như popover trên macOS.

| Tab | Tính năng |
|---|---|
| **Agent** | Phiên Claude Code (qua hook) và Codex (đọc log), hạn mức 5 giờ / 7 ngày, token và chi phí theo ngày/tuần/tháng, duyệt quyền công cụ từ cửa sổ nổi |
| **Clipboard** | Lịch sử văn bản đã chép, tìm kiếm, ghim, `Ctrl+Shift+V` để mở và dán nhanh (`↑↓`, `Enter`, `1–9`) |
| **Cửa sổ & Màn hình** | Chia cửa sổ bằng `Ctrl+Alt+…` (nửa, 1/3, 2/3, góc, giữa, sang màn kế); độ sáng màn ngoài qua DDC/CI |
| **Dọn dẹp & Hệ thống** | CPU, RAM, ổ đĩa, mạng, tiến trình nặng; dọn file tạm, thumbnail, crash dump, cache trình duyệt và công cụ lập trình |

## Bảo mật

- **Kênh hook:** named pipe `\\.\pipe\machub-agent-<user>`, DACL chỉ cho tài khoản hiện tại và SYSTEM,
  từ chối kết nối từ xa, `first_pipe_instance` (không chạy song song với tiến trình đã chiếm tên).
  Hook kiểm tra tiến trình server chạy dưới **cùng tài khoản** (so SID) rồi mới gửi dữ liệu hay nhận quyết định.
- **Duyệt quyền:** không bao giờ tự cho phép. Hết giờ, đóng cửa sổ hay app không chạy → Claude Code hỏi trong terminal
  như bình thường. Cửa sổ duyệt không có phím tắt "Cho phép" và không tự lấy focus.
- **Hook không bao giờ phá Claude Code:** luôn thoát mã 0, không in ra stderr, chỉ in JSON quyết định hợp lệ.
- **Cài hook:** sửa `~/.claude/settings.json` có sao lưu (`settings.json.machub-backup-<thời điểm>`), ghi qua file tạm rồi đổi tên,
  giữ nguyên hook của người khác; gỡ hook trả lại statusLine cũ.
- **OAuth (tùy chọn, mặc định tắt):** đọc token Claude Code ở `~/.claude/.credentials.json` để hỏi hạn mức; không làm mới token,
  không lưu token, 5 phút một lần. Endpoint không có tài liệu chính thức nên có thể đổi bất cứ lúc nào.
- **Clipboard:** lưu `%APPDATA%\MacHub\clipboard.bin` mã hóa DPAPI theo tài khoản Windows; mã hóa lỗi thì không ghi.
  Bỏ qua nội dung app nguồn đánh dấu riêng tư (`ExcludeClipboardContentFromMonitorProcessing`,
  `CanIncludeInClipboardHistory = 0`, `Clipboard Viewer Ignore`) — trình quản lý mật khẩu dùng các cờ này.
- **Dọn rác:** chỉ các thư mục đã liệt kê, chỉ file cũ hơn 1 giờ, không theo symlink/junction, bỏ qua file đang mở.
  Không đụng cookie, mật khẩu hay lịch sử trình duyệt.

## Phát triển

Cần Rust stable, Node 22 và WebView2 (có sẵn trên Windows 11).

```powershell
cd windows
npm ci
npm run tauri dev           # tự build hook rồi chạy app
cargo test --workspace      # unit test + test hook qua named pipe thật
npx tauri build --bundles nsis
```

Trên Linux/macOS vẫn kiểm tra được phần lõi: `cargo test -p machub-core -p machub-agent-hook`
(hook dùng socket Unix thay named pipe) và `cargo check --target x86_64-pc-windows-gnu` cho toàn bộ app.

Biến môi trường hữu ích khi kiểm thử: `MACHUB_AGENT_SUPPORT_DIR` (thư mục dữ liệu), `MACHUB_AGENT_PIPE` (tên pipe),
`CLAUDE_CONFIG_DIR` (thư mục cấu hình Claude Code).

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `crates/machub-core` | Lõi không phụ thuộc UI: đọc log Claude/Codex, hạn mức, giá, tổng hợp, cài hook, giao thức pipe |
| `crates/machub-agent-hook` | Chương trình Claude Code gọi qua hook/statusLine, chuyển sự kiện tới app |
| `src-tauri/src/agent.rs` | Server named pipe, trạng thái phiên, duyệt quyền, quét log, OAuth |
| `src-tauri/src/clipboard.rs` | Lắng nghe clipboard, lưu DPAPI |
| `src-tauri/src/winsnap.rs`, `displays.rs` | Chia cửa sổ (bù viền DWM), DDC/CI |
| `src-tauri/src/cleaner.rs`, `sysmon.rs` | Dọn rác an toàn, theo dõi hệ thống |
| `src/` | Giao diện React (4 tab + cửa sổ duyệt quyền) |

CI: `.github/workflows/windows.yml` chạy test trên `windows-latest`, build bộ cài NSIS, cài im lặng, mở app,
kiểm tra named pipe và gửi sự kiện thật qua hook đã cài.

## Giới hạn hiện tại

- Bộ cài chưa ký số (Windows SmartScreen sẽ cảnh báo lần đầu) và chưa có cập nhật tự động.
- Clipboard mới lưu văn bản (chưa có ảnh/file).
- Độ sáng màn hình laptop không chỉnh được ở đây (cần WMI); chỉ màn ngoài hỗ trợ DDC/CI.
- Chưa có AltTab thay thế và quay màn hình như bản macOS.

Giấy phép GPLv3, như MacHub.
