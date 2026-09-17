mod audio;
pub mod secrets;
mod session;
mod storage;
pub mod translation;

use audio::AudioCaptureBackend;

use serde_json::{json, Value};
use std::sync::Arc;
use tauri::{Manager, State, WebviewWindow};

type SharedState = Arc<session::Shared>;
fn main_only(window: &WebviewWindow) -> Result<(), String> {
    if window.label() == "main" {
        Ok(())
    } else {
        Err("此操作仅允许在主窗口使用".into())
    }
}
#[tauri::command]
fn devices(
    window: WebviewWindow,
    input_mode: Option<audio::InputMode>,
) -> Result<Vec<audio::AudioDevice>, String> {
    main_only(&window)?;
    match input_mode.unwrap_or_default() {
        audio::InputMode::Microphone => audio::MicrophoneBackend.devices(),
        audio::InputMode::System => audio::SystemAudioBackend.devices(),
    }
}
#[tauri::command]
fn key_status(window: WebviewWindow) -> Result<bool, String> {
    main_only(&window)?;
    Ok(secrets::SecretStore::read()?.is_some())
}
#[tauri::command]
fn save_key(window: WebviewWindow, key: String) -> Result<(), String> {
    main_only(&window)?;
    secrets::SecretStore::save(&key)
}
#[tauri::command]
fn delete_key(window: WebviewWindow) -> Result<(), String> {
    main_only(&window)?;
    secrets::SecretStore::delete()
}
#[tauri::command]
fn snapshot(state: State<SharedState>) -> session::Snapshot {
    state.snapshot.lock().unwrap().clone()
}
#[tauri::command]
fn start_session(
    window: WebviewWindow,
    app: tauri::AppHandle,
    state: State<SharedState>,
    config: session::Config,
) -> Result<(), String> {
    main_only(&window)?;
    session::begin(app, state.inner().clone(), config)
}
#[tauri::command]
fn stop_session(
    window: WebviewWindow,
    app: tauri::AppHandle,
    state: State<SharedState>,
) -> Result<(), String> {
    main_only(&window)?;
    if let Some(tx) = state.control.lock().unwrap().as_ref() {
        session::emit(
            &app,
            &state,
            json!({"type":"status", "state":"STOPPING", "message":"正在保存最后的字幕…"}),
        );
        let _ = tx.send(true);
    }
    Ok(())
}
#[tauri::command]
fn set_overlay(
    window: WebviewWindow,
    app: tauri::AppHandle,
    state: State<SharedState>,
    visible: bool,
    click_through: bool,
) -> Result<(), String> {
    main_only(&window)?;
    let overlay = app.get_webview_window("overlay").ok_or("字幕窗口不可用")?;
    overlay
        .set_ignore_cursor_events(click_through)
        .map_err(|_| "无法设置鼠标穿透")?;
    state
        .overlay_click_through
        .store(click_through, std::sync::atomic::Ordering::Relaxed);
    if visible {
        overlay.show().map_err(|_| "无法显示字幕窗口")
    } else {
        overlay.hide().map_err(|_| "无法隐藏字幕窗口")
    }
    .map_err(String::from)
}
#[tauri::command]
fn overlay_status(
    window: WebviewWindow,
    app: tauri::AppHandle,
    state: State<SharedState>,
) -> Result<Value, String> {
    main_only(&window)?;
    let overlay = app.get_webview_window("overlay").ok_or("字幕窗口不可用")?;
    Ok(
        json!({"visible":overlay.is_visible().map_err(|_| "无法读取字幕窗口状态")?,
        "click_through":state.overlay_click_through.load(std::sync::atomic::Ordering::Relaxed)}),
    )
}
#[tauri::command]
fn compact_overlay(
    window: WebviewWindow,
    state: State<SharedState>,
    compact: bool,
) -> Result<(), String> {
    if window.label() != "overlay" {
        return Err("仅字幕窗口允许此操作".into());
    }
    let mut saved = state.overlay_saved_size.lock().unwrap();
    if compact {
        if saved.is_none() {
            *saved = Some(window.inner_size().map_err(|_| "无法读取字幕大小")?);
        }
        window
            .set_min_size(Some(tauri::LogicalSize::new(180., 56.)))
            .map_err(|_| "无法收起字幕")?;
        window
            .set_size(tauri::LogicalSize::new(200., 64.))
            .map_err(|_| "无法收起字幕")?;
    } else {
        window
            .set_min_size(Some(tauri::LogicalSize::new(480., 280.)))
            .map_err(|_| "无法展开字幕")?;
        if let Some(size) = saved.take() {
            window.set_size(size).map_err(|_| "无法展开字幕")?;
        }
    }
    Ok(())
}
#[tauri::command]
async fn export_session(
    window: WebviewWindow,
    state: State<'_, SharedState>,
    format: String,
) -> Result<String, String> {
    main_only(&window)?;
    let path = state
        .journal_path
        .lock()
        .unwrap()
        .clone()
        .ok_or("尚无会话可导出")?;
    tauri::async_runtime::spawn_blocking(move || storage::export(&path, &format))
        .await
        .map_err(|_| "导出失败")?
}
#[tauri::command]
async fn environment(window: WebviewWindow) -> Result<Value, String> {
    main_only(&window)?;
    #[cfg(target_os = "macos")]
    {
        let bridge = macos_bridge_path(&window);
        let mut result = json!({"python_ready":false,"system_audio_supported":true,
            "models":[],"cuda_available":false,"backend":"apple_speech"});
        if !bridge.is_file() { return Ok(result); }
        let output = tokio::time::timeout(std::time::Duration::from_secs(15),
            tokio::process::Command::new(bridge).args(["--doctor", "--locale", "en-US"]).output()).await;
        if let Ok(Ok(output)) = output {
            if let Ok(info) = serde_json::from_slice::<Value>(&output.stdout) {
                let available = info["available"].as_bool().unwrap_or(false);
                result["python_ready"] = json!(available);
                if available && info["installed"].as_bool().unwrap_or(false) {
                    result["models"] = json!(["apple-speech-en-US"]);
                }
            }
        }
        return Ok(result);
    }
    #[cfg(not(target_os = "macos"))]
    {
    let root = runtime_root(&window);
    let python = root.join(if cfg!(windows) {
        ".venv/Scripts/python.exe"
    } else {
        ".venv/bin/python"
    });
    let model_dir = window
        .path()
        .app_data_dir()
        .map_err(|_| "无法访问模型目录")?
        .join("models");
    std::fs::create_dir_all(&model_dir).map_err(|_| "无法创建模型目录")?;
    let mut result = json!({"python_ready":false,"system_audio_supported":cfg!(windows),"models":[],"cuda_available":false,"model_dir":model_dir});
    if !python.is_file() {
        return Ok(result);
    }
    let mut command = tokio::process::Command::new(python);
    command
        .arg(root.join("asr-sidecar/main.py"))
        .args(["--model-dir", model_dir.to_string_lossy().as_ref()])
        .arg("--doctor")
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    if let Ok(Ok(output)) =
        tokio::time::timeout(std::time::Duration::from_secs(15), command.output()).await
    {
        if output.status.success() {
            if let Ok(info) = serde_json::from_slice::<Value>(&output.stdout) {
                result["python_ready"] = json!(true);
                result["models"] = info["models"].clone();
                result["cuda_available"] = info["cuda_available"].clone();
            }
        }
    }
    Ok(result)
    }
}
#[tauri::command]
async fn download_model(window: WebviewWindow, model: String) -> Result<(), String> {
    main_only(&window)?;
    #[cfg(target_os = "macos")]
    {
        if !["apple-speech-en-US", "distil-large-v3"].contains(&model.as_str()) {
            return Err("Mac 版当前仅支持 Apple 英文语音模型".into());
        }
        let output = tokio::time::timeout(std::time::Duration::from_secs(3600),
            tokio::process::Command::new(macos_bridge_path(&window))
                .args(["--prepare", "--locale", "en-US"]).output()).await
            .map_err(|_| "Apple 语音模型准备超时")?
            .map_err(|_| "无法启动 Apple Speech Bridge")?;
        if !output.status.success() { return Err("Apple 语音模型准备失败".into()); }
        return Ok(());
    }
    #[cfg(not(target_os = "macos"))]
    {
    if !["distil-large-v3", "distil-medium.en", "distil-small.en"].contains(&model.as_str()) {
        return Err("未知识别模型".into());
    }
    static DOWNLOADING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
    if DOWNLOADING.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return Err("已有模型正在下载".into());
    }
    struct Reset;
    impl Drop for Reset {
        fn drop(&mut self) {
            DOWNLOADING.store(false, std::sync::atomic::Ordering::SeqCst);
        }
    }
    let _reset = Reset;
    let root = runtime_root(&window);
    let model_dir = window
        .path()
        .app_data_dir()
        .map_err(|_| "无法访问模型目录")?
        .join("models");
    std::fs::create_dir_all(&model_dir).map_err(|_| "无法创建模型目录")?;
    let mut command = tokio::process::Command::new(root.join(if cfg!(windows) {
        ".venv/Scripts/python.exe"
    } else {
        ".venv/bin/python"
    }));
    command
        .arg(root.join("asr-sidecar/main.py"))
        .args(["--model-dir", model_dir.to_string_lossy().as_ref()])
        .args(["--download-model", "--model", &model])
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    let output = tokio::time::timeout(std::time::Duration::from_secs(3600), command.output())
        .await
        .map_err(|_| "下载超时，请重试")?
        .map_err(|_| "无法启动模型下载")?;
    if !output.status.success() {
        return Err("模型下载失败，请检查网络后重试；已下载的缓存会保留".into());
    }
    Ok(())
    }
}

