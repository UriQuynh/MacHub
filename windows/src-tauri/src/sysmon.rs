// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! Theo dõi hệ thống: CPU, RAM, ổ đĩa, mạng, tiến trình ăn tài nguyên.

use serde::Serialize;
use std::sync::Mutex;
use std::time::Instant;
use sysinfo::{Disks, Networks, ProcessRefreshKind, ProcessesToUpdate, System};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiskInfo {
    pub mount: String,
    pub total: u64,
    pub available: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcInfo {
    pub pid: u32,
    pub name: String,
    pub cpu: f32,
    pub memory: u64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub cpu: f32,
    pub cores: usize,
    pub memory_used: u64,
    pub memory_total: u64,
    pub swap_used: u64,
    pub swap_total: u64,
    pub disks: Vec<DiskInfo>,
    pub net_rx_per_sec: u64,
    pub net_tx_per_sec: u64,
    pub uptime: u64,
    pub top: Vec<ProcInfo>,
}

#[derive(Default)]
pub struct Monitor {
    state: Mutex<Option<(System, Networks, Instant)>>,
}

impl Monitor {
    pub fn snapshot(&self) -> Result<Snapshot, String> {
        let mut g = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if g.is_none() {
            let mut sys = System::new().map_err(|e| e.to_string())?;
            sys.refresh_cpu_usage();
            let nets = Networks::new_with_refreshed_list().map_err(|e| e.to_string())?;
            *g = Some((sys, nets, Instant::now()));
        }
        let Some((sys, nets, last)) = g.as_mut() else { unreachable!() };
        sys.refresh_cpu_usage();
        sys.refresh_memory();
        sys.refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing().with_cpu().with_memory());
        nets.refresh(true);
        let secs = last.elapsed().as_secs_f64().max(0.5);
        *last = Instant::now();
        let (rx, tx) = nets.values().fold((0u64, 0u64), |(r, t), n| (r + n.received(), t + n.transmitted()));
        let cores = sys.cpus().len().max(1);
        let mut top: Vec<ProcInfo> = sys
            .processes()
            .values()
            .map(|p| ProcInfo {
                pid: p.pid().as_u32(),
                name: p.name().to_string_lossy().into_owned(),
                cpu: p.cpu_usage() / cores as f32,
                memory: p.memory(),
            })
            .collect();
        top.sort_by(|a, b| b.cpu.partial_cmp(&a.cpu).unwrap_or(std::cmp::Ordering::Equal).then(b.memory.cmp(&a.memory)));
        top.truncate(8);
        let disks = Disks::new_with_refreshed_list()
            .map(|d| d.iter()
            .map(|d| DiskInfo { mount: d.mount_point().to_string_lossy().into_owned(), total: d.total_space(), available: d.available_space() })
            .filter(|d| d.total > 0)
            .collect::<Vec<_>>())
            .unwrap_or_default();
        Ok(Snapshot {
            cpu: sys.global_cpu_usage(),
            cores,
            memory_used: sys.used_memory(),
            memory_total: sys.total_memory(),
            swap_used: sys.used_swap(),
            swap_total: sys.total_swap(),
            disks,
            net_rx_per_sec: (rx as f64 / secs) as u64,
            net_tx_per_sec: (tx as f64 / secs) as u64,
            uptime: System::uptime().unwrap_or(0),
            top,
        })
    }
}
