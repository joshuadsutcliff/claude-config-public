#!/usr/bin/env python3
"""Build a SHA256 integrity manifest for this repo.

Usage (from the repo root):
    python3 scripts/build-manifest.py

Walks the repo, hashes every file, and writes:
  - scripts/manifest.json    (per-file sha256 + bytes, plus an aggregate)
  - scripts/manifest.sha256  (the aggregate hash alone)

Adapted from the Apache-2.0 provenance scripts in Compound AI Operating Standards
(github.com/cameronpsutcliff/compound-ai-operating-standards).
"""
import hashlib
import json
import os
import sys
from pathlib import Path

VERSION = "1.0.0"
ORIGIN_ID = "claude-config-public"

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_JSON = REPO_ROOT / "scripts" / "manifest.json"
MANIFEST_SHA = REPO_ROOT / "scripts" / "manifest.sha256"

# Paths (repo-relative) never included in the manifest.
EXCLUDE_FILES = {"scripts/manifest.json", "scripts/manifest.sha256", ".DS_Store"}
EXCLUDE_DIRS = {".git"}


def iter_files(root: Path):
    """Yield repo-relative POSIX paths of files to hash, deterministically."""
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
    files = []
    for rel, abs_path in iter_files(REPO_ROOT):
        files.append({
            "path": rel,
            "sha256": sha256_file(abs_path),
            "bytes": abs_path.stat().st_size,
        })

    files.sort(key=lambda e: e["path"])

    # Deterministic aggregate over "path:sha256:bytes\n" lines.
    agg = hashlib.sha256()
    for e in files:
        agg.update(f"{e['path']}:{e['sha256']}:{e['bytes']}\n".encode("utf-8"))
    aggregate = agg.hexdigest()

    manifest = {
        "origin_id": ORIGIN_ID,
        "version": VERSION,
        "file_count": len(files),
        "aggregate_sha256": aggregate,
        "files": files,
    }

    MANIFEST_JSON.write_text(json.dumps(manifest, indent=2) + "\n")
    MANIFEST_SHA.write_text(aggregate + "\n")

    print(f"manifest: {len(files)} files, aggregate {aggregate}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
