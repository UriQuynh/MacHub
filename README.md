# MacHub — Bộ tiện ích tất-cả-trong-một cho Mac và Windows

[![Release](https://img.shields.io/github/v/release/UriQuynh/MacHub?include_prereleases&label=b%E1%BA%A3n%20m%E1%BB%9Bi%20nh%E1%BA%A5t)](https://github.com/UriQuynh/MacHub/releases)
[![CI](https://github.com/UriQuynh/MacHub/actions/workflows/ci.yml/badge.svg)](https://github.com/UriQuynh/MacHub/actions/workflows/ci.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Windows%2010%2F11-black.svg)](#-t%E1%BA%A3i-v%E1%BB%81)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> **MacHub** là bản fork của [**HyperMac**](https://github.com/mrgoose000000-gif/HyperMac) (© 2026 Nguyễn Khắc Đại, GPLv3).
> Ứng dụng menu bar viết bằng Swift thuần, gom nhiều tiện ích vào một chỗ: chia cửa sổ, AltTab, cắt/dán trong Finder,
> lịch sử clipboard, khóa sạc pin & điều khiển quạt qua SMC, nhiệt độ, dọn rác & gỡ app, màn hình ảo, chụp & chú thích màn hình.
>
> Hướng phát triển: giao diện **notch** (dạng pill trên màn không có notch), lõi chuyển cửa sổ từ
> [alt-tab-macos](https://github.com/lwouis/alt-tab-macos), và studio quay màn hình dựa trên [Recordly](https://github.com/webadderallorg/recordly).

---

## 📥 Tải về

| Phiên bản | Tải về | Yêu cầu |
|---|---|---|
| 🍎 **macOS** | [**MacHub.dmg**](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub.dmg) · [MacHub.zip](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub.zip) | macOS 14+, Apple Silicon (M1–M5) |
| 🪟 **Windows** | [**MacHub-Windows-Setup.exe**](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub-Windows-Setup.exe) | Windows 10/11 x64 (WebView2, có sẵn trên Windows 11) |
| 🧩 **Extension trình duyệt** (MacHub Responsive) | [**MacHub-Responsive-Extension.zip**](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub-Responsive-Extension.zip) | Chrome, Edge, Brave, Arc (Chromium ≥ 116) |

Các link trên luôn trỏ tới **bản phát hành mới nhất**. Mọi phiên bản cũ, ghi chú thay đổi và mã SHA-256
(file `.sha256` đi kèm) nằm ở trang [**Releases**](https://github.com/UriQuynh/MacHub/releases).

### 🗂️ Tải theo từng phiên bản

Link cố định theo phiên bản (không đổi khi có bản mới). Mẫu chung:
`https://github.com/UriQuynh/MacHub/releases/download/v<phiên-bản>/<tên-file>`.

| Phiên bản | Ngày | macOS | Windows | Extension | Ghi chú |
|---|---|---|---|---|---|
| **v0.1.2** (mới nhất) | 2026-11-20 | [.dmg](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub.dmg) · [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub.zip) | [Setup.exe](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub-Windows-Setup.exe) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub-Windows-Setup.exe.sha256) | [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub-Responsive-Extension.zip) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.2/MacHub-Responsive-Extension.zip.sha256) | [Release v0.1.2](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.2) |
| **v0.1.1** | 2026-11-19 | [.dmg](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub.dmg) · [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub.zip) | [Setup.exe](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub-Windows-Setup.exe) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub-Windows-Setup.exe.sha256) | [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub-Responsive-Extension.zip) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.1/MacHub-Responsive-Extension.zip.sha256) | [Release v0.1.1](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.1) |
| **v0.1.0** | 2026-11-19 | [.dmg](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub.dmg) · [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub.zip) | [Setup.exe](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub-Windows-Setup.exe) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub-Windows-Setup.exe.sha256) | [.zip](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub-Responsive-Extension.zip) · [SHA-256](https://github.com/UriQuynh/MacHub/releases/download/v0.1.0/MacHub-Responsive-Extension.zip.sha256) | [Release v0.1.0](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.0) |

Mỗi lần phát hành bản mới, thêm một dòng lên đầu bảng. Link macOS có dạng
`.../download/v<phiên-bản>/MacHub.dmg` và `.../MacHub.zip`.

**Kiểm tra toàn vẹn** (so với file `.sha256` cùng bản):

```bash
shasum -a 256 MacHub-Responsive-Extension.zip      # macOS / Linux
Get-FileHash .\MacHub-Windows-Setup.exe             # Windows (PowerShell)
```

### 🍎 macOS

1. Mở `MacHub.dmg`, kéo `MacHub.app` vào **Applications** (hoặc giải nén `MacHub.zip`).
2. MacHub ký bằng chứng chỉ tự ký (chưa notarize), nên lần đầu macOS sẽ chặn. Mở
   **System Settings → Privacy & Security**, bấm **Open Anyway** ở mục MacHub. Không cần dùng `xattr -cr`.
3. Mở MacHub, bấm vào thẻ **Cấp quyền phần mềm** ở tab Màn hình để cấp quyền. **Bắt buộc cấp cả 2 quyền** để Alt-Tab và phím tắt chạy đủ:

   | Quyền | Dùng để | Thiếu thì |
   |---|---|---|
   | **Trợ năng** (Accessibility) | Bắt phím tắt toàn cục, điều khiển / đóng / đưa cửa sổ lên trước | Phím tắt và Alt-Tab không hoạt động |
   | **Ghi màn hình** (Screen Recording) | Đọc tiêu đề và ảnh xem trước của cửa sổ trong Alt-Tab, kể cả cửa sổ ở Space khác | Alt-Tab thiếu cửa sổ hoặc không có tiêu đề / ảnh xem trước |

   Sau khi cấp **Ghi màn hình**, hãy **thoát và mở lại MacHub** để quyền có hiệu lực. Bluetooth chỉ cần khi dùng tính năng liên quan.

Sau lần đầu, các bản mới tự đến qua **Sparkle** (có kiểm chữ ký), không cần tải lại.

### 🪟 Windows

1. Chạy `MacHub-Windows-Setup.exe` — cài cho tài khoản hiện tại, không cần quyền Administrator.
2. Bộ cài chưa ký số nên **SmartScreen** có thể cảnh báo: bấm **More info → Run anyway**.
   Có thể đối chiếu mã trong `MacHub-Windows-Setup.exe.sha256` bằng `Get-FileHash .\MacHub-Windows-Setup.exe`.
3. MacHub nằm ở khay hệ thống (góc phải thanh taskbar). Bấm icon hoặc `Ctrl+Alt+M` để mở.
   Chi tiết tính năng và phím tắt: [`windows/README.md`](windows/README.md).

Bản Windows chưa tự cập nhật: tải lại bộ cài mới và chạy đè lên bản cũ.

### 🧩 Extension MacHub Responsive

Xem một trang web ở kích thước **mobile / tablet / desktop cùng lúc**, thay cho DevTools (F12).

1. Giải nén `MacHub-Responsive-Extension.zip` vào một thư mục cố định (đừng xóa sau khi cài).
2. Mở `chrome://extensions` (Edge: `edge://extensions`), bật **Developer mode**.
3. Bấm **Load unpacked**, chọn thư mục vừa giải nén, rồi ghim extension lên thanh công cụ.
4. Đang ở trang cần xem → bấm icon extension hoặc **Alt+Shift+R**.

Hướng dẫn đầy đủ: [`extensions/responsive/README.md`](extensions/responsive/README.md).

---

## 🔒 Bảo mật & quyền riêng tư

- **Cập nhật có chữ ký:** Sparkle kiểm chữ ký EdDSA của gói và chữ ký code của app mới trước khi cài.
- **Helper root tối thiểu:** khóa sạc/quạt chạy qua `/Library/PrivilegedHelperTools/com.machub.app.power`; rule sudoers chỉ cho đúng user cài và đúng file đó; helper tự kiểm tra mọi tham số.
- **`smc` build từ mã nguồn** trong `Vendor/smc-command` (smcFanControl, GPLv2+), không dùng binary dựng sẵn.
- **Clipboard mã hóa trên đĩa** (AES-256-GCM, khóa trong Keychain); bỏ qua nội dung đánh dấu ẩn như mật khẩu.
- **Không telemetry.** Kết nối mạng: kiểm tra bản cập nhật trên GitHub, và (chỉ khi bạn bật) đọc hạn mức Claude qua OAuth.
- Log ở `~/Library/Logs/MacHub/machub.log`.

---

## 🤖 Theo dõi agent (Claude Code & Codex)

Tab **Agent** trong bảng MacHub:
- **Phiên**: phiên đang chạy / xong / subagent xong / chờ duyệt, kèm repo, nhánh, model, prompt gần nhất.
- **Hạn mức**: 5H, 7D (và 7D theo model nếu bật OAuth) của Claude; 5H/7D của Codex, có giờ reset.
- **Token & Chi phí**: hôm nay / 7 ngày / 30 ngày, theo model và dự án. Chi phí là **ước tính theo giá API**.
- **Duyệt quyền**: khi Claude Code xin chạy lệnh, một bảng nhỏ hiện góc màn hình với *Cho phép / Luôn cho phép / Từ chối / Hỏi trong terminal*.
  Không trả lời kịp → Claude Code hỏi trong terminal như bình thường. MacHub không bao giờ tự cho phép.

Cài đặt: tab Agent → ⚙ → **Cài hook** (sửa `~/.claude/settings.json`, có sao lưu, gỡ được). Codex được đọc tự động từ `~/.codex/sessions`.

## 🎮 BẢNG HƯỚNG DẪN SỬ DỤNG & PHÍM TẮT

MacHub nằm gọn gàng trên thanh Menu Bar góc trên bên phải (biểu tượng `⌘`). Dưới đây là phím tắt của các tính năng:

### ✂️ 1. Cắt & Dán Tệp Trong Finder (Giống Ctrl+X ➔ Ctrl+V trên Windows)
Mang cơ chế Cut & Paste quen thuộc từ Windows lên Finder của macOS:
* **Cắt tệp / thư mục:** Chọn tệp trong Finder và bấm **`⌘ Command + X`**.
  * MacHub sẽ nhận diện và đưa tệp vào trạng thái Cắt, hiển thị thông báo nổi (HUD Toast): `✂️ Đã cắt: [Tên tệp] • Bấm ⌘V để di chuyển • Esc để hủy` kèm âm thanh phản hồi nhẹ.
* **Dán / Di chuyển tệp:** Di chuyển tới thư mục đích và bấm **`⌘ Command + V`**.
  * Tệp sẽ được di chuyển tức thì (*Move Item Here*) vào thư mục mới thay vì phải bấm tổ hợp `⌥ Option + ⌘ Command + V` khó nhớ của macOS.
* **Hủy lệnh cắt:** Bấm phím **`Esc`** hoặc bấm **`⌘ Command + C`** (chuyển sang sao chép bình thường).
* **Thông minh khi đổi tên:** Tự động phát hiện khi bạn đang đổi tên tệp (*rename*) hoặc gõ tìm kiếm để giữ nguyên chức năng cắt văn bản bình thường.

---

### 🪟 2. Chia Cửa Sổ (Thay thế Rectangle)
Điều khiển cửa sổ siêu tốc độ trễ 0ms, tự động căn chuẩn tỷ lệ khi chuyển màn hình:

| Thao tác | Phím tắt mặc định | Mô tả |
| :--- | :--- | :--- |
| **Nửa trên** | `⌃ Control + ⌥ Option + ↑` | Cửa sổ chiếm 50% bên trên |
| **Nửa dưới** | `⌃ Control + ⌥ Option + ↓` | Cửa sổ chiếm 50% bên dưới |
| **Nửa trái** | `⌃ Control + ⌥ Option + ←` | Cửa sổ chiếm 50% bên trái |
| **Nửa phải** | `⌃ Control + ⌥ Option + →` | Cửa sổ chiếm 50% bên phải |
| **Toàn màn hình** | `⌃ Control + ⌥ Option + ↵ Return` | Phóng to cửa sổ đầy màn hình |
| **Căn giữa** | `⌃ Control + ⌥ Option + ⌫ Delete` | Thu cửa sổ về chính giữa màn hình |
| **Chia 4 góc màn hình** | `⌃⌥ + ←↑ / →↑ / ←↓ / →↓`<br>hoặc `⌃⌥ + U / I / J / K`<br>hoặc Numpad `7 / 9 / 1 / 3` | Bố trí cửa sổ vào 1/4 góc màn hình |
| **Sang màn hình khác** | `⌥ Option + ⌘ Command + → / ←` | Di chuyển cửa sổ qua màn hình phụ/chính (scale chuẩn tỷ lệ) |

---

### 🔀 3. Chuyển Đổi Cửa Sổ Trực Quan (Thay thế AltTab)
Trình chuyển đổi cửa sổ dạng xem trước trực quan (Thumbnail Live Preview) cực xịn:
* **Mở trình chuyển đổi:** Nhấn giữ **`⌘ Command + Tab`** (hoặc `⌥ Option + Tab`).
* **Lưới đa hàng thích ứng (Adaptive Grid):** Tự động dàn thành nhiều hàng cân đối, hình ảnh xem trước kích thước lớn (260x188pt), sắc nét và rõ ràng.
* **Điều hướng 4 chiều:** Bấm các phím mũi tên **`↑ ↓ ← →`** để duyệt giữa các hàng và cột; bấm `Tab` để sang ô tiếp theo, `~` để lùi lại.
* **Lọc theo màn hình hiện tại (Multi-Monitor):** Tùy chọn chỉ hiển thị các cửa sổ đang nằm trên màn hình mà con trỏ chuột đang đứng (`[ 🖥️ Màn hình này ]`).
* **Chuẩn MRU:** Đảo nhanh giữa 2 cửa sổ gần nhất chỉ bằng 1 cú nhấp thả.
* **Thao tác nhanh:**
  * Bấm phím **`W`**: Đóng nhanh cửa sổ đang chọn.
  * Bấm phím **`Q`**: Thoát hẳn ứng dụng đó (`Quit`).
  * Bấm phím **`Esc`**: Hủy chuyển đổi.

---

### 📋 4. Lịch Sử Clipboard (Thay thế Maccy)
Lưu trữ lịch sử văn bản, hình ảnh, liên kết, mã màu đã sao chép:
* **Mở Clipboard:** Bấm **`⌘ Command + ⇧ Shift + C`** (hoặc `⌘ + ⇧ + V`).
* **Dán siêu tốc:** Bấm phím số **`1` đến `9`** để dán tức thì dòng tương ứng vào văn bản mà không cần click chuột.
* **Thao tác nhanh:**
  * Bấm **`↵ Enter`**: Dán mục đang chọn.
  * Bấm **`⌥ Option + P`**: Ghim / Bỏ ghim mục quan trọng lên đầu.
  * Bấm **`⌥ Option + ⌫ Delete`**: Xóa mục khỏi lịch sử.
  * Gõ chữ để tìm kiếm nhanh nội dung trong lịch sử.
* **Bảo mật:** Tự động phát hiện và bỏ qua mật khẩu từ Keychain, 1Password, Bitwarden...

---

### 🔋 5. Khóa Sạc Pin 80% & Sleep Guard (Thay thế AlDente Pro)
Bảo vệ phần cứng tối đa, đặc biệt phù hợp cho các dòng MacBook cắm sạc liên tục:
* **Khóa sạc ở 80% (SMC AC Bypass):** Ghi trực tiếp vào chip điều khiển nguồn Apple Silicon, ngắt dòng điện vào cell pin khi đạt 80%. Máy chuyển sang chạy điện củ sạc 100%, triệt tiêu nguy cơ phồng pin, chai pin.
* **Nút Sạc Đầy (Top-Up 100%):** Bấm nút sạc đầy tạm thời khi chuẩn bị mang máy ra ngoài.
* **Sleep Guard:** Tự động duy trì lệnh ngắt sạc khi gập máy và tự tắt Bluetooth để chống tụt pin qua đêm (0% hao hụt pin).

---

### 🖥️ 6. Màn Hình Ngoài & Chỉnh Độ Sáng (Thay thế BetterDisplay)
* **Chỉnh sáng màn hình ngoài bằng `F1 / F2`:** Bấm phím F1/F2 trên bàn phím Mac để tăng/giảm độ sáng màn hình rời thông qua chuẩn phần cứng DDC/CI.
* **Ngắt mềm màn ngoài (Software Sleep):** Tắt tạm thời tín hiệu màn ngoài khi không dùng mà không cần rút dây cáp Type-C/HDMI.

---

### ☕ 7. Chống Ngủ Màn Hình (Thay thế Amphetamine)
* Nhấp vào biểu tượng ly cafe trên menu MacHub để giữ màn hình luôn sáng khi đang render video, tải file nặng hoặc thuyết trình (`15 phút`, `30 phút`, `1 giờ`, `Vô hạn`).

---

### 🖱️ 8. Mẹo Chuột: Mở Mission Control Siêu Nhanh
* Nhấp đồng thời **Chuột Trái + Chuột Phải** (hoặc nhấn giữ chuột trái rồi click chuột phải) $\rightarrow$ MacHub sẽ lập tức mở **Mission Control** mà không cần với tay lên bàn phím!

---

### 🧹 9. Dọn Dẹp Rác Hệ Thống & Gỡ Cài Đặt Ứng Dụng (Thay thế CleanMyMac & AppCleaner)
Tích hợp trực tiếp tại tab **Dọn dẹp** trên thanh điều khiển của MacHub, chia thành 3 phân vùng chuyên sâu:
* **✨ Dọn rác hệ thống (System Junk Cleaner):**
  * Tự động quét song song đa luồng toàn bộ Bộ nhớ đệm (`~/Library/Caches`), Nhật ký lỗi (`~/Library/Logs`), Thùng rác (`~/.Trash`), và Dữ liệu rác Xcode (`DerivedData`).
  * Sử dụng giải thuật C-level `du` đo đếm dung lượng siêu tốc, giải phóng hàng chục GB dung lượng SSD chỉ trong vài giây.
  * Tích hợp dọn sạch Thùng rác qua cầu nối Finder AppleScript chuẩn xác, an toàn, không lo bị chặn quyền macOS.
* **📦 Gỡ bỏ ứng dụng tận gốc (Smart App Uninstaller):**
  * Liệt kê toàn bộ ứng dụng cài đặt trong `/Applications` sắp xếp theo dung lượng thực tế.
  * Tự động truy quét và bóc tách mọi tệp tàn dư (*leftovers*) rải rác trong `Application Support` (kể cả thư mục lồng sâu 2 cấp của Google, Microsoft, Adobe...), `Caches`, `Preferences`, `Saved Application State`, `Containers`, `Group Containers`, `WebKit Data`, `HTTPStorages`.
  * Cơ chế Thùng rác an toàn: Chuyển toàn bộ ứng dụng và tệp rác vào Thùng rác (`~/.Trash`) thay vì xóa vĩnh viễn (`rm -rf`), người dùng có thể khôi phục lại bất kỳ lúc nào nếu đổi ý.
  * Tự động Fallback Finder: Nếu ứng dụng thuộc quyền sở hữu quản trị `root:wheel` (như OneDrive, Microsoft Office), app tự động ủy quyền qua Finder để gỡ bỏ thành công mà không báo lỗi.
* **📂 Dò tìm tệp lớn & tệp cũ (Large Files Finder):**
  * Tùy chọn lọc kích thước: `≥ 100MB`, `≥ 200MB`, `≥ 500MB`, `≥ 1GB` trong các thư mục dung lượng lớn (`Downloads`, `Movies`, `Documents`).
  * Xem nhanh vị trí tệp trong Finder hoặc dọn ngay vào Thùng rác với một chạm.

---

### 📊 10. Trình Quản Lý Tác Vụ (Giống Task Manager của Windows)

Mở bằng **⌃⇧Esc** (đổi được trong tab Phím tắt) hoặc nút đồng hồ ở thanh trên cùng của MacHub. Cửa sổ chỉ lấy số liệu khi đang mở nên không tốn CPU lúc rảnh.

- **Tiến trình**: gom theo ứng dụng (Chrome, VS Code... gồm cả tiến trình phụ), tách "Ứng dụng" và "Tiến trình nền"; cột CPU, Bộ nhớ, Đĩa, Năng lượng tô màu theo mức dùng; bấm tiêu đề cột để sắp xếp, ô tìm kiếm lọc theo tên, PID hoặc đường dẫn.
- **Hiệu năng**: đồ thị 60 giây cho CPU (kèm từng nhân), Bộ nhớ (wired, nén, swap), Đĩa, Mạng, GPU.
- **Chi tiết**: danh sách phẳng có PID, trạng thái, người dùng, số luồng, đường dẫn.
- **Kết thúc tác vụ** (có hỏi xác nhận), **Buộc dừng**, **Tạm dừng / Tiếp tục**, đổi độ ưu tiên (nice), mở vị trí trong Finder, sao chép đường dẫn. Tiến trình hệ thống quan trọng (`launchd`, `WindowServer`, `loginwindow`...) và chính MacHub bị chặn; tiến trình của root hoặc người dùng khác cần quyền quản trị nên không dừng được từ đây.
- Không cần cấp thêm quyền nào. Chưa có: Khởi động cùng máy, Dịch vụ, Lịch sử ứng dụng, dòng lệnh đầy đủ của tiến trình.

---

## ❓ CÂU HỎI THƯỜNG GẶP (FAQ)

<details>
<summary><b>1. Máy Mac chip Intel ("Chip I") có dùng được MacHub không?</b></summary>

> **Không hỗ trợ.** MacHub được tối ưu chuyên sâu và chỉ hỗ trợ các dòng máy Mac chạy chip **Apple Silicon** (M1, M2, M3, M4...). Do ứng dụng khai thác trực tiếp tập lệnh kiến trúc ARM64, quản lý bypass sạc qua Apple Silicon SMC và đọc cảm biến nhiệt độ phần cứng đặc thù của dòng chip M, nên không thể chạy trên các đời máy Mac cũ dùng chip Intel.
</details>

<details>
<summary><b>2. Dùng bàn phím cơ ngoài (Aula, Keychron, RK...) bấm F3 lại bị chuyển tab?</b></summary>

> Hiện tượng này là do firmware của bàn phím cơ ngoài ở chế độ Windows tự động phát macro `Cmd+Tab` khi bấm F3.
> 
> **Cách xử lý:**
> - Bấm **`Fn + F3`** để gửi tín hiệu F3 nguyên bản.
> - Hoặc dùng phím tắt chuẩn macOS: **`Control + Mũi tên lên (⌃ + ↑)`** để mở Mission Control.
> - Hoặc click đồng thời **Chuột Trái + Chuột Phải** để mở Mission Control bằng chuột.
> </details>

<details>
<summary><b>3. Làm thế nào để MacHub tự động chạy khi mở máy Mac?</b></summary>

> Bạn chỉ cần mở bảng điều khiển MacHub từ thanh Menu Bar ➔ chuyển sang tab **Phím tắt & Cửa sổ** ➔ Gạt bật mục **"Khởi động cùng macOS"**.
> 
> MacHub sử dụng dịch vụ nền `SMAppService` chính thức của Apple (hỗ trợ macOS 13, 14, 15+) kèm cơ chế dự phòng `System Events`, tự động kích hoạt ngay khi bạn đăng nhập vào máy mà không cần cấu hình thủ công.
</details>

<details>
<summary><b>4. Cập nhật phiên bản mới như thế nào?</b></summary>

> MacHub tự kiểm tra mỗi ngày qua Sparkle. Bấm nút **"Cập nhật"** ở chân trang để kiểm tra ngay. Bản cập nhật chỉ được cài khi chữ ký EdDSA và chữ ký code đều khớp bản đang chạy.
</details>

<details>
<summary><b>5. Cập nhật xong thì mất quyền Trợ năng / phím tắt không chạy?</b></summary>

> Đây là di chứng của kiểu ký **ad-hoc**: mỗi bản build có "danh tính" (cdhash) khác nhau nên macOS coi là app mới và vô hiệu hoá quyền cũ.
>
> MacHub luôn được ký bằng **chứng chỉ cố định** `MacHub Self-Signed` và tự khôi phục quyền Trợ năng sau mỗi lần cập nhật.
</details>

<details>
<summary><b>6. Alt-Tab không hiện hoặc thiếu cửa sổ?</b></summary>

> Kiểm tra **System Settings → Privacy & Security** xem MacHub đã bật cả **Trợ năng** lẫn **Ghi màn hình** chưa. Thiếu Trợ năng thì phím tắt không chạy; thiếu Ghi màn hình thì Alt-Tab không thấy đủ cửa sổ (nhất là cửa sổ ở Space khác hoặc Stage Manager).
>
> Sau khi cấp **Ghi màn hình**, hãy thoát và mở lại MacHub. Nếu đang chạy app Alt-Tab khác (ví dụ AltTab), hãy tắt đi để hai app không tranh phím tắt.
</details>

---

## 🪟 Bản Windows

Thư mục [`windows/`](windows/README.md) chứa MacHub cho Windows 10/11 (Tauri 2: Rust + React), gồm 4 tab:

| Tab | Tính năng |
|---|---|
| **Agent** | Phiên Claude Code / Codex, hạn mức 5 giờ & 7 ngày, token & chi phí, duyệt quyền công cụ từ cửa sổ nổi |
| **Clipboard** | Lịch sử văn bản mã hóa DPAPI, tìm, ghim, `Ctrl+Shift+V` dán nhanh |
| **Cửa sổ & Màn hình** | Chia cửa sổ `Ctrl+Alt+←/→/↑/↓…`, độ sáng màn hình ngoài qua DDC/CI |
| **Dọn dẹp & Hệ thống** | CPU, RAM, ổ đĩa, mạng, tiến trình; dọn file tạm và cache an toàn |

Tải bộ cài: [MacHub-Windows-Setup.exe](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub-Windows-Setup.exe).

## 🧩 Extension MacHub Responsive

Extension Chrome/Edge trong [`extensions/responsive/`](extensions/responsive/README.md): mở một trang ở nhiều khung thiết bị
cùng lúc (iPhone, Pixel, iPad, laptop, desktop, kích thước tự chọn), đồng bộ cuộn và điều hướng, xoay khung, chụp ảnh toàn bộ.
Tải về: [MacHub-Responsive-Extension.zip](https://github.com/UriQuynh/MacHub/releases/latest/download/MacHub-Responsive-Extension.zip).

## 🛠️ Tự build từ mã nguồn

Yêu cầu: macOS 14+, Xcode Command Line Tools (Swift 5.9+, clang).

```bash
git clone https://github.com/UriQuynh/MacHub.git
cd MacHub
./scripts/setup-signing-identity.sh   # một lần: chứng chỉ ký cố định để không mất quyền Trợ năng
./build.sh                            # build + cài /Applications + mở app
./build.sh --no-run                   # chỉ đóng gói vào build/
```

Bản tự build chưa có khóa Sparkle sẽ tắt tự cập nhật. Người phát hành xem `AGENTS.md` mục 3.

Bản Windows và extension: xem [`windows/README.md`](windows/README.md) và [`extensions/responsive/README.md`](extensions/responsive/README.md).

### Phát hành

**Thiết lập một lần** trên Mac của người phát hành (cần để có `MacHub.dmg` và tự cập nhật qua Sparkle):

```bash
./scripts/setup-signing-identity.sh   # tạo chứng chỉ ký cố định "MacHub Self-Signed" trong ~/.machub-signing
./scripts/export-ci-signing.sh        # xuất .p12 + base64, in mật khẩu; rồi thêm 2 secret vào repo (bên dưới)
./scripts/setup-sparkle-keys.sh       # tạo khóa Sparkle, ghi khóa công khai vào config/sparkle_public_ed_key
                                      # và đặt secret MACHUB_SPARKLE_ED_PRIVATE_KEY qua gh
```

Hai secret cho chứng chỉ ký (đặt bằng `gh` để khỏi dán sai):

```bash
gh secret set MACHUB_SIGNING_P12_BASE64 --repo UriQuynh/MacHub < ~/.machub-signing/ci-signing.p12.base64
gh secret set MACHUB_SIGNING_P12_PASSWORD --repo UriQuynh/MacHub   # dán mật khẩu mà export-ci-signing.sh in ra
```

Sau `setup-sparkle-keys.sh`, commit `config/sparkle_public_ed_key`. Đủ 3 secret `MACHUB_SIGNING_P12_BASE64`,
`MACHUB_SIGNING_P12_PASSWORD`, `MACHUB_SPARKLE_ED_PRIVATE_KEY` thì CI mới phát hành được bản macOS. Không commit
file `.p12`/`.base64`/khóa riêng, và đừng tạo lại chứng chỉ (đổi root hash sẽ làm người dùng mất quyền Trợ năng).
Chi tiết và các lỗi đã gặp: `AGENTS.md` mục 3 và Phụ lục A7.

**Mỗi lần phát hành:** sửa `VERSION` (và version trong `windows/src-tauri/tauri.conf.json`, `windows/package.json`,
`extensions/responsive/manifest.json` cho khớp), merge vào `main`, rồi đẩy tag `v<VERSION>`. CI tự tạo Release:
- `release.yml` → `MacHub.dmg`, `MacHub.zip`, `appcast.xml` (cần chứng chỉ ký + khóa Sparkle, xem `AGENTS.md` mục 3);
- `release-assets.yml` → `MacHub-Windows-Setup.exe`, `MacHub-Responsive-Extension.zip` kèm `.sha256`.

---

## 📝 Nhật ký thay đổi

### [Chưa phát hành]
- Thêm **Trình quản lý tác vụ** (⌃⇧Esc): danh sách tiến trình gom theo ứng dụng, đồ thị hiệu năng CPU/RAM/đĩa/mạng/GPU, kết thúc / buộc dừng / tạm dừng tiến trình, đổi độ ưu tiên.

### [0.1.2] — 2026-11-20 ([tải về](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.2))
- Hết hỏi mật khẩu Keychain liên tục khi bật đọc hạn mức Claude: token Claude Code được đọc qua `/usr/bin/security`, cache trong bộ nhớ đến khi hết hạn, chặn gọi chồng; từ chối thì nghỉ 6 giờ.

### [0.1.1] — 2026-11-19 ([tải về](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.1))
- Alt-Tab hiện cửa sổ của mọi app ở mọi Space (trước đây chỉ Space hiện tại) và không còn loại nhầm cửa sổ ở dải Stage Manager. Phím `W` chưa đóng được cửa sổ ở Space khác.
- macOS cần cả quyền **Trợ năng** và **Ghi màn hình**; sau khi cấp Ghi màn hình hãy mở lại MacHub.

### [0.1.0] — 2026-11-19: tách khỏi HyperMac v1.9.8 ([tải về](https://github.com/UriQuynh/MacHub/releases/tag/v0.1.0))
Bản này có macOS (Apple Silicon, ký bằng chứng chỉ cố định + Sparkle), Windows và extension.

Những thay đổi so với HyperMac v1.9.8 (commit `c01fdd8`), theo yêu cầu ghi chú chỉnh sửa của GPLv3:
- Đổi tên thành MacHub (bundle ID `com.machub.app`, đường dẫn helper, chứng chỉ ký).
- Bỏ màn hình kích hoạt qua nhóm Zalo và phần Donate/QR của tác giả gốc; chân trang dẫn về dự án HyperMac.
- Thay bộ cập nhật tự viết bằng Sparkle 2 (chữ ký EdDSA, appcast do CI ký).
- Gỡ binary `smc` dựng sẵn; build từ `Vendor/smc-command`.
- Mã hóa lịch sử & ảnh clipboard; log chuyển khỏi `/tmp`.
- Tách `Views.swift` thành các file trong `Sources/UI/`.
- CI: bắt buộc ký bằng chứng chỉ cố định, kiểm tra tag khớp `VERSION`, pin action theo commit.
- **Theo dõi agent** (tab Agent trong popover): phiên Claude Code qua hook, Codex qua log, hạn mức 5 giờ/7 ngày,
  token & chi phí, duyệt quyền công cụ (không bao giờ tự cho phép).
- **Bản Windows** (Tauri 2): agent, clipboard DPAPI, chia cửa sổ + DDC/CI, dọn rác + theo dõi hệ thống.
- **Extension MacHub Responsive** cho Chrome/Edge.
- CI: unit test + E2E trên macOS, Windows và extension; bắt buộc check `test` trước khi merge vào `main`.

Lịch sử phiên bản trước đó: xem [HyperMac](https://github.com/mrgoose000000-gif/HyperMac) và `git log`.

---

## 👤 Bản quyền

- **MacHub** — chỉnh sửa © 2026 MacHub contributors.
- Dựa trên **HyperMac** — © 2026 **Nguyễn Khắc Đại** ([@khacdai24](https://github.com/khacdai24)). Nếu thấy hữu ích, hãy ghé ủng hộ tác giả gốc tại repo HyperMac.
- Phát hành theo **[GNU GPLv3](LICENSE)**. Thành phần bên thứ ba và giấy phép riêng: xem [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
