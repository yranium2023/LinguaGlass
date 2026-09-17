use linguaglass_lib::translation::{self, DeepSeekTranslationService, Job};
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    io::{self, BufRead, Write},
    time::Instant,
};

fn emit(value: Value) {
    let mut stdout = io::stdout().lock();
    let _ = writeln!(stdout, "{value}");
    let _ = stdout.flush();
}

fn string(value: &Value, key: &str, limit: usize) -> Result<String, String> {
    let text = value[key].as_str().unwrap_or("").trim().to_owned();
    if text.is_empty() || text.len() > limit {
        return Err(format!("参数 {key} 无效"));
    }
    Ok(text)
}

#[tokio::main]
async fn main() {
    // The main app is the sole Keychain owner. This helper receives one in-memory
    // copy at launch and never talks to Security.framework itself.
    emit(json!({"type":"service_ready"}));
    let translator = DeepSeekTranslationService::new();
    let mut history = VecDeque::new();
    let mut cached_key: Option<String> = None;

    for line in io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        if line.len() > 32_768 { continue; }
        let Ok(command) = serde_json::from_str::<Value>(&line) else { continue; };
        let request_id = command["request_id"].as_str().unwrap_or("").to_owned();
        match command["type"].as_str().unwrap_or("") {
            "key_status" => emit(json!({"type":"key_status", "request_id":request_id,
                "key_ready":cached_key.is_some()})),
            "set_runtime_key" => match string(&command, "key", 512) {
                Ok(key) => {
                    cached_key = Some(key);
                    emit(json!({"type":"key_status", "request_id":request_id, "key_ready":true}));
                }
                Err(message) => emit(json!({"type":"service_error", "request_id":request_id, "message":message})),
            },
            "clear_runtime_key" => {
                cached_key = None;
                emit(json!({"type":"key_status", "request_id":request_id, "key_ready":false}));
            }
            "reset_context" => {
                history.clear();
                emit(json!({"type":"context_reset", "request_id":request_id}));
            }
            "translate" => {
                let id = command["id"].as_str().unwrap_or("").to_owned();
                let text = match string(&command, "text", 12_000) {
                    Ok(text) if !id.is_empty() => text,
                    _ => {
                        emit(json!({"type":"translation_error", "id":id, "message":"翻译文本无效"}));
                        continue;
                    }
                };
                if cached_key.is_none() {
                    emit(json!({"type":"translation_error", "id":id, "request_id":request_id,
                        "message":"尚未设置 DeepSeek API Key，英文已保留"}));
                    continue;
                }
                let key = cached_key.clone().unwrap_or_default();
                let service = match &translator {
                    Ok(service) => service.clone(),
                    Err(message) => {
                        emit(json!({"type":"translation_error", "id":id, "message":message}));
                        continue;
                    }
                };
                let requested_model = command["model"].as_str().unwrap_or("deepseek-v4-flash");
                let model = if ["deepseek-v4-flash", "deepseek-v4-pro"].contains(&requested_model) {
                    requested_model.to_owned()
                } else {
                    "deepseek-v4-flash".to_owned()
                };
                let domain = command["domain"].as_str().unwrap_or("General").to_owned();
                let glossary = command["glossary"].as_str().unwrap_or("").to_owned();
                let context_length = command["context_length"].as_u64().unwrap_or(3).min(4) as usize;
                let provisional = command["provisional"].as_bool().unwrap_or(false);
                let job = Job {
                    id: id.clone(),
                    text: text.clone(),
                    context: history.iter().cloned().collect(),
                    queued_at: Instant::now(),
                    provisional,
                };
                if !provisional { translation::remember(&mut history, text, context_length); }
                emit(json!({"type":"translation_started", "id":id, "request_id":request_id}));
                tokio::spawn(async move {
                    let result = service
                        .translate(&key, translation::body(&job, &model, &domain, &glossary), |translated| {
                            emit(json!({"type":"translation_delta", "id":id, "request_id":request_id, "text":translated}));
                        })
                        .await;
                    match result {
                        Ok(output) => emit(json!({"type":"translation_done", "id":id, "text":output.text,
                            "request_id":request_id, "first_token_ms":output.first_token_ms,
                            "total_ms":output.total_ms})),
                        Err(message) => emit(json!({"type":"translation_error", "id":id,
                            "request_id":request_id, "message":message})),
                    }
                });
            }
            "stop" => break,
            _ => emit(json!({"type":"service_error", "request_id":request_id, "message":"未知服务命令"})),
        }
    }
}
