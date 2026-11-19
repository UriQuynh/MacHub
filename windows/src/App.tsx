// SPDX-License-Identifier: GPL-3.0-only
import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { api } from "./api";
import AgentTab from "./tabs/AgentTab";
import ClipboardTab from "./tabs/ClipboardTab";
import WindowsTab from "./tabs/WindowsTab";
import SystemTab from "./tabs/SystemTab";

const TABS = [
  { id: "agent", label: "Agent" },
  { id: "clipboard", label: "Clipboard" },
  { id: "windows", label: "Cửa sổ & Màn hình" },
  { id: "system", label: "Dọn dẹp & Hệ thống" },
] as const;
type TabId = (typeof TABS)[number]["id"];

export default function App() {
  const [tab, setTab] = useState<TabId>("agent");
  const [version, setVersion] = useState("");
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    api.appVersion().then(setVersion).catch(() => {});
    const un = listen<string>("select-tab", (e) => {
      if (TABS.some((t) => t.id === e.payload)) setTab(e.payload as TabId);
    });
    // Chỉ chạy các vòng làm mới khi bảng đang hiện.
    const w = getCurrentWindow();
    const unFocus = w.onFocusChanged(({ payload }) => setVisible(payload));
    const esc = (e: KeyboardEvent) => {
      if (e.key === "Escape") api.hideWindow();
    };
    window.addEventListener("keydown", esc);
    return () => {
      un.then((f) => f());
      unFocus.then((f) => f());
      window.removeEventListener("keydown", esc);
    };
  }, []);

  return (
    <div className="shell">
      <header className="header" data-tauri-drag-region>
        <div className="brand" data-tauri-drag-region>
          <span className="logo">◆</span> MacHub <span className="muted small">Windows {version}</span>
        </div>
        <button className="icon-btn" title="Ẩn (Esc)" onClick={() => api.hideWindow()}>
          ✕
        </button>
      </header>
      <nav className="tabs" role="tablist">
        {TABS.map((t) => (
          <button key={t.id} role="tab" aria-selected={tab === t.id} className={tab === t.id ? "tab active" : "tab"} onClick={() => setTab(t.id)}>
            {t.label}
          </button>
        ))}
      </nav>
      <main className="content">
        {tab === "agent" && <AgentTab />}
        {tab === "clipboard" && <ClipboardTab />}
        {tab === "windows" && <WindowsTab />}
        {tab === "system" && <SystemTab active={visible} />}
      </main>
    </div>
  );
}
