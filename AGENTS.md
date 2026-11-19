# AGENTS.md — MacHub

> Tài liệu cho AI coding agent (Claude Code, Cursor, OpenCode…) đọc trước khi sửa dự án.
> MacHub là bản fork của **HyperMac** (Nguyễn Khắc Đại, GPLv3). Phụ lục A giữ lại ghi chú kỹ thuật
> kế thừa từ HyperMac (đã đổi tên định danh); số phiên bản trong đó là của HyperMac.

## 1. Tổng quan

- App menu bar thuần Swift cho macOS 14+ (Apple Silicon), SwiftPM + AppKit + SwiftUI, chạy ẩn Dock (`LSUIElement`).
- Bundle ID `com.machub.app`, module/target `MacHub`, chứng chỉ ký `MacHub Self-Signed`.
- Giấy phép: GPLv3. Mã lấy từ Recordly (AGPLv3) giữ AGPLv3; ghi nguồn trong `THIRD_PARTY_NOTICES.md`.
- Lộ trình: P0 bảo mật → P0.5 hạ tầng → P1 giao diện notch → P1.5 thay AltTab bằng lõi alt-tab-macos →
  P2 tiện ích (lịch, to-do, Claude Code, nhạc) → P3 clipboard nâng cao → P4 studio quay màn hình (Recordly) → P5.

## 2. Build & kiểm tra

```bash
swift build -c release        # chỉ biên dịch
./build.sh --no-run           # build + đóng gói build/MacHub.app, .zip, .dmg (không cài)
./build.sh                    # build + cài /Applications + mở lại (pkill MacHub trước)
swift test                    # unit test (Tests/ScreenshotAnnotationTests)
```

- Một nguồn cấu hình duy nhất: `VERSION` (số phiên bản), `config/release.env` (`GITHUB_REPO`, `BUNDLE_ID`),
  `config/sparkle_public_ed_key` (khóa công khai Sparkle). `build.sh` ghi chúng vào Info.plist.
- `smc` được **biên dịch từ `Vendor/smc-command`** trong `build.sh` (xem `Vendor/smc-command/SOURCE.md`).
  Không thêm lại binary dựng sẵn vào `Resources/`.
- Log runtime: `~/Library/Logs/MacHub/machub.log` (`appLog()` trong `Sources/Logger.swift`).

## 3. Cập nhật tự động (Sparkle)

- `Sources/UpdateManager.swift` bọc `SPUStandardUpdaterController` (Sparkle 2.10.1, pin `exact` trong `Package.swift`).
- Feed: `https://github.com/<GITHUB_REPO>/releases/latest/download/appcast.xml`, do CI tạo và ký.
- Bản build chưa có khóa (`__SPARKLE_PUBLIC_ED_KEY__`) hoặc chưa có `GITHUB_REPO` → `UpdateManager.updatesDisabled == true`.
- Thiết lập một lần trên máy phát hành: `./scripts/setup-sparkle-keys.sh` (private key ở Keychain + secret
  `MACHUB_SPARKLE_ED_PRIVATE_KEY`). Mất private key = không phát hành được bản cập nhật cho người dùng cũ.
- Phát hành: sửa `VERSION`, commit, tag `v<VERSION>` rồi push tag. CI từ chối tag không khớp `VERSION`,
  thiếu chứng chỉ ký hoặc thiếu khóa Sparkle. Tag có hậu tố (`v0.2.0-rc1`) → prerelease, không vào feed.
- Secrets cần có: `MACHUB_SIGNING_P12_BASE64`, `MACHUB_SIGNING_P12_PASSWORD`, `MACHUB_SPARKLE_ED_PRIVATE_KEY`.

## 4. Bản đồ mã nguồn

