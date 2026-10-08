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
import plistlib
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

DEFAULT_IMAGE = None


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
        output_parts = []
        if result.stdout and result.stdout.strip():
            output_parts.append(f"--- STDOUT ---\n{result.stdout.strip()}")
        if result.stderr and result.stderr.strip():
            output_parts.append(f"--- STDERR ---\n{result.stderr.strip()}")
        diag = "\n\n".join(output_parts) if output_parts else "(No output recorded on stdout or stderr)"
        print(f"[!] Swift compilation failed (exit code {result.returncode}):\n{diag}", file=sys.stderr)
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
    app_name: str = "Altr Stream.app",
) -> Path:
    """Assemble the standalone Altr Stream.app macOS bundle."""
    app_dir = output_dir / app_name
    macos_dir = app_dir / "Contents" / "MacOS"
    resources_dir = app_dir / "Contents" / "Resources"

    # Clean existing bundle if present
    if app_dir.exists():
        if app_dir.is_dir() and not app_dir.is_symlink():
            shutil.rmtree(app_dir)
        else:
            app_dir.unlink()

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
        try:
            with open(info_plist_src, "rb") as f:
                plist_data = plistlib.load(f)
            plist_data["CFBundleShortVersionString"] = version
            plist_data["CFBundleVersion"] = version
            with open(dest_plist, "wb") as f:
                plistlib.dump(plist_data, f)
        except Exception:
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
    <key>CFBundleVersion</key>
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

    # 5. Maintain backwards-compatible symlinks between 'Altr Stream.app' and 'Altr Stream Installer.app'
    compat_name = "Altr Stream Installer.app" if app_name == "Altr Stream.app" else "Altr Stream.app"
    compat_link = output_dir / compat_name
    if compat_link.exists() or compat_link.is_symlink():
        if compat_link.is_dir() and not compat_link.is_symlink():
            shutil.rmtree(compat_link)
        else:
            compat_link.unlink()
    try:
        compat_link.symlink_to(app_dir.name)
    except OSError:
        pass

    print(f"[+] Assembled macOS application bundle: {app_dir}")
    return app_dir


def archive_app_bundle(app_bundle: Path, output_zip: Path) -> Path:
    """Create a distributable zip archive of the .app bundle preserving permissions, symlinks, and signature."""
    if output_zip.exists():
        output_zip.unlink()

    output_zip.parent.mkdir(parents=True, exist_ok=True)

    # 1. Prefer macOS native ditto tool (Apple standard for packaging .app bundles)
    ditto_bin = shutil.which("ditto")
    if ditto_bin and sys.platform == "darwin":
        cmd = [ditto_bin, "-c", "-k", "--keepParent", str(app_bundle), str(output_zip)]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0 and output_zip.is_file():
            print(f"[+] Created macOS app archive via ditto: {output_zip} ({output_zip.stat().st_size:,} bytes)")
            return output_zip

    # 2. Fallback to standard zip CLI preserving symlinks (-y)
    zip_bin = shutil.which("zip")
    if zip_bin:
        cmd = [zip_bin, "-r", "-y", "-q", str(output_zip.resolve()), app_bundle.name]
        res = subprocess.run(cmd, cwd=app_bundle.parent, capture_output=True, text=True)
        if res.returncode == 0 and output_zip.is_file():
            print(f"[+] Created macOS app archive via zip: {output_zip} ({output_zip.stat().st_size:,} bytes)")
            return output_zip

    # 3. Fallback to python zipfile preserving POSIX attributes
    import stat as stat_mod
    import zipfile
    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(app_bundle):
            for item in dirs + files:
                p = Path(root) / item
                arcname = str(p.relative_to(app_bundle.parent))
                st = os.lstat(p)
                if stat_mod.S_ISLNK(st.st_mode):
                    link_target = os.readlink(p)
                    zinfo = zipfile.ZipInfo(arcname)
                    zinfo.create_system = 3
                    zinfo.external_attr = (stat_mod.S_IFLNK | 0o777) << 16
                    zf.writestr(zinfo, link_target)
                elif p.is_file():
                    with open(p, "rb") as f:
                        data = f.read()
                    zinfo = zipfile.ZipInfo(arcname)
                    zinfo.create_system = 3
                    zinfo.external_attr = (st.st_mode & 0xFFFF) << 16
                    zf.writestr(zinfo, data)

    print(f"[+] Created macOS app archive via zipfile: {output_zip} ({output_zip.stat().st_size:,} bytes)")
    return output_zip


