#!/usr/bin/env python3
"""Altr Stream — Windows Native Installer Builder.

Compiles the Go installer engine for Windows amd64 and builds
the native Inno Setup 6 installer executable (Altr-Stream-Installer.exe).

Usage:
    python3 scripts/build_windows_installer.py [--version 1.0.0-beta] [--image ghcr.io/helloaltr/altr-stream:0.13.7-alpha] [--output-dir dist]
"""

from __future__ import annotations

import argparse
import hashlib
import os
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


def build_go_engine(output_path: Path, version: str, image: str) -> Path:
    """Cross-compile the shared Go installer engine for Windows amd64."""
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
    env["GOOS"] = "windows"
    env["GOARCH"] = "amd64"
    env["CGO_ENABLED"] = "0"
    cache_dir = REPO_ROOT / ".build_cache" / "go"
    cache_dir.mkdir(parents=True, exist_ok=True)
    env["GOPATH"] = str(cache_dir.resolve())

    print(f"  → Building Go engine for Windows amd64...")
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Go engine compilation failed (exit {res.returncode}):\n{res.stderr}\n{res.stdout}")

    if not output_path.exists():
        raise FileNotFoundError(f"Expected engine binary not found at {output_path}")

    engine_sha = compute_sha256(output_path)
    print(f"  ✔ Go engine compiled: {output_path.name} ({output_path.stat().st_size:,} bytes, SHA-256: {engine_sha})")
    return output_path


def find_iscc_runner() -> tuple[list[str], str]:
    """Find available Inno Setup compiler runner (native ISCC or Docker container)."""
    # 1. Native ISCC in PATH or standard Windows locations
    native_iscc = shutil.which("iscc") or shutil.which("ISCC.exe")
    if not native_iscc and sys.platform == "win32":
        standard_paths = [
            Path(r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"),
            Path(r"C:\Program Files\Inno Setup 6\ISCC.exe"),
        ]
        for p in standard_paths:
            if p.exists():
                native_iscc = str(p)
                break

    if native_iscc:
        return [native_iscc], "native"

    # 2. Docker container fallback with amake/innosetup
    docker_bin = shutil.which("docker")
    if docker_bin:
        try:
            res = subprocess.run([docker_bin, "info"], capture_output=True, text=True, timeout=10)
            if res.returncode == 0:
                return [
                    docker_bin,
                    "run",
                    "--rm",
                    "-v",
                    f"{REPO_ROOT}:/work",
                    "-w",
                    "/work/packaging/windows",
                    "amake/innosetup",
                ], "docker"
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            pass

    raise RuntimeError(
        "Inno Setup 6 compiler (iscc) not found.\n"
        "To build on Windows: Install Inno Setup 6 (https://jrsoftware.org/isdl.php) and ensure ISCC is in PATH.\n"
        "To build on macOS/Linux: Ensure Docker Desktop or Docker Engine is running to use the amake/innosetup image."
    )


def compile_inno_setup(
    iss_file: Path,
    output_dir: Path,
    version: str,
    image: str,
) -> Path:
    """Compile the Inno Setup script into Altr-Stream-Installer.exe."""
    output_dir.mkdir(parents=True, exist_ok=True)
    runner, runner_type = find_iscc_runner()

    target_exe = output_dir / "Altr-Stream-Installer.exe"
    if target_exe.exists():
        target_exe.unlink()

    print(f"  → Compiling Windows installer via {runner_type} Inno Setup runner...")

    default_dist = REPO_ROOT / "dist"
    default_dist.mkdir(parents=True, exist_ok=True)
    for stale in default_dist.glob("Altr-Stream-Installer*"):
        try:
            stale.unlink()
        except OSError:
            pass

    needs_perm_reset = False
    if runner_type == "docker" and os.name != "nt":
        try:
            default_dist.chmod(0o777)
            needs_perm_reset = True
        except OSError:
            pass

    try:
        if runner_type == "docker":
            cmd = runner + [
                f"/DMyAppVersion={version}",
                f"/DMyDockerImage={image}",
                "Altr-Stream.iss",
            ]
        else:
            cmd = runner + [
                f"/DMyAppVersion={version}",
                f"/DMyDockerImage={image}",
                f"/DMyOutputDir={output_dir.resolve()}",
                str(iss_file.resolve()),
            ]

        res = subprocess.run(cmd, cwd=iss_file.parent, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Inno Setup compilation failed (exit {res.returncode}):\n{res.stderr}\n{res.stdout}")
    finally:
        if needs_perm_reset:
            try:
                default_dist.chmod(0o755)
            except OSError:
                pass

    built_exe = (default_dist / "Altr-Stream-Installer.exe") if runner_type == "docker" else target_exe
    if not built_exe.exists():
        raise FileNotFoundError(f"Expected installer executable not found at {built_exe}")

    if built_exe.resolve() != target_exe.resolve():
        shutil.copy2(built_exe, target_exe)

    # Validate PE header (MZ signature)
    with open(target_exe, "rb") as f:
        magic = f.read(2)
        if magic != b"MZ":
            raise ValueError(f"Invalid executable format: {target_exe} does not start with MZ signature")

    print(f"  ✔ Windows installer built: {target_exe.name} ({target_exe.stat().st_size:,} bytes)")
    return target_exe


def build_windows_installer(
    version: str = CANONICAL_VERSION,
    image: str = DEFAULT_IMAGE,
    output_dir: Path | None = None,
    skip_engine_build: bool = False,
) -> Path:
    """End-to-end build pipeline for the Windows native installer."""
    if output_dir is None:
        output_dir = REPO_ROOT / "dist"
    output_dir.mkdir(parents=True, exist_ok=True)

    engine_output = REPO_ROOT / "packaging" / "windows" / "build" / "altr-installer-engine.exe"
    if not skip_engine_build or not engine_output.exists():
        build_go_engine(engine_output, version=version, image=image)

    iss_file = REPO_ROOT / "packaging" / "windows" / "Altr-Stream.iss"
    installer_exe = compile_inno_setup(
        iss_file=iss_file,
        output_dir=output_dir,
        version=version,
        image=image,
    )

    sha = compute_sha256(installer_exe)
    engine_sha = compute_sha256(engine_output)
    print(f"\nWindows Installer Packaging Complete:")
    print(f"  Embedded Engine: {engine_output}")
    print(f"  Engine Size:     {engine_output.stat().st_size:,} bytes")
    print(f"  Engine SHA-256:  {engine_sha}")
    print(f"  Artifact:        {installer_exe}")
    print(f"  Installer Size:  {installer_exe.stat().st_size:,} bytes")
    print(f"  SHA-256:         {sha}")

    return installer_exe


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Altr Stream Windows native installer (.exe).")
    parser.add_argument(
        "--version",
        default=CANONICAL_VERSION,
        help=f"Canonical application version (default: {CANONICAL_VERSION})",
    )
    parser.add_argument(
        "--image",
        default=DEFAULT_IMAGE,
        help=f"Target Docker image tag (default: {DEFAULT_IMAGE})",
    )
    parser.add_argument(
        "--output-dir",
        default="dist",
        help="Directory to place output executable (default: dist)",
    )
    parser.add_argument(
        "--skip-engine-build",
        action="store_true",
        help="Skip Go engine compilation if already present in packaging/windows/build",
    )

    args = parser.parse_args()
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = REPO_ROOT / output_dir

    try:
        build_windows_installer(
            version=args.version.lstrip("v"),
            image=args.image,
            output_dir=output_dir,
            skip_engine_build=args.skip_engine_build,
        )
        return 0
    except Exception as exc:
        print(f"\n❌ Error building Windows installer: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
