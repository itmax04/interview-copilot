#!/usr/bin/env python3
"""Install the pinned filter models (COPILOT-05 R-08); verify every file with SHA256 and size.
Usage: scripts/fetch-filter-models.py  (INTERVIEWCOPILOT_MODELS_DIR overrides the destination)."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / 'filter-models.json').read_text())
models = Path(os.environ.get('INTERVIEWCOPILOT_MODELS_DIR', str(Path.home() / 'Library/Application Support/InterviewCopilot/models')))

def checksum(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
        return digest.hexdigest()

for model in manifest['models']:
    dest = models / model['folder']
    for entry in model['files']:
        path = dest / entry['path']
        if path.is_file() and path.stat().st_size == entry['size'] and checksum(path) == entry['sha256']:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(dir=path.parent) as staging:
            partial = Path(staging) / (path.name + '.part')
            url = f"https://huggingface.co/{model['repo']}/resolve/{model['revision']}/{entry['path']}"
            subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3', '--output', str(partial), url], check=True)
            if partial.stat().st_size != entry['size'] or checksum(partial) != entry['sha256']:
                raise RuntimeError(f"SHA256 mismatch: {model['repo']}/{entry['path']}")
            partial.replace(path)
    print(f"{model['repo']}: {len(model['files'])} files verified, revision {model['revision'][:12]}")
