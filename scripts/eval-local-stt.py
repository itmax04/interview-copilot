#!/usr/bin/env python3
"""Compare local engines using a manifest of audio paths and reference transcripts.
Usage: scripts/eval-local-stt.py /path/manifest.json /path/results.json
Run `swift build -c release --product copilot-eval` first. No cloud API calls.
"""
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
clips = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
bin_dir = subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=root, text=True).strip()
cli = Path(bin_dir) / 'copilot-eval'
models = Path(os.environ.get('INTERVIEWCOPILOT_MODELS_DIR', str(Path.home() / 'Library/Application Support/InterviewCopilot/models')))
profiles = [('medium-reduced', 'stt', 'ggml-medium-q5_0.bin', False),
            ('medium-full', 'stt', 'ggml-medium-q5_0.bin', True),
            ('turbo-full', 'stt', 'ggml-large-v3-turbo-q5_0.bin', True),
            ('parakeet-auto', 'stt-parakeet', 'parakeet-tdt-0.6b-v3', False)]

def words(text):
    return re.findall(r"[^\W_]+(?:['’][^\W_]+)*", text.lower().replace('ё', 'е').replace('’', "'"), re.U)

def distance(a, b):
    previous = list(range(len(b) + 1))
    for i, token in enumerate(a, 1):
        current = [i]
        for j, other in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (token != other)))
        previous = current
    return previous[-1]

results = []
for profile, command, model, full in profiles:
    for language in ['uk', 'ru', 'en']:
        batch = [clip for clip in clips if clip['language'] == language]
        if not batch:
            continue
        by_filename = {Path(clip['path']).name: clip for clip in batch}
        if len(by_filename) != len(batch):
            raise ValueError('Audio filenames must be unique within each language')
        args = [str(cli), command, str(models / model)] + [clip['path'] for clip in batch]
        if command == 'stt':
            args += ['--lang', language]
        if full:
            args += ['--full-context']
        log = subprocess.check_output(args, text=True, cwd=root)
        parsed = []
        for line in log.splitlines():
            match = re.match(r'(.+) audio_s=([\d.]+) elapsed_ms=([\d.]+) lang=(\w+) .*text=(.*)', line)
            if match:
                clip = by_filename[match[1]]
                expected = words(clip['expected'])
                parsed.append(dict(**clip, profile=profile, text=match[5], elapsed_ms=float(match[3]),
                                   detected_language=match[4], words=len(expected), errors=distance(expected, words(match[5]))))
        if len(parsed) != len(batch):
            raise RuntimeError(f'{profile}/{language}: incomplete results')
        results += parsed
        output.parent.mkdir(parents=True, exist_ok=True)
        partial = output.with_name(output.name + '.part')
        partial.write_text(json.dumps(results, ensure_ascii=False, indent=2))
        partial.replace(output)
    group = [row for row in results if row['profile'] == profile]
    total = sum(row['words'] for row in group)
    if total:
        wer = 100 * sum(row['errors'] for row in group) / total
        print(f"{profile}: {len(group)} clips, WER {wer:.2f}%, median {statistics.median(row['elapsed_ms'] for row in group):.0f} ms", flush=True)
