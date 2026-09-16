use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use serde::{Deserialize, Serialize};
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc,
};
use tokio::sync::mpsc;

#[derive(Serialize)]
pub struct AudioDevice {
    pub id: String,
    pub name: String,
}
pub struct Frame {
    pub samples: Vec<f32>,
    pub sample_rate: u32,
    pub start: f64,
}
#[derive(Clone, Copy, Default, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum InputMode {
    #[default]
    Microphone,
    System,
}
impl InputMode {
    pub fn validate(self) -> Result<(), String> {
        if self == Self::System && !cfg!(target_os = "windows") {
            Err("当前平台暂不支持系统音频采集".into())
        } else {
            Ok(())
        }
    }
}
pub fn list(mode: InputMode) -> Result<Vec<AudioDevice>, String> {
    mode.validate()?;
    let host = cpal::default_host();
    let devices = if mode == InputMode::System {
        host.output_devices()
    } else {
        host.input_devices()
    }
    .map_err(|_| "无法枚举音频设备")?;
    Ok(devices
        .enumerate()
        .filter_map(|(index, device)| {
            let name = device.name().ok()?;
            Some(AudioDevice {
                id: format!("{index}|{name}"),
                name,
            })
        })
        .collect())
}
pub trait AudioCaptureBackend {
    fn devices(&self) -> Result<Vec<AudioDevice>, String>;
}
pub struct MicrophoneBackend;
pub struct SystemAudioBackend;
impl AudioCaptureBackend for SystemAudioBackend {
    fn devices(&self) -> Result<Vec<AudioDevice>, String> {
        list(InputMode::System)
    }
}
impl AudioCaptureBackend for MicrophoneBackend {
    fn devices(&self) -> Result<Vec<AudioDevice>, String> {
        list(InputMode::Microphone)
    }
}
pub fn capture(
    mode: InputMode,
    device_id: Option<String>,
    gain: f32,
    tx: mpsc::Sender<Frame>,
    stop: Arc<AtomicBool>,
    dropped: Arc<AtomicU64>,
    errors: mpsc::UnboundedSender<String>,
) -> tokio::sync::oneshot::Receiver<Result<(), String>> {
    let (ready_tx, ready_rx) = tokio::sync::oneshot::channel();
    std::thread::spawn(move || {
        let result = (|| {
            mode.validate()?;
            let host = cpal::default_host();
            let device = if let Some(id) = device_id {
                let (index, name) = id.split_once('|').ok_or("设备选择已过期，请刷新设备列表")?;
                let index: usize = index.parse().map_err(|_| "设备选择无效")?;
                let mut devices = if mode == InputMode::System {
                    host.output_devices()
                } else {
                    host.input_devices()
                }
                .map_err(|_| "无法枚举音频设备")?;
                devices
                    .nth(index)
                    .filter(|d| d.name().ok().as_deref() == Some(name))
            } else {
                if mode == InputMode::System {
                    host.default_output_device()
                } else {
                    host.default_input_device()
                }
            }
            .ok_or("找不到所选音频设备，请刷新列表并检查系统声音设置")?;
            // CPAL 0.16 WASAPI enables AUDCLNT_STREAMFLAGS_LOOPBACK when an
            // output endpoint is opened with build_input_stream.
            let config = if mode == InputMode::System {
                device.default_output_config()
            } else {
                device.default_input_config()
            }
            .map_err(|_| "无法读取音频设备格式")?;
            let stream_config = config.config();
            let stream = match config.sample_format() {
                cpal::SampleFormat::F32 => {
                    build::<f32>(&device, &stream_config, tx, dropped, errors, gain)
                }
                cpal::SampleFormat::I16 => {
                    build::<i16>(&device, &stream_config, tx, dropped, errors, gain)
                }
                cpal::SampleFormat::U16 => {
                    build::<u16>(&device, &stream_config, tx, dropped, errors, gain)
                }
                _ => return Err("暂不支持该音频设备的采样格式".to_string()),
            }?;
            stream
                .play()
                .map_err(|_| "无法启动音频采集，请检查设备连接及系统权限")?;
            Ok(stream)
        })();
        match result {
            Ok(stream) => {
                let _ = ready_tx.send(Ok(()));
                while !stop.load(Ordering::Relaxed) {
                    std::thread::sleep(std::time::Duration::from_millis(40));
                }
                drop(stream);
            }
            Err(error) => {
                let _ = ready_tx.send(Err(error));
            }
        }
    });
    ready_rx
}
fn build<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    tx: mpsc::Sender<Frame>,
    dropped: Arc<AtomicU64>,
    errors: mpsc::UnboundedSender<String>,
    gain: f32,
) -> Result<cpal::Stream, String>
where
    T: cpal::SizedSample,
    f32: cpal::FromSample<T>,
{
    let channels = config.channels as usize;
    let rate = config.sample_rate.0;
    let wall_start = std::time::Instant::now();
    let mut epoch: Option<(cpal::StreamInstant, f64)> = None;
    device
        .build_input_stream(
            config,
            move |data: &[T], info: &cpal::InputCallbackInfo| {
                let samples: Vec<f32> = data
                    .chunks_exact(channels)
                    .map(|frame| {
                        frame.iter().map(|s| s.to_sample::<f32>()).sum::<f32>() / channels as f32
                            * gain
                    })
                    .collect();
                let capture = info.timestamp().capture;
                let (first, base) = epoch.get_or_insert_with(|| {
                    (
                        capture,
                        (wall_start.elapsed().as_secs_f64() - samples.len() as f64 / rate as f64)
                            .max(0.),
                    )
                });
                let start = *base
                    + capture
                        .duration_since(first)
                        .map(|d| d.as_secs_f64())
                        .unwrap_or(0.);
                if tx
                    .try_send(Frame {
                        samples,
                        sample_rate: rate,
                        start,
                    })
                    .is_err()
                {
                    dropped.fetch_add(1, Ordering::Relaxed);
                }
            },
            move |_| {
                let _ = errors.send("音频设备连接中断，请刷新设备并重新开始。".into());
            },
            None,
        )
        .map_err(|_| "无法打开音频设备".into())
}