| Đường dẫn | Vai trò |
|---|---|
| `Sources/AppMain.swift` | Entry point, `AppDelegate`, status item, popover |
| `Sources/UI/` | UI SwiftUI, mỗi màn/thẻ một file (`MainView`, `HeaderBar`, `HardwareTabView`, `DisplaysTabView`, `ShortcutsTabView`, `BatteryCardView`, `ThermalAndFanCardView`, `FooterView`, `DisplayComponents`) |
| `Sources/WindowManager.swift`, `AltTabOverlayView.swift` | AltTab (sẽ thay bằng lõi alt-tab-macos ở P1.5) |
| `Sources/WindowSnapManager.swift`, `WindowFrameHistory.swift` | Chia cửa sổ, khôi phục khung |
| `Sources/KeyInterceptor.swift` | CGEventTap toàn cục cho phím tắt |
| `Sources/ClipboardManager.swift`, `ClipboardOverlayView.swift` | Lịch sử clipboard (lưu mã hóa) |
| `Sources/SecureStore.swift` | AES-256-GCM, khóa trong Keychain; dùng cho mọi dữ liệu nhạy cảm lưu đĩa |
| `Sources/BatteryManager.swift`, `FanManager.swift`, `ThermalManager.swift` | Khóa sạc, quạt, nhiệt độ |
| `Sources/PrivilegedHelper.swift`, `Resources/machub-power`, `Resources/install-helper.sh` | Helper root qua sudoers giới hạn |
| `Sources/DisplayManager.swift`, `VirtualDisplayManager.swift`, `VirtualDisplayBridge/` | Độ sáng, DDC, màn hình ảo |
| `Sources/SystemCleanerManager.swift`, `CleanerTabView.swift` | Dọn rác, gỡ app |
| `Sources/ScreenshotManager.swift`, `ScreenshotOverlayView.swift`, `ScreenshotAnnotationRenderer.swift` | Chụp & chú thích |
| `Sources/UpdateManager.swift` | Sparkle |
| `Sources/AgentKit/` | Thư viện thuần Foundation: đọc transcript Claude Code / rollout Codex, hạn mức (statusLine, OAuth), bảng giá, tổng hợp token, socket Unix, cài hook vào `~/.claude/settings.json` |
| `Sources/AgentHook/main.swift` | `machub-agent-hook`: Claude Code gọi qua hook/statusLine, chuyển sự kiện tới app qua socket; luôn thoát 0, không bao giờ tự cho phép |
| `Sources/Agents/` | `AgentMonitor` (trạng thái phiên, duyệt quyền, quét log), `AgentApprovalPanel`, OAuth (tùy chọn), cài hook |
| `Sources/UI/AgentTabView.swift` | Tab Agent: Phiên / Hạn mức / Token / Chi phí / Cài đặt |
| `Sources/Logger.swift`, `ShellHelper.swift` | Log, `shell()` |
| `Vendor/smc-command/` | Mã nguồn `smc` (GPLv2+) |
| `extensions/responsive/` | Extension Chrome *MacHub Responsive*: xem trang ở nhiều kích thước cùng lúc (MV3, JS thuần; test: `tests/e2e_test.py`) |

## 5. Quy ước

- UI và log tiếng Việt (kèm `tr(vi, en)`); tên biến/hàm tiếng Anh.
- Style UI: token trong `Sources/Theme.swift` (`FS.*`, `Rad.*`); không chữ < 10pt; `.bold` chỉ cho số lớn.
- Manager là `@MainActor`; không chạy `Process`/`shell()` nặng trên main thread.
- Giữ `swift-tools-version: 5.9` (Swift 5 language mode).
- **Bảo mật:**
  - Không ghi dữ liệu người dùng hay log vào `/tmp` chung; dùng `NSTemporaryDirectory()` hoặc thư mục trong `~/Library`.
  - Dữ liệu nhạy cảm (clipboard, sau này: board riêng tư, bản ghi màn hình tạm) đi qua `SecureStore`.
  - Mọi giá trị đưa vào `shell()` phải là số hoặc đã kiểm tra chặt; ưu tiên `Process` với `arguments` thay cho chuỗi lệnh.
  - Helper chạy root (`machub-power`) phải tự kiểm tra mọi tham số; không mở rộng rule sudoers.
  - Không thêm binary dựng sẵn không có nguồn vào repo.
- Không hardcode đường dẫn máy dev. Không tự tạo tag/release khi chưa được xác nhận.
- **Theo dõi agent:**
  - Hook phải luôn thoát 0, không in ra stderr; với `PermissionRequest`, không có quyết định rõ ràng thì KHÔNG in gì
    (Claude Code tự hỏi trong terminal). Không bao giờ thêm đường "tự cho phép".
  - Chỉ sửa `~/.claude/settings.json` khi người dùng bấm nút; luôn sao lưu; chỉ đụng mục chứa `machub-agent-hook`.
  - Prompt / tin nhắn chỉ giữ trong RAM, không ghi đĩa. OAuth mặc định tắt, không tự làm mới token.
  - Kiểm thử: `swift test --filter AgentKitTests` (gồm chạy thật `machub-agent-hook` với socket).
  - Dữ liệu mẫu cho UI: `MACHUB_PREVIEW=1 MACHUB_PREVIEW_TAB=4 MACHUB_AGENT_FIXTURES=1 MACHUB_PREVIEW_OUT=/tmp/agent.png`.

