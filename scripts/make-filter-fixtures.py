#!/usr/bin/env python3
"""Синтетический набор для eval `filter` (COPILOT-05 P-01): вопросы с терминами, «ТВ» на других языках, шум без речи,
вопросы на фоне музыки. Голоса macOS `say`, шум — синтез numpy (детерминированный seed). 16 кГц моно WAV.
Звук в Git не попадает (evals/audio/filter/ в .gitignore); манифест evals/filter/audio-cases.json — в Git.
Usage: scripts/make-filter-fixtures.py"""
import json, subprocess, tempfile, wave
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parent.parent
out = root / "evals/audio/filter"
out.mkdir(parents=True, exist_ok=True)
SR = 16000
rng = np.random.default_rng(20261023)

def say(voice, text):
    with tempfile.TemporaryDirectory() as tmp:
        aiff, wav = Path(tmp) / "a.aiff", Path(tmp) / "a.wav"
        subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        with wave.open(str(wav)) as w:
            return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768

def save(name, x):
    x = np.concatenate([np.zeros(int(0.4 * SR)), x, np.zeros(int(0.6 * SR))])
    x = np.clip(x, -1, 1)
    with wave.open(str(out / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    return name

def music(seconds, level):
    t = np.arange(int(seconds * SR)) / SR
    notes = [220, 262, 330, 392, 440, 392, 330, 262]
    y = np.zeros_like(t)
    for i, f in enumerate(notes * int(seconds)):
        a, b = int(i * 0.5 * SR), int((i + 1) * 0.5 * SR)
        if a >= len(t): break
        seg = t[a:b] - t[a]
        y[a:b] += np.sin(2 * np.pi * f * seg) * np.exp(-3 * seg) + 0.5 * np.sin(2 * np.pi * f * 1.5 * seg) * np.exp(-4 * seg)
    return y / np.max(np.abs(y)) * level

def noise(kind, seconds):
    n = int(seconds * SR)
    if kind == "white": return rng.normal(0, 0.05, n)
    if kind == "pink":  # улица / шум вентилятора: низкие частоты
        w = rng.normal(0, 1, n); y = np.cumsum(w); y -= np.convolve(y, np.ones(400) / 400, mode="same")
        return y / np.max(np.abs(y)) * 0.15
    if kind == "keyboard":
        y = np.zeros(n)
        for at in rng.integers(0, n - 400, size=int(seconds * 7)):
            y[at:at + 400] += rng.normal(0, 0.3, 400) * np.exp(-np.arange(400) / 60)
        return y
    if kind == "hum": t = np.arange(n) / SR; return 0.1 * np.sin(2 * np.pi * 50 * t) + 0.05 * np.sin(2 * np.pi * 100 * t)
    if kind == "music": return music(seconds, 0.3)
    raise ValueError(kind)

cases = []
def case(name, x, setting, channel, expect, tag, text=""):
    cases.append(dict(file=save(name, x), setting=setting, channel=channel, expect=expect, tag=tag, text=text))

questions = [
    ("Milena", "ru", "Как вы настраивали CI/CD и code review в GitLab?"),
    ("Milena", "ru", "Какой у вас опыт с SwiftUI, Combine и async await?"),
    ("Milena", "ru", "Работали ли вы с Kafka, Redis и PostgreSQL?"),
    ("Milena", "ru", "Почему вы выбрали MVVM, а не VIPER?"),
    ("Lesya", "uk", "Розкажіть, як ви використовували Kubernetes і Docker у production."),
    ("Lesya", "uk", "Чи працювали ви з REST API та GraphQL?"),
    ("Lesya", "uk", "Як ви організовували unit та integration тести в CI?"),
    ("Lesya", "uk", "Що таке dependency injection і навіщо він потрібен?"),
    ("Samantha", "en", "How did you set up code review and continuous integration in your team?"),
    ("Samantha", "en", "Tell me about a time you fixed a memory leak in production."),
]
for i, (voice, lang, text) in enumerate(questions):
    q = say(voice, text)
    case(f"q-{lang}-{i}.wav", q, lang, "mic", "keep", "terms" if lang != "en" else "question", text)
    bed = noise("music", len(q) / SR)[: len(q)] * 0.35  # вопрос на фоне тихой музыки
    case(f"q-{lang}-{i}-music.wav", q + bed, lang, "mic", "keep", "question+music", text)

tv = [
    ("Anna", "de", "Heute Abend gibt es in den Nachrichten einen Bericht über das Wetter in Berlin."),
    ("Anna", "de", "Der Zug nach München hat leider zwanzig Minuten Verspätung."),
    ("Anna", "de", "Wir sehen uns morgen um acht Uhr vor dem Kino."),
    ("Thomas", "fr", "Bonjour à tous, aujourd'hui nous allons parler de la météo et du sport."),
    ("Thomas", "fr", "Le match de football commence à vingt heures ce soir."),
    ("Daniel", "en", "And now the weather forecast for the weekend: sunny with a light breeze."),
    ("Fred", "en", "I really love watching football matches with my friends on Sunday."),
    ("Karen", "en", "The traffic on the highway is very heavy this morning, so please drive carefully."),
]
for i, (voice, lang, text) in enumerate(tv):
    x = say(voice, text) * 0.6  # ТВ тише собеседника
    for setting in ("uk", "ru"):
        case(f"tv-{lang}-{i}-{setting}.wav", x, setting, "mic", "drop", f"foreign-{lang}", text)

for kind in ("white", "pink", "keyboard", "hum", "music"):
    for i in range(4):
        case(f"noise-{kind}-{i}.wav", noise(kind, 2.5 + i), "uk", "mic", "none", f"noise-{kind}")

(root / "evals/filter/audio-cases.json").write_text(json.dumps(cases, ensure_ascii=False, indent=1) + "\n")
print(f"{len(cases)} cases -> {out}")
