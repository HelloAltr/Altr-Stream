#!/usr/bin/env python3
"""Altr Stream — Release Artifact Packager.

Generates OS-specific automated installers, bundled Gum setup archives,
the manual Docker Compose deployment bundle, and cryptographic checksums for a given release tag/version.

Usage:
    python3 scripts/package_release.py [--version 0.13.7-alpha] [--tag v0.13.7-alpha] [--output-dir dist]
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

# Add src to pythonpath to resolve canonical version if not specified
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "src"))

try:
    from altr_stream.__version__ import __version__ as CANONICAL_VERSION
except ImportError:
    CANONICAL_VERSION = "0.13.7-alpha"

GUM_VERSION = "2.0.2"
GUM_PINNED_VERSION = GUM_VERSION
GUM_CHECKSUMS = {
    "gum_2.0.2_Darwin_arm64.tar.gz": "4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890",
    "gum_2.0.2_Darwin_x86_64.tar.gz": "5374966c7c7199ea879fcaa525ddc6d447a098d3d35496e430a9a1ef38d30485",
    "gum_2.0.2_Linux_x86_64.tar.gz": "d842e06d93dbed90af48cb8dd10698db6f22e331fc40346bb37bbc753109edc2",
    "gum_2.0.2_Linux_arm64.tar.gz": "8ebf8b54ec1e8c81f2bb58b59ff9b70998186a4d11375f0cf357b80e0ccfa1d5",
    "gum_2.0.2_Windows_x86_64.zip": "0397091dec9b4e8f00e02b90fd3eb07bf45acabbdb61d67437950f18e03a8b79",
}
GUM_OFFICIAL_CHECKSUMS = GUM_CHECKSUMS


def compute_sha256(file_path: Path) -> str:
    """Compute hex-encoded SHA-256 hash of a file."""
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            hasher.update(chunk)
    return hasher.hexdigest()


def ensure_gum_archive(filename: str, cache_dir: Path) -> Path:
    """Ensure a pinned Gum release archive exists and matches its SHA-256 checksum."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    archive_path = cache_dir / filename
    expected_sha = GUM_CHECKSUMS.get(filename)
    if not expected_sha:
        raise ValueError(f"Unknown Gum archive filename: {filename}")

    if archive_path.is_file():
        actual_sha = compute_sha256(archive_path)
        if actual_sha == expected_sha:
            return archive_path
        print(f"  ⚠ Cached {filename} hash mismatch ({actual_sha} != {expected_sha}), re-fetching...")
        archive_path.unlink()

    url = f"https://github.com/charmbracelet/gum/releases/download/v{GUM_VERSION}/{filename}"
    print(f"  ↓ Downloading {filename} from official release...")
    req = urllib.request.Request(url, headers={"User-Agent": "AltrStream-ReleasePackager"})
    with urllib.request.urlopen(req, timeout=30) as resp, open(archive_path, "wb") as out_file:
        shutil.copyfileobj(resp, out_file)

    actual_sha = compute_sha256(archive_path)
    if actual_sha != expected_sha:
        archive_path.unlink()
        raise ValueError(f"Verification failed for {filename}! Checksum mismatch: {actual_sha} != {expected_sha}")

    return archive_path


