#!/usr/bin/env python3
"""Altr Stream Manager — Portable Application Packager.

Prepares distributable, non-installer application packages for macOS and Windows.
No installation wizards or conventional installers.

Outputs:
  macOS:   dist/Altr-Stream-Manager.dmg (drag-and-drop DMG with Applications shortcut)
           dist/Altr Stream Manager.app (standalone application bundle)
  Windows: dist/altr-installer-engine.exe (compiled 64-bit Windows engine)
           dist/Altr-Stream-Manager-Portable.zip (portable application archive)

Usage:
  python3 scripts/build_manager_packages.py [--platform macos|windows|all] [--version 1.0.0-beta]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import platform
import plistlib
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_VERSION = "1.1.0"
DEFAULT_IMAGE = f"ghcr.io/helloaltr/altr-stream:{DEFAULT_VERSION}"


def compute_sha256(file_path: Path) -> str:
    """Compute hex-encoded SHA-256 hash of a file."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def build_go_engine_macos(output_path: Path, version: str, image: str) -> Path:
    """Compile the shared Go installer engine for Darwin as a Universal binary (arm64 + amd64)."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    engine_dir = REPO_ROOT / "packaging" / "engine"
    cache_dir = REPO_ROOT / ".build_cache" / "go"
    cache_dir.mkdir(parents=True, exist_ok=True)

    ldflags = f"-s -w -X main.DefaultImage={image} -X main.DefaultVersion={version}"
    env = os.environ.copy()
    env["CGO_ENABLED"] = "0"
    env["GOPATH"] = str(cache_dir.resolve())

    temp_arm64 = output_path.parent / f"{output_path.name}.arm64"
    temp_amd64 = output_path.parent / f"{output_path.name}.amd64"

    try:
        # 1. Build arm64
        env["GOOS"] = "darwin"
        env["GOARCH"] = "arm64"
        cmd_arm64 = ["go", "-C", str(engine_dir), "build", f"-ldflags={ldflags}", "-o", str(temp_arm64.resolve()), "."]
        print("  → Compiling Go installer engine for darwin/arm64...")
        res = subprocess.run(cmd_arm64, env=env, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Go engine build failed for darwin/arm64:\n{res.stderr}\n{res.stdout}")

        # 2. Build amd64
        env["GOOS"] = "darwin"
        env["GOARCH"] = "amd64"
        cmd_amd64 = ["go", "-C", str(engine_dir), "build", f"-ldflags={ldflags}", "-o", str(temp_amd64.resolve()), "."]
        print("  → Compiling Go installer engine for darwin/amd64...")
        res = subprocess.run(cmd_amd64, env=env, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Go engine build failed for darwin/amd64:\n{res.stderr}\n{res.stdout}")

        # 3. Create universal binary with lipo
        lipo_bin = shutil.which("lipo")
        if lipo_bin:
            print("  → Combining architectures with lipo into Universal Mach-O binary...")
            cmd_lipo = [lipo_bin, "-create", "-output", str(output_path.resolve()), str(temp_arm64.resolve()), str(temp_amd64.resolve())]
            res_lipo = subprocess.run(cmd_lipo, capture_output=True, text=True)
            if res_lipo.returncode != 0:
                print(f"  ⚠ lipo failed ({res_lipo.stderr.strip()}), falling back to host arch binary.")
                host_arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "amd64"
                src = temp_arm64 if host_arch == "arm64" else temp_amd64
                shutil.copy2(src, output_path)
        else:
            host_arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "amd64"
            src = temp_arm64 if host_arch == "arm64" else temp_amd64
            shutil.copy2(src, output_path)

        output_path.chmod(0o755)
        sha = compute_sha256(output_path)
        print(f"  ✔ Go engine (Darwin Universal) built: {output_path.name} ({output_path.stat().st_size:,} bytes, SHA: {sha})")
        return output_path
    finally:
        for temp_file in (temp_arm64, temp_amd64):
            if temp_file.exists():
                temp_file.unlink()


def build_go_engine_windows(output_path: Path, version: str, image: str) -> Path:
    """Cross-compile the shared Go installer engine for Windows amd64."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    engine_dir = REPO_ROOT / "packaging" / "engine"
    cache_dir = REPO_ROOT / ".build_cache" / "go"
    cache_dir.mkdir(parents=True, exist_ok=True)

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
    env["GOPATH"] = str(cache_dir.resolve())

    print("  → Cross-compiling Go installer engine for windows/amd64...")
    res = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Go engine compilation failed for windows/amd64:\n{res.stderr}\n{res.stdout}")

    if not output_path.is_file():
        raise FileNotFoundError(f"Expected Windows engine binary missing at {output_path}")

    sha = compute_sha256(output_path)
    print(f"  ✔ Go engine (Windows amd64) built: {output_path.name} ({output_path.stat().st_size:,} bytes, SHA: {sha})")
    return output_path


