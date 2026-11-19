// SPDX-License-Identifier: GPL-3.0-only
import { useEffect, useRef, useState } from "react";
import { api, Display, Layout } from "../api";

export default function WindowsTab() {
  const [layouts, setLayouts] = useState<Layout[]>([]);
  const [displays, setDisplays] = useState<Display[] | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const timers = useRef<Record<string, number>>({});

  const loadDisplays = () => api.displayList().then(setDisplays).catch(() => setDisplays([]));

  useEffect(() => {
    api.snapLayouts().then(setLayouts);
    loadDisplays();
  }, []);

  // DDC/CI chậm (~50 ms/lệnh) → gửi giá trị cuối sau khi ngừng kéo 150 ms.
  const setBrightness = (d: Display, value: number) => {
    setDisplays((ds) => ds?.map((x) => (x.id === d.id ? { ...x, brightness: value } : x)) ?? null);
    clearTimeout(timers.current[d.id]);
    timers.current[d.id] = window.setTimeout(() => {
      api.displaySetBrightness(d.id, value).catch((e) => setMsg(String(e)));
    }, 150);
  };

  return (
    <div className="stack">
      <section className="card">
        <div className="card-title">Chia cửa sổ</div>
        <div className="tiny muted">Dùng phím tắt khi đang ở cửa sổ cần chia, hoặc bấm nút (áp dụng cho cửa sổ phía sau MacHub).</div>
        <div className="grid">
          {layouts.map((l) => (
            <button key={l.id} className="snap" onClick={() => api.snapApply(l.id).catch((e) => setMsg(String(e)))}>
              <span>{l.label}</span>
              <span className="kbd">{l.keys}</span>
            </button>
          ))}
        </div>
        <div className="tiny muted">Ctrl+Shift+V: lịch sử clipboard · Ctrl+Alt+M: mở/ẩn MacHub</div>
      </section>

      <section className="card">
        <div className="row between">
          <div className="card-title">Độ sáng màn hình ngoài (DDC/CI)</div>
          <button className="btn small" onClick={loadDisplays}>
            Tải lại
          </button>
        </div>
        {displays === null && <div className="muted small">Đang dò màn hình…</div>}
        {displays?.length === 0 && <div className="muted small">Không tìm thấy màn hình.</div>}
        {displays?.map((d) => (
          <div key={d.id} className="display">
            <div className="row between small">
              <span>
                <strong>{d.name}</strong> {d.primary && <span className="muted">· chính</span>}
              </span>
              <span className="muted">
                {d.width}×{d.height}
              </span>
            </div>
            {d.brightness == null ? (
              <div className="tiny muted">Màn này không hỗ trợ DDC/CI (màn laptop chỉnh bằng phím Fn / Windows).</div>
            ) : (
              <div className="row gap">
                <input
                  type="range"
                  min={0}
                  max={d.maxBrightness}
                  value={d.brightness}
                  onChange={(e) => setBrightness(d, Number(e.target.value))}
                  aria-label={`Độ sáng ${d.name}`}
                />
                <span className="small num">{Math.round((d.brightness / d.maxBrightness) * 100)}%</span>
              </div>
            )}
          </div>
        ))}
      </section>
      {msg && <div className="tiny warn-text">{msg}</div>}
    </div>
  );
}
