// MacHub Responsive — trang viewer: hiển thị một URL trong nhiều khung kích thước thiết bị.
import { DEFAULT_DEVICES, DEFAULT_ENABLED, TYPE_LABEL } from "./devices.js";

const STORE_KEY = "mhResponsive";
const READY_TIMEOUT_MS = 8000;
const PAGE_PADDING_Y = 52; // padding trên + dưới của .frames
const DEVICE_HEAD = 42; // chiều cao tiêu đề khung + khoảng cách
const PAGE_PADDING_X = 48; // padding trái + phải của .frames
const FRAME_GAP = 24; // khoảng cách giữa các khung (.frames gap)
const MIN_CARD_W = 150; // đủ chỗ cho tên máy + 3 nút

const $ = (sel) => document.querySelector(sel);
const els = {
  form: $("#url-form"),
  input: $("#url-input"),
  reloadAll: $("#reload-all"),
  zoom: $("#zoom"),
  syncScroll: $("#sync-scroll"),
  syncNav: $("#sync-nav"),
  devicesBtn: $("#devices-btn"),
  panel: $("#devices-panel"),
  groups: $("#device-groups"),
  customForm: $("#custom-form"),
  resetDevices: $("#reset-devices"),
  shotBtn: $("#shot-btn"),
  themeBtn: $("#theme-btn"),
  stage: $("#stage"),
  frames: $("#frames"),
  empty: $("#empty"),
  tpl: $("#frame-tpl"),
};

const settings = {
  enabled: [...DEFAULT_ENABLED],
  custom: [],
  rotated: {},
  zoom: "fit",
  syncScroll: true,
  syncNav: true,
  theme: "system",
};

let myTabId = null;
let currentUrl = "";
/** @type {Map<string, {device: object, root: HTMLElement, iframe: HTMLIFrameElement, body: HTMLElement, hint: HTMLElement, frameId: number|null, href: string, pending: boolean, timer: number|null}>} */
const frames = new Map();

// ───────────────────────── Khởi động ─────────────────────────

init().catch((err) => console.error("[MacHub Responsive]", err));

async function init() {
  const stored = (await chrome.storage.local.get(STORE_KEY))[STORE_KEY];
  if (stored && typeof stored === "object") Object.assign(settings, stored);
  applyTheme();

  // Phải đăng ký quy tắc gỡ X-Frame-Options cho tab này TRƯỚC khi nạp iframe.
  const res = await chrome.runtime.sendMessage({ type: "mh-register-viewer" });
  myTabId = res?.tabId ?? (await chrome.tabs.getCurrent())?.id ?? null;

  els.zoom.value = settings.zoom;
  els.syncScroll.checked = settings.syncScroll;
  els.syncNav.checked = settings.syncNav;
  bindUi();
  renderDevicePanel();

  const fromQuery = new URLSearchParams(location.search).get("url");
  if (fromQuery) {
    setUrl(normalizeUrl(fromQuery), { replace: true });
  } else {
    renderFrames();
    els.input.focus();
  }
}

// ───────────────────────── Cài đặt ─────────────────────────

function save() {
  chrome.storage.local.set({ [STORE_KEY]: settings });
}

function allDevices() {
  return [...DEFAULT_DEVICES, ...settings.custom];
}

function deviceSize(device) {
  const rotated = !!settings.rotated[device.id];
  return rotated ? { w: device.h, h: device.w } : { w: device.w, h: device.h };
}

function applyTheme() {
  const root = document.documentElement;
  if (settings.theme === "system") root.removeAttribute("data-theme");
  else root.dataset.theme = settings.theme;
}

// ───────────────────────── URL ─────────────────────────