---

# Phụ lục A — Ghi chú kế thừa từ HyperMac

## A5. Thay đổi v1.5.2 (2026-10-28)

### A5.1. AltTab hết delay ~0.5s
- `WindowManager.refreshWindows()` **không còn chụp thumbnail đồng bộ**; `thumbnail = nil` khi dựng danh sách.
- `beginThumbnailCapture()` chụp ảnh nền bằng `DispatchQueue.global(qos: .userInitiated)`, cập nhật UI trên main; có `thumbnailGeneration` để huỷ khi HUD đóng.
- HUD được hiện ngay sau khi liệt kê cửa sổ; ảnh xem trước xuất hiện dần.
- Giảm `AXUIElementSetMessagingTimeout` từ `0.1` → `0.05`.
- `showOverlay()` tái sử dụng `NSHostingController` (không tạo mới mỗi lần).
- Thêm `handleModifierReleased()`; `KeyInterceptor` gọi hàm này khi nhả `⌘/⌥`.
- `handleShortcut()` reset `isModifierHeld`/`gIsAltTabVisible` nếu danh sách cửa sổ rỗng.

### A5.2. Clipboard: giới hạn lưu & dọn dẹp
- `ClipboardManager.maxItemsCount`: `0` = **không giới hạn**; hỗ trợ 50/100/200/500/∞.
- Thêm `autoCleanupDays` (UserDefaults key `clipboard_auto_cleanup_days`): `0/7/30/90` ngày.
- `applyRetentionPolicy()` tự xoá mục **chưa ghim** cũ hơn số ngày cấu hình; chạy khi khởi động, khi thêm clip và khi đổi cài đặt.
- `cleanupNow()` cho nút "Dọn ngay": trả về số mục đã xoá và hiện `cleanupMessage` (tự ẩn sau 3.5s). Trước đây bấm không có phản hồi nên trông như "không dọn" — thực chất chỉ xoá mục cũ hơn 30 ngày mà lịch sử toàn mục mới.
- `requestClearAllUnpinned()` cho nút "Xoá tất cả": xoá mọi mục chưa ghim, cần bấm 2 lần (`pendingClearAllConfirm`, tự huỷ sau 4s).
- `trimItems()` xử lý đúng trường hợp không giới hạn; luôn giữ mục đã ghim.
- UI mới trong `Views.swift`: hàng chip giới hạn, hàng "Tự động xoá", 2 nút "Dọn ngay" / "Xoá tất cả", dòng thông báo kết quả, cảnh báo khi chọn ∞.

### A5.3. Phím tắt Clipboard HUD
- `KeyInterceptor.swift` xử lý khi `gIsClipboardHUDVisible`:
  - `1–9` → `pasteItemAt(index:)` (chỉ khi ô tìm kiếm đang rỗng, cờ `gIsClipboardSearchEmpty`).
  - `↑/↓` → `selectPrevious()/selectNext()`.
  - `↵`/numpad Enter → `pasteSelectedItem()`.
  - `⌥P` → `togglePinSelected()`; `⌥⌫` → `deleteSelectedItem()`; `⎋` → đóng.
- `ClipboardManager` thêm `selectedItem`, `clampSelection()`, `selectNext/Previous`, `pasteSelectedItem`, `pasteItemAt`, `togglePinSelected`, `deleteSelectedItem`.
- `⌘`/`⌃` được thả qua để không phá shortcut hệ thống.
- `ClipboardOverlayView` Enter dùng mục đang chọn (không còn luôn dán mục đầu).

### A5.4. Cỡ chữ phím tắt
- `ClipboardOverlayView.legendItem`: 7.5 → 9.5/9.
- `AltTabOverlayView.HintChip`: 8 → 9.5.
- `Views.swift` `shortcutPill`: 8 → 9.5/9.

