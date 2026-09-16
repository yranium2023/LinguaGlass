"""Persistent local ASR with a separate ingestion and inference thread."""
import threading
import uuid

import numpy as np

from jobs import Jobs

RATE = 16000
STREAMING_COMMIT_SECONDS = 20.0
NATURAL_SILENCE_MS = 900


class Engine:
    def __init__(self, emit, model_name, device, model_path=None, hotwords="",
                 silence_ms=NATURAL_SILENCE_MS,
                 max_segment_seconds=STREAMING_COMMIT_SECONDS,
                 patience=1.2):
        from gpu_runtime import configure
        configure()
        from faster_whisper import WhisperModel
        from faster_whisper.vad import VadOptions, get_speech_timestamps
        import soxr

        self.emit = emit
        self.hotwords = hotwords.strip() or None
        self.silence_ms = min(2000, max(400, int(silence_ms)))
        self.max_segment_seconds = min(30.0, max(8.0, float(max_segment_seconds)))
        self.patience = min(2.0, max(1.0, float(patience)))
        # Downloads are an explicit setup step; listening must work offline.
        self.model = WhisperModel(
            model_path or model_name, device=device,
            compute_type="float16" if device == "cuda" else "int8",
            local_files_only=True,
        )
        # Prime CUDA kernels and memory allocations before real audio arrives.
        # A short silent inference avoids charging the first sentence with setup cost.
        if device == "cuda":
            list(self.model.transcribe(
                np.zeros(RATE, dtype=np.float32), language="en",
                beam_size=1, vad_filter=False, condition_on_previous_text=False,
            )[0])
        self.detect = lambda x: get_speech_timestamps(x, VadOptions(
            min_silence_duration_ms=self.silence_ms, speech_pad_ms=180,
            min_speech_duration_ms=160,
        ))
        self.soxr = soxr
        self.resampler = None
        self.input_rate = None
        self.expected_start = None
        self.buffer = np.empty(0, dtype=np.float32)
        self.origin = 0.0
        self.checked_at = 0
        self.partial_at = 0
        self.segment_id = str(uuid.uuid4())
        self.group_id = str(uuid.uuid4())
        self.jobs = Jobs()
        self.worker = threading.Thread(target=self.run, name="local-asr")
        self.worker.start()

    def feed(self, rate, start, samples):
        # Preserve the waveform when the user raises input gain. Clamping in the
        # capture callback flattened loud syllables and noticeably hurt ASR.
        peak = float(np.max(np.abs(samples))) if len(samples) else 0.0
        if peak > .98:
            samples = samples * (.98 / peak)
        discontinuity = self.expected_start is not None and abs(start - self.expected_start) > 0.05
        if rate != self.input_rate or discontinuity:
            if self.resampler is not None:
                self.append(self.resampler.resample_chunk(np.empty(0, dtype=np.float32), last=True))
            self.finalize()
            self.input_rate = rate
            self.resampler = self.soxr.ResampleStream(rate, RATE, 1, dtype="float32", quality="HQ")
            self.origin = start
            if discontinuity:
                self.emit("warning", message="音频出现间断，已开始新的识别片段。")
        self.expected_start = start + len(samples) / rate
        self.append(self.resampler.resample_chunk(samples))

    def append(self, samples):
        self.buffer = np.concatenate((self.buffer, samples))
        if len(self.buffer) - self.checked_at < int(RATE * .256):
            return
        self.checked_at = len(self.buffer)
        speech = self.detect(self.buffer)
        if not speech:
            if len(self.buffer) > RATE * 2:
                self.trim(len(self.buffer) - RATE // 2)
            return
        # Keep padding but discard long leading silence.
        first = speech[0]["start"]
        last_end = speech[-1]["end"]
        # Preserve enough acoustic context for coherent recognition. Translation
        # previews use the rolling partial result and do not force an ASR cut.
        has_ended = last_end < len(self.buffer) - int(RATE * .48)
        hit_streaming_limit = len(self.buffer) >= RATE * self.max_segment_seconds
        if has_ended or hit_streaming_limit:
            self.finalize(speech, continues=hit_streaming_limit and not has_ended)
        elif len(self.buffer) - self.partial_at >= int(RATE * 0.8):
            self.partial_at = len(self.buffer)
            self.jobs.put((self.segment_id, self.group_id, self.origin + first / RATE,
                           self.buffer[first:].copy()), final=False)

    def trim(self, count):
        self.buffer = self.buffer[count:].copy()
        self.origin += count / RATE
        self.checked_at = len(self.buffer)
        self.partial_at = 0

    def finalize(self, speech=None, continues=False):
        if len(self.buffer):
            speech = self.detect(self.buffer) if speech is None else speech
            if speech:
                begin, end = speech[0]["start"], speech[-1]["end"]
                accepted = self.jobs.put((self.segment_id, self.group_id,
                                          self.origin + begin / RATE,
                                          self.buffer[begin:end].copy()), final=True)
                if not accepted:
                    self.emit("warning", message="识别速度跟不上音频，部分片段未识别；请换用较小模型。")
                    self.emit("asr_clear", id=self.segment_id)
            else:
                self.emit("asr_clear", id=self.segment_id)
            self.trim(len(self.buffer))
        self.segment_id = str(uuid.uuid4())
        if not continues:
            self.group_id = str(uuid.uuid4())

    def run(self):
        while (item := self.jobs.get()) is not None:
            (segment_id, group_id, start, audio), final = item
            try:
                segments, _ = self.model.transcribe(
                    audio, language="en", condition_on_previous_text=False,
                    beam_size=5 if final else 1, vad_filter=not final,
                    patience=self.patience if final else 1.0,
                    word_timestamps=not final,
                    vad_parameters={"min_silence_duration_ms": self.silence_ms},
                    hotwords=self.hotwords,
                )
                if final:
                    # Whisper can yield several internal segments for one audio
                    # chunk. They belong to one visible utterance and one API job.
                    text = " ".join(segment.text.strip() for segment in segments).strip()
                    if text:
                        self.emit("asr_final", id=segment_id, group_id=group_id, start=start,
                                  end=start + len(audio) / RATE, text=text)
                    else:
                        self.emit("asr_clear", id=segment_id)
                else:
                    # Whisper yields words with timestamps. Emit each word as it
                    # becomes available so the UI feels live instead of sentence-batched.
                    words = []
                    for segment in segments:
                        if segment.words:
                            words.extend(word.word.strip() for word in segment.words if word.word.strip())
                        elif segment.text.strip():
                            words.append(segment.text.strip())
                    text = ""
                    for word in words:
                        text = f"{text} {word}".strip()
                        self.emit("asr_partial", id=segment_id, group_id=group_id, start=start,
                                  end=start + len(audio) / RATE, text=text)
                    if text:
                        self.emit("translation_hint", id=segment_id, group_id=group_id,
                                  start=start, end=start + len(audio) / RATE, text=text)
            except Exception:
                self.emit("warning", message="本地识别失败，请检查模型或计算设备。")
                if final:
                    self.emit("asr_clear", id=segment_id)

    def close(self):
        if self.resampler is not None:
            self.append(self.resampler.resample_chunk(np.empty(0, dtype=np.float32), last=True))
        self.finalize()
        self.jobs.close()
        self.worker.join()



