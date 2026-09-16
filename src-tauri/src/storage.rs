use serde_json::{json, Value};
use std::{
    collections::HashMap,
    io::{BufRead, BufReader},
    path::Path,
};

fn stamp(seconds: f64) -> String {
    let ms = (seconds.max(0.) * 1000.).round() as u64;
    format!(
        "{:02}:{:02}:{:02},{:03}",
        ms / 3600000,
        ms / 60000 % 60,
        ms / 1000 % 60,
        ms % 1000
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamps_round_across_hour_boundary() {
        assert_eq!(stamp(3599.9996), "01:00:00,000");
        assert_eq!(stamp(-1.), "00:00:00,000");
    }

    #[test]
    fn export_preserves_english_after_failure_and_correlates_translation() {
        let dir = std::env::temp_dir().join(format!("linguaglass-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir(&dir).unwrap();
        let input = dir.join("session.jsonl");
        let events = [
            json!({"type":"asr_final","id":"a","start":0.1,"end":2.,"text":"Gradient descent."}),
            json!({"type":"asr_final","id":"b","start":2.,"end":4.,"text":"A second sentence."}),
            json!({"type":"translation_error","id":"b","message":"Offline"}),
            json!({"type":"translation_done","id":"a","text":"梯度下降。"}),
        ];
        std::fs::write(
            &input,
            events
                .iter()
                .map(Value::to_string)
                .collect::<Vec<_>>()
                .join("\n"),
        )
        .unwrap();
        let json_path = export(&input, "json").unwrap();
        let rows: Value =
            serde_json::from_str(&std::fs::read_to_string(&json_path).unwrap()).unwrap();
        assert_eq!(rows[0]["zh"], "梯度下降。");
        assert_eq!(rows[1]["en"], "A second sentence.");
        assert_eq!(rows[1]["translation_error"], "Offline");
        for format in ["srt", "md", "txt"] {
            let output = export(&input, format).unwrap();
            let text = std::fs::read_to_string(&output).unwrap();
            assert!(text.contains("A second sentence."));
            if format == "srt" {
                assert!(text.contains("00:00:00,100 --> 00:00:02,000"));
            }
            std::fs::remove_file(output).unwrap();
        }
        assert!(export(&input, "exe").is_err());
        std::fs::remove_file(json_path).unwrap();
        std::fs::remove_file(input).unwrap();
        std::fs::remove_dir(dir).unwrap();
    }
}
pub fn export(path: &Path, format: &str) -> Result<String, String> {
    if !["txt", "md", "json", "srt"].contains(&format) {
        return Err("不支持的导出格式".into());
    }
    let file = std::fs::File::open(path).map_err(|_| "无法读取会话记录")?;
    let mut rows: Vec<Value> = Vec::new();
    let mut index = HashMap::new();
    for line in BufReader::new(file).lines() {
        let line = line.map_err(|_| "读取会话记录失败")?;
        let Ok(e) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let id = e["id"].as_str().unwrap_or("").to_string();
        match e["type"].as_str().unwrap_or("") {
            "asr_final" => {
                index.insert(id.clone(), rows.len());
                rows.push(json!({"id":id, "start":e["start"], "end":e["end"], "en":e["text"], "zh":"", "translation_error":null}));
            }
            "translation_done" => {
                if let Some(i) = index.get(&id) {
                    rows[*i]["zh"] = e["text"].clone();
                }
            }
            "translation_error" => {
                if let Some(i) = index.get(&id) {
                    rows[*i]["translation_error"] = e["message"].clone();
                }
            }
            _ => {}
        }
    }
    let text = if format == "json" {
        serde_json::to_string_pretty(&rows).map_err(|_| "导出失败")?
    } else {
        rows.iter()
            .enumerate()
            .map(|(i, r)| {
                let start = stamp(r["start"].as_f64().unwrap_or(0.));
                let end = stamp(r["end"].as_f64().unwrap_or(0.));
                let en = r["en"].as_str().unwrap_or("");
                let zh = r["zh"].as_str().unwrap_or("");
                match format {
                    "srt" => format!("{}\n{} --> {}\n{}\n{}\n\n", i + 1, start, end, en, zh),
                    "md" => format!("### {start}\n\n{en}\n\n{zh}\n\n"),
                    _ => format!("[{start}]\nEN: {en}\nZH: {zh}\n\n"),
                }
            })
            .collect::<String>()
    };
    let output = path.with_extension(format);
    std::fs::write(&output, text).map_err(|_| "无法写入导出文件")?;
    Ok(output.to_string_lossy().into_owned())
}
