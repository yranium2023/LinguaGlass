use crate::{
    audio,
    secrets::SecretStore,
    translation::{self, DeepSeekTranslationService, Job},
};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, VecDeque},
    fs::File,
    io::Write,
    path::PathBuf,
    process::Stdio,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tauri::{AppHandle, Emitter, Manager};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::Command,
    sync::{mpsc, watch},
};

#[derive(Clone, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub input_mode: audio::InputMode,
    pub device_id: Option<String>,
    pub gain: f32,
    pub asr_model: String,
    pub compute: String,
    pub translation_model: String,
    pub domain: String,
    pub glossary: String,
    pub context_length: usize,
    #[serde(default = "default_asr_silence_seconds")]
    pub asr_silence_seconds: f32,
    #[serde(default = "default_asr_max_segment_seconds")]
    pub asr_max_segment_seconds: u32,
    #[serde(default = "default_asr_patience")]
    pub asr_patience: f32,
}
fn default_asr_silence_seconds() -> f32 {
    0.9
}
fn default_asr_max_segment_seconds() -> u32 {
    20
}
fn default_asr_patience() -> f32 {
    1.2
}
impl Config {
    pub fn validate(&self) -> Result<(), String> {
        self.input_mode.validate()?;
        if !["distil-large-v3", "distil-medium.en", "distil-small.en"]
            .contains(&self.asr_model.as_str())
            || !["cpu", "cuda"].contains(&self.compute.as_str())
            || !["deepseek-v4-flash", "deepseek-v4-pro"].contains(&self.translation_model.as_str())
            || !self.gain.is_finite()
            || !(0.0..=2.0).contains(&self.gain)
            || !self.asr_silence_seconds.is_finite()
            || !(0.4..=2.0).contains(&self.asr_silence_seconds)
            || !(8..=30).contains(&self.asr_max_segment_seconds)
            || !self.asr_patience.is_finite()
            || !(1.0..=2.0).contains(&self.asr_patience)
            || self.context_length > 4
            || self.glossary.len() > 12000
            || self.domain.len() > 100
        {
            return Err("设置参数无效".into());
        }
        Ok(())
    }
}
#[derive(Clone, Serialize)]
pub struct Snapshot {
    pub seq: u64,
    pub session_id: String,
    pub state: String,
    pub events: VecDeque<Value>,
}
impl Default for Snapshot {
    fn default() -> Self {
        Self {
            seq: 0,
            session_id: String::new(),
            state: "IDLE".into(),
            events: VecDeque::new(),
        }
    }
}
#[derive(Default)]
pub struct Shared {
    pub overlay_click_through: AtomicBool,
    pub overlay_saved_size: Mutex<Option<tauri::PhysicalSize<u32>>>,
    pub control: Mutex<Option<watch::Sender<bool>>>,
    pub snapshot: Mutex<Snapshot>,
    pub journal: Mutex<Option<File>>,
    pub journal_path: Mutex<Option<PathBuf>>,
}

pub fn emit(app: &AppHandle, shared: &Shared, mut event: Value) {
    let mut snapshot = shared.snapshot.lock().unwrap();
    snapshot.seq += 1;
    event["seq"] = json!(snapshot.seq);
    event["session_id"] = json!(snapshot.session_id);
    let kind = event["type"].as_str().unwrap_or("").to_owned();
    if kind == "status" {
        snapshot.state = event["state"].as_str().unwrap_or("IDLE").into();
    }
    if kind.starts_with("asr_") || kind.starts_with("translation_") {
        let id = event["id"].clone();
        let family = if kind.starts_with("asr_") {
            "asr_"
        } else {
            "translation_"
        };
        snapshot
            .events
            .retain(|e| !(e["id"] == id && e["type"].as_str().unwrap_or("").starts_with(family)));
        snapshot.events.push_back(event.clone());
        while snapshot.events.len() > 900 {
            snapshot.events.pop_front();
        }
    } else if kind == "latency" {
        snapshot.events.push_back(event.clone());
        while snapshot.events.len() > 900 {
            snapshot.events.pop_front();
        }
    }
    if [
        "asr_final",
        "translation_done",
        "translation_error",
        "latency",
        "status",
        "warning",
        "error",
    ]
    .contains(&kind.as_str())
    {
        if let Some(file) = shared.journal.lock().unwrap().as_mut() {
            if writeln!(file, "{event}")
                .and_then(|_| file.flush())
                .is_err()
            {
                // Keep live recognition alive, but make data loss visible.
                let _ = app.emit("pipeline", json!({"type":"warning", "message":"会话记录写入失败，请检查磁盘空间。", "session_id": snapshot.session_id}));
            }
        }
    }
    let _ = app.emit("pipeline", event);
}

