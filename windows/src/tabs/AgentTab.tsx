// SPDX-License-Identifier: GPL-3.0-only
import { useCallback, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { AgentView, api, ago, countdown, LimitSnapshot, Session, tokens, usd } from "../api";

const STATE_LABEL: Record<Session["state"], string> = {
  idle: "Chờ",
  running: "Đang chạy",
  waitingApproval: "Chờ duyệt",
  waitingInput: "Chờ trả lời",
  subagentDone: "Subagent xong",
  finished: "Xong",
  ended: "Đã đóng",
};

function Limits({ title, snap }: { title: string; snap?: LimitSnapshot | null }) {
  if (!snap || snap.windows.length === 0)
    return (
      <div className="card">
        <div className="card-title">{title}</div>
        <div className="muted small">Chưa có số liệu hạn mức.</div>
      </div>
    );
  return (
    <div className="card">
      <div className="card-title">
        {title} <span className="muted small">· {snap.source} · {ago(snap.observedAt)}</span>
      </div>
      {snap.windows.map((w) => (
        <div key={w.id} className="limit">
          <div className="row between small">
            <span>{w.label}</span>
            <span>
              <strong>{Math.round(w.usedPercent)}%</strong>
              {w.resetsAt && <span className="muted"> · đặt lại sau {countdown(w.resetsAt)}</span>}
            </span>
          </div>
          <div className="bar">
            <div className={w.usedPercent >= 90 ? "fill hot" : w.usedPercent >= 70 ? "fill warm" : "fill"} style={{ width: `${Math.min(100, w.usedPercent)}%` }} />
          </div>
        </div>
      ))}
    </div>
  );
}

export default function AgentTab() {
  const [v, setV] = useState<AgentView | null>(null);
  const [error, setError] = useState<string | null>(null);
  const load = useCallback(
    () =>
      api
        .agentView()
        .then((x) => {
          setV(x);
          setError(null);
        })
        .catch((e) => setError(String(e))),
    [],
  );

  useEffect(() => {
    load();
    const un = listen("agent-updated", load);
    return () => {
      un.then((f) => f());
    };
  }, [load]);

  if (error) return <div className="card warn">{error}</div>;
  if (!v) return <div className="muted">Đang tải…</div>;

  const s = v.settings;
  const totals = Object.entries(v.summary.byProvider);

  return (
    <div className="stack">
      {v.serverError && <div className="card warn">{v.serverError}</div>}
      {v.approvals.length > 0 && (
        <div className="card accent">
          <strong>{v.approvals.length} yêu cầu chờ duyệt</strong> — xem cửa sổ góc dưới phải màn hình.
        </div>
      )}

      <section>
        <div className="row between">
          <h3>Phiên ({v.running} đang hoạt động)</h3>
          <button className="btn small" onClick={() => api.agentRescan()}>
            Quét lại
          </button>
        </div>
        {v.sessions.length === 0 && <div className="muted small">Chưa có phiên nào trong 12 giờ qua.</div>}
        {v.sessions.slice(0, 12).map((x) => (
          <div key={x.id} className={x.active ? "session active" : "session"}>
            <div className="row between">
              <span>
                <span className={`badge ${x.provider}`}>{x.provider === "claude" ? "Claude" : "Codex"}</span>{" "}
                <strong>{x.title || x.repo || x.id.split(":")[1]?.slice(0, 8)}</strong>
                {x.branch && <span className="muted small"> · {x.branch}</span>}
              </span>
              <span className={`state ${x.state}`}>
                {STATE_LABEL[x.state]}
                {x.runningSubagents > 0 ? ` · ${x.runningSubagents} subagent` : ""}
              </span>
            </div>
            {(x.lastMessage || x.lastPrompt) && <div className="muted small clamp">{x.lastMessage || x.lastPrompt}</div>}
            <div className="muted tiny">
              {x.model ?? ""} · {ago(x.updatedAt)}
            </div>
          </div>
        ))}
      </section>

      <Limits title="Claude" snap={v.claudeLimits} />
      <Limits title="Codex" snap={v.codexLimits} />

      <section className="card">
        <div className="row between">
          <div className="card-title">Token & chi phí</div>
          <div className="seg">
            {(["today", "week", "month"] as const).map((r) => (
              <button key={r} className={v.range === r ? "on" : ""} onClick={() => api.agentSetRange(r)}>
                {r === "today" ? "Hôm nay" : r === "week" ? "7 ngày" : "30 ngày"}
              </button>
            ))}
          </div>
        </div>
        {totals.length === 0 && <div className="muted small">Chưa có dữ liệu.</div>}
        {totals.map(([p, t]) => (
          <div key={p} className="row between small">
            <span>{p === "claude" ? "Claude" : "Codex"}</span>
            <span>
              {tokens(t!.total)} token · {usd(t!.costUsd)}
              {t!.hasEstimate ? " (ước tính)" : ""}
            </span>
          </div>
        ))}
        {v.summary.byModel.slice(0, 5).map((r) => (
          <div key={r.provider + r.name} className="row between tiny muted">
            <span>{r.name}</span>
            <span>
              {tokens(r.totals.total)} · {usd(r.totals.costUsd)}
            </span>
          </div>
        ))}
        <div className="tiny muted">Chi phí tính theo bảng giá API công khai, có thể khác hóa đơn gói thuê bao.</div>
      </section>

      <section className="card">
        <div className="card-title">Thiết lập Claude Code</div>
        <div className="small">
          Hook: {v.hookState.installed ? "đã cài" : "chưa cài"}
          {v.hookState.installed && ` (theo dõi ${v.hookState.observe ? "✓" : "✗"}, duyệt quyền ${v.hookState.approvals ? "✓" : "✗"}, statusLine ${v.hookState.statusLine ? "✓" : "✗"})`}
        </div>
        <div className="row gap wrap">
          <button className="btn primary small" onClick={() => api.agentInstall(true)}>
            {v.hookState.installed ? "Cài lại" : "Cài hook"}
          </button>
          {v.hookState.installed && (
            <button className="btn small" onClick={() => api.agentUninstall()}>
              Gỡ hook
            </button>
          )}
        </div>
        {v.setupMessage && <div className="tiny muted">{v.setupMessage}</div>}
        <label className="check">
          <input type="checkbox" checked={s.approvalsEnabled} onChange={(e) => api.agentSettings({ ...s, approvalsEnabled: e.target.checked })} />
          Duyệt quyền từ MacHub (tắt → luôn hỏi trong terminal)
        </label>
        <label className="check">
          Hết giờ chờ duyệt:
          <select value={s.approvalTimeout} onChange={(e) => api.agentSettings({ ...s, approvalTimeout: Number(e.target.value) })}>
            {[30, 60, 120, 180, 300].map((n) => (
              <option key={n} value={n}>
                {n} giây
              </option>
            ))}
          </select>
        </label>
        <label className="check">
          <input type="checkbox" checked={s.oauthEnabled} onChange={(e) => api.agentSettings({ ...s, oauthEnabled: e.target.checked })} />
          Lấy hạn mức Claude qua OAuth (endpoint không chính thức, 5 phút/lần)
        </label>
        {v.oauthError && <div className="tiny warn-text">{v.oauthError}</div>}
      </section>
    </div>
  );
}
