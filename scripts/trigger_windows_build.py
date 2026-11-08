#!/usr/bin/env python3
"""Trigger Windows Test Build on GitHub Actions.

Can be run directly, via VS Code / Antigravity IDE Task, or via terminal.
Triggers .github/workflows/build-windows.yml either via:
1. GitHub CLI (`gh workflow run build-windows.yml`),
2. GitHub REST API (if GITHUB_TOKEN is set), or
3. Pushing the current commit to the `test-windows` branch on GitHub.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

# Ensure stdout and stderr handle UTF-8 characters safely on Windows (cp1252 fix)
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

REPO_ROOT = Path(__file__).resolve().parent.parent
REPO_NAME = "HelloAltr/Altr-Stream"
WORKFLOW_FILE = "build-windows.yml"


def run_cmd(cmd: list[str]) -> tuple[int, str, str]:
    res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    return res.returncode, res.stdout.strip(), res.stderr.strip()


def trigger_via_gh() -> bool:
    gh_bin = shutil.which("gh")
    if not gh_bin:
        return False
    # Check auth
    code, _, _ = run_cmd([gh_bin, "auth", "status"])
    if code != 0:
        return False

    print("→ Triggering workflow via GitHub CLI (gh)...")
    code, out, err = run_cmd([gh_bin, "workflow", "run", WORKFLOW_FILE])
    if code == 0:
        print("✔ Successfully dispatched workflow via GitHub CLI!")
        print(f"  Actions URL: https://github.com/{REPO_NAME}/actions/workflows/{WORKFLOW_FILE}")
        return True
    print(f"⚠ gh workflow run failed: {err}")
    return False


def trigger_via_api() -> bool:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        return False

    print("→ Triggering workflow via GitHub REST API...")
    url = f"https://api.github.com/repos/{REPO_NAME}/actions/workflows/{WORKFLOW_FILE}/dispatches"
    req = urllib.request.Request(
        url,
        data=json.dumps({"ref": "main", "inputs": {"version": "1.1.0"}}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "Antigravity-IDE",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status in (200, 204):
                print("✔ Successfully dispatched workflow via GitHub API!")
                print(f"  Actions URL: https://github.com/{REPO_NAME}/actions/workflows/{WORKFLOW_FILE}")
                return True
    except Exception as e:
        print(f"⚠ API dispatch failed: {e}")
    return False


def trigger_via_git_push() -> bool:
    print("→ Triggering workflow via Git push to 'test-windows' branch...")
    code, current_branch, _ = run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"])
    if code != 0:
        current_branch = "main"

    # Push current HEAD to origin/test-windows
    push_cmd = ["git", "push", "origin", "HEAD:test-windows", "--force"]
    code, out, err = run_cmd(push_cmd)
    if code == 0:
        print("✔ Pushed commit to 'test-windows' branch on GitHub.")
        print("  Workflow 'Build Windows Manager (Test Artifact)' is now running!")
        print(f"  Track progress & download artifact here:\n  https://github.com/{REPO_NAME}/actions/workflows/{WORKFLOW_FILE}")
        return True
    else:
        print(f"✖ Git push failed:\n{err or out}")
        return False


def main() -> None:
    print("=" * 70)
    print(" Antigravity IDE — Trigger Windows Build Workflow")
    print("=" * 70)

    if trigger_via_gh():
        return
    if trigger_via_api():
        return
    if trigger_via_git_push():
        return

    print("\n[!] Could not automatically trigger.")
    print("    You can trigger it directly from your browser:")
    print(f"    https://github.com/{REPO_NAME}/actions/workflows/{WORKFLOW_FILE}")
    print("    Click 'Run workflow' -> select branch -> 'Run workflow'.")


if __name__ == "__main__":
    main()

