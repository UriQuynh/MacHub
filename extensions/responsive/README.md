# MacHub Responsive — extension Chrome

Xem một trang web ở nhiều kích thước **mobile / tablet / desktop cùng lúc** trên một màn hình,
thay cho việc mở DevTools (F12) rồi đổi từng thiết bị.

## Cài đặt (Load unpacked)

1. Mở `chrome://extensions`, bật **Developer mode** (góc trên bên phải).
2. Bấm **Load unpacked**, chọn thư mục `extensions/responsive` trong repo MacHub.
3. Ghim biểu tượng extension lên thanh công cụ (biểu tượng mảnh ghép → ghim *MacHub Responsive*).

Dùng được trên Chrome, Edge, Brave, Arc (Chromium ≥ 116).

## Cách dùng

- Đang ở trang cần xem → bấm biểu tượng extension hoặc **Alt+Shift+R**. Tab viewer mở ngay cạnh.
- Gõ URL ở thanh trên (vd. `localhost:3000` — tự thêm `http://` cho địa chỉ nội bộ).
- **Thiết bị**: bật/tắt máy có sẵn (iPhone, Pixel, Galaxy, iPad, Laptop, Desktop) hoặc thêm kích thước riêng.
- Mỗi khung: **xoay** ngang/dọc, **tải lại**, **mở trong tab mới**.
- **Thu phóng**: *Vừa màn hình* (mọi khung lọt trọn) hoặc 33/50/75/100%.
- **Đồng bộ cuộn**: cuộn một khung, các khung khác cuộn theo tỉ lệ.
- **Đồng bộ điều hướng**: bấm link trong một khung, các khung khác mở cùng trang.
- **Chụp**: lưu ảnh PNG toàn bộ viewer. Phím **R**: tải lại tất cả. Nút ◑: giao diện sáng/tối.
- Cài đặt (thiết bị, thu phóng, đồng bộ, giao diện) được lưu cho lần sau.

Với file cục bộ (`file://`): vào `chrome://extensions` → *MacHub Responsive* → bật **Allow access to file URLs**.

## Cách hoạt động & quyền riêng tư

- Nhiều trang chặn bị nhúng bằng `X-Frame-Options` hoặc CSP `frame-ancestors`. Extension gỡ hai header này
  **chỉ cho iframe trong đúng tab viewer đang mở** (session rule theo `tabId`, tự xóa khi đóng tab).
  Các tab duyệt web khác không bị ảnh hưởng. Vì CSP của trang bị gỡ trong khung xem trước, chỉ nên
  dùng viewer để xem trang của bạn hoặc trang tin cậy.
- `frame-agent.js` chạy trong mọi frame nhưng thoát ngay, trừ khi frame nằm trực tiếp trong viewer
  của extension (kiểm tra `location.ancestorOrigins`). Nó chỉ gửi vị trí cuộn và URL hiện tại cho viewer.
- Không gửi dữ liệu ra ngoài, không analytics.

## Giới hạn

- Chỉ giả lập **kích thước viewport** (media query, layout). User-Agent, cảm ứng và `devicePixelRatio`
  không đổi — trang phân biệt thiết bị bằng UA phía server có thể vẫn trả bản desktop.
- Điều hướng kiểu SPA (`pushState`) không được đồng bộ; chỉ đồng bộ khi trang tải lại.
- Trang dựa vào cookie bên thứ ba (một số trang đăng nhập) có thể không giữ phiên trong khung.

## Kiểm thử

```bash
pip install playwright && python -m playwright install chromium
python extensions/responsive/tests/e2e_test.py   # 20 bài: nhúng trang chặn iframe, breakpoint, đồng bộ, xoay, zoom…
```