pub fn begin(app: AppHandle, shared: Arc<Shared>, config: Config) -> Result<(), String> {
    config.validate()?;
    let mut control = shared.control.lock().unwrap();
    if control.is_some() {
        return Err("请等待当前会话结束".into());
    }
    let root = runtime_root(&app);
    let python = root.join(if cfg!(windows) {
        ".venv/Scripts/python.exe"
    } else {
        ".venv/bin/python"
    });
    let model_dir = app_data_dir(&app)?.join("models");
    std::fs::create_dir_all(&model_dir).map_err(|_| "无法创建模型目录")?;
    if !python.is_file() {
        return Err("尚未安装本地识别环境，请先运行 scripts/setup.ps1".into());
    }
    let session_id = uuid::Uuid::new_v4().to_string();
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|_| "无法访问应用数据目录")?
        .join("sessions");
    std::fs::create_dir_all(&dir).map_err(|_| "无法创建会话目录")?;
    let path = dir.join(format!("{session_id}.jsonl"));
    let file = File::create(&path).map_err(|_| "无法保存会话记录")?;
    *shared.journal.lock().unwrap() = Some(file);
    *shared.journal_path.lock().unwrap() = Some(path);
    {
        let mut snapshot = shared.snapshot.lock().unwrap();
        snapshot.session_id = session_id;
        snapshot.events.clear();
    }
    let (stop_tx, stop_rx) = watch::channel(false);
    *control = Some(stop_tx);
    drop(control);
    emit(
        &app,
        &shared,
        json!({"type":"status", "state":"INITIALIZING", "message":"正在加载本地语音模型…"}),
    );
    tauri::async_runtime::spawn(async move {
        let result = run(&app, &shared, config, python, root, model_dir, stop_rx).await;
        if let Err(message) = result {
            emit(&app, &shared, json!({"type":"error", "message": message}));
        }
        emit(&app, &shared, json!({"type":"status", "state":"IDLE"}));
        *shared.journal.lock().unwrap() = None;
        *shared.control.lock().unwrap() = None;
    });
    Ok(())
}

