"""Exercise actual stdin/stdout IPC and the downloaded model with a local fixture.

Usage: .venv/Scripts/python.exe scripts/smoke_asr.py --realtime --device cuda
"""
import base64
import argparse
import json
import pathlib
import queue
import subprocess
import sys
import threading
import time

import numpy as np
from faster_whisper import decode_audio

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("audio", nargs="?", default=str(root / "test-assets/english-jfk.flac"))
parser.add_argument("--device", choices=["cpu", "cuda"], default="cuda")
parser.add_argument("--model", default="distil-large-v3")
parser.add_argument("--realtime", action="store_true")
args = parser.parse_args()
audio = decode_audio(args.audio, sampling_rate=48000)
audio = np.concatenate((audio, np.zeros(48000, dtype=np.float32)))
events = queue.Queue()
started = time.monotonic()
process = subprocess.Popen([sys.executable, '-u', str(root/'asr-sidecar/main.py'),
                            '--model', args.model, '--device', args.device],
                           stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           creationflags=0x08000000 if sys.platform == 'win32' else 0)

def reader():
    for line in process.stdout:
        events.put(json.loads(line))
    events.put({'type':'eof'})

threading.Thread(target=reader, daemon=True).start()
received = []
try:
    while True:
        event = events.get(timeout=90)
        if event['type']=='ready':
            break
        if event['type'] in ['error','eof']:
            raise RuntimeError(event)
    ready = time.monotonic()
    for i in range(0,len(audio),4800):
        samples = audio[i:i+4800].astype('<f4').tobytes()
        message = {'type':'audio','sample_rate':48000,'start':i/48000,
                   'pcm':base64.b64encode(samples).decode('ascii')}
        process.stdin.write((json.dumps(message)+'\n').encode())
        process.stdin.flush()
        if args.realtime:
            time.sleep(len(audio[i:i+4800]) / 48000)
    process.stdin.write(b'{"type":"stop"}\n')
    process.stdin.close()
    while True:
        event = events.get(timeout=90)
        received.append(event)
        if event['type']=='stopped':
            break
        if event['type'] in ['error','eof']:
            raise RuntimeError(event)
    assert process.wait(timeout=10)==0
    finals = [e for e in received if e['type']=='asr_final']
    text = ' '.join(e['text'] for e in finals)
    assert 'country' in text.lower(), text
    assert 'americans' in text.lower(), text
    assert all(e['start'] < e['end'] for e in finals)
    visible_groups = 0
    previous_end = None
    for event in finals:
        if previous_end is None or event['start'] - previous_end > 2:
            visible_groups += 1
        previous_end = event['end']
    assert visible_groups == 1, finals
    partial_count = sum(e['type']=='asr_partial' for e in received)
    if args.realtime:
        assert partial_count > 0, received
    report = {'model':args.model,'device':args.device, 'source_seconds':len(audio)/48000,
              'load_seconds':round(ready-started,2),'processing_seconds':round(time.monotonic()-ready,2),
              'finals':finals,'visible_groups':visible_groups,
              'partial_count':partial_count}
    (root/'artifacts/asr-smoke.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
finally:
    if process.poll() is None:
        process.kill()
    process.wait()