#[cfg(target_os = "macos")]
fn macos_bridge_path(window: &WebviewWindow) -> std::path::PathBuf {
    if let Ok(current) = std::env::current_exe() {
        if let Some(parent) = current.parent() {
            let bundled = parent.join("LinguaGlassSpeechBridge");
            if bundled.is_file() { return bundled; }
        }
    }
    runtime_root(window).join("native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge")
}

fn runtime_root(window: &WebviewWindow) -> std::path::PathBuf {
    if let Ok(resource) = window.path().resource_dir() {
        if resource.join("asr-sidecar").join("main.py").is_file() {
            return resource;
        }
    }
    std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}
pub fn run() {
    tauri::Builder::default()
        .manage(Arc::new(session::Shared::default()))
        .invoke_handler(tauri::generate_handler![
            devices,
            key_status,
            save_key,
            delete_key,
            snapshot,
            start_session,
            stop_session,
            set_overlay,
            overlay_status,
            compact_overlay,
            export_session,
            environment,
            download_model
        ])
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "overlay" {
                    api.prevent_close();
                    let _ = window.hide();
                }
                if window.label() == "main" {
                    api.prevent_close();
                    let shared = window.state::<SharedState>().inner().clone();
                    let control = shared.control.lock().unwrap().clone();
                    if let Some(tx) = control {
                        let _ = tx.send(true);
                        let app = window.app_handle().clone();
                        tauri::async_runtime::spawn(async move {
                            for _ in 0..750 {
                                if app.state::<SharedState>().control.lock().unwrap().is_none() {
                                    break;
                                }
                                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                            }
                            app.exit(0);
                        });
                    } else {
                        window.app_handle().exit(0);
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("Unable to launch LinguaGlass");
}
