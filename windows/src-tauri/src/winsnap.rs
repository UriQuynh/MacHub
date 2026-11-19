// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Chia cửa sổ (kiểu Rectangle) và dán vào cửa sổ trước đó.

use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub struct Layout {
    pub id: &'static str,
    pub label: &'static str,
    pub keys: &'static str,
}

/// Bố cục + phím tắt mặc định (Ctrl+Alt+…, không đụng Win+mũi tên của Windows).
pub const LAYOUTS: &[Layout] = &[
    Layout { id: "left", label: "Nửa trái", keys: "Ctrl+Alt+←" },
    Layout { id: "right", label: "Nửa phải", keys: "Ctrl+Alt+→" },
    Layout { id: "top", label: "Nửa trên", keys: "Ctrl+Alt+↑" },
    Layout { id: "bottom", label: "Nửa dưới", keys: "Ctrl+Alt+↓" },
    Layout { id: "maximize", label: "Toàn màn hình", keys: "Ctrl+Alt+Enter" },
    Layout { id: "center", label: "Giữa màn hình", keys: "Ctrl+Alt+C" },
    Layout { id: "first-third", label: "1/3 trái", keys: "Ctrl+Alt+D" },
    Layout { id: "center-third", label: "1/3 giữa", keys: "Ctrl+Alt+F" },
    Layout { id: "last-third", label: "1/3 phải", keys: "Ctrl+Alt+G" },
    Layout { id: "first-two-thirds", label: "2/3 trái", keys: "Ctrl+Alt+E" },
    Layout { id: "last-two-thirds", label: "2/3 phải", keys: "Ctrl+Alt+T" },
    Layout { id: "top-left", label: "Góc trên trái", keys: "Ctrl+Alt+U" },
    Layout { id: "top-right", label: "Góc trên phải", keys: "Ctrl+Alt+I" },
    Layout { id: "bottom-left", label: "Góc dưới trái", keys: "Ctrl+Alt+J" },
    Layout { id: "bottom-right", label: "Góc dưới phải", keys: "Ctrl+Alt+K" },
    Layout { id: "next-display", label: "Sang màn hình kế", keys: "Ctrl+Alt+Shift+→" },
];

/// Hình chữ nhật đích trong vùng làm việc (x, y, w, h).
pub fn target_rect(id: &str, area: (i32, i32, i32, i32), current: (i32, i32, i32, i32)) -> Option<(i32, i32, i32, i32)> {
    let (x, y, w, h) = area;
    let (hw, hh, t) = (w / 2, h / 2, w / 3);
    Some(match id {
        "left" => (x, y, hw, h),
        "right" => (x + hw, y, w - hw, h),
        "top" => (x, y, w, hh),
        "bottom" => (x, y + hh, w, h - hh),
        "maximize" => (x, y, w, h),
        "center" => {
            let (cw, ch) = (current.2.min(w), current.3.min(h));
            (x + (w - cw) / 2, y + (h - ch) / 2, cw, ch)
        }
        "first-third" => (x, y, t, h),
        "center-third" => (x + t, y, t, h),
        "last-third" => (x + 2 * t, y, w - 2 * t, h),
        "first-two-thirds" => (x, y, 2 * t, h),
        "last-two-thirds" => (x + t, y, w - t, h),
        "top-left" => (x, y, hw, hh),
        "top-right" => (x + hw, y, w - hw, hh),
        "bottom-left" => (x, y + hh, hw, h - hh),
        "bottom-right" => (x + hw, y + hh, w - hw, h - hh),
        _ => return None,
    })
}

