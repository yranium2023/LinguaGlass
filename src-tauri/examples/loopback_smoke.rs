//! Actual WASAPI loopback validation; emits a short quiet 1 kHz test tone.
#[allow(dead_code)]
#[path = "../src/audio/mod.rs"]
mod audio;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Arc,
};
use std::time::{Duration, Instant};

fn main() {
    let runtime = tokio::runtime::Runtime::new().unwrap();
    runtime.block_on(async {
        let (tx, mut rx) = tokio::sync::mpsc::channel(128);
        let (err_tx, mut err_rx) = tokio::sync::mpsc::unbounded_channel();
        let stop = Arc::new(AtomicBool::new(false));
        let dropped = Arc::new(AtomicU64::new(0));
        audio::capture(
            audio::InputMode::System,
            None,
            1.,
            tx,
            stop.clone(),
            dropped.clone(),
            err_tx,
        )
        .await
        .unwrap()
        .unwrap();
        let device = cpal::default_host()
            .default_output_device()
            .expect("No playback device");
        let supported = device.default_output_config().unwrap();
        let config = supported.config();
        let stream = match supported.sample_format() {
            cpal::SampleFormat::F32 => tone::<f32>(&device, &config),
            cpal::SampleFormat::I16 => tone::<i16>(&device, &config),
            cpal::SampleFormat::U16 => tone::<u16>(&device, &config),
            _ => panic!("unsupported output format"),
        };
        stream.play().unwrap();
        let started = Instant::now();
        let mut captured = 0;
        let mut max_rms = 0f32;
        let mut last_start = -1.;
        while started.elapsed() < Duration::from_secs(2) {
            if let Ok(Some(frame)) =
                tokio::time::timeout(Duration::from_millis(200), rx.recv()).await
            {
                assert!(frame.start >= last_start, "Non-monotonic capture time");
                last_start = frame.start;
                captured += frame.samples.len();
                let rms = (frame.samples.iter().map(|s| s * s).sum::<f32>()
                    / frame.samples.len().max(1) as f32)
                    .sqrt();
                max_rms = max_rms.max(rms);
            }
        }
        stop.store(true, Ordering::Relaxed);
        drop(stream);
        assert!(err_rx.try_recv().is_err(), "Audio error");
        assert!(captured > 16000, "No loopback data");
        assert!(max_rms > 0.0005, "Loopback did not capture the test signal");
        assert_eq!(dropped.load(Ordering::Relaxed), 0);
        println!(
            "LOOPBACK_OK samples={captured} peak_rms={max_rms:.5} last_timestamp={last_start:.3}"
        );
    });
}
fn tone<T>(device: &cpal::Device, config: &cpal::StreamConfig) -> cpal::Stream
where
    T: cpal::SizedSample + cpal::FromSample<f32>,
{
    let channels = config.channels as usize;
    let rate = config.sample_rate.0 as f32;
    let mut frame_index = 0f32;
    device
        .build_output_stream(
            config,
            move |data: &mut [T], _| {
                for frame in data.chunks_exact_mut(channels) {
                    let sample =
                        (frame_index * 1000. * 2. * std::f32::consts::PI / rate).sin() * 0.03;
                    frame_index = (frame_index + 1.) % rate;
                    for out in frame {
                        *out = T::from_sample(sample);
                    }
                }
            },
            |_| {},
            None,
        )
        .unwrap()
}