### A5.5. Gỡ Fan Control
- Xoá toàn bộ `activeFanControlCard`, 4 chế độ quạt, slider RPM, Smart Curve, preset RPM trong `Views.swift`.
- `ThermalManager.swift` viết lại: chỉ còn đọc nhiệt độ HID/PMU, trạng thái thermal, pill nhiệt độ Menu Bar. Đã xoá `FanControlMode`, `ThermalSensorTarget`, `FanModel`, `detectFans`, `applyActiveFanProfile`, `restoreFansToAuto`.
- `AppMain.applicationWillTerminate` không còn gọi `restoreFansToAuto()`.
- `menuBarDisplayMode` bị bỏ; Menu Bar chỉ hiện `44°C`.
- Tab "Quạt & Nhiệt độ" đổi thành **"Nhiệt độ & Cảm biến"**.

### A5.6. Phiên bản & tài liệu
- Bump `1.5.1` → `1.5.2` tại: `build.sh`, `Sources/UpdateManager.swift`, `version.json`, badge/README.
- Thêm changelog v1.5.2 trong `README.md`.
- Cần tạo tag `v1.5.2` và push để GitHub Actions tạo release khớp `version.json`.

## A6. Thay đổi v1.6.0 (2026-10-28)

### A6.1. Đo tốc độ chép file — `Sources/DiskSpeedManager.swift`
- UI: `FileTransferSpeedCard` trong `HardwareCareTabView`, đặt ngay dưới thanh chọn
  Pin / Nhiệt độ (luôn hiển thị, không phụ thuộc segment đang chọn).
- **Mặc định TẮT**: người dùng bật bằng switch trên card (lưu ở
  `UserDefaults["disk_speed_enabled"]`). Khi tắt, không có timer, không quét ổ/tiến
  trình, không cấp phát bộ đếm.
- **Chỉ chạy khi popover mở**: `AppDelegate` là `NSPopoverDelegate`; `popoverDidShow`
  → `setPopoverVisible(true)`, `popoverDidClose` → `setPopoverVisible(false)`.
  Đóng bảng là dừng timer + `sampler.reset()` + xoá số liệu đã publish.
- Kiến trúc: `DiskSpeedManager` (`@MainActor`, `ObservableObject`) giữ `Timer` 1s trên
  main run loop; mỗi tick đẩy `DiskSpeedSampler.sample()` sang `DispatchQueue` nền.
  Sampler tính delta byte / delta thời gian (`max(0.25s, …)`) → MB/s.

**Ổ vật lý (chính xác):**
- Duyệt `IOMedia` có `Whole = true`, lấy **cha trực tiếp**; chỉ nhận khi class cha là
  `IOBlockStorageDriver` (nơi có property `Statistics`).
- `AppleAPFSContainerScheme` cũng có `Statistics` riêng → nếu không lọc theo class
  cha, tốc độ sẽ bị cộng trùng (gấp đôi) giữa `disk0` và `disk3`.
- Bỏ qua media ảo của file `.dmg/.iso` (IORegistry name chứa `Disk Image`) để ổ
  "Tor Browser"… không xuất hiện như ổ cứng thật.
- Tên hiển thị: đi ngược cây IORegistry từ volume đang mount (`getmntinfo`) lên tới
  IOMedia vật lý (`mediaEntry(forBSDName:)`), chọn volume gốc `/` hoặc volume lớn
  nhất. Fallback: `Device Characteristics → Product Name` (`APPLE SSD…` →
  `SSD nội bộ`), cuối cùng là BSD name.
- Dòng chi tiết trong card hiển thị **nguồn → đích** (ổ đọc nhiều nhất → ổ ghi nhiều
  nhất), ví dụ `U280-Pro → SSD nội bộ`; nếu cùng một ổ thì chỉ hiện tên ổ.

**NAS / ổ mạng (xấp xỉ):**
- `networkVolumeHosts()` lấy host từ `getmntinfo` (`//user@host/share`, `host:/path`).
- `route -n get <host>` (cache 60s) → tên interface (`en0`, `en1`, …).
- Đọc byte counter 64-bit của interface qua `sysctl` MIB
  `[CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]` (`if_msghdr2.ifm_data`).
- Nếu không resolve được interface: cộng các interface `en*`/`ppp*`.
- Đây là tốc độ **của card mạng**, không phải riêng phiên SMB → có thể lẫn traffic khác.

