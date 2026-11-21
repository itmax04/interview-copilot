#!/usr/bin/env python3
"""Метрики задержек из логов приложения (AC-01…AC-03, evals/README.md «Живой сценарий»).

Использование:
  scripts/metrics.py --last 30m            # читает `log show` за последние 30 минут
  scripts/metrics.py --start "2026-10-07 10:00:00" --end "2026-10-07 10:15:00"
  scripts/metrics.py saved.log             # файл с выводом `log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info`

В логах только числа и ID (R-24), текста реплик там нет.
  AC-01  phrase_end → transcript_final   (phrase_end_to_final_ms)     порог ≤ 1000 мс (медиана)
  AC-02  turn_end → card_shown           (card_shown ms_from_turn_end) порог ≤ 500 мс (медиана)
  AC-03  turn_end → first_token          (first_token ms_from_turn_end) порог ≤ 2500 мс (медиана, COPILOT-03)
  C15-AC-03 speech_end → first_token      (first_token ms_from_speech_end) медиана ≤ 3000 мс и p90 ≤ 5000 мс (COPILOT-15 spec AC-03)
  C15 redecode decode_ms                  медиана ≤ 500 мс для вопроса ≤ 15 с (COPILOT-15 spec AC-03)
  C4-AC-01  speech_end → first_token      ≤ 1000 мс (COPILOT-04) — УСТАРЕЛО: заменено C15-AC-03 (порог 1000 мс не достижим
            при T = 1000 мс и повторном распознавании); строка справочная, на код возврата не влияет
Опережающие запросы (COPILOT-04 R-01): draft_start / draft_used / draft_cancelled.
"""
import argparse
import re
import statistics
import subprocess
import sys

# имя: (regex, порог медианы, порог p90 или None, влияет на код возврата)
PATTERNS = {
    "AC-01 phrase_end → transcript_final": (re.compile(r"transcript_final .*phrase_end_to_final_ms=(\d+)"), 1000, None, True),
    "AC-02 turn_end → card_shown": (re.compile(r"card_shown .*ms_from_turn_end=(\d+)"), 500, None, True),
    # Только подсказки на ход (kind=hint): ручные запросы к сильной модели и скриншоты в AC-03 не входят.
    "AC-03 turn_end → first_token": (re.compile(r"first_token turn=\d+ kind=hint .*ms_from_turn_end=(\d+)"), 2500, None, True),
    # COPILOT-15 AC-03: от конца речи до первых слов подсказки.
    "C15-AC-03 speech_end → first_token": (re.compile(r"first_token turn=\d+ kind=hint .*ms_from_speech_end=(\d+)"), 3000, 5000, True),
    # COPILOT-15 AC-03: повторное распознавание вопроса целиком; decode_ms включает ожидание очереди движка.
    "C15 redecode decode_ms": (re.compile(r"redecode turn=-?\d+ .*decode_ms=(\d+)"), 500, None, True),
    # Устарело (COPILOT-04), заменено строкой C15-AC-03: только для справки.
    "C4-AC-01 speech_end → first_token (устарело)": (re.compile(r"first_token turn=\d+ kind=hint .*ms_from_speech_end=(\d+)"), 1000, None, False),
}


def read_log(args):
    if args.file:
        with open(args.file, encoding="utf-8") as f:
            return f.read()
    cmd = ["/usr/bin/log", "show", "--predicate", 'subsystem == "com.itmax04.interviewcopilot"', "--info"]
    if args.start:
        cmd += ["--start", args.start]
        if args.end:
            cmd += ["--end", args.end]
    else:
        cmd += ["--last", args.last]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout


def p90(values):
    s = sorted(values)
    return s[min(len(s) - 1, int(round(0.9 * (len(s) - 1))))]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", nargs="?")
    ap.add_argument("--last", default="30m")
    ap.add_argument("--start")
    ap.add_argument("--end")
    args = ap.parse_args()
    text = read_log(args)
    ok = True
    print("| Метрика | n | медиана, мс | p90, мс | порог (медиана / p90) | результат |")
    print("|---|---|---|---|---|---|")
    for name, (rx, limit, limit90, counts) in PATTERNS.items():
        shown = f"≤ {limit}" + (f" / ≤ {limit90}" if limit90 else "")
        values = [int(m.group(1)) for m in rx.finditer(text)]
        if not values:
            print(f"| {name} | 0 | — | — | {shown} | NOT RUN |")
            continue
        med = statistics.median(values)
        high = p90(values)
        passed = med <= limit and (limit90 is None or high <= limit90)
        verdict = "PASS" if passed else "FAIL"
        if not counts:
            verdict += " (справочно)" if passed else " (справочно, не влияет)"
        else:
            ok = ok and passed
        print(f"| {name} | {len(values)} | {med:.0f} | {high} | {shown} | {verdict} |")
    drafts = len(re.findall(r"draft_start ", text))
    if drafts:
        used = len(re.findall(r"draft_used ", text))
        cancelled = len(re.findall(r"draft_cancelled ", text))
        spec = [int(m) for m in re.findall(r"first_token turn=\d+ kind=hint .*ms_from_speech_end=(\d+) .*speculative=1", text)]
        plain = [int(m) for m in re.findall(r"first_token turn=\d+ kind=hint .*ms_from_speech_end=(\d+) .*speculative=0", text)]
        print(f"\nОпережающие запросы: начато {drafts}, пригодилось {used}, отменено {cancelled}")
        if spec:
            print(f"  первые слова с опережающим запросом: медиана {statistics.median(spec):.0f} мс (n={len(spec)})")
        if plain:
            print(f"  первые слова без него: медиана {statistics.median(plain):.0f} мс (n={len(plain)})")
    failed = re.findall(r"redecode_failed turn=-?\d+ reason=(\w+)", text)
    if failed:
        print(f"\nredecode_failed: {len(failed)} ({ {r: failed.count(r) for r in sorted(set(failed))} })")
    langs = re.findall(r"transcript_final .*lang=(\w+)", text)
    if langs:
        counts = {l: langs.count(l) for l in sorted(set(langs))}
        print(f"\nЯзыки итоговых реплик: {counts}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
