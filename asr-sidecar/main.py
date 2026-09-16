import argparse
import json
import sys

from protocol import Emitter, MAX_LINE_BYTES, decode_audio


def main():
    from gpu_runtime import configure, available
    configure()
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="distil-large-v3")
    parser.add_argument("--model-path")
    parser.add_argument("--model-dir", help="Directory used for downloaded Whisper models")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    parser.add_argument("--domain", default="")
    parser.add_argument("--glossary", default="")
    parser.add_argument("--silence-ms", type=int, default=900)
    parser.add_argument("--max-segment-seconds", type=float, default=20.0)
    parser.add_argument("--patience", type=float, default=1.2)
    parser.add_argument("--download-model", action="store_true")
    parser.add_argument("--doctor", action="store_true")
    args = parser.parse_args()
    if args.doctor:
        import importlib.util
        required = ["faster_whisper", "numpy", "soxr", "onnxruntime", "ctranslate2"]
        missing = [name for name in required if importlib.util.find_spec(name) is None]
        models = []
        cuda_available = False
        if not missing:
            from faster_whisper.utils import download_model
            import ctranslate2
            for model in ['distil-large-v3','distil-medium.en','distil-small.en']:
                try:
                    download_model(model, cache_dir=args.model_dir, local_files_only=True)
                    models.append(model)
                except Exception:
                    pass
            try:
                cuda_available = available()
            except Exception:
                pass
        print(json.dumps({"python": sys.version.split()[0], "missing": missing,
                          "models":models,"cuda_available":cuda_available}))
        return 1 if missing else 0
    if args.download_model:
        from faster_whisper.utils import download_model
        print(download_model(args.model, cache_dir=args.model_dir))
        return 0
    sys.stdout.reconfigure(encoding="utf-8")
    emit = Emitter(sys.stdout)
    engine = None
    try:
        from engine import Engine
        emit("status", state="INITIALIZING", message="正在加载本地语音模型…")
        if args.device == "cuda":
            emit("status", state="INITIALIZING", message="正在预热 GPU，首次启动请稍候…")
        hotwords = []
        if args.domain and args.domain.lower() != "general":
            hotwords.append(args.domain.strip())
        for line in args.glossary.splitlines():
            term = line.split("=", 1)[0].strip()
            if term:
                hotwords.append(term)
        engine = Engine(
            emit,
            args.model,
            args.device,
            args.model_path or _local_model_path(args.model, args.model_dir),
            ", ".join(hotwords)[:2000],
            args.silence_ms,
            args.max_segment_seconds,
            args.patience,
        )
        emit("ready")
        while True:
            line = sys.stdin.buffer.readline(MAX_LINE_BYTES + 1)
            if not line:
                break
            if len(line) > MAX_LINE_BYTES:
                raise ValueError("Oversized IPC message")
            message = json.loads(line)
            if message.get("type") == "stop":
                break
            if message.get("type") != "audio":
                raise ValueError("Unknown IPC message")
            engine.feed(*decode_audio(message))
    except Exception:
        # Do not leak paths, arbitrary exception strings or third-party payloads.
        emit("error", message="本地识别不可用：请运行环境检查，下载模型并确认 CPU/CUDA 设置。")
        return 1
    finally:
        if engine is not None:
            engine.close()
        emit("stopped")
    return 0


def _local_model_path(model: str, model_dir: str | None) -> str | None:
    """Resolve a downloaded model without allowing inference to fetch it."""
    if not model_dir:
        return None
    from faster_whisper.utils import download_model
    try:
        return str(download_model(model, cache_dir=model_dir, local_files_only=True))
    except Exception as exc:
        raise RuntimeError("model is not installed") from exc


if __name__ == "__main__":
    raise SystemExit(main())