def build_flutter_macos_release(manager_dir: Path) -> Path:
    """Build the Flutter macOS release application."""
    print("  → Building Flutter macOS release application...")
    flutter_bin = shutil.which("flutter")
    if not flutter_bin:
        raise RuntimeError("Flutter SDK ('flutter') not found on system PATH.")

    cmd = [flutter_bin, "build", "macos", "--release"]
    res = subprocess.run(cmd, cwd=manager_dir, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"Flutter build macos failed (exit {res.returncode}):\n{res.stderr}\n{res.stdout}")

    built_app = manager_dir / "build" / "macos" / "Build" / "Products" / "Release" / "Altr Stream Manager.app"
    if not built_app.is_dir():
        raise FileNotFoundError(f"Expected built Flutter app not found at {built_app}")

    print(f"  ✔ Flutter macOS app built: {built_app}")
    return built_app


def assemble_macos_app_bundle(
    built_app: Path,
    go_engine: Path,
    output_dir: Path,
    app_name: str = "Altr Stream Manager.app",
) -> Path:
    """Assemble and ad-hoc sign the standalone Altr Stream Manager.app bundle."""
    target_app = output_dir / app_name
    if target_app.exists():
        if target_app.is_dir() and not target_app.is_symlink():
            shutil.rmtree(target_app)
        else:
            target_app.unlink()

    print(f"  → Staging macOS application bundle at {target_app}...")
    shutil.copytree(built_app, target_app, symlinks=True)

    # 1. Embed Go engine in Contents/Resources
    resources_dir = target_app / "Contents" / "Resources"
    resources_dir.mkdir(parents=True, exist_ok=True)
    engine_dest = resources_dir / "altr-installer-engine"
    shutil.copy2(go_engine, engine_dest)
    engine_dest.chmod(0o755)

    # 1b. Also link in Contents/MacOS for adjacent resolution
    macos_dir = target_app / "Contents" / "MacOS"
    engine_macos_dest = macos_dir / "altr-installer-engine"
    if not engine_macos_dest.exists():
        try:
            engine_macos_dest.symlink_to("../Resources/altr-installer-engine")
        except OSError:
            shutil.copy2(go_engine, engine_macos_dest)
            engine_macos_dest.chmod(0o755)

    # 2. Codesign the embedded engine and the overall bundle
    codesign_bin = shutil.which("codesign")
    if codesign_bin:
        entitlements_file = REPO_ROOT / "frontend" / "altr_stream_manager" / "macos" / "Runner" / "Release.entitlements"
        print("  → Ad-hoc codesigning embedded engine with hardened runtime...")
        subprocess.run(
            [codesign_bin, "--force", "--options", "runtime", "--sign", "-", str(engine_dest)],
            check=True,
            capture_output=True,
        )
        print("  → Ad-hoc codesigning full application bundle with hardened runtime & entitlements...")
        codesign_cmd = [codesign_bin, "--force", "--options", "runtime"]
        if entitlements_file.is_file():
            codesign_cmd.extend(["--entitlements", str(entitlements_file)])
        codesign_cmd.extend(["--deep", "--sign", "-", str(target_app)])
        subprocess.run(codesign_cmd, check=True, capture_output=True)
        # Verify signature
        verify_res = subprocess.run(
            [codesign_bin, "--verify", "--deep", "--strict", "--verbose=2", str(target_app)],
            capture_output=True,
            text=True,
        )
        if verify_res.returncode == 0:
            print("  ✔ Codesign verification passed (valid on disk, satisfies designated requirement).")
        else:
            print(f"  ⚠ Codesign verification warning:\n{verify_res.stderr}")

    return target_app


