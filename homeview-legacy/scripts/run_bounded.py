#!/usr/bin/env python3
"""Run one command and stop it when the timeout expires.

The log receives the combined output. A timeout exits 124 and appends
TIMED_OUT. The command's arguments are not copied into the report.
"""
import argparse
import os
import signal
import subprocess
from pathlib import Path


def run_bounded(argv, log_path, timeout):
    """Stop the command and every process it starts when the deadline hits."""
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab") as log:
        proc = subprocess.Popen(
            list(argv), stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
            log.write(("\nTIMED_OUT after %s seconds\n" % timeout).encode())
            return 124


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("argv", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    argv = args.argv[1:] if args.argv[:1] == ["--"] else args.argv
    if not argv:
        raise SystemExit("missing command")
    raise SystemExit(run_bounded(argv, args.log, args.timeout))


if __name__ == "__main__":
    main()
