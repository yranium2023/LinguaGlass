"""Local JSON Lines protocol. stdout is reserved for protocol messages."""
import base64
import json
import math
import threading

MAX_LINE_BYTES = 2_000_000


def decode_audio(message):
    import numpy as np
    rate = message.get("sample_rate")
    if not isinstance(rate, int) or not 8000 <= rate <= 192000:
        raise ValueError("Unsupported sample rate")
    start = message.get("start")
    if not isinstance(start, (int, float)) or not math.isfinite(start) or start < 0:
        raise ValueError("Invalid audio timestamp")
    raw = base64.b64decode(message["pcm"], validate=True)
    if len(raw) % 4 or len(raw) > rate * 4 * 2:
        raise ValueError("Invalid PCM frame length")
    samples = np.frombuffer(raw, dtype="<f4")
    if not np.isfinite(samples).all():
        raise ValueError("Non-finite PCM")
    return rate, float(start), np.clip(samples, -1, 1)


class Emitter:
    def __init__(self, stream):
        self.stream = stream
        self.lock = threading.Lock()

    def __call__(self, kind, **fields):
        with self.lock:
            self.stream.write(json.dumps({"type": kind, **fields}, ensure_ascii=False) + "\n")
            self.stream.flush()