def build_pkg_installer(
    app_bundle: Path,
    output_pkg: Path,
    version: str,
    scripts_dir: Path | None = None,
    identifier: str = "com.helloaltr.altr-stream",
    install_location: str = "/Applications",
) -> Path:
    """Build a standalone macOS distribution installer (.pkg) using Apple's pkgbuild and productbuild."""
    pkgbuild_bin = shutil.which("pkgbuild")
    productbuild_bin = shutil.which("productbuild")

    if not pkgbuild_bin or not productbuild_bin:
        raise RuntimeError("Native macOS packaging tools 'pkgbuild' or 'productbuild' not found on system PATH.")

    if scripts_dir is None:
        scripts_dir = REPO_ROOT / "packaging" / "macos" / "scripts"

    if output_pkg.exists():
        output_pkg.unlink()

    output_pkg.parent.mkdir(parents=True, exist_ok=True)
    temp_component_pkg = output_pkg.parent / "Altr-Stream-Component.pkg"
    if temp_component_pkg.exists():
        temp_component_pkg.unlink()

    try:
        # 1. Build component package with pkgbuild
        cmd_pkg = [
            pkgbuild_bin,
            "--component",
            str(app_bundle.resolve()),
            "--install-location",
            install_location,
            "--identifier",
            identifier,
            "--version",
            version,
        ]
        if scripts_dir and scripts_dir.is_dir():
            cmd_pkg.extend(["--scripts", str(scripts_dir.resolve())])

        cmd_pkg.append(str(temp_component_pkg.resolve()))

        print(f"[*] Building component package with pkgbuild: {temp_component_pkg.name}...")
        res_pkg = subprocess.run(cmd_pkg, capture_output=True, text=True)
        if res_pkg.returncode != 0:
            print(f"[!] pkgbuild failed (exit code {res_pkg.returncode}):\n{res_pkg.stderr}", file=sys.stderr)
            raise RuntimeError(f"pkgbuild failed: {res_pkg.stderr.strip()}")

        # 2. Build final distribution product archive with productbuild
        cmd_prod = [
            productbuild_bin,
            "--package",
            str(temp_component_pkg.resolve()),
            str(output_pkg.resolve()),
        ]

        print(f"[*] Building product distribution installer with productbuild: {output_pkg.name}...")
        res_prod = subprocess.run(cmd_prod, capture_output=True, text=True)
        if res_prod.returncode != 0:
            print(f"[!] productbuild failed (exit code {res_prod.returncode}):\n{res_prod.stderr}", file=sys.stderr)
            raise RuntimeError(f"productbuild failed: {res_prod.stderr.strip()}")

        if not output_pkg.is_file() or output_pkg.stat().st_size == 0:
            raise RuntimeError(f"Generated package is missing or empty: {output_pkg}")

        print(f"[+] Created macOS .pkg installer: {output_pkg} ({output_pkg.stat().st_size:,} bytes)")
        return output_pkg
    finally:
        if temp_component_pkg.exists():
            temp_component_pkg.unlink()


