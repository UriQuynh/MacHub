// SPDX-License-Identifier: GPL-3.0-only
// Kiểu dữ liệu + lời gọi tới phần Rust.

import { invoke } from "@tauri-apps/api/core";

export type Provider = "claude" | "codex";

export interface LimitWindow {
  id: string;
  label: string;
  usedPercent: number;
  resetsAt?: string | null;
  windowMinutes?: number | null;
}
export interface LimitSnapshot {
  provider: Provider;
  windows: LimitWindow[];
  observedAt: string;
  source: string;
  plan?: string | null;
}
export interface Totals {
  input: number;
  output: number;
  cacheWrite: number;
  cacheRead: number;
  requests: number;
  costUsd: number;
  hasEstimate: boolean;
  unpricedTokens: number;
  total: number;
}
export interface Row {
  provider: Provider;
  name: string;
  totals: Totals;
}
export interface Summary {
  byProvider: Partial<Record<Provider, Totals>>;
  byModel: Row[];
  byProject: Row[];
}
export interface Session {
  id: string;
  provider: Provider;
  title?: string | null;
  cwd?: string | null;
  repo?: string | null;
  branch?: string | null;
  model?: string | null;
  state: "idle" | "running" | "waitingApproval" | "waitingInput" | "subagentDone" | "finished" | "ended";
  active: boolean;
  lastPrompt?: string | null;
  lastMessage?: string | null;
  updatedAt: string;
  runningSubagents: number;
}
export interface Approval {
  id: number;
  toolName: string;
  summary: string;
  detail?: string | null;
  project?: string | null;
  canAlwaysAllow: boolean;
  createdAt: string;
}
export interface AgentSettings {
  approvalsEnabled: boolean;
  approvalTimeout: number;
  oauthEnabled: boolean;
}
export interface HookState {
  observe: boolean;
  approvals: boolean;
  statusLine: boolean;
  installed: boolean;
}
export interface AgentView {
  sessions: Session[];
  running: number;
  approvals: Approval[];
  claudeLimits?: LimitSnapshot | null;
  codexLimits?: LimitSnapshot | null;
  summary: Summary;
  range: "today" | "week" | "month";
  hookState: HookState;
  settings: AgentSettings;
  oauthError?: string | null;
  serverError?: string | null;
  setupMessage?: string | null;
}
export interface ClipItem {
  id: number;
  text: string;
  copiedAt: string;
  pinned: boolean;
}
export interface Layout {
  id: string;
  label: string;
  keys: string;
}
export interface Display {
  id: string;
  name: string;
  primary: boolean;
  width: number;
  height: number;
  brightness?: number | null;
  maxBrightness: number;
}
export interface Category {
  id: string;
  label: string;
  description: string;
  bytes: number;
  files: number;
}
export interface CleanResult {
  freed: number;
  removed: number;
  skipped: number;
}
export interface SysSnapshot {
  cpu: number;
  cores: number;
  memoryUsed: number;
  memoryTotal: number;
  swapUsed: number;
  swapTotal: number;
  disks: { mount: string; total: number; available: number }[];
  netRxPerSec: number;
  netTxPerSec: number;
  uptime: number;
  top: { pid: number; name: string; cpu: number; memory: number }[];
}

export const api = {
  agentView: () => invoke<AgentView>("agent_view"),
  agentSetRange: (range: string) => invoke<void>("agent_set_range", { range }),
  agentRespond: (id: number, decision: "allow" | "always" | "deny" | "terminal") =>
    invoke<boolean>("agent_respond", { id, decision }),
  agentSettings: (settings: AgentSettings) => invoke<void>("agent_settings", { settings }),
  agentInstall: (statusLine: boolean) => invoke<void>("agent_install", { statusLine }),
  agentUninstall: () => invoke<void>("agent_uninstall"),
  agentRescan: () => invoke<void>("agent_rescan"),
  clipList: (query: string) => invoke<ClipItem[]>("clip_list", { query }),
  clipPin: (id: number, pinned: boolean) => invoke<void>("clip_pin", { id, pinned }),
  clipDelete: (id: number) => invoke<void>("clip_delete", { id }),
  clipClear: () => invoke<number>("clip_clear"),
  clipUse: (id: number, paste: boolean) => invoke<void>("clip_use", { id, paste }),
  snapLayouts: () => invoke<Layout[]>("snap_layouts"),
  snapApply: (id: string) => invoke<void>("snap_apply", { id }),
  displayList: () => invoke<Display[]>("display_list"),
  displaySetBrightness: (id: string, value: number) => invoke<void>("display_set_brightness", { id, value }),
  cleanerScan: () => invoke<Category[]>("cleaner_scan"),
  cleanerClean: (ids: string[]) => invoke<CleanResult>("cleaner_clean", { ids }),
  systemSnapshot: () => invoke<SysSnapshot>("system_snapshot"),
  hideWindow: () => invoke<void>("hide_window"),
  appVersion: () => invoke<string>("app_version"),
};

// ───────────── Định dạng ─────────────

export function bytes(n: number): string {
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0;
  let v = n;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)} ${u[i]}`;
}

export function tokens(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return `${n}`;
}

export function usd(n: number): string {
  return n >= 100 ? `$${Math.round(n)}` : `$${n.toFixed(2)}`;
}

export function countdown(iso?: string | null): string {
  if (!iso) return "";
  const s = Math.max(0, Math.round((new Date(iso).getTime() - Date.now()) / 1000));
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (d > 0) return `${d}n ${h}g`;
  if (h > 0) return `${h}g ${m}p`;
  return `${m}p`;
}

export function ago(iso: string): string {
  const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  if (s < 60) return "vừa xong";
  if (s < 3600) return `${Math.floor(s / 60)} phút trước`;
  if (s < 86400) return `${Math.floor(s / 3600)} giờ trước`;
  return `${Math.floor(s / 86400)} ngày trước`;
}
