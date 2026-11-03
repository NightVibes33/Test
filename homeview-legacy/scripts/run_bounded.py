#!/usr/bin/env python3
"""Run one command and stop it when the timeout expires.

The log receives the combined output. A timeout exits 124 and appends
TIMED_OUT. The command's arguments are not copied into the report.
"""
import argparse
import subprocess
from pathlib import Path


def run_bounded(argv, log_path, timeout):
    log_path = Path(log_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab") as log:
        try:
            completed = subprocess.run(
                list(argv), stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            log.write(("\nTIMED_OUT after %s seconds\n" % timeout).encode())
            return 124
    return completed.returncode


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
