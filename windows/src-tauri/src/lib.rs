// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 MacHub contributors.

//! MacHub cho Windows: icon khay hệ thống + bảng điều khiển nổi.

mod agent;
mod cleaner;
mod clipboard;
mod displays;
mod sysmon;
mod winsnap;

use std::sync::atomic::{AtomicIsize, Ordering};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder, WindowEvent};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use tauri_plugin_positioner::{Position, WindowExt};

/// Cửa sổ đang được dùng trước khi bật bảng clipboard (để dán vào đó).
static PASTE_TARGET: AtomicIsize = AtomicIsize::new(0);

// ───────────── Cửa sổ ─────────────

fn main_window(app: &AppHandle) -> Option<tauri::WebviewWindow> {
    app.get_webview_window("main")
}

fn show_main(app: &AppHandle, tab: Option<&str>, near_tray: bool) {
    let Some(w) = main_window(app) else { return };
    if near_tray {
        let _ = w.move_window(Position::TrayCenter);
    } else {
        let _ = w.move_window(Position::Center);
    }
    let _ = w.show();
    let _ = w.set_focus();
    if let Some(t) = tab {
        let _ = app.emit("select-tab", t);
    }
    if let Some(a) = app.try_state::<agent::Agent>() {
        a.set_visible(true);
    }
}

fn hide_main(app: &AppHandle) {
    if let Some(w) = main_window(app) {
        let _ = w.hide();
    }
    if let Some(a) = app.try_state::<agent::Agent>() {
        a.set_visible(false);
    }
}

fn toggle_main(app: &AppHandle) {
    match main_window(app) {
        Some(w) if w.is_visible().unwrap_or(false) => hide_main(app),
        _ => show_main(app, None, true),
    }
}

pub(crate) fn show_approval_window(app: &AppHandle) {
    let app = app.clone();
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        let w = match handle.get_webview_window("approval") {
            Some(w) => w,
            None => match WebviewWindowBuilder::new(&handle, "approval", WebviewUrl::App("index.html".into()))
                .title("MacHub — Duyệt quyền")
                .inner_size(420.0, 300.0)
                .resizable(false)
                .decorations(false)
                .always_on_top(true)
                .skip_taskbar(false)
                .visible(false)
                .build()
            {
                Ok(w) => w,
                Err(_) => return,
            },
        };
        let _ = w.move_window(Position::BottomRight);
        let _ = w.show();
        // Không lấy focus: tránh người dùng đang gõ lỡ tay bấm phím vào cửa sổ duyệt.
    });
}

pub(crate) fn hide_approval_window(app: &AppHandle) {
    let handle = app.clone();
    let _ = app.run_on_main_thread(move || {
        if let Some(w) = handle.get_webview_window("approval") {
            let _ = w.hide();
        }
    });
}

// ───────────── Lệnh cho giao diện ─────────────

type R<T> = Result<T, String>;

#[tauri::command]
fn agent_view(agent: State<agent::Agent>) -> agent::AgentView {
    agent.view()
}
#[tauri::command]
fn agent_set_range(agent: State<agent::Agent>, range: String) {
    agent.set_range(&range)
}
#[tauri::command]
fn agent_respond(agent: State<agent::Agent>, id: u64, decision: String) -> bool {
    agent.respond(id, &decision)
}
#[tauri::command]
fn agent_settings(agent: State<agent::Agent>, settings: agent::AgentSettings) {
    agent.update_settings(settings)
}
#[tauri::command]
fn agent_install(agent: State<agent::Agent>, status_line: bool) {
    agent.install(status_line)
}
#[tauri::command]
fn agent_uninstall(agent: State<agent::Agent>) {
    agent.uninstall()
}
#[tauri::command]
fn agent_rescan(agent: State<agent::Agent>) {
    agent.rescan();
    agent.refresh_oauth(true);
}

#[tauri::command]
fn clip_list(clip: State<clipboard::Clipboard>, query: String) -> Vec<clipboard::ClipItem> {
    clip.list(&query)
}
#[tauri::command]
fn clip_pin(clip: State<clipboard::Clipboard>, id: u64, pinned: bool) {
    clip.set_pinned(id, pinned)
}
#[tauri::command]
fn clip_delete(clip: State<clipboard::Clipboard>, id: u64) {
    clip.delete(id)
}
#[tauri::command]
fn clip_clear(clip: State<clipboard::Clipboard>) -> usize {
    clip.clear_unpinned()
}
/// Chép mục; nếu `paste` thì ẩn bảng và dán vào cửa sổ trước đó.
#[tauri::command]
fn clip_use(app: AppHandle, clip: State<clipboard::Clipboard>, id: u64, paste: bool) -> R<()> {
    clip.copy(id)?;
    if paste {
        hide_main(&app);
        let target = PASTE_TARGET.swap(0, Ordering::SeqCst);
        if target != 0 {
            std::thread::spawn(move || winsnap::paste_into(target));
        }
    }
    Ok(())
}

#[tauri::command]
fn snap_layouts() -> &'static [winsnap::Layout] {
    winsnap::LAYOUTS
}
/// Bấm từ giao diện: ẩn bảng trước để cửa sổ phía sau thành foreground.
#[tauri::command]
fn snap_apply(app: AppHandle, id: String) -> R<()> {
    hide_main(&app);
    std::thread::sleep(std::time::Duration::from_millis(150));
    winsnap::snap(&id, own_hwnd(&app))
}
#[tauri::command]
fn display_list() -> Vec<displays::Display> {
    displays::list()
}
#[tauri::command]
fn display_set_brightness(id: String, value: u32) -> R<()> {
    displays::set_brightness(&id, value)
}

