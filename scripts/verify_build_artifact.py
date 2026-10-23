#!/usr/bin/env python3
"""Verify real Flutter build artifacts and emit a machine-readable SHA-256 manifest.

This is intentionally conservative: a ZIP named .apk or a stub .exe must fail.
It does not claim device-level functional testing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

MIN_APK_BYTES = 1_000_000
MIN_WINDOWS_EXE_BYTES = 10_000


def digest_file(path: Path) -> dict:
    sha = hashlib.sha256()
    with path.open('rb') as file:
        while chunk := file.read(1024 * 1024):
            sha.update(chunk)
    return {"path": path.as_posix(), "bytes": path.stat().st_size, "sha256": sha.hexdigest()}


def verify_android(apk: Path) -> dict:
    if not apk.is_file() or apk.stat().st_size < MIN_APK_BYTES:
        raise ValueError(f"APK missing or implausibly small: {apk}")
    if not zipfile.is_zipfile(apk):
        raise ValueError(f"Not a valid APK ZIP: {apk}")
    with zipfile.ZipFile(apk) as archive:
        names = set(archive.namelist())
        requirements = {
            "manifest": "AndroidManifest.xml" in names,
            "dex": any(n.startswith("classes") and n.endswith(".dex") for n in names),
            "flutter_engine": any(n.startswith("lib/") and n.endswith("/libflutter.so") for n in names),
            "flutter_assets": any(n.startswith("assets/flutter_assets/") for n in names),
        }
        if not all(requirements.values()):
            raise ValueError(f"APK structure validation failed: {requirements}")
        if archive.testzip() is not None:
            raise ValueError("APK archive has a corrupt entry")
    return {"kind": "android-debug", **digest_file(apk), "structure": requirements}


def _is_pe(exe: Path) -> bool:
    try:
        with exe.open('rb') as f:
            data = f.read(64)
            if len(data) < 64 or data[:2] != b'MZ':
                return False
            offset = struct.unpack_from('<I', data, 60)[0]
            if offset < 64 or offset > 4_000_000:
                return False
            f.seek(offset)
            return f.read(4) == b'PE\0\0'
    except OSError:
        return False


def verify_windows(folder: Path) -> dict:
    if not folder.is_dir():
        raise ValueError(f"Windows bundle missing: {folder}")
    executables = [p for p in folder.glob('*.exe') if p.stat().st_size >= MIN_WINDOWS_EXE_BYTES and _is_pe(p)]
    dll = folder / 'flutter_windows.dll'
    assets = folder / 'data' / 'flutter_assets'
    if not executables or not dll.is_file() or dll.stat().st_size < 100_000 or not assets.is_dir() or not any(assets.iterdir()):
        raise ValueError("Incomplete Windows Flutter bundle: need PE executable, flutter_windows.dll and data/flutter_assets")
    files = sorted(p for p in folder.rglob('*') if p.is_file())
    return {"kind": "windows-debug", "root": folder.as_posix(), "file_count": len(files),
            "total_bytes": sum(p.stat().st_size for p in files),
            "executables": [digest_file(p) for p in executables],
            "all_files": [digest_file(p) for p in files]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--apk', type=Path)
    group.add_argument('--windows', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify_android(args.apk) if args.apk else verify_windows(args.windows)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        print(f"BUILD_ARTIFACT_INVALID: {exc}", file=sys.stderr)
        return 1
    print(f"BUILD_ARTIFACT_VERIFIED: {args.out}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
