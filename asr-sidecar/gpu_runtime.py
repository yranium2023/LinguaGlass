"""Discover project-local NVIDIA wheels without changing system PATH."""
import os
import site
from pathlib import Path

_handles = []


def configure():
    if os.name != "nt" or _handles:
        return
    for base in site.getsitepackages():
        for directory in sorted((Path(base) / "nvidia").glob("*/bin")):
            _handles.append(os.add_dll_directory(str(directory)))
            os.environ["PATH"] = str(directory) + os.pathsep + os.environ.get("PATH", "")


def available():
    configure()
    try:
        import ctypes
        import ctranslate2
        if ctranslate2.get_cuda_device_count() < 1:
            return False
        if os.name == "nt":
            for name in ("cublas64_12.dll", "cudnn64_9.dll"):
                ctypes.WinDLL(name)
        return "float16" in ctranslate2.get_supported_compute_types("cuda")
    except Exception:
        return False
