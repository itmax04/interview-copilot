"""Run two copies of each standalone model installer against one offline fixture."""
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import os
import shutil
import subprocess
import sys

repo = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(__file__).resolve().parents[1]
payload = b"deterministic model installer fixture"
entry = {"path": "probe.bin", "size": len(payload), "sha256": sha256(payload).hexdigest()}
shim = """#!/usr/bin/env python3
from pathlib import Path
import os
import sys
import time
args = sys.argv[1:]
option = "--output" if "--output" in args else "-o"
partial = Path(args[args.index(option) + 1])
partial.write_bytes(b"deterministic model installer fixture")
marks = Path(os.environ["IC_INSTALL_RACE_MARKS"])
(marks / str(os.getpid())).write_text(str(partial))
deadline = time.monotonic() + 5
while len(list(marks.iterdir())) < 2 and time.monotonic() < deadline:
    time.sleep(0.01)
if len(list(marks.iterdir())) != 2:
    raise SystemExit("Timed out waiting for both downloads")
"""
for script, manifest, value, prefix in (
    ("fetch-parakeet.py", "parakeet-models.json", {"repo": "test/fixture", "revision": "abc", "files": [entry]}, "parakeet-tdt-0.6b-v3"),
    ("fetch-filter-models.py", "filter-models.json", {"models": [{"folder": "test-filter", "repo": "test/fixture", "revision": "abc", "files": [entry]}]}, "test-filter"),
    ("fetch-models.sh", "models.sha256", f"{entry['sha256']} probe.bin {len(payload)} https://example.invalid/probe.bin\n", ""),
):
    with TemporaryDirectory() as scratch:
        root = Path(scratch)
        for folder in ("scripts", "bin", "marks", "models"):
            (root / folder).mkdir()
        executable = root / "scripts" / script
        shutil.copy2(repo / "scripts" / script, executable)
        (root / manifest).write_text(value if isinstance(value, str) else json.dumps(value))
        (root / "bin/curl").write_text(shim)
        (root / "bin/curl").chmod(0o755)
        env = {
            **os.environ,
            "PATH": str(root / "bin") + os.pathsep + os.environ["PATH"],
            "INTERVIEWCOPILOT_MODELS_DIR": str(root / "models"),
            "IC_INSTALL_RACE_MARKS": str(root / "marks"),
        }
        interpreter = "/bin/bash" if script.endswith(".sh") else sys.executable
        command = [interpreter, str(executable)]
        processes = [subprocess.Popen(command, env=env) for _ in range(2)]
        try:
            codes = [process.wait(timeout=20) for process in processes]
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.wait()
        target = root / "models" / prefix / "probe.bin"
        checksum_ok = target.is_file() and sha256(target.read_bytes()).hexdigest() == entry["sha256"]
        print(f"{script} exits={codes} installed_checksum_ok={checksum_ok}")
        assert codes == [0, 0] and checksum_ok
        paths = {mark.read_text() for mark in (root / "marks").iterdir()}
        assert len(paths) == 2, "expected two distinct download paths"
        assert set(target.parent.iterdir()) == {target}, "unexpected staging files"
