#!/usr/bin/env python3
"""Ключи строк интерфейса (COPILOT-10) и проверка английской таблицы.

Ключ — русский текст из кода. Источники ключей:
  1. строки-литералы SwiftUI (`Text("…")`, `Button("…")` …) — из файлов `.stringsdata`, которые пишет компилятор
     (`-emit-localized-strings`); интерполяция в них уже заменена на %@ / %lld;
  2. `L("…")`, `L10n.t("…")`, `L10n.f("…")` — строки, которые собираются в коде;
  3. прочие строки с кириллицей в коде окон (`Sources/InterviewCopilot`) — подписи компонентов, разделы, статусы:
     они приходят в `Text(String)` переменной и переводятся там же.
Строки не для интерфейса (тексты для чтения вслух, примеры речи, данные снимков) — в `scripts/l10n-ignore.txt`.

  scripts/l10n-keys.py <папка .stringsdata> [--table Resources/en.lproj/Localizable.strings] [--missing] [--unused]
"""
import argparse
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYR = re.compile(r"[А-Яа-яЁё]")
CALL = re.compile(r'(?<![A-Za-z0-9_])(?:L|L10n\.t|L10n\.f)\(\s*"((?:[^"\\\n]|\\.)*)"')
# Формы числительного `RussianPlural.form(n, "вопрос", "вопроса", "вопросов")` — часто внутри интерполяции.
PLURAL = re.compile(r'form\([^,]+,\s*"([^"]+)",\s*"([^"]+)",\s*"([^"]+)"\)')
# Файлы окон без строк интерфейса или с данными, не с подписями.
SKIP_FILES = ("UISnapshots.swift", "SmokeTest.swift")


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")


def swift_files(sub):
    return sorted(glob.glob(os.path.join(ROOT, "Sources", sub, "**", "*.swift"), recursive=True))


def code_lines(path):
    for i, line in enumerate(open(path, encoding="utf-8"), 1):
        st = line.strip()
        if st.startswith("//") or "Log." in line or "print(" in line:
            continue
        yield i, line


def compiler_keys(dirs):
    keys = {}
    for d in dirs:
        for f in glob.glob(os.path.join(d, "*.stringsdata")):
            data = json.load(open(f, encoding="utf-8"))
            src = data.get("source", "")
            # Сборка инкрементальная: файлы неизмененного кода остаются от прошлых запусков, удаленного — пропускаются.
            if "/Sources/" not in src or "/checkouts/" in src or not os.path.exists(src):
                continue
            for entries in data.get("tables", {}).values():
                for e in entries:
                    keys.setdefault(e["key"], f"{os.path.relpath(src, ROOT)}:{e['location']['startingLine']}")
    return keys


def call_keys():
    keys = {}
    for sub in ("CopilotCore", "CopilotEmbeddings", "InterviewCopilot"):
        for path in swift_files(sub):
            if path.endswith(SKIP_FILES):
                continue
            for i, line in code_lines(path):
                for m in CALL.finditer(line):
                    keys.setdefault(unescape(m.group(1)), f"{os.path.relpath(path, ROOT)}:{i}")
                for m in PLURAL.finditer(line):
                    for form in m.groups():
                        keys.setdefault(form, f"{os.path.relpath(path, ROOT)}:{i}")
    return keys


def literals(line):
    """Строковые литералы строки кода; литерал с интерполяцией `\\(…)` — None (его ключ дает компилятор или `L`)."""
    out, i, n = [], 0, len(line)
    while i < n:
        if line[i] != '"':
            i += 1
            continue
        i += 1
        buf, interpolated = "", False
        while i < n and line[i] != '"':
            if line.startswith("\\(", i):
                interpolated, depth, i = True, 1, i + 2
                while i < n and depth:  # строки внутри интерполяции не закрывают литерал
                    depth += {"(": 1, ")": -1}.get(line[i], 0)
                    i += 1
                continue
            if line[i] == "\\" and i + 1 < n:
                buf += line[i:i + 2]
                i += 2
                continue
            buf += line[i]
            i += 1
        i += 1
        out.append(None if interpolated else buf)
    return out


def ui_literal_keys():
    keys = {}
    for path in swift_files("InterviewCopilot"):
        if path.endswith(SKIP_FILES):
            continue
        for i, line in code_lines(path):
            for s in literals(line):
                if s and CYR.search(s):
                    keys.setdefault(unescape(s), f"{os.path.relpath(path, ROOT)}:{i}")
    return keys


def load_table(path):
    """Разбор .strings: "ключ" = "значение"; (комментарии /* */ и //)."""
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    table = {}
    for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, flags=re.M):
        table[unescape(m.group(1))] = unescape(m.group(2))
    return table


def specifiers(s):
    return sorted(re.findall(r"%(?:\d+\$)?(?:lld|ld|d|@|\.\d+f|f)", s))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stringsdata", nargs="+")
    ap.add_argument("--table", default=os.path.join(ROOT, "Resources/en.lproj/Localizable.strings"))
    ap.add_argument("--missing", action="store_true", help="ключи без перевода (код возврата 1, если есть)")
    ap.add_argument("--unused", action="store_true", help="переводы, ключей которых больше нет в коде")
    ap.add_argument("--json", action="store_true", help="все ключи с местом в коде")
    args = ap.parse_args()

    ignore_path = os.path.join(ROOT, "scripts/l10n-ignore.txt")
    ignore = [l.rstrip("\n") for l in open(ignore_path, encoding="utf-8")
              if l.strip() and not l.startswith("#")] if os.path.exists(ignore_path) else []

    keys = {}
    for source in (compiler_keys(args.stringsdata), call_keys(), ui_literal_keys()):
        for k, where in source.items():
            keys.setdefault(k, where)
    keys = {k: v for k, v in keys.items() if CYR.search(k) and not any(k.startswith(p) for p in ignore)}

    if args.json:
        json.dump(keys, sys.stdout, ensure_ascii=False, indent=1)
        return 0

    table = load_table(args.table)
    status = 0
    missing = [k for k in keys if k not in table]
    bad = [k for k in keys if k in table and specifiers(k) != specifiers(table[k])]
    print(f"l10n: {len(keys)} keys, {len(table)} translations, {len(missing)} missing, {len(bad)} format mismatches")
    if args.missing:
        for k in missing:
            print(f"  missing  {keys[k]}  {json.dumps(k, ensure_ascii=False)}")
        status = 1 if missing else 0
    for k in bad:
        print(f"  format   {keys[k]}  {json.dumps(k, ensure_ascii=False)} → {json.dumps(table[k], ensure_ascii=False)}")
        status = 1
    if args.unused:
        for k in table:
            if k not in keys:
                print(f"  unused   {json.dumps(k, ensure_ascii=False)}")
    return status


if __name__ == "__main__":
    sys.exit(main())