def install_gum_binary(
    dest_path: Path,
    archive_name: str | None = None,
    cache_dir: Path | None = None,
) -> Path:
    """Download, verify against pinned SHA-256, and extract official Gum binary to dest_path."""
    if archive_name is None:
        import platform
        system = platform.system()
        machine = platform.machine().lower()
        if system == "Linux":
            if machine in ("x86_64", "amd64"):
                archive_name = "gum_2.0.2_Linux_x86_64.tar.gz"
            elif machine in ("aarch64", "arm64"):
                archive_name = "gum_2.0.2_Linux_arm64.tar.gz"
        elif system == "Darwin":
            if machine in ("arm64", "aarch64"):
                archive_name = "gum_2.0.2_Darwin_arm64.tar.gz"
            else:
                archive_name = "gum_2.0.2_Darwin_x86_64.tar.gz"
        elif system == "Windows":
            archive_name = "gum_2.0.2_Windows_x86_64.zip"

    if not archive_name or archive_name not in GUM_CHECKSUMS:
        raise ValueError(f"Unsupported platform or unknown archive for Gum: {archive_name}")

    if cache_dir is None:
        cache_dir = REPO_ROOT / ".cache" / "gum"

    archive_path = ensure_gum_archive(archive_name, cache_dir)
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    if archive_name.endswith(".tar.gz"):
        with tarfile.open(archive_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.name.endswith("/gum") or member.name == "gum":
                    extracted_f = tar.extractfile(member)
                    if extracted_f:
                        dest_path.write_bytes(extracted_f.read())
                        dest_path.chmod(dest_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                        return dest_path
    elif archive_name.endswith(".zip"):
        with zipfile.ZipFile(archive_path, "r") as zf:
            for name in zf.namelist():
                if name.endswith("gum.exe") or name == "gum.exe":
                    data = zf.read(name)
                    dest_path.write_bytes(data)
                    return dest_path

    raise RuntimeError(f"Could not locate gum executable in archive {archive_name}")


def generate_deployment_readme(version: str, tag: str) -> str:
    """Generate the concise user README for the manual deployment bundle."""
    return f"""# Altr Stream Manual Deployment Bundle — {tag}

This archive contains the standalone Docker Compose configuration for **Altr Stream {tag}**.

## Prerequisites
- Docker Engine 24.0+
- Docker Compose v2.20+

## Quick Start

1. Start Altr Stream in the background:
   ```bash
   docker compose up -d
   ```

2. Verify that the container is healthy:
   ```bash
   docker compose ps
   ```

3. Open the web interface:
   - Web Application: http://localhost:8000
   - REST API Docs:   http://localhost:8000/docs
   - Healthcheck:     http://localhost:8000/api/v1/health

## Persistent Storage
All state (configured sources, logical models, field mappings, internal metadata)
is persisted in the named Docker volume `altr_stream_data`.

Data is preserved across container recreations and restarts.

## Stopping the Service
```bash
docker compose stop
```

For detailed production instructions, see `DEPLOYMENT.md`.
"""


def package_release(
    version: str,
    tag: str | Path | None = None,
    output_dir: Path | None = None,
    bundle_gum: bool = True,
) -> list[Path]:
    """Build all release assets and return list of generated artifact paths."""
    if output_dir is None and isinstance(tag, Path):
        output_dir = tag
        tag = f"v{version}"
    elif tag is None:
        tag = f"v{version}"
    elif isinstance(tag, str) and output_dir is None:
        output_dir = Path("dist")

    assert output_dir is not None
    output_dir.mkdir(parents=True, exist_ok=True)
    templates_dir = REPO_ROOT / "packaging" / "templates"
    installers_dir = REPO_ROOT / "packaging" / "installers"
    gum_cache_dir = REPO_ROOT / ".cache" / "gum"

    generated_files: list[Path] = []

    print(f"Building release artifacts for Altr Stream {tag} (Version: {version})...")
    print(f"Output directory: {output_dir}")

    # User-facing installer selection guide
    installer_readme_src = templates_dir / "INSTALLER_README.md"
    installer_readme_dest = output_dir / "README.txt"
    if installer_readme_src.exists():
        shutil.copy2(installer_readme_src, installer_readme_dest)
        generated_files.append(installer_readme_dest)
        print(f"  ✔ Created: {installer_readme_dest.name}")

    # 1. macOS Installer (Altr-Stream_macOS_Installer.command)
    macos_src = installers_dir / "Altr-Stream_macOS_Installer.command"
    macos_dest = output_dir / "Altr-Stream_macOS_Installer.command"
    if macos_src.exists():
        content = macos_src.read_text(encoding="utf-8")
        content = re.sub(r'ALTR_VERSION="[^"]+"', f'ALTR_VERSION="{version}"', content)
        macos_dest.write_text(content, encoding="utf-8")
        macos_dest.chmod(macos_dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        generated_files.append(macos_dest)
        print(f"  ✔ Created: {macos_dest.name}")

    # 2. Linux Installer (Altr-Stream_Linux_Installer.sh)
    linux_src = installers_dir / "Altr-Stream_Linux_Installer.sh"
    linux_dest = output_dir / "Altr-Stream_Linux_Installer.sh"
    if linux_src.exists():
        content = linux_src.read_text(encoding="utf-8")
        content = re.sub(r'ALTR_VERSION="[^"]+"', f'ALTR_VERSION="{version}"', content)
        linux_dest.write_text(content, encoding="utf-8")
        linux_dest.chmod(linux_dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        generated_files.append(linux_dest)
        print(f"  ✔ Created: {linux_dest.name}")

    # 3. Windows Installer (Altr-Stream_Windows_Installer.ps1)
    win_src = installers_dir / "Altr-Stream_Windows_Installer.ps1"
    win_dest = output_dir / "Altr-Stream_Windows_Installer.ps1"
    if win_src.exists():
        content = win_src.read_text(encoding="utf-8")
        content = re.sub(r'\$Version\s*=\s*"[^"]+"', f'$Version = "{version}"', content)
        win_dest.write_text(content, encoding="utf-8")
        generated_files.append(win_dest)
        print(f"  ✔ Created: {win_dest.name}")

    # 4. Bundled Setup Packages (with pinned, verified Gum binaries)
    if bundle_gum:
        try:
            # 4a. macOS Setup Bundle (Altr-Stream_macOS_Installer.command + bin/gum)
            darwin_arm_archive = ensure_gum_archive("gum_2.0.2_Darwin_arm64.tar.gz", gum_cache_dir)
            macos_staging = output_dir / "altr-stream-setup-macos"
            if macos_staging.exists():
                shutil.rmtree(macos_staging)
            (macos_staging / "bin").mkdir(parents=True)

            shutil.copy2(macos_dest, macos_staging / "Altr-Stream_macOS_Installer.command")
            if installer_readme_src.exists():
                shutil.copy2(installer_readme_src, macos_staging / "README.txt")
            with tarfile.open(darwin_arm_archive, "r:gz") as tar:
                for member in tar.getmembers():
                    if member.name.endswith("/gum"):
                        extracted_f = tar.extractfile(member)
                        if extracted_f:
                            gum_dest = macos_staging / "bin" / "gum"
                            gum_dest.write_bytes(extracted_f.read())
                            gum_dest.chmod(0o755)
                            break

            macos_bundle_zip = output_dir / "altr-stream-setup-macos.zip"
            with zipfile.ZipFile(macos_bundle_zip, "w", zipfile.ZIP_DEFLATED) as zf:
                for root, _, files in os.walk(macos_staging):
                    for file in files:
                        full_p = Path(root) / file
                        arc_name = full_p.relative_to(macos_staging)
                        zf.write(full_p, arcname=str(arc_name))
            shutil.rmtree(macos_staging)
            generated_files.append(macos_bundle_zip)
            print(f"  ✔ Created: {macos_bundle_zip.name}")

            # 4b. Linux Setup Bundle (Altr-Stream_Linux_Installer.sh + bin/gum)
            linux_archive = ensure_gum_archive("gum_2.0.2_Linux_x86_64.tar.gz", gum_cache_dir)
            linux_staging = output_dir / "altr-stream-setup-linux"
            if linux_staging.exists():
                shutil.rmtree(linux_staging)
            (linux_staging / "bin").mkdir(parents=True)

            shutil.copy2(linux_dest, linux_staging / "Altr-Stream_Linux_Installer.sh")
            if installer_readme_src.exists():
                shutil.copy2(installer_readme_src, linux_staging / "README.txt")
            with tarfile.open(linux_archive, "r:gz") as tar:
                for member in tar.getmembers():
                    if member.name.endswith("/gum"):
                        extracted_f = tar.extractfile(member)
                        if extracted_f:
                            gum_dest = linux_staging / "bin" / "gum"
                            gum_dest.write_bytes(extracted_f.read())
                            gum_dest.chmod(0o755)
                            break

            linux_bundle_tar = output_dir / "altr-stream-setup-linux.tar.gz"
            with tarfile.open(linux_bundle_tar, "w:gz") as tar:
                tar.add(linux_staging, arcname="altr-stream-setup-linux")
            shutil.rmtree(linux_staging)
            generated_files.append(linux_bundle_tar)
            print(f"  ✔ Created: {linux_bundle_tar.name}")

            # 4c. Windows Setup Bundle (Altr-Stream_Windows_Installer.ps1 + bin\gum.exe)
            win_archive = ensure_gum_archive("gum_2.0.2_Windows_x86_64.zip", gum_cache_dir)
            win_staging = output_dir / "altr-stream-setup-windows"
            if win_staging.exists():
                shutil.rmtree(win_staging)
            (win_staging / "bin").mkdir(parents=True)

            shutil.copy2(win_dest, win_staging / "Altr-Stream_Windows_Installer.ps1")
            if installer_readme_src.exists():
                shutil.copy2(installer_readme_src, win_staging / "README.txt")
            with zipfile.ZipFile(win_archive, "r") as zf:
                for name in zf.namelist():
                    if name.endswith("gum.exe"):
                        extracted_bytes = zf.read(name)
                        gum_dest = win_staging / "bin" / "gum.exe"
                        gum_dest.write_bytes(extracted_bytes)
                        break

            win_bundle_zip = output_dir / "altr-stream-setup-windows.zip"
            with zipfile.ZipFile(win_bundle_zip, "w", zipfile.ZIP_DEFLATED) as zf:
                for root, _, files in os.walk(win_staging):
                    for file in files:
                        full_p = Path(root) / file
                        arc_name = full_p.relative_to(win_staging)
                        zf.write(full_p, arcname=str(arc_name))
            shutil.rmtree(win_staging)
            generated_files.append(win_bundle_zip)
            print(f"  ✔ Created: {win_bundle_zip.name}")
        except Exception as e:
            print(f"  ⚠ Note: Gum bundling encountered an error or network limitation: {e}")
            print("     Continuing with installer scripts and manual deployment bundle...")

    # 5. Manual Deployment Bundle
    bundle_name = f"altr-stream-{tag}-deployment"
    bundle_dir = output_dir / bundle_name
    if bundle_dir.exists():
        shutil.rmtree(bundle_dir)
    bundle_dir.mkdir(parents=True)

    # Compose template
    compose_tpl = templates_dir / "docker-compose.template.yml"
    compose_dest = bundle_dir / "docker-compose.yml"
    if compose_tpl.exists():
        rendered_compose = compose_tpl.read_text(encoding="utf-8").replace("{{VERSION}}", version)
        compose_dest.write_text(rendered_compose, encoding="utf-8")
    else:
        # Fallback to base docker-compose.yml
        base_compose = (REPO_ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        compose_dest.write_text(base_compose, encoding="utf-8")

    # .env.example
    env_example = templates_dir / ".env.example"
    if env_example.exists():
        shutil.copy(env_example, bundle_dir / ".env.example")

    # README.md for manual bundle
    (bundle_dir / "README.md").write_text(generate_deployment_readme(version, tag), encoding="utf-8")

    # DEPLOYMENT.md
    if (REPO_ROOT / "DEPLOYMENT.md").exists():
        shutil.copy(REPO_ROOT / "DEPLOYMENT.md", bundle_dir / "DEPLOYMENT.md")

    # Archive as .tar.gz
    tar_path = output_dir / f"{bundle_name}.tar.gz"
    with tarfile.open(tar_path, "w:gz") as tar:
        tar.add(bundle_dir, arcname=bundle_name)
    generated_files.append(tar_path)
    print(f"  ✔ Created: {tar_path.name}")

    # Archive as .zip
    zip_path = output_dir / f"{bundle_name}.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(bundle_dir):
            for file in files:
                file_full = Path(root) / file
                rel_path = file_full.relative_to(output_dir)
                zf.write(file_full, arcname=str(rel_path))
    generated_files.append(zip_path)
    print(f"  ✔ Created: {zip_path.name}")

    # Remove temporary uncompressed bundle dir
    shutil.rmtree(bundle_dir)

    # 6. Checksums (SHA256SUMS)
    checksum_lines: list[str] = []
    for artifact in generated_files:
        sha = compute_sha256(artifact)
        checksum_lines.append(f"{sha}  {artifact.name}")

    checksum_file = output_dir / "SHA256SUMS"
    checksum_file.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")
    generated_files.append(checksum_file)
    print(f"  ✔ Created: {checksum_file.name}")

    return generated_files


def main() -> int:
    parser = argparse.ArgumentParser(description="Package Altr Stream release assets.")
    parser.add_argument(
        "--version",
        default=CANONICAL_VERSION,
        help=f"Clean application version string (default: {CANONICAL_VERSION})",
    )
    parser.add_argument(
        "--tag",
        default=None,
        help="Release tag name (default: v{version})",
    )
    parser.add_argument(
        "--output-dir",
        default="dist",
        help="Directory to place release artifacts (default: dist)",
    )
    parser.add_argument(
        "--install-gum-binary",
        default=None,
        help="Download, verify against pinned checksum, and install Gum binary to the specified path",
    )
    parser.add_argument(
        "--install-gum-archive",
        default=None,
        help="Optional archive name to extract when using --install-gum-binary (e.g. gum_2.0.2_Linux_x86_64.tar.gz)",
    )

    args = parser.parse_args()

    if args.install_gum_binary:
        target = Path(args.install_gum_binary)
        if not target.is_absolute():
            target = Path.cwd() / target
        installed = install_gum_binary(target, archive_name=args.install_gum_archive)
        print(f"Installed verified Gum binary to: {installed}")
        return 0

    version = args.version.lstrip("v")
    tag = args.tag if args.tag else f"v{version}"
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = REPO_ROOT / output_dir

    artifacts = package_release(version=version, tag=tag, output_dir=output_dir)
    print("\nPackage generation complete:")
    for a in artifacts:
        print(f"  - {a.relative_to(REPO_ROOT) if a.is_relative_to(REPO_ROOT) else a} ({a.stat().st_size:,} bytes)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
