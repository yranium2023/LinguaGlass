"""Extract a small 16 kHz mono WAV fixture from a longer public recording."""

from __future__ import annotations

import argparse
import wave
from pathlib import Path

import av


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    parser.add_argument("--start", type=float, default=0)
    parser.add_argument("--duration", type=float, default=90)
    args = parser.parse_args()

    container = av.open(str(args.source))
    stream = container.streams.audio[0]
    if args.start:
        container.seek(int(args.start / float(stream.time_base)), stream=stream)
    resampler = av.AudioResampler(format="s16", layout="mono", rate=16_000)
    written = 0
    limit = round(args.duration * 16_000)
    args.target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(args.target), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16_000)
        for frame in container.decode(stream):
            timestamp = float(frame.pts * frame.time_base) if frame.pts is not None else 0
            if timestamp + float(frame.samples / frame.sample_rate) <= args.start:
                continue
            for converted in resampler.resample(frame):
                samples = converted.to_ndarray().reshape(-1)
                remaining = limit - written
                if remaining <= 0:
                    return
                samples = samples[:remaining]
                output.writeframes(samples.tobytes())
                written += len(samples)
                if written >= limit:
                    return


if __name__ == "__main__":
    main()
