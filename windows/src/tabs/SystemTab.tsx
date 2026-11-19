// SPDX-License-Identifier: GPL-3.0-only
import { useEffect, useState } from "react";
import { api, bytes, Category, SysSnapshot } from "../api";

function Meter({ label, value, text }: { label: string; value: number; text: string }) {
  return (
    <div className="meter">
      <div className="row between small">
        <span>{label}</span>
        <span>{text}</span>
      </div>
      <div className="bar">
        <div className={value >= 90 ? "fill hot" : value >= 75 ? "fill warm" : "fill"} style={{ width: `${Math.min(100, value)}%` }} />
      </div>
    </div>
  );
}

function uptime(s: number) {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  return d > 0 ? `${d} ngày ${h} giờ` : `${h} giờ ${Math.floor((s % 3600) / 60)} phút`;
}

export default function SystemTab({ active }: { active: boolean }) {
  const [snap, setSnap] = useState<SysSnapshot | null>(null);
  const [cats, setCats] = useState<Category[] | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set(["user-temp", "thumbnails", "crash-dumps"]));
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // Lấy mẫu 2 giây/lần, chỉ khi bảng đang mở.
  useEffect(() => {
    if (!active) return;
    const tick = () => api.systemSnapshot().then(setSnap).catch(() => {});
    tick();
    const t = setInterval(tick, 2000);
    return () => clearInterval(t);
  }, [active]);

  const scan = () => {
    setCats(null);
    setMsg(null);
    api.cleanerScan().then(setCats);
  };
  useEffect(scan, []);

  const clean = async () => {
    setBusy(true);
    try {
      const r = await api.cleanerClean([...picked]);
      setMsg(`Đã giải phóng ${bytes(r.freed)} (${r.removed} file)${r.skipped ? `, bỏ qua ${r.skipped} file đang dùng` : ""}.`);
      scan();
    } catch (e) {
      setMsg(String(e));
    } finally {
      setBusy(false);
    }
  };

  const total = cats?.filter((c) => picked.has(c.id)).reduce((a, c) => a + c.bytes, 0) ?? 0;

  return (
    <div className="stack">
      <section className="card">
        <div className="card-title">Hệ thống</div>
        {!snap && <div className="muted small">Đang đo…</div>}
        {snap && (
          <>
            <Meter label={`CPU (${snap.cores} luồng)`} value={snap.cpu} text={`${Math.round(snap.cpu)}%`} />
            <Meter label="RAM" value={(snap.memoryUsed / snap.memoryTotal) * 100} text={`${bytes(snap.memoryUsed)} / ${bytes(snap.memoryTotal)}`} />
            {snap.disks.map((d) => (
              <Meter key={d.mount} label={`Ổ ${d.mount}`} value={((d.total - d.available) / d.total) * 100} text={`còn ${bytes(d.available)} / ${bytes(d.total)}`} />
            ))}
            <div className="row between small">
              <span>Mạng ↓ {bytes(snap.netRxPerSec)}/s · ↑ {bytes(snap.netTxPerSec)}/s</span>
              <span className="muted">Bật {uptime(snap.uptime)}</span>
            </div>
            <div className="tiny muted top-gap">Tiến trình dùng nhiều nhất</div>
            {snap.top.map((p) => (
              <div key={p.pid} className="row between tiny">
                <span className="clamp1">{p.name}</span>
                <span className="num">
                  {p.cpu.toFixed(1)}% · {bytes(p.memory)}
                </span>
              </div>
            ))}
          </>
        )}
      </section>

      <section className="card">
        <div className="row between">
          <div className="card-title">Dọn rác</div>
          <button className="btn small" onClick={scan} disabled={busy}>
            Quét lại
          </button>
        </div>
        <div className="tiny muted">Chỉ xóa file cũ hơn 1 giờ trong các thư mục tạm/cache dưới đây; không theo liên kết, không đụng file đang mở.</div>
        {!cats && <div className="muted small">Đang quét…</div>}
        {cats?.map((c) => (
          <label key={c.id} className="check cat">
            <input
              type="checkbox"
              checked={picked.has(c.id)}
              onChange={(e) => {
                const n = new Set(picked);
                if (e.target.checked) n.add(c.id);
                else n.delete(c.id);
                setPicked(n);
              }}
            />
            <span className="grow">
              <span className="small">{c.label}</span>
              <span className="tiny muted block">{c.description}</span>
            </span>
            <span className="small num">{bytes(c.bytes)}</span>
          </label>
        ))}
        <button className="btn primary" disabled={busy || !cats || picked.size === 0 || total === 0} onClick={clean}>
          {busy ? "Đang dọn…" : `Dọn ${bytes(total)}`}
        </button>
        {msg && <div className="tiny muted">{msg}</div>}
      </section>
    </div>
  );
}
