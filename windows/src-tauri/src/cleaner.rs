// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Dọn rác an toàn: chỉ vài thư mục tạm/cache đã biết, KHÔNG theo symlink/junction,
//! bỏ qua file đang bị khóa, chỉ xóa file cũ hơn 1 giờ để không phá app đang chạy.

use serde::Serialize;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Category {
    pub id: &'static str,
    pub label: &'static str,
    pub description: &'static str,
    pub bytes: u64,
    pub files: u64,
}

struct Def {
    id: &'static str,
    label: &'static str,
    description: &'static str,
    roots: fn() -> Vec<PathBuf>,
}

fn env(k: &str) -> Option<PathBuf> {
    std::env::var_os(k).map(PathBuf::from)
}

fn local() -> Option<PathBuf> {
    env("LOCALAPPDATA")
}

const DEFS: &[Def] = &[
    Def { id: "user-temp", label: "File tạm của bạn", description: "%TEMP% — file tạm app để lại.", roots: || env("TEMP").into_iter().collect() },
    Def {
        id: "thumbnails",
        label: "Bộ đệm ảnh thu nhỏ",
        description: "thumbcache_*.db của Explorer (tự tạo lại).",
        roots: || local().map(|l| l.join("Microsoft\\Windows\\Explorer")).into_iter().collect(),
    },
    Def {
        id: "crash-dumps",
        label: "Báo cáo lỗi & crash dump",
        description: "CrashDumps và WER của tài khoản.",
        roots: || {
            local()
                .map(|l| vec![l.join("CrashDumps"), l.join("Microsoft\\Windows\\WER\\ReportArchive"), l.join("Microsoft\\Windows\\WER\\ReportQueue")])
                .unwrap_or_default()
        },
    },
    Def {
        id: "browser-cache",
        label: "Cache trình duyệt",
        description: "Cache Chrome / Edge / Brave (không đụng cookie, mật khẩu, lịch sử).",
        roots: || {
            let Some(l) = local() else { return vec![] };
            let mut v = Vec::new();
            for b in ["Google\\Chrome", "Microsoft\\Edge", "BraveSoftware\\Brave-Browser"] {
                let ud = l.join(b).join("User Data");
                let Ok(rd) = std::fs::read_dir(&ud) else { continue };
                for p in rd.flatten() {
                    let n = p.file_name().to_string_lossy().into_owned();
                    if n == "Default" || n.starts_with("Profile ") {
                        v.push(p.path().join("Cache"));
                        v.push(p.path().join("Code Cache"));
                        v.push(p.path().join("GPUCache"));
                    }
                }
            }
            v
        },
    },
    Def {
        id: "dev-cache",
        label: "Cache công cụ lập trình",
        description: "npm-cache, pip cache, Yarn cache.",
        roots: || {
            let mut v = Vec::new();
            if let Some(a) = env("APPDATA") {
                v.push(a.join("npm-cache"));
            }
            if let Some(l) = local() {
                v.push(l.join("npm-cache"));
                v.push(l.join("pip\\Cache"));
                v.push(l.join("Yarn\\Cache"));
            }
            v
        },
    },
];

const MIN_AGE: Duration = Duration::from_secs(3600);

fn is_reparse(m: &std::fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        m.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0
    }
    #[cfg(not(windows))]
    {
        m.file_type().is_symlink()
    }
}

fn eligible(id: &str, p: &Path, m: &std::fs::Metadata, now: SystemTime) -> bool {
    if id == "thumbnails" && !p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("thumbcache_")) {
        return false;
    }
    m.modified().ok().and_then(|t| now.duration_since(t).ok()).is_some_and(|age| age >= MIN_AGE)
}

/// Duyệt cây, không theo reparse point. `act` trả về true nếu file được tính.
fn walk(dir: &Path, depth: usize, f: &mut dyn FnMut(&Path, &std::fs::Metadata)) {
    if depth > 32 {
        return;
    }
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        let Ok(m) = std::fs::symlink_metadata(&p) else { continue };
        if is_reparse(&m) {
            continue;
        }
        if m.is_dir() {
            walk(&p, depth + 1, f);
        } else if m.is_file() {
            f(&p, &m);
        }
    }
}

fn roots_of(d: &Def) -> Vec<PathBuf> {
    (d.roots)()
        .into_iter()
        .filter(|r| std::fs::symlink_metadata(r).is_ok_and(|m| m.is_dir() && !is_reparse(&m)))
        .collect()
}

pub fn scan() -> Vec<Category> {
    let now = SystemTime::now();
    DEFS.iter()
        .map(|d| {
            let (mut bytes, mut files) = (0u64, 0u64);
            for r in roots_of(d) {
                walk(&r, 0, &mut |p, m| {
                    if eligible(d.id, p, m, now) {
                        bytes += m.len();
                        files += 1;
                    }
                });
            }
            Category { id: d.id, label: d.label, description: d.description, bytes, files }
        })
        .collect()
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanResult {
    pub freed: u64,
    pub removed: u64,
    pub skipped: u64,
}

pub fn clean(ids: &[String]) -> CleanResult {
    let now = SystemTime::now();
    let mut res = CleanResult { freed: 0, removed: 0, skipped: 0 };
    for d in DEFS.iter().filter(|d| ids.iter().any(|i| i == d.id)) {
        for r in roots_of(d) {
            walk(&r, 0, &mut |p, m| {
                if !eligible(d.id, p, m, now) {
                    return;
                }
                match std::fs::remove_file(p) {
                    Ok(_) => {
                        res.freed += m.len();
                        res.removed += 1;
                    }
                    Err(_) => res.skipped += 1, // đang bị khóa / không có quyền
                }
            });
            remove_empty_dirs(&r, 0);
        }
    }
    res
}

fn remove_empty_dirs(dir: &Path, depth: usize) {
    if depth > 32 {
        return;
    }
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if std::fs::symlink_metadata(&p).is_ok_and(|m| m.is_dir() && !is_reparse(&m)) {
            remove_empty_dirs(&p, depth + 1);
            let _ = std::fs::remove_dir(&p); // chỉ thành công khi rỗng
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_old_files_are_eligible() {
        let dir = tempfile::tempdir().unwrap();
        let f = dir.path().join("a.tmp");
        std::fs::write(&f, b"x").unwrap();
        let m = std::fs::metadata(&f).unwrap();
        assert!(!eligible("user-temp", &f, &m, SystemTime::now()), "file mới không được xóa");
        assert!(eligible("user-temp", &f, &m, SystemTime::now() + Duration::from_secs(7200)));
        assert!(!eligible("thumbnails", &f, &m, SystemTime::now() + Duration::from_secs(7200)), "chỉ thumbcache_*");
    }

    #[cfg(unix)]
    #[test]
    fn walk_does_not_follow_links() {
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(outside.path().join("keep.txt"), b"x").unwrap();
        let root = tempfile::tempdir().unwrap();
        std::os::unix::fs::symlink(outside.path(), root.path().join("link")).unwrap();
        let mut seen = 0;
        walk(root.path(), 0, &mut |_, _| seen += 1);
        assert_eq!(seen, 0);
    }
}
