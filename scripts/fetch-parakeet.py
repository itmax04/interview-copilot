#!/usr/bin/env python3
"""Install the pinned Parakeet v3 Core ML files; verify every file with SHA256."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'parakeet-models.json').read_text())
models = Path(os.environ.get('INTERVIEWCOPILOT_MODELS_DIR', str(Path.home() / 'Library/Application Support/InterviewCopilot/models')))
dest = models / 'parakeet-tdt-0.6b-v3'

def checksum(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def fetch(entry):
    path = dest / entry['path']
    if path.is_file() and checksum(path) == entry['sha256']:
        return entry['path']
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + '.part')
    url = f"https://huggingface.co/{manifest['repo']}/resolve/{manifest['revision']}/{entry['path']}"
    subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', '--output', str(partial), url], check=True)
    if partial.stat().st_size != entry['size'] or checksum(partial) != entry['sha256']:
        partial.unlink()
        raise RuntimeError(f"SHA256 mismatch: {entry['path']}")
    partial.replace(path)
    return entry['path']

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
    files = list(executor.map(fetch, manifest['files']))
print(f"Parakeet v3: {len(files)} files verified, revision {manifest['revision']}")
