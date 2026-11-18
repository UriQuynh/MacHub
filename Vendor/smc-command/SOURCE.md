# smc-command (vendored)

Công cụ dòng lệnh `smc` dùng để đọc/ghi khóa SMC (khóa sạc, quạt). MacHub cài nó
vào `/Library/PrivilegedHelperTools/com.machub.app.smc` với chủ sở hữu root, nên
**không dùng binary dựng sẵn**: `build.sh` biên dịch từ đúng mã nguồn trong thư mục này.

- Nguồn: https://github.com/hholtmann/smcFanControl/tree/master/smc-command
- Commit: `e1bd672bcd2d72eddff9b6da7b9cae38e35c4206`
- Giấy phép: GNU GPL v2 hoặc mới hơn (xem `LICENSE`) — tương thích với GPLv3 của MacHub.
- Copyright (C) 2006 devnull; Portions Copyright (C) 2013 Michael Wilber.
- Thay đổi: không có (giữ nguyên bản gốc).

Binary cũ `Resources/smc` của HyperMac (sha256 `e3b4392c966dee700f3e1d6cc3812c0d487954c3d6d77b91f521a9590aadae44`)
khớp chuỗi phiên bản `0.01` và bộ tham số của công cụ này, nhưng không có nguồn kèm theo nên đã bị gỡ.

Cập nhật: thay `smc.c`/`smc.h` bằng bản mới từ upstream, sửa commit ở trên và rà diff trước khi merge.
