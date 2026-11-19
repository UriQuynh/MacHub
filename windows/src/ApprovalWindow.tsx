// SPDX-License-Identifier: GPL-3.0-only
// Cửa sổ nổi góc màn hình khi Claude Code xin quyền dùng công cụ.
// KHÔNG có phím tắt "Cho phép": phải bấm chuột, tránh vô tình duyệt khi đang gõ.
import { useCallback, useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { api, ago, Approval } from "./api";

export default function ApprovalWindow() {
  const [items, setItems] = useState<Approval[]>([]);
  const load = useCallback(() => api.agentView().then((v) => setItems(v.approvals)).catch(() => {}), []);

  useEffect(() => {
    load();
    const un = listen("agent-updated", load);
    const t = setInterval(load, 5000);
    return () => {
      un.then((f) => f());
      clearInterval(t);
    };
  }, [load]);

  const a = items[0];
  if (!a) return <div className="approval empty">Không có yêu cầu nào.</div>;

  const respond = (d: "allow" | "always" | "deny" | "terminal") => api.agentRespond(a.id, d).then(load);

  return (
    <div className="approval">
      <div className="approval-head" data-tauri-drag-region>
        <strong>Claude Code xin quyền</strong>
        <span className="muted small">
          {a.project ? `${a.project} · ` : ""}
          {ago(a.createdAt)}
          {items.length > 1 ? ` · còn ${items.length - 1} yêu cầu` : ""}
        </span>
      </div>
      <div className="tool-name">{a.toolName}</div>
      <pre className="tool-summary">{a.summary}</pre>
      {a.detail && <div className="muted small">{a.detail}</div>}
      <div className="row gap wrap">
        <button className="btn primary" onClick={() => respond("allow")}>
          Cho phép lần này
        </button>
        {a.canAlwaysAllow && (
          <button className="btn" onClick={() => respond("always")}>
            Luôn cho phép
          </button>
        )}
        <button className="btn" onClick={() => respond("deny")}>
          Từ chối
        </button>
        <button className="btn ghost" onClick={() => respond("terminal")}>
          Hỏi trong terminal
        </button>
      </div>
    </div>
  );
}
