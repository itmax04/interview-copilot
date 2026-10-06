#!/usr/bin/env bash
# Синтетические аудио-фикстуры для whisper (evals/README.md «Аудио-фикстуры»): голоса macOS `say`, 16 кГц моно WAV.
# uk — Lesya, ru — Milena, en — Samantha (plan.md P-04). Текст — вымышленные вопросы собеседования.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/evals/audio"
mkdir -p "$OUT"

make() { # $1 файл, $2 голос, $3 текст
  say -v "$2" -o "$OUT/$1.aiff" "$3"
  afconvert -f WAVE -d LEI16@16000 -c 1 "$OUT/$1.aiff" "$OUT/$1.wav"
  rm -f "$OUT/$1.aiff"
  echo "$1.wav"
}

make uk-about-me     Lesya    "Розкажіть, будь ласка, про себе і про свій досвід роботи."
make uk-conflict     Lesya    "Опишіть ситуацію, коли у вас був конфлікт у команді. Як ви його вирішили?"
make ru-about-me     Milena   "Расскажите, пожалуйста, о себе и о своём опыте работы."
make ru-weakness     Milena   "Какая у вас самая слабая сторона и что вы с ней делаете?"
make en-about-me     Samantha "Could you tell me a little bit about yourself and your background?"
make en-why-company  Samantha "Why do you want to join our company, and what do you know about our product?"
