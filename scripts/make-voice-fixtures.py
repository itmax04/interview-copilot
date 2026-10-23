#!/usr/bin/env python3
"""Синтетический набор для eval `voice` (COPILOT-05 R-03, AC-03): образцы «владельцев» (~25 с) и короткие фразы
своих и чужих голосов macOS `say`, в том числе свой голос на другом языке. 16 кГц моно WAV в evals/audio/voice/
(в Git не попадают), манифест evals/filter/voice-cases.json — в Git. Usage: scripts/make-voice-fixtures.py"""
import json, subprocess, tempfile, wave
from pathlib import Path
import numpy as np

root = Path(__file__).resolve().parent.parent
out = root / "evals/audio/voice"
out.mkdir(parents=True, exist_ok=True)
SR = 16000

def say(voice, text):
    with tempfile.TemporaryDirectory() as tmp:
        aiff, wav = Path(tmp) / "a.aiff", Path(tmp) / "a.wav"
        subprocess.run(["say", "-v", voice, "-o", str(aiff), text], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(aiff), str(wav)], check=True)
        with wave.open(str(wav)) as w:
            return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768

def save(name, x):
    x = np.clip(np.concatenate([np.zeros(int(0.3 * SR)), x, np.zeros(int(0.5 * SR))]), -1, 1)
    with wave.open(str(out / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
    return name

passages = {
    "ru": "Меня зовут Алексей, я разработчик мобильных приложений. Последние пять лет я пишу на Swift и работаю в продуктовых командах. "
          "Мне нравится разбираться в архитектуре, проводить код-ревью и помогать младшим коллегам. В свободное время я читаю книги и катаюсь на велосипеде.",
    "uk": "Мене звати Олексій, я розробник мобільних застосунків. Останні п'ять років я пишу на Swift і працюю в продуктових командах. "
          "Мені подобається розбиратися в архітектурі, проводити код-рев'ю та допомагати молодшим колегам. У вільний час я читаю книжки і катаюся на велосипеді.",
    "en": "My name is Alex and I am a mobile developer. For the last five years I have been writing Swift and working in product teams. "
          "I enjoy software architecture, code reviews and mentoring junior colleagues. In my free time I read books and ride my bike.",
}
phrases = {
    "ru": ["Расскажите о своём последнем проекте.", "Как вы решаете конфликты в команде?", "Почему вы хотите сменить работу?", "Какие у вас сильные стороны?"],
    "uk": ["Розкажіть про свій останній проєкт.", "Як ви вирішуєте конфлікти в команді?", "Чому ви хочете змінити роботу?", "Які ваші сильні сторони?"],
    "en": ["Tell me about your last project.", "How do you resolve conflicts in a team?", "Why do you want to change your job?", "What are your main strengths?"],
    "de": ["Erzählen Sie mir von Ihrem letzten Projekt.", "Wie lösen Sie Konflikte im Team?", "Warum möchten Sie den Job wechseln?", "Was sind Ihre Stärken?"],
    "fr": ["Parlez-moi de votre dernier projet.", "Comment résolvez-vous les conflits?", "Pourquoi voulez-vous changer d'emploi?", "Quelles sont vos forces?"],
}
voices = {"Milena": "ru", "Lesya": "uk", "Samantha": "en", "Daniel": "en", "Fred": "en", "Karen": "en", "Anna": "de", "Thomas": "fr"}
owners = {"Milena": "ru", "Lesya": "uk", "Samantha": "en"}

cases = {"owners": {}, "tests": []}
for owner, lang in owners.items():
    cases["owners"][owner] = save(f"enroll-{owner}.wav", say(owner, passages[lang]))
for voice, lang in voices.items():
    for i, p in enumerate(phrases[lang]):
        cases["tests"].append({"file": save(f"{voice}-{lang}-{i}.wav", say(voice, p)), "speaker": voice, "lang": lang})
# Свой голос на другом языке: отпечаток не должен зависеть от языка.
for voice, lang in (("Milena", "en"), ("Lesya", "ru"), ("Samantha", "ru")):
    for i, p in enumerate(phrases[lang][:2]):
        cases["tests"].append({"file": save(f"{voice}-{lang}-cross-{i}.wav", say(voice, p)), "speaker": voice, "lang": lang})
(root / "evals/filter/voice-cases.json").write_text(json.dumps(cases, ensure_ascii=False, indent=1) + "\n")
print(f"{len(cases['owners'])} owners, {len(cases['tests'])} tests -> {out}")
