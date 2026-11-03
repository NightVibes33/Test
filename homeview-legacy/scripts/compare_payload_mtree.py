#!/usr/bin/env python3
"""Compare an extracted payload tree with an Apple mtree listing.

Counts only. The mtree file is not copied into the published report.
"""
import argparse
import json
from pathlib import Path


def file_paths(text):
    paths = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("/set") or line.startswith("/unset"):
            continue
        token = line.split()[0]
        if token in (".", ".."):
            continue
        if token.startswith("./"):
            token = token[2:]
        if "type=dir" in line:
            continue
        if "type=file" in line or "size=" in line:
            paths.append(token[:300])
            if len(paths) >= 200000:
                break
    return paths


def coverage(mtree_paths, present_paths):
    have = set(present_paths)
    missing = [path for path in mtree_paths if path not in have]
    bread = [path for path in mtree_paths if "BreadBoard.app/" in path or path.endswith("BreadBoard.app")]
    bread_missing = [path for path in bread if path not in have]
    return {
        "mtree_file_count": len(mtree_paths),
        "present_file_count": len(mtree_paths) - len(missing),
        "missing_file_count": len(missing),
        "missing_sample": missing[:15],
        "breadboard_mtree_files": len(bread),
        "breadboard_mtree_missing": len(bread_missing),
        "mtree_is_not_proof_the_payload_is_that_dmg": True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mtree", required=True)
    parser.add_argument("--files", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    mtree = Path(args.mtree)
    listing = Path(args.files)
    report = coverage(
        file_paths(mtree.read_text(encoding="utf-8", errors="replace") if mtree.is_file() else ""),
        [line.strip() for line in (listing.read_text(encoding="utf-8", errors="replace") if listing.is_file() else "").splitlines()],
    )
    Path(args.output).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"mtree_files": report["mtree_file_count"],
                      "present": report["present_file_count"],
                      "breadboard_missing": report["breadboard_mtree_missing"]}))


if __name__ == "__main__":
    main()
