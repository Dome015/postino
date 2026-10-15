#!/usr/bin/env python3
"""Exercise the release cURL runner with slow, failed and malformed fixtures."""
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile


root = Path(__file__).resolve().parent.parent
python = shutil.which("python3")
assert python, "Python is required for the cURL fixture checks"
cases = [
    ("delayed startup", f"/bin/sleep 6\nexec {shlex.quote(python)} \"$@\"", 0,
     "Passed executable cURL exports"),
    ("startup failure", "print -u2 'Simulated fixture startup failure'\nexit 17", 1,
     "cURL fixture exited before publishing its port."),
    ("invalid port", 'print not-a-port > "${@[-1]}"\nexec /bin/sleep 60', 1,
     "cURL fixture published an invalid port: not-a-port"),
    ("startup timeout", "print -u2 'Simulated stalled fixture'\nexec /bin/sleep 60", 1,
     "Timed out after 30 seconds waiting for the cURL fixture port."),
]
with tempfile.TemporaryDirectory(prefix="curl-startup-checks-", dir=root / "build") as directory:
    scratch = Path(directory)
    launcher = scratch / "python3"
    pid_file = scratch / "fixture-pid"
    env = dict(os.environ, PATH=str(scratch) + os.pathsep + os.environ["PATH"],
               POSTINO_CURL_TEST_PID=str(pid_file))
    for name, script, status, expected in cases:
        print(f"Checking {name}…", flush=True)
        pid_file.unlink(missing_ok=True)
        launcher.write_text('#!/bin/zsh\nprint -r -- "$$" > "$POSTINO_CURL_TEST_PID"\n' + script + "\n")
        launcher.chmod(0o700)
        before = set((root / "build").glob("curl-fixture.*"))
        try:
            result = subprocess.run([str(root / "scripts/test-curl.sh")], cwd=root, env=env,
                                    capture_output=True, text=True, timeout=90)
            output = result.stdout + result.stderr
            assert result.returncode == status and expected in output, f"{name}: {result.returncode}\n{output}"
            if name == "startup failure":
                assert "Simulated fixture startup failure" in output, "The fixture error log must be shown"
            if name == "startup timeout":
                assert "Simulated stalled fixture" in output, "The timeout must show the fixture log"
            assert set((root / "build").glob("curl-fixture.*")) == before, "Fixture directories must be cleaned up"
            pid = int(pid_file.read_text())
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                pass
            else:
                raise AssertionError(f"{name}: fixture process was left running")
        finally:
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), signal.SIGTERM)
                except ProcessLookupError:
                    pass
        print(f"Passed {name}", flush=True)

for arguments in [[], [""], ["invalid"], ["0"], ["65536"]]:
    result = subprocess.run([str(root / "build/curl-checks"), *arguments], capture_output=True, text=True)
    assert result.returncode == 1 and "Usage: curl-checks" in result.stderr, "Invalid ports must fail without invoking cURL"
print("Passed cURL fixture startup, diagnostics, port validation and process cleanup checks", flush=True)