export function normalizeUrl(raw) {
  let s = String(raw || "").trim();
  if (!s) return "";
  if (!/^[a-z][a-z0-9+.-]*:/i.test(s)) {
    const isLocal = /^(localhost|127\.|0\.0\.0\.0|\[::1\]|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/i.test(s) || /\.local(:|\/|$)/i.test(s);
    s = (isLocal ? "http://" : "https://") + s;
  }
  try {
    const u = new URL(s);
    if (!["http:", "https:", "file:"].includes(u.protocol)) return "";
    return u.href;
  } catch {
    return "";
  }
}

function setUrl(url, { replace = false } = {}) {
  currentUrl = url;
  els.input.value = url;
  const qs = url ? `?url=${encodeURIComponent(url)}` : "";
  history[replace ? "replaceState" : "pushState"](null, "", location.pathname + qs);
  try {
    document.title = url ? `${new URL(url).host || "file"} — Responsive` : "MacHub Responsive";
  } catch {
    document.title = "MacHub Responsive";
  }
  renderFrames();
}

// ───────────────────────── Khung thiết bị ─────────────────────────

function renderFrames() {
  const enabled = allDevices().filter((d) => settings.enabled.includes(d.id));
  els.empty.hidden = !!currentUrl && enabled.length > 0;
  if (!currentUrl) {
    els.empty.hidden = false;
  }

  // Giữ lại khung đang có nếu thiết bị vẫn bật và URL không đổi; tạo mới phần còn lại.
  for (const [id, entry] of frames) {
    if (!enabled.find((d) => d.id === id)) {
      clearTimeout(entry.timer);
      entry.root.remove();
      frames.delete(id);
    }
  }

  for (const device of enabled) {
    let entry = frames.get(device.id);
    if (!entry) {
      entry = createFrame(device);
      frames.set(device.id, entry);
    }
    els.frames.appendChild(entry.root); // giữ đúng thứ tự
  }
  // Đặt kích thước khung TRƯỚC khi nạp trang, để trang đo đúng viewport ngay từ đầu.
  layout();
  if (!currentUrl) return;
  for (const entry of frames.values()) {
    if (entry.href !== currentUrl) loadFrame(entry, currentUrl);
  }
}

function createFrame(device) {
  const root = els.tpl.content.firstElementChild.cloneNode(true);
  const iframe = root.querySelector("iframe");
  const entry = {
    device,
    root,
    iframe,
    body: root.querySelector(".device-body"),
    hint: root.querySelector(".device-hint"),
    frameId: null,
    href: "",
    pending: false,
    timer: null,
  };
  root.dataset.device = device.id;
  root.querySelector(".device-name").textContent = device.name;
  iframe.name = `mh-frame:${device.id}`;
  iframe.title = device.name;

  root.querySelector(".rotate").addEventListener("click", () => {
    settings.rotated[device.id] = !settings.rotated[device.id];
    save();
    layout();
  });
  root.querySelector(".reload").addEventListener("click", () => loadFrame(entry, entry.href || currentUrl));
  root.querySelector(".open").addEventListener("click", () => {
    const url = entry.href || currentUrl;
    if (url) chrome.tabs.create({ url });
  });
  return entry;
}

function loadFrame(entry, url) {
  if (!url) return;
  entry.pending = true; // lần nạp do viewer chủ động → không lan sang khung khác
  entry.href = url;
  entry.hint.hidden = true;
  clearTimeout(entry.timer);
  entry.timer = setTimeout(() => {
    entry.hint.textContent =
      url.startsWith("file:")
        ? "Chưa tải được tệp. Vào chrome://extensions → MacHub Responsive → bật “Cho phép truy cập vào URL tệp”."
        : "Chưa nhận được tín hiệu từ trang. Nếu khung trống, trang có thể cần đăng nhập/cookie hoặc chặn nhúng bằng cách khác.";
    entry.hint.hidden = false;
  }, READY_TIMEOUT_MS);
  entry.iframe.src = url;
}

function computeScale() {
  if (settings.zoom !== "fit") return Number(settings.zoom) || 1;
  const list = [...frames.values()];
  if (!list.length) return 1;
  const sizes = list.map((e) => deviceSize(e.device));
  const maxH = Math.max(...sizes.map((s) => s.h));
  const sumW = sizes.reduce((a, s) => a + s.w, 0);
  // "Vừa màn hình": mọi khung lọt trọn trong vùng nhìn, cả chiều cao lẫn chiều rộng.
  const availH = els.stage.clientHeight - PAGE_PADDING_Y - DEVICE_HEAD;
  const availW = els.stage.clientWidth - PAGE_PADDING_X - FRAME_GAP * (list.length - 1);
  return Math.max(0.2, Math.min(1, availH / maxH, availW / sumW));
}

function layout() {
  const scale = computeScale();
  for (const entry of frames.values()) {
    const { w, h } = deviceSize(entry.device);
    entry.root.querySelector(".device-size").textContent =
      `${w}×${h}` + (scale !== 1 ? ` · ${Math.round(scale * 100)}%` : "");
    entry.root.querySelector(".rotate").setAttribute("aria-pressed", String(!!settings.rotated[entry.device.id]));
    Object.assign(entry.iframe.style, { width: `${w}px`, height: `${h}px`, transform: `scale(${scale})` });
    Object.assign(entry.body.style, { width: `${w * scale}px`, height: `${h * scale}px` });
    entry.root.style.width = `${Math.max(w * scale, MIN_CARD_W)}px`;
  }
}

// ───────────────────────── Tin nhắn từ khung ─────────────────────────

chrome.runtime.onMessage.addListener((msg, sender) => {
  if (!msg?.type?.startsWith("mh-") || sender.tab?.id !== myTabId || !sender.frameId) return;
  const entry = frames.get(msg.device);
  if (!entry) return;
  entry.frameId = sender.frameId;

  if (msg.type === "mh-frame-ready") {
    clearTimeout(entry.timer);
    entry.hint.hidden = true;
    const changed = msg.href !== entry.href;
    entry.href = msg.href;
    if (entry.pending) {
      entry.pending = false; // kết thúc lần nạp do viewer gây ra (kể cả khi trang tự chuyển hướng)
      return;
    }
    // Người dùng bấm link bên trong khung → các khung khác mở theo.
    if (changed && settings.syncNav) {
      currentUrl = msg.href;
      els.input.value = msg.href;
      history.replaceState(null, "", `${location.pathname}?url=${encodeURIComponent(msg.href)}`);
      for (const other of frames.values()) {
        if (other !== entry && other.href !== msg.href) loadFrame(other, msg.href);
      }
    }
  } else if (msg.type === "mh-scroll" && settings.syncScroll) {
    for (const other of frames.values()) {
      if (other === entry || !other.frameId) continue;
      chrome.tabs
        .sendMessage(myTabId, { type: "mh-apply-scroll", x: msg.x, y: msg.y }, { frameId: other.frameId })
        .catch(() => {});
    }
  }
});

// ───────────────────────── Bảng thiết bị ─────────────────────────

function renderDevicePanel() {
  els.groups.textContent = "";
  const byType = {};
  for (const d of allDevices()) (byType[d.type] ||= []).push(d);

  for (const type of ["mobile", "tablet", "desktop", "custom"]) {
    const list = byType[type];
    if (!list?.length) continue;
    const title = document.createElement("div");
    title.className = "panel-title";
    title.textContent = TYPE_LABEL[type];
    els.groups.appendChild(title);

    for (const d of list) {
      const label = document.createElement("label");
      label.className = "device-option";
      const cb = document.createElement("input");
      cb.type = "checkbox";
      cb.checked = settings.enabled.includes(d.id);
      cb.addEventListener("change", () => {
        settings.enabled = cb.checked
          ? [...settings.enabled, d.id]
          : settings.enabled.filter((id) => id !== d.id);
        save();
        renderFrames();
      });
      const name = document.createElement("span");
      name.textContent = d.name;
      const dim = document.createElement("span");
      dim.className = "dim";
      dim.textContent = `${d.w}×${d.h}`;
      label.append(cb, name, dim);

      if (type === "custom") {
        const rm = document.createElement("button");
        rm.type = "button";
        rm.className = "btn icon sm remove";
        rm.title = "Xóa kích thước này";
        rm.setAttribute("aria-label", `Xóa ${d.name}`);
        rm.textContent = "×";
        rm.addEventListener("click", (e) => {
          e.preventDefault();
          settings.custom = settings.custom.filter((c) => c.id !== d.id);
          settings.enabled = settings.enabled.filter((id) => id !== d.id);
          delete settings.rotated[d.id];
          save();
          renderDevicePanel();
          renderFrames();
        });
        label.appendChild(rm);
      }
      els.groups.appendChild(label);
    }
  }
}

// ───────────────────────── Sự kiện giao diện ─────────────────────────

function bindUi() {
  els.form.addEventListener("submit", (e) => {
    e.preventDefault();
    const url = normalizeUrl(els.input.value);
    if (!url) {
      els.input.setCustomValidity("URL không hợp lệ (chỉ http, https, file)");
      els.input.reportValidity();
      return;
    }
    els.input.setCustomValidity("");
    for (const entry of frames.values()) entry.href = ""; // buộc nạp lại kể cả khi trùng URL
    setUrl(url);
  });
  els.input.addEventListener("input", () => els.input.setCustomValidity(""));

  els.reloadAll.addEventListener("click", reloadAll);
  addEventListener("keydown", (e) => {
    const typing = e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement;
    if (!typing && !e.metaKey && !e.ctrlKey && !e.altKey && e.key.toLowerCase() === "r") reloadAll();
    if (e.key === "Escape") togglePanel(false);
  });

  els.zoom.addEventListener("change", () => {
    settings.zoom = els.zoom.value;
    save();
    layout();
  });
  els.syncScroll.addEventListener("change", () => {
    settings.syncScroll = els.syncScroll.checked;
    save();
  });
  els.syncNav.addEventListener("change", () => {
    settings.syncNav = els.syncNav.checked;
    save();
  });

  els.devicesBtn.addEventListener("click", () => togglePanel());
  document.addEventListener("click", (e) => {
    if (!els.panel.hidden && !els.panel.contains(e.target) && e.target !== els.devicesBtn) togglePanel(false);
  });

  els.customForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const w = Math.round(Number($("#custom-w").value));
    const h = Math.round(Number($("#custom-h").value));
    if (!(w >= 200 && w <= 3840 && h >= 200 && h <= 3840)) return;
    const name = $("#custom-name").value.trim() || `${w}×${h}`;
    const id = `custom-${Date.now().toString(36)}`;
    settings.custom.push({ id, name, w, h, type: "custom" });
    settings.enabled.push(id);
    save();
    els.customForm.reset();
    renderDevicePanel();
    renderFrames();
  });

  els.resetDevices.addEventListener("click", () => {
    settings.enabled = [...DEFAULT_ENABLED];
    settings.custom = [];
    settings.rotated = {};
    save();
    renderDevicePanel();
    renderFrames();
  });

  els.themeBtn.addEventListener("click", () => {
    const order = ["system", "light", "dark"];
    settings.theme = order[(order.indexOf(settings.theme) + 1) % order.length];
    els.themeBtn.title = `Giao diện: ${{ system: "theo hệ thống", light: "sáng", dark: "tối" }[settings.theme]}`;
    applyTheme();
    save();
  });

  els.shotBtn.addEventListener("click", screenshot);
  addEventListener("resize", layout);
}

function togglePanel(force) {
  const open = force ?? els.panel.hidden;
  els.panel.hidden = !open;
  els.devicesBtn.setAttribute("aria-expanded", String(open));
}

function reloadAll() {
  for (const entry of frames.values()) loadFrame(entry, entry.href || currentUrl);
}

async function screenshot() {
  togglePanel(false);
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  try {
    const dataUrl = await chrome.tabs.captureVisibleTab({ format: "png" });
    const a = document.createElement("a");
    let host = "page";
    try {
      host = new URL(currentUrl).host.replace(/[^a-z0-9.-]/gi, "_") || "page";
    } catch {}
    const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
    a.href = dataUrl;
    a.download = `responsive-${host}-${stamp}.png`;
    a.click();
  } catch (err) {
    console.error("[MacHub Responsive] screenshot", err);
  }
}