**Tiến trình đang chép:**
- `proc_listallpids` + `proc_pid_rusage(pid, RUSAGE_INFO_V4)` lấy
  `ri_diskio_bytesread/written`; lưu counter của frame trước để tính delta.
- Chỉ gắn tên tiến trình khi `peak >= 3 MB/s` **và** `peak >= 50%` tổng lưu lượng,
  nếu không sẽ hiện nhầm I/O nền (Spotlight, `BackgroundShortcutRunner`).
- Hạn chế đã biết: ghi qua page cache có thể xong trước nhịp lấy mẫu nên tiến trình
  có thể không hiện (ví dụ `dd` tốc độ cao); số liệu ổ cứng vẫn đúng.

**Debug:** đặt `MACHUB_DISKSPEED_DEBUG=1` để log mỗi mẫu vào `~/Library/Logs/MacHub/machub.log`
(dòng `💾 DiskSpeed: …`). Hook `MACHUB_DISKSPEED_TEST_HOST` đã được gỡ.

### A6.2. Kiểm thử giao diện không cần chụp màn hình
- `MACHUB_PREVIEW=1` mở cửa sổ 380×570 chứa `MainView` (không tạo status item).
- `MACHUB_PREVIEW_TAB=0|1|2` chọn tab (mặc định 1).
- `MACHUB_PREVIEW_OUT=/tmp/ui.png` render thẳng ra PNG bằng `ImageRenderer`
  rồi thoát — hữu ích khi terminal không có quyền Screen Recording.
- `MACHUB_DISKSPEED_FAKE=1` nạp số liệu giả (U280-Pro → SSD, LAN en0) để kiểm tra
  layout dòng chi tiết. **Chỉ dùng khi phát triển**, không ảnh hưởng người dùng.
- `MACHUB_DISKSPEED_AUTOSTART=1` giả lập popover đang mở lúc khởi động;
  `MACHUB_DISKSPEED_AUTOCLOSE=<giây>` tự đóng sau N giây — dùng để kiểm tra
  timer bật/tắt mà không cần bấm menu bar.
- Lưu ý: `ImageRenderer` không render nội dung bên trong `ScrollView`, nên ảnh
  preview chỉ dùng để kiểm tra phần header/tab/card, không thay thế kiểm thử thật.

### A6.3. Phiên bản & tài liệu
- Bump `1.5.2` → `1.6.0` tại: `build.sh`, `Sources/UpdateManager.swift`, `version.json`,
  badge + nút tải trong `README.md`.
- Thêm changelog v1.6.0 trong `README.md`.
- Cần tạo tag `v1.6.0` và push để GitHub Actions tạo release khớp `version.json`.

## A7. Chứng chỉ ký cố định (bắt buộc cho TCC)

**Vấn đề:** ký ad-hoc (`codesign -s -`) khiến cdhash đổi sau mỗi lần build →
macOS coi là app khác → **thu hồi quyền Accessibility** → `⌘Tab`, `⌘⇧C` không chạy
cho tới khi người dùng cấp lại tay.

**Giải pháp đã áp dụng:** chứng chỉ self-signed cố định `MacHub Self-Signed`.

```bash
./scripts/setup-signing-identity.sh   # chạy 1 lần
./build.sh                            # build.sh tự dùng identity này
```

- Script sinh key + cert (EKU `codeSigning`) trong `~/.machub-signing/` (mode 700),
  import vào login keychain, rồi thêm trust policy Code Signing ở user domain.
- `build.sh` tự dò identity; nếu có thì ký bằng nó, nếu không thì fallback ad-hoc
  (kèm cảnh báo). Có thể override bằng biến môi trường `MACHUB_SIGN_IDENTITY`.
- Designated Requirement hiện tại (`codesign -d -r-`):
  `identifier "com.machub.app" and certificate root = H"5f052de8…"`
  → **không phụ thuộc nội dung binary**, nên quyền TCC giữ nguyên qua mọi rebuild.

**Nếu vẫn mất quyền / app không nhận phím tắt:**

```bash
# 1. Kiểm tra chữ ký
codesign -dv --verbose=4 /Applications/MacHub.app | grep Authority
# 2. Xoá entry TCC cũ rồi mở lại app để prompt
tccutil reset Accessibility com.machub.app
open /Applications/MacHub.app
# 3. System Settings → Privacy & Security → Accessibility → bật MacHub
```

