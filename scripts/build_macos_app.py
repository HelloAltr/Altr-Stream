#!/usr/bin/env python3
"""Altr Stream — macOS Native Application Builder.

Compiles the Go installer engine for Darwin (arm64/amd64), builds
the native SwiftUI wrapper application (Altr Stream), and bundles
the complete native application:

    dist/Altr Stream.app/
        Contents/
            MacOS/
                Altr Stream
            Resources/
                altr-installer-engine
            Info.plist

Usage:
    python3 scripts/build_macos_app.py [--version 1.0.0-beta] [--image ghcr.io/helloaltr/altr-stream:0.13.7-alpha] [--output-dir dist]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "src"))

try:
    from altr_stream.__version__ import __version__ as CANONICAL_VERSION
except ImportError:
    CANONICAL_VERSION = "1.0.0-beta"

DEFAULT_IMAGE = "ghcr.io/helloaltr/altr-stream:0.13.7-alpha"


def compute_sha256(file_path: Path) -> str:
    """Compute hex-encoded SHA-256 hash of a file."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def detect_host_arch() -> str:
    """Detect darwin architecture (arm64 or amd64)."""
    machine = platform.machine().lower()
    if machine in ("arm64", "aarch64"):
        return "arm64"
    return "amd64"


def build_go_engine(output_path: Path, version: str, image: str, arch: str) -> Path:
    """Compile the shared Go installer engine for Darwin."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    engine_dir = REPO_ROOT / "packaging" / "engine"

    ldflags = f"-s -w -X main.DefaultImage={image} -X main.DefaultVersion={version}"
    cmd = [
        "go",
        "-C",
        str(engine_dir),
        "build",
        f"-ldflags={ldflags}",
        "-o",
        str(output_path.resolve()),
        ".",
    ]

    env = os.environ.copy()
    env["GOOS"] = "darwin"
    env["GOARCH"] = arch
    env["CGO_ENABLED"] = "0"
    cache_dir = REPO_ROOT / ".build_cache" / "go"
    cache_dir.mkdir(parents=True, exist_ok=True)
    env["GOPATH"] = str(cache_dir.resolve())

    print(f"[*] Compiling Go installer engine for darwin/{arch}...")
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[!] Go engine compilation failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    output_path.chmod(0o755)
    print(f"[+] Go engine built successfully: {output_path} ({output_path.stat().st_size:,} bytes)")
    return output_path


def build_swift_app(arch: str) -> Path:
    """Compile the native Swift application using Swift Package Manager."""
    swift_proj = REPO_ROOT / "packaging" / "macos" / "AltrStreamApp"
    print(f"[*] Compiling native SwiftUI app in {swift_proj}...")

    cmd = ["swift", "build", "-c", "release"]
    result = subprocess.run(cmd, cwd=swift_proj, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[!] Swift compilation failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    built_bin = swift_proj / ".build" / "release" / "Altr Stream"
    if not built_bin.is_file():
        # Check alternate naming or architecture directory
        candidates = list((swift_proj / ".build").glob("**/release/Altr Stream"))
        if candidates:
            built_bin = candidates[0]
        else:
            print(f"[!] Could not locate compiled Swift binary 'Altr Stream'", file=sys.stderr)
            sys.exit(1)

    print(f"[+] Swift app built successfully: {built_bin} ({built_bin.stat().st_size:,} bytes)")
    return built_bin


def assemble_app_bundle(
    swift_binary: Path,
    go_engine_binary: Path,
    output_dir: Path,
    version: str,
) -> Path:
    """Assemble the standalone Altr Stream.app macOS bundle."""
    app_dir = output_dir / "Altr Stream.app"
    macos_dir = app_dir / "Contents" / "MacOS"
    resources_dir = app_dir / "Contents" / "Resources"

    # Clean existing bundle if present
    if app_dir.exists():
        shutil.rmtree(app_dir)

    macos_dir.mkdir(parents=True, exist_ok=True)
    resources_dir.mkdir(parents=True, exist_ok=True)

    # 1. Copy executable
    dest_exe = macos_dir / "Altr Stream"
    shutil.copy2(swift_binary, dest_exe)
    dest_exe.chmod(0o755)

    # 2. Copy embedded Go engine
    dest_engine = resources_dir / "altr-installer-engine"
    shutil.copy2(go_engine_binary, dest_engine)
    dest_engine.chmod(0o755)

    # 3. Write Info.plist
    info_plist_src = REPO_ROOT / "packaging" / "macos" / "Info.plist"
    dest_plist = app_dir / "Contents" / "Info.plist"
    if info_plist_src.is_file():
        shutil.copy2(info_plist_src, dest_plist)
    else:
        dest_plist.write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Altr Stream</string>
    <key>CFBundleIdentifier</key>
    <string>com.helloaltr.altr-stream</string>
    <key>CFBundleName</key>
    <string>Altr Stream</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{version}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
""", encoding="utf-8")

    # 4. Ad-hoc codesign bundle for local macOS execution
    try:
        subprocess.run(["codesign", "--force", "--deep", "-s", "-", str(app_dir)], check=True, capture_output=True)
        print(f"[+] Ad-hoc signed application bundle: {app_dir}")
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"[-] Codesign skipped or failed: {e}")

    print(f"[+] Assembled macOS application bundle: {app_dir}")
    return app_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Altr Stream macOS App Builder")
    parser.add_argument("--version", default=CANONICAL_VERSION, help=f"Altr Stream version (default: {CANONICAL_VERSION})")
    parser.add_argument("--image", default=DEFAULT_IMAGE, help=f"Docker image reference (default: {DEFAULT_IMAGE})")
    parser.add_argument("--arch", default=None, help="Target architecture: arm64 or amd64 (default: host architecture)")
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "dist", help="Output directory")
    args = parser.parse_args()

    target_arch = args.arch or detect_host_arch()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print(" Altr Stream — Native macOS App Builder")
    print(f" Target Arch: darwin/{target_arch}")
    print(f" Version:     {args.version}")
    print(f" Image:       {args.image}")
    print(f" Output Dir:  {args.output_dir}")
    print("=" * 60)

    # 1. Build Go Engine
    engine_path = args.output_dir / "altr-installer-engine"
    build_go_engine(engine_path, args.version, args.image, target_arch)
    engine_sha = compute_sha256(engine_path)
    print(f"    SHA-256 (engine): {engine_sha}")

    # 2. Build Swift App
    swift_bin = build_swift_app(target_arch)
    swift_sha = compute_sha256(swift_bin)
    print(f"    SHA-256 (swift):  {swift_sha}")

    # 3. Assemble .app Bundle
    app_bundle = assemble_app_bundle(swift_bin, engine_path, args.output_dir, args.version)

    print("\n" + "=" * 60)
    print(" Build Complete!")
    print(f" App Bundle:      {app_bundle}")
    print(f" Architecture:    darwin/{target_arch}")
    print(f" Embedded Engine: {app_bundle / 'Contents' / 'Resources' / 'altr-installer-engine'}")
    print(f" Engine SHA-256:  {engine_sha}")
    print("=" * 60)


if __name__ == "__main__":
    main()
