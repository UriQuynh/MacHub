// SPDX-License-Identifier: GPL-3.0-only
import { useCallback, useEffect, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { ago, api, ClipItem } from "../api";

export default function ClipboardTab() {
  const [q, setQ] = useState("");
  const [items, setItems] = useState<ClipItem[]>([]);
  const [sel, setSel] = useState(0);
  const [confirmClear, setConfirmClear] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const input = useRef<HTMLInputElement>(null);

  const load = useCallback(() => api.clipList(q).then(setItems).catch(() => {}), [q]);

  useEffect(() => {
    load();
    const un = listen("clipboard-updated", load);
    return () => {
      un.then((f) => f());
    };
  }, [load]);

  useEffect(() => {
    input.current?.focus();
    const un = listen("select-tab", () => {
      setQ("");
      setSel(0);
      input.current?.focus();
    });
    return () => {
      un.then((f) => f());
    };
  }, []);

  useEffect(() => setSel(0), [q]);

  const use = (it: ClipItem, paste: boolean) =>
    api
      .clipUse(it.id, paste)
      .then(() => !paste && setMsg("Đã chép."))
      .catch((e) => setMsg(String(e)));

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === "ArrowDown") {
      setSel((s) => Math.min(items.length - 1, s + 1));
      e.preventDefault();
    } else if (e.key === "ArrowUp") {
      setSel((s) => Math.max(0, s - 1));
      e.preventDefault();
    } else if (e.key === "Enter" && items[sel]) {
      use(items[sel], true);
    } else if (!q && /^[1-9]$/.test(e.key) && items[Number(e.key) - 1]) {
      use(items[Number(e.key) - 1], true);
      e.preventDefault();
    }
  };

  const clear = () => {
    if (!confirmClear) {
      setConfirmClear(true);
      setTimeout(() => setConfirmClear(false), 4000);
      return;
    }
    setConfirmClear(false);
    api.clipClear().then((n) => {
      setMsg(`Đã xóa ${n} mục chưa ghim.`);
      load();
    });
  };

  return (
    <div className="stack" onKeyDown={onKey}>
      <input ref={input} className="search" placeholder="Tìm trong lịch sử…  (↑↓ chọn, Enter dán, 1–9 dán nhanh)" value={q} onChange={(e) => setQ(e.target.value)} />
      <div className="row between tiny muted">
        <span>{items.length} mục · lưu mã hóa DPAPI, bỏ qua nội dung app đánh dấu riêng tư</span>
        <button className="btn small" onClick={clear}>
          {confirmClear ? "Bấm lần nữa để xóa" : "Xóa chưa ghim"}
        </button>
      </div>
      {msg && <div className="tiny muted">{msg}</div>}
      {items.length === 0 && <div className="muted small">Chưa có gì. Chép (Ctrl+C) một đoạn văn bản bất kỳ.</div>}
      <ul className="clips">
        {items.map((it, i) => (
          <li key={it.id} className={i === sel ? "clip sel" : "clip"} onMouseEnter={() => setSel(i)} onDoubleClick={() => use(it, true)}>
            <div className="clip-text">
              {!q && i < 9 && <span className="kbd">{i + 1}</span>}
              {it.text.length > 400 ? it.text.slice(0, 400) + "…" : it.text}
            </div>
            <div className="row between tiny muted">
              <span>
                {it.pinned ? "📌 " : ""}
                {ago(it.copiedAt)} · {it.text.length} ký tự
              </span>
              <span className="row gap">
                <button className="link" onClick={() => use(it, false)}>
                  Chép
                </button>
                <button className="link" onClick={() => api.clipPin(it.id, !it.pinned).then(load)}>
                  {it.pinned ? "Bỏ ghim" : "Ghim"}
                </button>
                <button className="link" onClick={() => api.clipDelete(it.id).then(load)}>
                  Xóa
                </button>
              </span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