**Không commit** `~/.machub-signing/` hay file `.p12` vào repo (chứa private key).
`.gitignore` đã chặn `*.p12` và `*.p12.base64`.

### A7.1. Ký bản phát hành trên GitHub Actions

Runner không có keychain của máy dev, nên phải đưa private key vào **GitHub Secrets**:

1. Xuất chứng chỉ (giữ nguyên key/cert cũ để root hash không đổi):

```bash
./scripts/export-ci-signing.sh
# → ~/.machub-signing/ci-signing.p12
# → ~/.machub-signing/ci-signing.p12.base64
# → in ra mật khẩu + certificate root SHA-1
```

2. Thêm 2 secret tại `Settings → Secrets and variables → Actions`:
   - `MACHUB_SIGNING_P12_BASE64`: nội dung file `.base64`
   - `MACHUB_SIGNING_P12_PASSWORD`: mật khẩu script in ra

3. Workflow `.github/workflows/release.yml` sẽ:
   - tạo keychain tạm, import `.p12`, mở partition list cho `codesign`,
   - **thêm keychain tạm vào search list** của user (codesign chỉ tìm identity
     trong các keychain thuộc search list; `--keychain` một mình là không đủ),
   - build với `MACHUB_SIGN_IDENTITY=MacHub Self-Signed` và
     `MACHUB_SIGN_KEYCHAIN=<keychain tạm>`,
   - verify `Authority=MacHub Self-Signed` + in DR,
   - xoá keychain tạm ở bước `always()`.

Nếu thiếu secret, workflow vẫn build nhưng **fallback ad-hoc** (kèm cảnh báo) —
khi đó quyền Accessibility sẽ mất sau update.

**Ba cái bẫy đã gặp thật (đừng sửa lại thành sai):**

- **p12 phải là định dạng legacy.** OpenSSL 3 mặc định xuất MAC SHA-256 + AES/PBES2;
  `security import` trên runner macOS 14 báo
  `MAC verification failed during PKCS12 import (wrong password?)` dù mật khẩu đúng.
  `scripts/export-ci-signing.sh` dùng `openssl pkcs12 -export -legacy` (SHA-1 + 3DES).
- **Không dùng `security find-identity -v`.** Cờ `-v` chỉ liệt kê identity *đã trust*;
  cert tự ký trên runner là untrusted nên `-v` trả 0 identity dù `codesign` ký được.
  `build.sh` và workflow đều dùng `find-identity -p codesigning` (không `-v`).
- **Không dùng `base64 --decode`.** `base64` của macOS 14 chỉ có `-D`; thậm chí secret
  có thể lẫn CRLF. Workflow strip whitespace rồi decode bằng `python3`, fallback
  `openssl base64 -d -A`, cuối cùng mới `base64 -D`, và tự nhận diện secret bị base64
  2 lớp.

**Nên set secret bằng CLI để tránh dán sai** (đã từng dán cả câu lệnh `pbcopy …`):

```bash
gh secret set MACHUB_SIGNING_P12_BASE64 --repo UriQuynh/MacHub \
  < ~/.machub-signing/ci-signing.p12.base64
gh secret set MACHUB_SIGNING_P12_PASSWORD --repo UriQuynh/MacHub \
  --body "hm-test-pass-2026"
```

Khi bước import fail, đọc lỗi bằng annotation công khai thay vì log:

```bash
gh run view <run-id> --repo UriQuynh/MacHub \
  --json jobs -q '.jobs[0].check_run_url' \
  | xargs -I{} gh api {}/annotations --jq '.[] | "\(.title): \(.message)"'
```

**Lưu ý quan trọng:**
- Chỉ cần **một lần** chuyển từ bản ad-hoc cũ (≤1.5.2) sang bản ký cert: TCC đổi
  DR nên quyền mất một lần; từ các bản sau thì giữ nguyên.
- Không bao giờ tạo lại cert/key (root hash đổi → mất quyền của mọi người).
  Cert hiện có hạn 10 năm (`-days 3650`).
- Secret chứa private key: nếu repo bị xâm nhập, key có thể bị lộ → phải tạo cert
  mới và chấp nhận mất quyền một lần. Xem mục 7.3.

### A7.2. Tự khôi phục quyền sau update — `Sources/AccessibilityRecovery.swift`

