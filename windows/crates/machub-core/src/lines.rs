// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

/// Đọc file JSONL theo phần mới ghi thêm, giữ lại dòng dở dang ở cuối.
#[derive(Debug, Default, Clone)]
pub struct IncrementalLineReader {
    pub offset: u64,
    remainder: Vec<u8>,
}

impl IncrementalLineReader {
    /// Các dòng hoàn chỉnh mới kể từ lần đọc trước. File bị ghi đè ngắn hơn → đọc lại từ đầu.
    pub fn read_new_lines(&mut self, path: &Path, max_bytes: u64) -> Vec<String> {
        let Ok(mut f) = File::open(path) else { return vec![] };
        let Ok(size) = f.seek(SeekFrom::End(0)) else { return vec![] };
        if size < self.offset {
            self.offset = 0;
            self.remainder.clear();
        }
        if size == self.offset || f.seek(SeekFrom::Start(self.offset)).is_err() {
            return vec![];
        }
        let mut buf = Vec::new();
        if f.take(max_bytes.min(size - self.offset)).read_to_end(&mut buf).is_err() || buf.is_empty() {
            return vec![];
        }
        self.offset += buf.len() as u64;

        let mut chunk = std::mem::take(&mut self.remainder);
        chunk.extend_from_slice(&buf);
        let mut lines = Vec::new();
        let mut start = 0;
        while let Some(pos) = chunk[start..].iter().position(|&b| b == b'\n') {
            let end = start + pos;
            let mut line = &chunk[start..end];
            if line.last() == Some(&b'\r') {
                line = &line[..line.len() - 1];
            }
            if !line.is_empty() {
                lines.push(String::from_utf8_lossy(line).into_owned());
            }
            start = end + 1;
        }
        self.remainder = chunk[start..].to_vec();
        lines
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[test]
    fn keeps_partial_line_and_handles_truncation() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("a.jsonl");
        std::fs::write(&p, "a\r\nb\npart").unwrap();
        let mut r = IncrementalLineReader::default();
        assert_eq!(r.read_new_lines(&p, u64::MAX), ["a", "b"]);
        std::fs::OpenOptions::new().append(true).open(&p).unwrap().write_all(b"ial\nc\n").unwrap();
        assert_eq!(r.read_new_lines(&p, u64::MAX), ["partial", "c"]);
        assert!(r.read_new_lines(&p, u64::MAX).is_empty());
        std::fs::write(&p, "z\n").unwrap();
        assert_eq!(r.read_new_lines(&p, u64::MAX), ["z"]);
    }
}
