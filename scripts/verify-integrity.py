#!/usr/bin/env python3
"""Verify this repo against its SHA256 manifest.

Usage (from the repo root):
    python3 scripts/verify-integrity.py

Re-hashes every file listed in scripts/manifest.json and reports OK / MODIFIED /
MISSING per file, plus LOCAL-ONLY for tracked-but-unlisted files. Recomputes the
aggregate hash and compares it. Exit code 0 if everything matches, 1 otherwise.

Adapted from the Apache-2.0 provenance scripts in Compound AI Operating Standards
(github.com/cameronpsutcliff/compound-ai-operating-standards).
"""
import hashlib
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_JSON = REPO_ROOT / "scripts" / "manifest.json"

EXCLUDE_FILES = {"scripts/manifest.json", "scripts/manifest.sha256", ".DS_Store"}
EXCLUDE_DIRS = {".git"}


def iter_files(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS)
        for name in sorted(filenames):
            abs_path = Path(dirpath) / name
            rel = abs_path.relative_to(root).as_posix()
            if rel in EXCLUDE_FILES or name == ".DS_Store":
                continue
            yield rel, abs_path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not MANIFEST_JSON.exists():
        print("ERROR: scripts/manifest.json not found. Run build-manifest.py first.")
        return 1

    manifest = json.loads(MANIFEST_JSON.read_text())
    listed = {e["path"]: e for e in manifest.get("files", [])}

    problems = 0
    for rel, entry in sorted(listed.items()):
        abs_path = REPO_ROOT / rel
        if not abs_path.exists():
            print(f"MISSING   {rel}")
            problems += 1
            continue
        if sha256_file(abs_path) != entry["sha256"]:
            print(f"MODIFIED  {rel}")
            problems += 1

    # Files present in the tree but absent from the manifest.
    on_disk = {rel for rel, _ in iter_files(REPO_ROOT)}
    for rel in sorted(on_disk - set(listed)):
        print(f"LOCAL-ONLY {rel}")
        problems += 1

    # Recompute the aggregate from the current on-disk listed files.
    agg = hashlib.sha256()
    for rel in sorted(listed):
        abs_path = REPO_ROOT / rel
        if abs_path.exists():
            agg.update(f"{rel}:{sha256_file(abs_path)}:{abs_path.stat().st_size}\n".encode("utf-8"))
    aggregate_ok = agg.hexdigest() == manifest.get("aggregate_sha256")

    print("-" * 40)
    print(f"files listed:   {len(listed)}")
    print(f"aggregate:      {'MATCH' if aggregate_ok else 'MISMATCH'}")
    if problems == 0 and aggregate_ok:
        print("result:         VERIFIED")
        return 0
    print(f"result:         FAILED ({problems} file problem(s))")
    return 1


if __name__ == "__main__":
    sys.exit(main())