#[tauri::command]
async fn cleaner_scan() -> Vec<cleaner::Category> {
    tauri::async_runtime::spawn_blocking(cleaner::scan).await.unwrap_or_default()
}
#[tauri::command]
async fn cleaner_clean(ids: Vec<String>) -> R<cleaner::CleanResult> {
    tauri::async_runtime::spawn_blocking(move || cleaner::clean(&ids)).await.map_err(|e| e.to_string())
}
#[tauri::command]
fn system_snapshot(mon: State<sysmon::Monitor>) -> R<sysmon::Snapshot> {
    mon.snapshot()
}

#[tauri::command]
fn hide_window(app: AppHandle) {
    hide_main(&app)
}
#[tauri::command]
fn app_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

fn own_hwnd(app: &AppHandle) -> Option<isize> {
    #[cfg(windows)]
    {
        main_window(app).and_then(|w| w.hwnd().ok()).map(|h| h.0 as isize)
    }
    #[cfg(not(windows))]
    {
        let _ = app;
        None
    }
}

// ───────────── Phím tắt toàn cục ─────────────

fn shortcut_table() -> Vec<(Shortcut, &'static str)> {
    let ca = Modifiers::CONTROL | Modifiers::ALT;
    let mut v = vec![
        (Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyV), "clipboard"),
        (Shortcut::new(Some(ca), Code::KeyM), "toggle"),
        (Shortcut::new(Some(ca | Modifiers::SHIFT), Code::ArrowRight), "next-display"),
    ];
    let snaps = [
        (Code::ArrowLeft, "left"),
        (Code::ArrowRight, "right"),
        (Code::ArrowUp, "top"),
        (Code::ArrowDown, "bottom"),
        (Code::Enter, "maximize"),
        (Code::KeyC, "center"),
        (Code::KeyD, "first-third"),
        (Code::KeyF, "center-third"),
        (Code::KeyG, "last-third"),
        (Code::KeyE, "first-two-thirds"),
        (Code::KeyT, "last-two-thirds"),
        (Code::KeyU, "top-left"),
        (Code::KeyI, "top-right"),
        (Code::KeyJ, "bottom-left"),
        (Code::KeyK, "bottom-right"),
    ];
    v.extend(snaps.into_iter().map(|(c, id)| (Shortcut::new(Some(ca), c), id)));
    v
}

fn on_shortcut(app: &AppHandle, action: &str) {
    match action {
        "clipboard" => {
            PASTE_TARGET.store(winsnap::foreground(), Ordering::SeqCst);
            show_main(app, Some("clipboard"), false);
        }
        "toggle" => toggle_main(app),
        layout => {
            let _ = winsnap::snap(layout, own_hwnd(app));
        }
    }
}

// ───────────── Khởi động ─────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let table = shortcut_table();
    let shortcuts: Vec<Shortcut> = table.iter().map(|(s, _)| *s).collect();

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| show_main(app, None, true)))
        .plugin(tauri_plugin_positioner::init())
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(move |app, sc, ev| {
                    if ev.state() != ShortcutState::Pressed {
                        return;
                    }
                    if let Some((_, action)) = table.iter().find(|(s, _)| s == sc) {
                        on_shortcut(app, action);
                    }
                })
                .build(),
        )
        .setup(move |app| {
            let handle = app.handle().clone();

            let agent = agent::Agent::new(handle.clone());
            agent.start();
            app.manage(agent);

            let clip = clipboard::Clipboard::new(handle.clone());
            clip.start();
            app.manage(clip);

            app.manage(sysmon::Monitor::default());

            // Phím tắt bị app khác chiếm thì bỏ qua từng phím, không làm hỏng cả app.
            for s in shortcuts {
                let _ = app.global_shortcut().register(s);
            }

            let open = MenuItem::with_id(app, "open", "Mở MacHub  (Ctrl+Alt+M)", true, None::<&str>)?;
            let clip_item = MenuItem::with_id(app, "clipboard", "Lịch sử clipboard  (Ctrl+Shift+V)", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Thoát", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &clip_item, &quit])?;
            let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray.png"))?;
            TrayIconBuilder::with_id("main")
                .icon(icon)
                .tooltip("MacHub")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "open" => show_main(app, None, true),
                    "clipboard" => show_main(app, Some("clipboard"), true),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, e| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &e);
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                        toggle_main(tray.app_handle());
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|w, e| {
            if w.label() == "main" {
                match e {
                    // Bảng nổi: mất focus thì ẩn, giống popover menu bar trên macOS.
                    WindowEvent::Focused(false) => hide_main(w.app_handle()),
                    WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        hide_main(w.app_handle());
                    }
                    _ => {}
                }
            } else if w.label() == "approval" {
                if let WindowEvent::CloseRequested { api, .. } = e {
                    api.prevent_close();
                    let _ = w.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            agent_view,
            agent_set_range,
            agent_respond,
            agent_settings,
            agent_install,
            agent_uninstall,
            agent_rescan,
            clip_list,
            clip_pin,
            clip_delete,
            clip_clear,
            clip_use,
            snap_layouts,
            snap_apply,
            display_list,
            display_set_brightness,
            cleaner_scan,
            cleaner_clean,
            system_snapshot,
            hide_window,
            app_version
        ])
        .run(tauri::generate_context!())
        .expect("không khởi động được MacHub");
}