#[cfg(windows)]
mod platform {
    use super::target_rect;
    use windows::Win32::Foundation::{HWND, LPARAM, RECT};
    use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_EXTENDED_FRAME_BOUNDS};
    use windows::Win32::Graphics::Gdi::{
        EnumDisplayMonitors, GetMonitorInfoW, MonitorFromWindow, HDC, HMONITOR, MONITORINFO, MONITOR_DEFAULTTONEAREST,
    };
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_CONTROL,
    };
    use windows::Win32::UI::WindowsAndMessaging::{
        GetClassNameW, GetForegroundWindow, GetWindowRect, IsIconic, IsZoomed, SetForegroundWindow, SetWindowPos, ShowWindow,
        SWP_NOACTIVATE, SWP_NOZORDER, SW_RESTORE,
    };

    fn rect_of(r: RECT) -> (i32, i32, i32, i32) {
        (r.left, r.top, r.right - r.left, r.bottom - r.top)
    }

    fn work_area(m: HMONITOR) -> Option<RECT> {
        let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        unsafe { GetMonitorInfoW(m, &mut mi).as_bool().then_some(mi.rcWork) }
    }

    fn monitors() -> Vec<HMONITOR> {
        unsafe extern "system" fn cb(m: HMONITOR, _: HDC, _: *mut RECT, lp: LPARAM) -> windows::core::BOOL {
            let v = &mut *(lp.0 as *mut Vec<HMONITOR>);
            v.push(m);
            true.into()
        }
        let mut v: Vec<HMONITOR> = Vec::new();
        unsafe {
            let _ = EnumDisplayMonitors(None, None, Some(cb), LPARAM(&mut v as *mut _ as isize));
        }
        v
    }

    /// Bỏ qua desktop, thanh taskbar và chính MacHub.
    fn is_snappable(h: HWND) -> bool {
        if h.0.is_null() {
            return false;
        }
        let mut buf = [0u16; 64];
        let n = unsafe { GetClassNameW(h, &mut buf) } as usize;
        let class = String::from_utf16_lossy(&buf[..n]);
        !matches!(class.as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd" | "Shell_SecondaryTrayWnd")
    }

    pub fn snap(id: &str, own: Option<isize>) -> Result<(), String> {
        let hwnd = unsafe { GetForegroundWindow() };
        if !is_snappable(hwnd) || own == Some(hwnd.0 as isize) {
            return Err("Không có cửa sổ phù hợp đang được chọn.".into());
        }
        unsafe {
            if IsZoomed(hwnd).as_bool() || IsIconic(hwnd).as_bool() {
                let _ = ShowWindow(hwnd, SW_RESTORE);
            }
        }
        let mon = unsafe { MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) };
        let mut window = RECT::default();
        unsafe { GetWindowRect(hwnd, &mut window) }.map_err(|e| e.to_string())?;
        // Viền vô hình của DWM (Win10/11): bù để cửa sổ khít mép.
        let mut frame = window;
        let _ = unsafe {
            DwmGetWindowAttribute(
                hwnd,
                DWMWA_EXTENDED_FRAME_BOUNDS,
                &mut frame as *mut _ as *mut std::ffi::c_void,
                std::mem::size_of::<RECT>() as u32,
            )
        };
        let (dl, dt, dr, db) = (frame.left - window.left, frame.top - window.top, window.right - frame.right, window.bottom - frame.bottom);

        let (target_mon, layout) = if id == "next-display" {
            let all = monitors();
            let i = all.iter().position(|m| *m == mon).unwrap_or(0);
            let next = all.get((i + 1) % all.len().max(1)).copied().unwrap_or(mon);
            (next, "maximize")
        } else {
            (mon, id)
        };
        let area = work_area(target_mon).ok_or("Không đọc được vùng màn hình.")?;
        let (x, y, w, h) = target_rect(layout, rect_of(area), rect_of(frame)).ok_or("Bố cục không hợp lệ.")?;
        unsafe {
            SetWindowPos(hwnd, None, x - dl, y - dt, w + dl + dr, h + dt + db, SWP_NOZORDER | SWP_NOACTIVATE)
                .map_err(|e| e.to_string())
        }
    }

    pub fn foreground() -> isize {
        unsafe { GetForegroundWindow().0 as isize }
    }

    /// Đưa cửa sổ cũ lên trước rồi gửi Ctrl+V.
    pub fn paste_into(hwnd: isize) {
        unsafe {
            let h = HWND(hwnd as *mut _);
            if !h.0.is_null() {
                let _ = SetForegroundWindow(h);
            }
            std::thread::sleep(std::time::Duration::from_millis(80));
            let key = |vk: VIRTUAL_KEY, up: bool| INPUT {
                r#type: INPUT_KEYBOARD,
                Anonymous: INPUT_0 {
                    ki: KEYBDINPUT {
                        wVk: vk,
                        wScan: 0,
                        dwFlags: if up { KEYEVENTF_KEYUP } else { KEYBD_EVENT_FLAGS(0) },
                        time: 0,
                        dwExtraInfo: 0,
                    },
                },
            };
            let v = VIRTUAL_KEY(b'V' as u16);
            let inputs = [key(VK_CONTROL, false), key(v, false), key(v, true), key(VK_CONTROL, true)];
            SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
    }
}

#[cfg(not(windows))]
mod platform {
    pub fn snap(_: &str, _: Option<isize>) -> Result<(), String> {
        Err("Chỉ hỗ trợ Windows".into())
    }
    pub fn foreground() -> isize {
        0
    }
    pub fn paste_into(_: isize) {}
}

pub use platform::{foreground, paste_into, snap};

#[cfg(test)]
mod tests {
    use super::target_rect;

    #[test]
    fn layouts_tile_the_work_area() {
        let area = (0, 0, 1921, 1041);
        let cur = (100, 100, 800, 600);
        let l = target_rect("left", area, cur).unwrap();
        let r = target_rect("right", area, cur).unwrap();
        assert_eq!(l.2 + r.2, 1921, "không hở / chồng ở số lẻ");
        let thirds: i32 = ["first-third", "center-third", "last-third"].iter().map(|i| target_rect(i, area, cur).unwrap().2).sum();
        assert_eq!(thirds, 1921);
        assert_eq!(target_rect("center", area, cur).unwrap(), (560, 220, 800, 600));
        assert!(target_rect("nope", area, cur).is_none());
    }
}
