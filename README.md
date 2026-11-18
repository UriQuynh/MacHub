# MacHub — Bộ tiện ích tất-cả-trong-một cho Mac (Apple Silicon)

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-black.svg)](#)
[![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon%20(arm64)-brightgreen.svg)](#)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

> **MacHub** là bản fork của [**HyperMac**](https://github.com/mrgoose000000-gif/HyperMac) (© 2026 Nguyễn Khắc Đại, GPLv3).
> Ứng dụng menu bar viết bằng Swift thuần, gom nhiều tiện ích vào một chỗ: chia cửa sổ, AltTab, cắt/dán trong Finder,
> lịch sử clipboard, khóa sạc pin & điều khiển quạt qua SMC, nhiệt độ, dọn rác & gỡ app, màn hình ảo, chụp & chú thích màn hình.
>
> Hướng phát triển: giao diện **notch** (dạng pill trên màn không có notch), lõi chuyển cửa sổ từ
> [alt-tab-macos](https://github.com/lwouis/alt-tab-macos), và studio quay màn hình dựa trên [Recordly](https://github.com/webadderallorg/recordly).

---

## 📥 Cài đặt

1. Tải `MacHub.zip` (hoặc `.dmg`) ở trang **Releases** của repo này, giải nén và kéo `MacHub.app` vào **Applications**.
2. MacHub ký bằng chứng chỉ tự ký (chưa notarize), nên lần đầu macOS sẽ chặn. Mở
   **System Settings → Privacy & Security**, bấm **Open Anyway** ở mục MacHub. Không cần dùng `xattr -cr`.
3. Mở MacHub, bấm vào thẻ **Cấp quyền phần mềm** ở tab Màn hình để cấp Trợ năng, Ghi màn hình, Bluetooth khi cần.

Sau lần đầu, các bản mới tự đến qua **Sparkle** (có kiểm chữ ký), không cần tải lại.

---

## 🔒 Bảo mật & quyền riêng tư

- **Cập nhật có chữ ký:** Sparkle kiểm chữ ký EdDSA của gói và chữ ký code của app mới trước khi cài.
- **Helper root tối thiểu:** khóa sạc/quạt chạy qua `/Library/PrivilegedHelperTools/com.machub.app.power`; rule sudoers chỉ cho đúng user cài và đúng file đó; helper tự kiểm tra mọi tham số.
- **`smc` build từ mã nguồn** trong `Vendor/smc-command` (smcFanControl, GPLv2+), không dùng binary dựng sẵn.
- **Clipboard mã hóa trên đĩa** (AES-256-GCM, khóa trong Keychain); bỏ qua nội dung đánh dấu ẩn như mật khẩu.
- **Không telemetry.** Kết nối mạng duy nhất là kiểm tra bản cập nhật trên GitHub.
- Log ở `~/Library/Logs/MacHub/machub.log`.

---

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

---

## 🛠️ Tự build từ mã nguồn

Yêu cầu: macOS 14+, Xcode Command Line Tools (Swift 5.9+, clang).

```bash
git clone https://github.com/<owner>/MacHub.git
cd MacHub
./scripts/setup-signing-identity.sh   # một lần: chứng chỉ ký cố định để không mất quyền Trợ năng
./build.sh                            # build + cài /Applications + mở app
./build.sh --no-run                   # chỉ đóng gói vào build/
```

Bản tự build chưa có khóa Sparkle sẽ tắt tự cập nhật. Người phát hành xem `AGENTS.md` mục 3.

---

## 📝 Nhật ký thay đổi

### [0.1.0] — chưa phát hành (2026-11-19): tách khỏi HyperMac v1.9.8
Những thay đổi so với HyperMac v1.9.8 (commit `c01fdd8`), theo yêu cầu ghi chú chỉnh sửa của GPLv3:
- Đổi tên thành MacHub (bundle ID `com.machub.app`, đường dẫn helper, chứng chỉ ký).
- Bỏ màn hình kích hoạt qua nhóm Zalo và phần Donate/QR của tác giả gốc; chân trang dẫn về dự án HyperMac.
- Thay bộ cập nhật tự viết bằng Sparkle 2 (chữ ký EdDSA, appcast do CI ký).
- Gỡ binary `smc` dựng sẵn; build từ `Vendor/smc-command`.
- Mã hóa lịch sử & ảnh clipboard; log chuyển khỏi `/tmp`.
- Tách `Views.swift` thành các file trong `Sources/UI/`.
- CI: bắt buộc ký bằng chứng chỉ cố định, kiểm tra tag khớp `VERSION`, pin action theo commit.

Lịch sử phiên bản trước đó: xem [HyperMac](https://github.com/mrgoose000000-gif/HyperMac) và `git log`.

---

## 👤 Bản quyền

- **MacHub** — chỉnh sửa © 2026 MacHub contributors.
- Dựa trên **HyperMac** — © 2026 **Nguyễn Khắc Đại** ([@khacdai24](https://github.com/khacdai24)). Nếu thấy hữu ích, hãy ghé ủng hộ tác giả gốc tại repo HyperMac.
- Phát hành theo **[GNU GPLv3](LICENSE)**. Thành phần bên thứ ba và giấy phép riêng: xem [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
