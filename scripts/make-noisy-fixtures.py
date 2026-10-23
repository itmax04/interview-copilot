#!/usr/bin/env python3
"""Набор для eval `enhance` (COPILOT-05 R-04): 10 вопросов uk/ru/en чистыми и на фоне — шум «улица» (SNR 5 дБ),
музыка, клавиатура, чужая речь «ТВ». Звук — evals/audio/noisy/ (не в Git), манифест — evals/filter/noisy-cases.json.
Usage: scripts/make-noisy-fixtures.py"""
import json, subprocess, tempfile, wave
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parent.parent
out = root / "evals/audio/noisy"
out.mkdir(parents=True, exist_ok=True)
SR = 16000
rng = np.random.default_rng(5)

def say(voice, text):
    with tempfile.TemporaryDirectory() as tmp:
        aiff, wav = Path(tmp) / "a.aiff", Path(tmp) / "a.wav"
        subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        with wave.open(str(wav)) as w:
            return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768

def rms(x): return float(np.sqrt(np.mean(x ** 2)) + 1e-9)

def fit(noise, n):
    reps = int(np.ceil(n / len(noise))); return np.tile(noise, reps)[:n]

def mix(speech, noise, snr_db):
    noise = fit(noise, len(speech))
    return speech + noise * (rms(speech) / rms(noise)) / (10 ** (snr_db / 20))

def pink(n):
    w = rng.normal(0, 1, n); y = np.cumsum(w); y -= np.convolve(y, np.ones(400) / 400, mode="same"); return y

def keyboard(n):
    y = np.zeros(n)
    for at in rng.integers(0, n - 400, size=int(n / SR * 8)):
        y[at:at + 400] += rng.normal(0, 1, 400) * np.exp(-np.arange(400) / 60)
    return y

def music(n):
    t = np.arange(n) / SR; y = np.zeros(n)
    for i, f in enumerate([220, 262, 330, 392, 440, 392, 330, 262] * 8):
        a, b = int(i * 0.5 * SR), int((i + 1) * 0.5 * SR)
        if a >= n: break
        s = t[a:b] - t[a]; y[a:b] += np.sin(2 * np.pi * f * s) * np.exp(-3 * s)
    return y

questions = [
    ("Milena", "ru", "Расскажите, пожалуйста, о своём последнем проекте."),
    ("Milena", "ru", "Как вы решаете конфликты в команде?"),
    ("Milena", "ru", "Почему вы хотите сменить место работы?"),
    ("Milena", "ru", "Какие задачи вы решали на прошлой работе?"),
    ("Lesya", "uk", "Розкажіть, будь ласка, про свій останній проєкт."),
    ("Lesya", "uk", "Як ви вирішуєте конфлікти в команді?"),
    ("Lesya", "uk", "Чому ви хочете змінити місце роботи?"),
    ("Samantha", "en", "Tell me about your most recent project."),
    ("Samantha", "en", "How do you handle disagreements in your team?"),
    ("Samantha", "en", "Why are you looking for a new job?"),
]
tv = say("Anna", "Heute Abend gibt es in den Nachrichten einen langen Bericht über das Wetter und den Verkehr in Berlin und München.")
cases = []
for i, (voice, lang, text) in enumerate(questions):
    q = np.concatenate([np.zeros(int(0.3 * SR)), say(voice, text), np.zeros(int(0.5 * SR))])
    n = len(q)
    variants = {"clean": q, "street-5db": mix(q, pink(n), 5), "music-5db": mix(q, music(n), 5),
                "keyboard-5db": mix(q, keyboard(n), 5), "tv-10db": mix(q, tv, 10)}
    for kind, x in variants.items():
        name = f"{lang}-{i}-{kind}.wav"
        x = np.clip(x / max(1.0, np.max(np.abs(x)) / 0.9), -1, 1)
        with wave.open(str(out / name), "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
        cases.append({"file": name, "lang": lang, "noise": kind, "text": text})
(root / "evals/filter/noisy-cases.json").write_text(json.dumps(cases, ensure_ascii=False, indent=1) + "\n")
print(f"{len(cases)} cases -> {out}")