async fn run(
    app: &AppHandle,
    shared: &Arc<Shared>,
    config: Config,
    python: PathBuf,
    root: PathBuf,
    model_dir: PathBuf,
    mut stop_rx: watch::Receiver<bool>,
) -> Result<(), String> {
    let mut command = Command::new(python);
    command
        .arg("-u")
        .arg(root.join("asr-sidecar/main.py"))
        .args(["--model", &config.asr_model, "--device", &config.compute])
        .args(["--model-dir", model_dir.to_string_lossy().as_ref()])
        .arg("--domain")
        .arg(&config.domain)
        .arg("--glossary")
        .arg(&config.glossary)
        .arg("--silence-ms")
        .arg((config.asr_silence_seconds * 1000.0).round().to_string())
        .arg("--max-segment-seconds")
        .arg(config.asr_max_segment_seconds.to_string())
        .arg("--patience")
        .arg(config.asr_patience.to_string())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    #[cfg(windows)]
    command.creation_flags(0x08000000);
    let mut child = command.spawn().map_err(|_| "无法启动 Python 识别进程")?;
    let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
    let mut input = child.stdin.take().unwrap();
    let (frame_tx, mut frames) = mpsc::channel::<audio::Frame>(64);
    let stop = Arc::new(AtomicBool::new(false));
    let dropped = Arc::new(AtomicU64::new(0));
    let (error_tx, mut errors) = mpsc::unbounded_channel();
    let writer_app = app.clone();
    let writer_shared = shared.clone();
    let writer = tauri::async_runtime::spawn(async move {
        let mut last_meter = 0.0;
        while let Some(frame) = frames.recv().await {
            if frame.start - last_meter >= 0.1 {
                last_meter = frame.start;
                let rms = (frame.samples.iter().map(|s| s * s).sum::<f32>()
                    / frame.samples.len().max(1) as f32)
                    .sqrt();
                emit(
                    &writer_app,
                    &writer_shared,
                    json!({"type":"level", "value":rms}),
                );
            }
            let bytes: Vec<u8> = frame.samples.iter().flat_map(|s| s.to_le_bytes()).collect();
            let message = json!({"type":"audio", "sample_rate":frame.sample_rate,
                "start":frame.start, "pcm":STANDARD.encode(bytes)})
            .to_string()
                + "\n";
            if input.write_all(message.as_bytes()).await.is_err() {
                return;
            }
        }
        let _ = input.write_all(b"{\"type\":\"stop\"}\n").await;
        let _ = input.shutdown().await;
    });
    let (translation_tx, mut translations) = mpsc::channel::<Job>(64);
    let translation_app = app.clone();
    let translation_shared = shared.clone();
    let translation_config = config.clone();
    let mut translator = tauri::async_runtime::spawn(async move {
        let service = DeepSeekTranslationService::new();
        while let Some(job) = translations.recv().await {
            let queue_ms = job.queued_at.elapsed().as_millis();
            let result = match (&service, SecretStore::read()) {
                (Ok(service), Ok(Some(key))) => {
                    emit(
                        &translation_app,
                        &translation_shared,
                        json!({"type":"translation_started", "id":job.id}),
                    );
                    service
                        .translate(
                            &key,
                            translation::body(
                                &job,
                                &translation_config.translation_model,
                                &translation_config.domain,
                                &translation_config.glossary,
                            ),
                            |text| {
                                emit(
                                    &translation_app,
                                    &translation_shared,
                                    json!({"type":"translation_delta", "id":job.id, "text":text}),
                                );
                            },
                        )
                        .await
                }
                (_, Ok(None)) => Err("尚未设置 API Key，英文已保留".into()),
                (_, Err(e)) => Err(e),
                (Err(e), _) => Err(e.clone()),
            };
            match result {
                Ok(output) => {
                    emit(
                        &translation_app,
                        &translation_shared,
                        json!({"type":"translation_done", "id":job.id, "text":output.text}),
                    );
                    emit(
                        &translation_app,
                        &translation_shared,
                        json!({"type":"latency", "id":job.id, "provisional":job.provisional,
                            "queue_ms":queue_ms,
                            "first_token_ms":output.first_token_ms, "total_ms":output.total_ms}),
                    );
                }
                Err(message) => emit(
                    &translation_app,
                    &translation_shared,
                    json!({"type":"translation_error", "id":job.id, "message":message}),
                ),
            }
        }
    });
    let mut frame_tx = Some(frame_tx);
    let mut history = VecDeque::new();
    let mut preview_translation_at: HashMap<String, f64> = HashMap::new();
    let mut stopping = false;
    let mut deadline = tokio::time::Instant::now() + Duration::from_secs(180);
    let mut listening = false;
    let mut failure = None;
    loop {
        tokio::select! {
            _ = stop_rx.changed(), if !stopping => {
                stopping = true; stop.store(true, Ordering::Relaxed); frame_tx.take();
                deadline = tokio::time::Instant::now() + Duration::from_secs(30);
            }
            _ = tokio::time::sleep_until(deadline), if stopping || !listening => {
                failure = Some("识别进程超时；已结束会话，已完成的英文仍保留。".into()); break;
            }
            Some(message) = errors.recv() => { failure = Some(message); break; }
            line = lines.next_line() => {
                let line = match line { Ok(Some(line)) if line.len() < 262144 => line,
                    Ok(None) => { if !stopping { failure = Some("本地识别进程已退出".into()); } break; },
                    _ => { failure = Some("本地识别通信失败".into()); break; } };
                let event: Value = match serde_json::from_str(&line) { Ok(v) => v, Err(_) => continue };
                match event["type"].as_str().unwrap_or("") {
                    "ready" if !stopping && !listening => {
                        if let Some(tx) = frame_tx.take() {
                            match tokio::time::timeout(Duration::from_secs(10), audio::capture(config.input_mode, config.device_id.clone(), config.gain, tx, stop.clone(), dropped.clone(), error_tx.clone())).await {
                                Ok(Ok(Ok(()))) => { listening = true;
                                    emit(app, shared, json!({"type":"status", "state":"LISTENING"})); },
                                Ok(Ok(Err(e))) => { failure = Some(e); break; },
                                _ => { failure = Some("音频采集启动失败或超时".into()); break; },
                            }
                        }
                    }
                    "asr_final" => {
                        let text = event["text"].as_str().unwrap_or("").trim().to_string();
                        let id = event["id"].as_str().unwrap_or("").to_string();
                        if text.is_empty() || text.len() > 12000 || id.is_empty() { continue; }
                        emit(app, shared, event);
                        let job = Job { id: id.clone(), text: text.clone(),
                            context: history.iter().cloned().collect(), queued_at: Instant::now(),
                            provisional: false };
                        translation::remember(&mut history, text, config.context_length);
                        emit(app, shared, json!({"type":"translation_queued", "id":id}));
                        if translation_tx.try_send(job).is_err() {
                            emit(app, shared, json!({"type":"translation_error", "id":id, "message":"翻译队列已满，英文已保留。"}));
                        }
                    }
                    "translation_hint" => {
                        let text = event["text"].as_str().unwrap_or("").trim().to_string();
                        let id = event["id"].as_str().unwrap_or("").to_string();
                        let end = event["end"].as_f64().unwrap_or(0.0);
                        let last = preview_translation_at.entry(id.clone()).or_insert(0.0);
                        if !text.is_empty() && text.len() <= 12000 && !id.is_empty()
                            && end - *last >= 2.0 {
                            *last = end;
                            let job = Job { id: id.clone(), text,
                                context: history.iter().cloned().collect(), queued_at: Instant::now(),
                                provisional: true };
                            emit(app, shared, json!({"type":"translation_queued", "id":id}));
                            if translation_tx.try_send(job).is_err() {
                                emit(app, shared, json!({"type":"translation_error", "id":id,
                                    "message":"翻译队列已满，英文识别继续。"}));
                            }
                        }
                    }
                    "error" => { emit(app, shared, event); failure = Some("本地识别无法继续，请检查环境。".into()); break; }
                    "asr_partial" | "asr_clear" | "warning" => emit(app, shared, event),
                    "stopped" => break,
                    _ => {}
                }
                let missed = dropped.swap(0, Ordering::Relaxed);
                if missed > 0 { emit(app, shared, json!({"type":"warning", "message":format!("音频处理过慢，丢失 {missed} 个音频块。请换用较小模型。")})); }
            }
        }
    }
    stop.store(true, Ordering::Relaxed);
    drop(frame_tx);
    let _ = child.kill().await;
    let _ = child.wait().await;
    writer.abort();
    let _ = writer.await;
    drop(translation_tx);
    if tokio::time::timeout(Duration::from_secs(30), &mut translator)
        .await
        .is_err()
    {
        translator.abort();
        let _ = translator.await;
        emit(
            app,
            shared,
            json!({"type":"warning", "message":"停止等待超时，剩余片段仅保留英文。"}),
        );
    }
    if let Some(message) = failure {
        Err(message)
    } else {
        Ok(())
    }
}

fn app_data_dir(app: &AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map_err(|_| "无法访问应用数据目录".into())
}

fn runtime_root(app: &AppHandle) -> PathBuf {
    if let Ok(resource) = app.path().resource_dir() {
        if resource.join("asr-sidecar").join("main.py").is_file() {
            return resource;
        }
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}