- Gọi trong `applicationDidFinishLaunching` **trước** `KeyInterceptor.shared.start()`.
- Mỗi lần khởi động, nếu `AXIsProcessTrusted() == false` **và**
  `UserDefaults["ax_recovery_version"] != phiên bản hiện tại`:
  - chạy `tccutil reset Accessibility com.machub.app` (xoá entry cũ bị kẹt),
  - lưu `ax_recovery_version` = phiên bản hiện tại (mỗi bản chỉ reset **một lần**,
    nên không lặp lại mỗi lần mở app và không phiền người dùng đã từ chối cấp quyền),
  - sau 0.8s gọi `AXIsProcessTrustedWithOptions(prompt: true)` để macOS hiện hộp
    thoại cấp lại.
- Không cần cờ "từng được cấp quyền": entry TCC bị kẹt sau update thường vẫn hiện
  trong System Settings nên không thể phân biệt bằng `UserDefaults`.
- Người dùng chỉ cần bật switch trong System Settings, **không phải xoá app và thêm lại**.
- `tccutil` chỉ reset được khi app có bundle ID hợp lệ; nếu không có, hàm bỏ qua im lặng.


### A7.3. Bảo mật repo & khoá ký

Private key trong secret = ai phát hành được app. Kiểm tra định kỳ bằng `gh`:

```bash
R=UriQuynh/MacHub
gh api repos/$R --jq '.permissions'                       # quyền của token hiện tại
gh api "repos/$R/collaborators?affiliation=direct" --jq '.[] | "\(.login) \(.role_name)"'
gh api "repos/$R/collaborators?affiliation=outside" --jq '.[] | .login'
gh api "repos/$R/invitations" --jq '.[] | .invitee.login'
gh api "repos/$R/actions/secrets" --jq '.secrets[] | "\(.name) \(.updated_at)"'
gh api "repos/$R/environments"
gh api "repos/$R/keys"      # deploy keys
gh api "repos/$R/hooks"     # webhooks
```

Hiện trạng (2026-10-30): chỉ owner `mrgoose000000-gif` có quyền admin; 0 outside
collaborator/invitation/team; 2 secret đúng tên; 0 environment; 0 deploy key;
0 webhook; `main` **chưa bảo vệ**; `allowed_actions=all`; secret scanning +
push protection đang bật.

Khuyến nghị (chưa bắt buộc, làm khi cần siết):

1. **Environment `release` + Required reviewers** rồi chuyển 2 secret vào environment
   và thêm `environment: release` cho job trong `release.yml`. Khi đó dù ai push tag,
   workflow vẫn phải chờ duyệt mới được dùng private key.
2. **Ruleset cho `main`**: chặn force-push và xoá nhánh (solo dev vẫn dùng được).
3. `Settings → Actions → General`: giới hạn allowed actions + bật *Require actions to
   be pinned to a full-length commit SHA*.
4. Bật 2FA/passkey cho tài khoản GitHub; xoá token cũ không dùng; kiểm tra
   `Settings → Sessions`.
5. Giữ `~/.machub-signing/` ngoài iCloud/Dropbox và bật FileVault.

## A8. Ghi chú kiểm thử

- Máy test: `MacBookPro17,1` (MacBook Pro M1, 1 quạt 1199–7199 RPM), macOS 26. (Máy cũ `Mac14,2` MacBook Air M2 không có quạt: `smc -f` trả `Total fans in system: 0`, thẻ Quạt tự ẩn.)
- Kiểm tra nhanh sau khi sửa:
  1. `⌘ + Tab` phải hiện HUD gần như tức thì (< ~100ms), thumbnail xuất hiện sau.
  2. `⌘ + ⇧ + C` mở Clipboard; thử `1–9`, `↑↓`, `↵`, `⌥P`, `⌥⌫`, `⎋`.
  3. Settings → Clipboard: chọn 500/∞, đổi "Tự động xoá", bấm "Dọn ngay".
  4. Tab nhiệt độ: thẻ Quạt (System / Medium / High / thanh trượt) + nhiệt độ, cảm biến, pill Menu Bar. Xem mục 9.5 để kiểm thử quạt.
  5. Ô **Chép file** (tab Pin & Phần cứng): chạy `dd if=/dev/zero of=/tmp/dstest.bin bs=1m count=600`
     → số `↑` phải nhảy lên hàng trăm MB/s và tên ổ là `Macintosh HD` / `SSD nội bộ`;
     chép thẻ nhớ → ổ rời phải thấy tên volume của cả hai ổ trong tooltip.
  6. NAS: mount SMB rồi chép file; chip mạng hiện `LAN enX` với tốc độ tương đương
     lưu lượng thực (đối chiếu `netstat -ibn` trước/sau khi chép).

