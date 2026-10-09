#!/usr/bin/env python3
"""Bound CI test time and record stacks when a runner cannot finish."""
import os
import signal
import subprocess
import sys

process = subprocess.Popen(['./scripts/swift.sh', 'test'], start_new_session=True)
try:
    sys.exit(process.wait(timeout=180))
except subprocess.TimeoutExpired:
    print('Tests exceeded 180 seconds; collecting runner diagnostics.', flush=True)
    listing = subprocess.check_output(['ps', '-axo', 'pid,ppid,command'], text=True)
    for line in listing.splitlines():
        if 'sessionbarPackageTests' in line or 'swiftpm_testing_helper' in line:
            print(line, flush=True)
            pid = int(line.strip().split()[0])
            subprocess.run(['/usr/bin/sample', str(pid), '2', '1'], timeout=15)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
    sys.exit(124)
