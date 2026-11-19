// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Độ sáng màn hình ngoài qua DDC/CI (VCP 0x10). Màn laptop dùng WMI nên không nằm ở đây.

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Display {
    /// Chỉ số ổn định trong một lần liệt kê: "<monitor>-<physical>".
    pub id: String,
    pub name: String,
    pub primary: bool,
    pub width: i32,
    pub height: i32,
    /// None khi màn không hỗ trợ DDC/CI.
    pub brightness: Option<u32>,
    pub max_brightness: u32,
}

#[cfg(windows)]
mod platform {
    use super::Display;
    use windows::Win32::Devices::Display::{
        DestroyPhysicalMonitors, GetNumberOfPhysicalMonitorsFromHMONITOR, GetPhysicalMonitorsFromHMONITOR,
        GetVCPFeatureAndVCPFeatureReply, SetVCPFeature, PHYSICAL_MONITOR,
    };
    use windows::Win32::Foundation::{LPARAM, RECT};
    use windows::Win32::Graphics::Gdi::{EnumDisplayMonitors, GetMonitorInfoW, HDC, HMONITOR, MONITORINFO};

    const VCP_BRIGHTNESS: u8 = 0x10;
    const MONITORINFOF_PRIMARY: u32 = 1;

    fn monitors() -> Vec<HMONITOR> {
        unsafe extern "system" fn cb(m: HMONITOR, _: HDC, _: *mut RECT, lp: LPARAM) -> windows::core::BOOL {
            (*(lp.0 as *mut Vec<HMONITOR>)).push(m);
            true.into()
        }
        let mut v: Vec<HMONITOR> = Vec::new();
        unsafe {
            let _ = EnumDisplayMonitors(None, None, Some(cb), LPARAM(&mut v as *mut _ as isize));
        }
        v
    }

    fn physical(m: HMONITOR) -> Vec<PHYSICAL_MONITOR> {
        unsafe {
            let mut n = 0u32;
            if GetNumberOfPhysicalMonitorsFromHMONITOR(m, &mut n).is_err() || n == 0 {
                return Vec::new();
            }
            let mut v = vec![PHYSICAL_MONITOR::default(); n as usize];
            if GetPhysicalMonitorsFromHMONITOR(m, &mut v).is_err() {
                return Vec::new();
            }
            v
        }
    }

    fn release(v: &[PHYSICAL_MONITOR]) {
        if !v.is_empty() {
            unsafe {
                let _ = DestroyPhysicalMonitors(v);
            }
        }
    }

    pub fn list() -> Vec<Display> {
        let mut out = Vec::new();
        for (mi, m) in monitors().into_iter().enumerate() {
            let mut info = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
            unsafe {
                let _ = GetMonitorInfoW(m, &mut info);
            }
            let r = info.rcMonitor;
            let phys = physical(m);
            for (pi, p) in phys.iter().enumerate() {
                let (mut cur, mut max) = (0u32, 0u32);
                let ok = unsafe { GetVCPFeatureAndVCPFeatureReply(p.hPhysicalMonitor, VCP_BRIGHTNESS, None, &mut cur, Some(&mut max)) } != 0;
                let desc = { let d = p.szPhysicalMonitorDescription; String::from_utf16_lossy(&d) };
                let name = desc.trim_end_matches('\0').trim().to_string();
                out.push(Display {
                    id: format!("{mi}-{pi}"),
                    name: if name.is_empty() { format!("Màn hình {}", mi + 1) } else { name },
                    primary: info.dwFlags & MONITORINFOF_PRIMARY != 0,
                    width: r.right - r.left,
                    height: r.bottom - r.top,
                    brightness: (ok && max > 0).then_some(cur),
                    max_brightness: if ok && max > 0 { max } else { 100 },
                });
            }
            release(&phys);
        }
        out
    }

    pub fn set_brightness(id: &str, value: u32) -> Result<(), String> {
        let (mi, pi) = id.split_once('-').and_then(|(a, b)| Some((a.parse::<usize>().ok()?, b.parse::<usize>().ok()?))).ok_or("Mã màn hình không hợp lệ.")?;
        let m = *monitors().get(mi).ok_or("Màn hình đã thay đổi — tải lại danh sách.")?;
        let phys = physical(m);
        let r = match phys.get(pi) {
            Some(p) => {
                let (mut cur, mut max) = (0u32, 0u32);
                let _ = unsafe { GetVCPFeatureAndVCPFeatureReply(p.hPhysicalMonitor, VCP_BRIGHTNESS, None, &mut cur, Some(&mut max)) };
                let v = value.min(if max > 0 { max } else { 100 });
                if unsafe { SetVCPFeature(p.hPhysicalMonitor, VCP_BRIGHTNESS, v) } != 0 {
                    Ok(())
                } else {
                    Err("Màn hình không nhận lệnh DDC/CI (kiểm tra bật DDC/CI trong menu màn hình).".into())
                }
            }
            None => Err("Màn hình đã thay đổi — tải lại danh sách.".into()),
        };
        release(&phys);
        r
    }
}

#[cfg(not(windows))]
mod platform {
    use super::Display;
    pub fn list() -> Vec<Display> {
        Vec::new()
    }
    pub fn set_brightness(_: &str, _: u32) -> Result<(), String> {
        Err("Chỉ hỗ trợ Windows".into())
    }
}

pub use platform::{list, set_brightness};
