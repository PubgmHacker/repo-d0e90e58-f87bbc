#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    CustomMenuItem, Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, SystemTrayMenuItem,
    WindowEvent,
};

#[tauri::command]
fn create_room() -> String {
    "new_room".into()
}

#[tauri::command]
fn join_by_code() -> String {
    "join".into()
}

fn main() {
    let quit = CustomMenuItem::new("quit".to_string(), "Quit Plink");
    let new_room = CustomMenuItem::new("new_room".to_string(), "New Room");
    let join = CustomMenuItem::new("join".to_string(), "Join by Code");
    let show = CustomMenuItem::new("show".to_string(), "Show Plink");
    let hide = CustomMenuItem::new("hide".to_string(), "Hide to Tray");

    let tray_menu = SystemTrayMenu::new()
        .add_item(new_room)
        .add_item(join)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(show)
        .add_item(hide)
        .add_native_item(SystemTrayMenuItem::Separator)
        .add_item(quit);

    let system_tray = SystemTray::new().with_menu(tray_menu);

    tauri::Builder::default()
        .system_tray(system_tray)
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::LeftClick { .. } => {
                if let Some(window) = app.get_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            }
            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "quit" => app.exit(0),
                "new_room" | "join" => {
                    if let Some(window) = app.get_window("main") {
                        let _ = window.show();
                        let _ = window.emit("menu-action", id.as_str());
                    }
                }
                "show" => {
                    if let Some(window) = app.get_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
                "hide" => {
                    if let Some(window) = app.get_window("main") {
                        let _ = window.hide();
                    }
                }
                _ => {}
            },
            _ => {}
        })
        .on_window_event(|event| {
            if let WindowEvent::CloseRequested { api, .. } = event.event() {
                api.prevent_close();
                let _ = event.window().hide();
            }
        })
        .invoke_handler(tauri::generate_handler![create_room, join_by_code])
        .run(tauri::generate_context!())
        .expect("error while running Plink");
}