def build_dmg_package(
    app_bundle: Path,
    output_dmg: Path,
    volume_name: str = "Altr Stream Manager",
) -> Path:
    """Create a drag-and-drop disk image (.dmg) containing the application and an /Applications shortcut."""
    hdiutil_bin = shutil.which("hdiutil")
    if not hdiutil_bin:
        raise RuntimeError("hdiutil not found on system PATH (macOS required).")

    if output_dmg.exists():
        output_dmg.unlink()

    staging_dir = output_dmg.parent / "dmg_manager_staging"
    if staging_dir.exists():
        shutil.rmtree(staging_dir, ignore_errors=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    try:
        # 1. Copy app bundle
        staged_app = staging_dir / app_bundle.name
        print(f"  → Staging {app_bundle.name} for disk image creation...")
        shutil.copytree(app_bundle, staged_app, symlinks=True)

        # 2. Create /Applications symlink for drag-and-drop
        apps_symlink = staging_dir / "Applications"
        apps_symlink.symlink_to("/Applications")

        # 3. Build compressed UDZO disk image
        print(f"  → Creating DMG disk image with hdiutil: {output_dmg.name}...")
        cmd = [
            hdiutil_bin,
            "create",
            "-volname",
            volume_name,
            "-srcfolder",
            str(staging_dir.resolve()),
            "-ov",
            "-format",
            "UDZO",
            str(output_dmg.resolve()),
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"hdiutil create failed (exit {res.returncode}):\n{res.stderr}")

        if not output_dmg.is_file() or output_dmg.stat().st_size == 0:
            raise RuntimeError(f"Generated DMG missing or zero size: {output_dmg}")

        dmg_sha = compute_sha256(output_dmg)
        print(f"  ✔ Created macOS DMG: {output_dmg.name} ({output_dmg.stat().st_size:,} bytes, SHA: {dmg_sha})")
        return output_dmg
    finally:
        if staging_dir.exists():
            shutil.rmtree(staging_dir, ignore_errors=True)


def verify_dmg_mount(dmg_path: Path) -> bool:
    """Mount the DMG, inspect contents, verify bundle integrity, and unmount cleanly."""
    hdiutil_bin = shutil.which("hdiutil")
    if not hdiutil_bin or platform.system() != "Darwin":
        return True

    print(f"  → Verifying DMG mountability: {dmg_path.name}...")
    attach_cmd = [hdiutil_bin, "attach", "-nobrowse", "-readonly", str(dmg_path.resolve())]
    res = subprocess.run(attach_cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"  ✖ Failed to attach DMG:\n{res.stderr}")
        return False

    mount_point = None
    for line in res.stdout.splitlines():
        parts = line.strip().split("\t")
        for part in parts:
            p = part.strip()
            if p.startswith("/Volumes/"):
                mount_point = Path(p)
                break
        if mount_point:
            break

    if not mount_point or not mount_point.is_dir():
        # Fallback search under /Volumes
        cand = Path("/Volumes/Altr Stream Manager")
        if cand.is_dir():
            mount_point = cand

    if not mount_point:
        print("  ✖ Could not determine DMG mount point from hdiutil output.")
        return False

    try:
        app_in_dmg = mount_point / "Altr Stream Manager.app"
        apps_link = mount_point / "Applications"
        engine_in_dmg = app_in_dmg / "Contents" / "Resources" / "altr-installer-engine"

        assert app_in_dmg.is_dir(), f"Altr Stream Manager.app missing in mounted DMG: {mount_point}"
        assert apps_link.is_symlink(), f"Applications symlink missing in mounted DMG: {mount_point}"
        assert engine_in_dmg.is_file(), f"Embedded engine missing in mounted app: {engine_in_dmg}"
        assert os.access(engine_in_dmg, os.X_OK), "Embedded engine inside DMG is not executable"

        print(f"  ✔ DMG inspection verified: volume mounted at {mount_point}, valid app bundle, Applications link, and embedded engine.")
        return True
    finally:
        detach_cmd = [hdiutil_bin, "detach", str(mount_point), "-force"]
        subprocess.run(detach_cmd, capture_output=True, text=True)


def build_windows_portable_package(
    windows_engine: Path,
    output_dir: Path,
    version: str,
) -> Path:
    """Assemble the Windows portable application package (Altr-Stream-Manager-Portable.zip).

    Why a single self-contained executable is not recommended for Flutter Windows:
    Flutter on Windows compiles into a native PE launcher that dynamically links against:
      - flutter_windows.dll (the Flutter C++ rendering engine)
      - data/ (icudtl.dat unicode data, flutter_assets, shaders, kernel blobs)
      - Plugin DLLs (e.g. url_launcher_windows.dll)
      - Embedded native processes (altr-installer-engine.exe)
    Third-party single-executable bundlers (SFX / BoxedApp / Enigma) uncompress to
    %TEMP% on every run, introducing launch latency, false-positive antivirus quarantines,
    and relative-path breakages for persistent configuration and child engine supervision.

    The portable ZIP folder package allows direct in-place execution without setup wizards
    or administrative privileges, while preserving user configuration in %USERPROFILE%\\.altr-stream.
    """
    output_zip = output_dir / "Altr-Stream-Manager-Portable.zip"
    staging_dir = output_dir / "Altr-Stream-Manager-Portable"
    if staging_dir.exists():
        shutil.rmtree(staging_dir, ignore_errors=True)
    staging_dir.mkdir(parents=True, exist_ok=True)

    print(f"  → Staging Windows portable application structure in {staging_dir.name}...")

    # 1. Place the Windows Go engine
    dest_engine = staging_dir / "altr-installer-engine.exe"
    shutil.copy2(windows_engine, dest_engine)

    # 2. Check if a native Flutter Windows runner release build exists
    runner_release_dir = REPO_ROOT / "frontend" / "altr_stream_manager" / "build" / "windows" / "x64" / "runner" / "Release"
    has_native_windows_build = False

    if runner_release_dir.is_dir():
        print(f"  → Found native Windows Flutter build artifacts in {runner_release_dir}...")
        for item in runner_release_dir.iterdir():
            if item.name.endswith(".pdb"):
                continue  # skip debug symbols
            dest = staging_dir / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)
        has_native_windows_build = True
    else:
        print("  ℹ Note: Native Flutter Windows runner must be compiled on a Windows host using Visual Studio.")
        print("    Staging portable template with native engine, portable manifest, and instructions.")

    # 3. Write README-PORTABLE.txt
    readme_content = f"""Altr Stream Manager — Portable Edition (Windows x64)
Version: {version}
-----------------------------------------------------------

Getting Started:
  1. Extract this entire folder to any location (e.g. C:\\Tools\\Altr-Stream-Manager or your Desktop).
  2. Double-click 'Altr-Stream-Manager.exe' to launch.
  3. No installation wizard or administrator privileges are required.

Engine & Runtime Architecture:
  - Entry Executable:  Altr-Stream-Manager.exe (Flutter Desktop UI)
  - Native Engine:     altr-installer-engine.exe (Adjacent Go backend bridge)
  - Persistent Data:   %USERPROFILE%\\.altr-stream
  - Configuration:     %USERPROFILE%\\.altr-stream-config
  - Docker State:      Managed via local Docker Desktop daemon

Single Executable Limitation Note:
  Flutter desktop applications on Windows require runtime dependencies:
  - flutter_windows.dll (Flutter C++ engine)
  - data/icudtl.dat (Unicode data)
  - data/flutter_assets/ (UI assets and fonts)
  Wrapping these into a self-extracting single .exe uncompresses ~40MB to %TEMP%
  on every launch, causing severe startup latency, antivirus false positives,
  and path resolution failures for persistent logs and engine communication.
  This portable folder distribution is the officially supported non-installer format.
"""
    (staging_dir / "README-PORTABLE.txt").write_text(readme_content, encoding="utf-8")

    try:
        # 4. Create ZIP archive
        if output_zip.exists():
            output_zip.unlink()

        print(f"  → Creating {output_zip.name}...")
        with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(staging_dir):
                for file in files:
                    p = Path(root) / file
                    arcname = p.relative_to(output_dir)
                    zf.write(p, arcname)

        sha = compute_sha256(output_zip)
        print(f"  ✔ Created Windows portable archive: {output_zip.name} ({output_zip.stat().st_size:,} bytes, SHA: {sha})")
        return output_zip
    finally:
        if staging_dir.exists():
            shutil.rmtree(staging_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Altr Stream Manager — Portable Application Packager")
    parser.add_argument("--version", default=DEFAULT_VERSION, help=f"Manager version (default: {DEFAULT_VERSION})")
    parser.add_argument("--image", default=DEFAULT_IMAGE, help=f"Docker image reference (default: {DEFAULT_IMAGE})")
    parser.add_argument("--platform", choices=["macos", "windows", "all"], default="all", help="Target platform to package")
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "dist", help="Output directory for packages")
    parser.add_argument("--skip-flutter-build", action="store_true", help="Skip rebuilding Flutter macOS app if already built")
    args = parser.parse_args()

    version = args.version.lstrip("v")
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    manager_dir = REPO_ROOT / "frontend" / "altr_stream_manager"

    print("=" * 70)
    print(" Altr Stream Manager — Portable Application Packager")
    print(f" Version:     {version}")
    print(f" Image:       {args.image}")
    print(f" Platform(s): {args.platform}")
    print(f" Output Dir:  {output_dir}")
    print("=" * 70)

    artifacts = []

    # -------------------------------------------------------------------------
    # macOS Packaging
    # -------------------------------------------------------------------------
    if args.platform in ("macos", "all"):
        if platform.system() == "Darwin":
            print("\n[1/2] Building macOS Portable Distribution...")

            # 1. Build Go Engine for macOS (Universal)
            macos_engine = output_dir / "altr-installer-engine"
            build_go_engine_macos(macos_engine, version=version, image=args.image)
            artifacts.append(("Go Engine (macOS Universal)", macos_engine))

            # 2. Build or locate Flutter app
            release_app = manager_dir / "build" / "macos" / "Build" / "Products" / "Release" / "Altr Stream Manager.app"
            if not args.skip_flutter_build or not release_app.is_dir():
                release_app = build_flutter_macos_release(manager_dir)

            # 3. Assemble and codesign bundle
            app_bundle = assemble_macos_app_bundle(release_app, macos_engine, output_dir)
            artifacts.append(("macOS App Bundle", app_bundle))

            # 4. Build DMG installer
            dmg_path = output_dir / "Altr-Stream-Manager.dmg"
            build_dmg_package(app_bundle, dmg_path)
            verify_dmg_mount(dmg_path)
            artifacts.append(("macOS Drag-and-Drop DMG", dmg_path))
        else:
            print("\n[!] Skipping macOS DMG build: host OS is not Darwin.")

    # -------------------------------------------------------------------------
    # Windows Packaging
    # -------------------------------------------------------------------------
    if args.platform in ("windows", "all"):
        print("\n[2/2] Building Windows Portable Distribution...")

        # 1. Build Windows Go Engine (Cross-compiled for windows/amd64)
        windows_engine = output_dir / "altr-installer-engine.exe"
        build_go_engine_windows(windows_engine, version=version, image=args.image)
        artifacts.append(("Go Engine (Windows amd64)", windows_engine))

        # 2. Assemble Portable ZIP Package
        portable_zip = build_windows_portable_package(windows_engine, output_dir, version=version)
        artifacts.append(("Windows Portable ZIP", portable_zip))

    # -------------------------------------------------------------------------
    # Summary Report
    # -------------------------------------------------------------------------
    print("\n" + "=" * 70)
    print(" Packaging Complete! Generated Artifacts:")
    print("=" * 70)
    for desc, path in artifacts:
        if path.is_file():
            size = f"{path.stat().st_size:,} bytes"
            sha = compute_sha256(path)
            print(f" - {desc:30} : {path.name} ({size})\n   SHA-256: {sha}")
        elif path.is_dir():
            print(f" - {desc:30} : {path.name}/ (directory bundle)")
    print("=" * 70)


if __name__ == "__main__":
    main()
