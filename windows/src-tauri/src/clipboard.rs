// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Lịch sử clipboard (văn bản).
//!
//! - Lắng nghe `WM_CLIPBOARDUPDATE` qua cửa sổ ẩn (message-only).
//! - BỎ QUA nội dung mà app nguồn đánh dấu không lưu lịch sử (trình quản lý mật khẩu dùng):
//!   `ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory = 0`, `Clipboard Viewer Ignore`.
//! - Lưu xuống đĩa đã mã hóa bằng DPAPI (`CryptProtectData`, gắn với tài khoản Windows): `%APPDATA%\MacHub\clipboard.bin`.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter};

pub const MAX_ITEMS: usize = 300;
const MAX_TEXT: usize = 256 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipItem {
    pub id: u64,
    pub text: String,
    pub copied_at: DateTime<Utc>,
    pub pinned: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct Store {
    next_id: u64,
    items: Vec<ClipItem>,
}

#[derive(Clone)]
pub struct Clipboard {
    store: Arc<Mutex<Store>>,
    /// Bỏ qua thay đổi do chính MacHub gây ra (khi bấm chép lại một mục).
    ignore_next: Arc<Mutex<Option<String>>>,
    app: AppHandle,
}

impl Clipboard {
    pub fn new(app: AppHandle) -> Clipboard {
        let store = load().unwrap_or_default();
        Clipboard { store: Arc::new(Mutex::new(store)), ignore_next: Default::default(), app }
    }

    pub fn list(&self, query: &str) -> Vec<ClipItem> {
        let q = query.trim().to_lowercase();
        let s = self.store.lock().unwrap_or_else(|e| e.into_inner());
        let mut v: Vec<ClipItem> = s.items.iter().filter(|i| q.is_empty() || i.text.to_lowercase().contains(&q)).cloned().collect();
        v.sort_by(|a, b| b.pinned.cmp(&a.pinned).then(b.copied_at.cmp(&a.copied_at)));
        v
    }

    fn add(&self, text: String) {
        if text.trim().is_empty() || text.len() > MAX_TEXT {
            return;
        }
        if let Ok(mut ig) = self.ignore_next.lock() {
            if ig.as_deref() == Some(text.as_str()) {
                *ig = None;
                return;
            }
        }
        {
            let mut s = self.store.lock().unwrap_or_else(|e| e.into_inner());
            let pinned = s.items.iter().any(|i| i.text == text && i.pinned);
            s.items.retain(|i| i.text != text);
            s.next_id += 1;
            let id = s.next_id;
            s.items.push(ClipItem { id, text, copied_at: Utc::now(), pinned });
            // Giữ mục đã ghim; bỏ mục cũ nhất khi vượt giới hạn.
            while s.items.len() > MAX_ITEMS {
                if let Some(pos) = s.items.iter().position(|i| !i.pinned) {
                    s.items.remove(pos);
                } else {
                    break;
                }
            }
            save(&s);
        }
        let _ = self.app.emit("clipboard-updated", ());
    }

    pub fn set_pinned(&self, id: u64, pinned: bool) {
        let mut s = self.store.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(i) = s.items.iter_mut().find(|i| i.id == id) {
            i.pinned = pinned;
        }
        save(&s);
    }

    pub fn delete(&self, id: u64) {
        let mut s = self.store.lock().unwrap_or_else(|e| e.into_inner());
        s.items.retain(|i| i.id != id);
        save(&s);
    }

    /// Xóa mọi mục chưa ghim. Trả về số mục đã xóa.
    pub fn clear_unpinned(&self) -> usize {
        let mut s = self.store.lock().unwrap_or_else(|e| e.into_inner());
        let before = s.items.len();
        s.items.retain(|i| i.pinned);
        save(&s);
        before - s.items.len()
    }

    /// Đặt mục vào clipboard hệ thống.
    pub fn copy(&self, id: u64) -> Result<(), String> {
        let text = {
            let s = self.store.lock().unwrap_or_else(|e| e.into_inner());
            s.items.iter().find(|i| i.id == id).map(|i| i.text.clone()).ok_or("Không tìm thấy mục.")?
        };
        if let Ok(mut ig) = self.ignore_next.lock() {
            *ig = Some(text.clone());
        }
        platform::set_text(&text)
    }

    pub fn start(&self) {
        let me = self.clone();
        platform::listen(move |text| me.add(text));
    }
}

fn store_path() -> std::path::PathBuf {
    machub_core::paths::support_dir().join("clipboard.bin")
}

const MAGIC: &[u8; 4] = b"MHW1";

fn load() -> Option<Store> {
    let data = std::fs::read(store_path()).ok()?;
    let body = data.strip_prefix(MAGIC)?;
    let plain = platform::unprotect(body)?;
    serde_json::from_slice(&plain).ok()
}

fn save(s: &Store) {
    let Ok(plain) = serde_json::to_vec(s) else { return };
    // Không mã hóa được → KHÔNG ghi bản rõ xuống đĩa.
    let Some(enc) = platform::protect(&plain) else { return };
    let path = store_path();
    if let Some(d) = path.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    let mut out = MAGIC.to_vec();
    out.extend_from_slice(&enc);
    let tmp = path.with_extension("tmp");
    if std::fs::write(&tmp, out).is_ok() {
        let _ = std::fs::rename(&tmp, &path);
    }
}

#[cfg(windows)]
mod platform {
    use std::sync::{Mutex, OnceLock};
    use windows::core::{w, PCWSTR};
    use windows::Win32::Foundation::{GlobalFree, HANDLE, HGLOBAL, HLOCAL, HWND, LocalFree, LPARAM, LRESULT, WPARAM};
    use windows::Win32::Security::Cryptography::{CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB};
    use windows::Win32::System::DataExchange::{
        AddClipboardFormatListener, CloseClipboard, EmptyClipboard, GetClipboardData, IsClipboardFormatAvailable, OpenClipboard,
        RegisterClipboardFormatW, SetClipboardData,
    };
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalSize, GlobalUnlock, GMEM_MOVEABLE};
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, RegisterClassW, TranslateMessage, HWND_MESSAGE, MSG,
        WINDOW_EX_STYLE, WINDOW_STYLE, WM_CLIPBOARDUPDATE, WNDCLASSW,
    };

    const CF_UNICODETEXT: u32 = 13;
    type Callback = Box<dyn Fn(String) + Send>;
    static CALLBACK: OnceLock<Mutex<Callback>> = OnceLock::new();

    /// Mở clipboard, thử lại vài lần vì app khác có thể đang giữ.
    fn open() -> bool {
        for _ in 0..10 {
            if unsafe { OpenClipboard(None) }.is_ok() {
                return true;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        false
    }

    fn excluded() -> bool {
        unsafe {
            let ex = RegisterClipboardFormatW(w!("ExcludeClipboardContentFromMonitorProcessing"));
            let ign = RegisterClipboardFormatW(w!("Clipboard Viewer Ignore"));
            if IsClipboardFormatAvailable(ex).is_ok() || IsClipboardFormatAvailable(ign).is_ok() {
                return true;
            }
            let can = RegisterClipboardFormatW(w!("CanIncludeInClipboardHistory"));
            if IsClipboardFormatAvailable(can).is_ok() {
                if let Ok(h) = GetClipboardData(can) {
                    let g = HGLOBAL(h.0);
                    let p = GlobalLock(g) as *const u32;
                    let allowed = !p.is_null() && *p != 0;
                    let _ = GlobalUnlock(g);
                    return !allowed;
                }
            }
            false
        }
    }

    fn read_text() -> Option<String> {
        if !open() {
            return None;
        }
        let result = unsafe {
            if excluded() || IsClipboardFormatAvailable(CF_UNICODETEXT).is_err() {
                None
            } else if let Ok(h) = GetClipboardData(CF_UNICODETEXT) {
                let g = HGLOBAL(h.0);
                let p = GlobalLock(g) as *const u16;
                let text = if p.is_null() {
                    None
                } else {
                    let max = GlobalSize(g) / 2;
                    let mut len = 0usize;
                    while len < max && *p.add(len) != 0 {
                        len += 1;
                    }
                    Some(String::from_utf16_lossy(std::slice::from_raw_parts(p, len)))
                };
                let _ = GlobalUnlock(g);
                text
            } else {
                None
            }
        };
        unsafe {
            let _ = CloseClipboard();
        }
        result
    }

    pub fn set_text(text: &str) -> Result<(), String> {
        let wide: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
        if !open() {
            return Err("Clipboard đang bị app khác giữ.".into());
        }
        let r = unsafe {
            (|| -> windows::core::Result<()> {
                EmptyClipboard()?;
                let g = GlobalAlloc(GMEM_MOVEABLE, wide.len() * 2)?;
                let p = GlobalLock(g) as *mut u16;
                if p.is_null() {
                    let _ = GlobalFree(Some(g));
                    return Err(windows::core::Error::from_thread());
                }
                std::ptr::copy_nonoverlapping(wide.as_ptr(), p, wide.len());
                let _ = GlobalUnlock(g);
                if let Err(e) = SetClipboardData(CF_UNICODETEXT, Some(HANDLE(g.0))) {
                    let _ = GlobalFree(Some(g));
                    return Err(e);
                }
                Ok(())
            })()
        };
        unsafe {
            let _ = CloseClipboard();
        }
        r.map_err(|e| e.to_string())
    }

    unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
        if msg == WM_CLIPBOARDUPDATE {
            // Chờ app nguồn ghi xong mọi định dạng.
            std::thread::sleep(std::time::Duration::from_millis(30));
            if let Some(text) = read_text() {
                if let Some(cb) = CALLBACK.get() {
                    if let Ok(cb) = cb.lock() {
                        cb(text);
                    }
                }
            }
            return LRESULT(0);
        }
        DefWindowProcW(hwnd, msg, wp, lp)
    }

    pub fn listen(cb: impl Fn(String) + Send + 'static) {
        let _ = CALLBACK.set(Mutex::new(Box::new(cb)));
        std::thread::spawn(|| unsafe {
            let Ok(hinst) = GetModuleHandleW(None) else { return };
            let class = w!("MacHubClipboardListener");
            let wc = WNDCLASSW { lpfnWndProc: Some(wndproc), hInstance: hinst.into(), lpszClassName: class, ..Default::default() };
            RegisterClassW(&wc);
            let Ok(hwnd) = CreateWindowExW(
                WINDOW_EX_STYLE(0),
                class,
                PCWSTR::null(),
                WINDOW_STYLE(0),
                0,
                0,
                0,
                0,
                Some(HWND_MESSAGE),
                None,
                Some(hinst.into()),
                None,
            ) else {
                return;
            };
            if AddClipboardFormatListener(hwnd).is_err() {
                return;
            }
            let mut msg = MSG::default();
            while GetMessageW(&mut msg, None, 0, 0).as_bool() {
                let _ = TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }
        });
    }

    pub fn protect(plain: &[u8]) -> Option<Vec<u8>> {
        unsafe {
            let input = CRYPT_INTEGER_BLOB { cbData: plain.len() as u32, pbData: plain.as_ptr() as *mut u8 };
            let mut out = CRYPT_INTEGER_BLOB::default();
            CryptProtectData(&input, w!("MacHub clipboard"), None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out).ok()?;
            let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
            let _ = LocalFree(Some(HLOCAL(out.pbData as *mut _)));
            Some(v)
        }
    }

    pub fn unprotect(enc: &[u8]) -> Option<Vec<u8>> {
        unsafe {
            let input = CRYPT_INTEGER_BLOB { cbData: enc.len() as u32, pbData: enc.as_ptr() as *mut u8 };
            let mut out = CRYPT_INTEGER_BLOB::default();
            CryptUnprotectData(&input, None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out).ok()?;
            let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
            let _ = LocalFree(Some(HLOCAL(out.pbData as *mut _)));
            Some(v)
        }
    }
}

#[cfg(not(windows))]
mod platform {
    pub fn set_text(_: &str) -> Result<(), String> {
        Err("Chỉ hỗ trợ Windows".into())
    }
    pub fn listen(_: impl Fn(String) + Send + 'static) {}
    pub fn protect(_: &[u8]) -> Option<Vec<u8>> {
        None
    }
    pub fn unprotect(_: &[u8]) -> Option<Vec<u8>> {
        None
    }
}
