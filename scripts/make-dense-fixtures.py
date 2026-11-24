#!/usr/bin/env python3
"""Synthetic dense-speech set for the `stt-dense` eval (COPILOT-15 AC-01): questions from evals/stt-dense/texts.json are
spoken by macOS `say` (rate 210), then cut near every 1.1 s at the lowest-energy point (like the live VAD median phrase),
so the eval can compare per-chunk, whole-question and joined-phrase recognition.
Output: evals/audio/stt-dense/<id>-full.wav, <id>-cNN.wav and manifest.json (not in Git).
Usage: scripts/make-dense-fixtures.py"""
import json, os, subprocess, tempfile, wave
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parent.parent
out = root / "evals/audio/stt-dense"
out.mkdir(parents=True, exist_ok=True)
SR = 16000

def read(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)

def write(path, x):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(x.astype(np.int16).tobytes())

manifest = []
for id_, voice, text in json.load(open(root / "evals/stt-dense/texts.json")):
    with tempfile.TemporaryDirectory() as tmp:
        aiff = Path(tmp) / "a.aiff"
        full = out / f"{id_}-full.wav"
        subprocess.run(["say", "-v", voice, "-r", "210", "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(full)], check=True)
    x = read(full)
    fr = 320
    energy = np.array([np.sqrt(np.mean(x[i:i + fr].astype(float) ** 2)) for i in range(0, len(x) - fr, fr)])
    cuts, t = [0], int(1.1 * SR)
    while t < len(x) - int(0.6 * SR):
        lo = max(cuts[-1] + int(0.5 * SR), t - int(0.3 * SR))
        hi = min(len(x) - fr, t + int(0.3 * SR))
        idx = range(lo // fr, hi // fr)
        best = min(idx, key=lambda k: energy[k]) if len(idx) else t // fr
        cuts.append(best * fr + fr // 2)
        t = cuts[-1] + int(1.1 * SR)
    cuts.append(len(x))
    chunks = []
    for i in range(len(cuts) - 1):
        p = out / f"{id_}-c{i:02d}.wav"
        write(p, x[cuts[i]:cuts[i + 1]])
        chunks.append(p.name)
    manifest.append({"id": id_, "lang": id_[:2], "text": text, "full": full.name, "chunks": chunks, "seconds": len(x) / SR})
    print(id_, f"{len(x) / SR:.1f}s", len(chunks), "chunks")
(out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))