def build_macos_app(
    version: str = CANONICAL_VERSION,
    image: str | None = None,
    arch: str | None = None,
    output_dir: Path | None = None,
    app_name: str = "Altr Stream.app",
    pkg_name: str = "Altr-Stream-Installer.pkg",
    archive_name: str = "Altr-Stream_macOS_Installer.app.zip",
    build_pkg: bool = True,
    build_zip: bool = True,
) -> Path:
    """Build the macOS native application, .pkg distribution installer, and optional zip archive."""
    if output_dir is None:
        output_dir = REPO_ROOT / "dist"
    output_dir.mkdir(parents=True, exist_ok=True)

    target_arch = arch or detect_host_arch()
    if image is None:
        image = f"ghcr.io/helloaltr/altr-stream:{version}"

    print("=" * 60)
    print(" Altr Stream — Native macOS App Builder")
    print(f" Target Arch: darwin/{target_arch}")
    print(f" Version:     {version}")
    print(f" Image:       {image}")
    print(f" Output Dir:  {output_dir}")
    print(f" App Name:    {app_name}")
    print(f" PKG Name:    {pkg_name}")
    print(f" Zip Name:    {archive_name}")
    print("=" * 60)

    # 1. Build Go Engine
    engine_path = output_dir / "altr-installer-engine"
    build_go_engine(engine_path, version, image, target_arch)
    engine_sha = compute_sha256(engine_path)
    print(f"    SHA-256 (engine): {engine_sha}")

    # 2. Build Swift App
    swift_bin = build_swift_app(target_arch)
    swift_sha = compute_sha256(swift_bin)
    print(f"    SHA-256 (swift):  {swift_sha}")

    # 3. Assemble .app Bundle
    app_bundle = assemble_app_bundle(swift_bin, engine_path, output_dir, version, app_name=app_name)

    # 4. Build .pkg installer (primary distribution format)
    pkg_path = output_dir / pkg_name
    if build_pkg:
        build_pkg_installer(app_bundle, pkg_path, version=version)
        pkg_sha = compute_sha256(pkg_path)
        print(f"    SHA-256 (pkg):    {pkg_sha}")

    # 5. Create Archive (fallback/auxiliary distribution format)
    archive_path = output_dir / archive_name
    if build_zip:
        archive_app_bundle(app_bundle, archive_path)
        archive_sha = compute_sha256(archive_path)
        print(f"    SHA-256 (zip):    {archive_sha}")

    print("\n" + "=" * 60)
    print(" Build Complete!")
    print(f" App Bundle:      {app_bundle}")
    if build_pkg:
        print(f" PKG Installer:   {pkg_path} (primary)")
    if build_zip:
        print(f" Zip Archive:     {archive_path} (fallback)")
    print(f" Architecture:    darwin/{target_arch}")
    print(f" Embedded Engine: {app_bundle / 'Contents' / 'Resources' / 'altr-installer-engine'}")
    print("=" * 60)

    return pkg_path if build_pkg else archive_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Altr Stream macOS App Builder")
    parser.add_argument("--version", default=CANONICAL_VERSION, help=f"Altr Stream version (default: {CANONICAL_VERSION})")
    parser.add_argument("--image", default=None, help="Docker image reference (default: ghcr.io/helloaltr/altr-stream:{version})")
    parser.add_argument("--arch", default=None, help="Target architecture: arm64 or amd64 (default: host architecture)")
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "dist", help="Output directory")
    parser.add_argument("--app-name", default="Altr Stream.app", help="Application bundle name")
    parser.add_argument("--pkg-name", default="Altr-Stream-Installer.pkg", help="Output PKG installer name")
    parser.add_argument("--archive-name", default="Altr-Stream_macOS_Installer.app.zip", help="Output archive name")
    parser.add_argument("--no-pkg", action="store_true", help="Skip building .pkg installer")
    parser.add_argument("--no-zip", action="store_true", help="Skip building .app.zip archive")
    args = parser.parse_args()

    build_macos_app(
        version=args.version,
        image=args.image,
        arch=args.arch,
        output_dir=args.output_dir,
        app_name=args.app_name,
        pkg_name=args.pkg_name,
        archive_name=args.archive_name,
        build_pkg=not args.no_pkg,
        build_zip=not args.no_zip,
    )


if __name__ == "__main__":
    main()