## A9. Điều khiển quạt (thêm lại, bản đơn giản kiểu iStat Menus)


### A9.1. Tính năng
- Thẻ **Quạt** trong tab "Nhiệt độ & Cảm biến": nút **System** (macOS tự điều khiển, mặc định), **Medium** (50% max RPM), **High** (80%), và **thanh trượt** tự chọn từ min RPM đến 100% (hiện `RPM (%)`). Ở chế độ System thanh trượt bám theo RPM thực tế.
- Không có rules editor, curve hay watchdog chống crash (quyết định của người dùng cho v1).

### A9.2. Cơ chế SMC (đã kiểm chứng trên M1, macOS 26)
- Ghi: `F0Md=01` (manual) rồi `F0Tg=<float32 little-endian>` (3000 RPM = `00803b45`). Không cần mở khoá `Ftst` (key trả "no data" trên M1); helper vẫn ghi `Ftst` nếu key tồn tại (M3/M4+ có thể cần, chưa kiểm thử).
- Trả về auto: `F0Md=00`, `F0Tg=00000000`.
- Đọc lại ngay sau khi ghi có thể ra giá trị cũ; `FanManager` chờ ~1.5s rồi kiểm chứng `F0Tg`, nếu lệch thì tự trả về System và báo lỗi.
- Đọc (không cần root): `Resources/smc -k F0Ac|F0Tg|F0Md|F0Mn|F0Mx|FNum -r` (định dạng `F0Ac  [flt ]  2985 (bytes ...)`, giá trị là trường thứ 4 khi tách theo khoảng trắng).

### A9.3. Helper đặc quyền
- `Resources/machub-power` (cài vào `/usr/local/bin`, sudoers NOPASSWD sẵn có) có thêm: `version` (in `HELPER_VERSION:2`), `fan-set <id 0-3> <rpm>` (chỉ nhận số nguyên trong khoảng min..max đọc từ SMC), `fan-auto <id>`.
- `FanManager` yêu cầu helper phiên bản >= 2; bản helper cũ → thẻ Quạt hiện nút cài lại (`BatteryManager.installHelper`, hỏi mật khẩu 1 lần).
- **Cài helper từ thư mục dưới `~/Documents`** bằng `osascript ... with administrator privileges` sẽ lỗi `Operation not permitted` (root bị TCC chặn). Sao chép 3 file (`install-helper.sh`, `smc`, `machub-power`) ra `/private/tmp/...` rồi cài từ đó. App đã cài trong `/Applications` thì không gặp lỗi này.

### A9.4. An toàn
- Về System: khi thoát app (`applicationWillTerminate`), trước khi ngủ, khi khởi động app, khi chọn System.
- CPU peak / GPU / hotspot >= 90°C → ép về System; chỉ cho điều khiển lại khi < 80°C.
- Nếu app crash/force-quit khi đang Manual, quạt giữ tốc độ cuối cho tới khi mở lại MacHub (tự reset về auto) hoặc khởi động lại máy.
- Không chạy cùng app điều khiển quạt khác (hai bên tranh `F0Tg`).

### A9.5. Kiểm thử
- Bấm High → `Resources/smc -k F0Tg -r` ≈ 5759, `F0Ac` tiến dần tới đó; Medium ≈ 3600; kéo thanh trượt 74% ≈ 5336; System → `F0Md` = 0, RPM giảm về 0.
- Thoát app khi đang Manual → quạt phải về auto.
- Đường 90°C chưa có hook giả nhiệt độ (chưa kiểm thử tự động).

### A9.6. Bản build cục bộ: tắt cập nhật tự động
- `UpdateManager.updatesDisabled = true`: không kiểm tra/tải cập nhật (không có kết nối mạng nào của app). Lý do: updater không kiểm chữ ký, URL tải lấy từ `version.json`, file tạm ở `/tmp`. Đặt `false` để bật lại — quyết định của người dùng khi commit/phát hành.
