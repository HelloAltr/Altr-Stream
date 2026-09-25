#!/usr/bin/env python3
"""Host-level supervisor executable script for Altr Stream."""

import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent

# Add project root src to sys.path so it can run directly on host
src_dir = ROOT_DIR / "src"
if str(src_dir) not in sys.path:
    sys.path.insert(0, str(src_dir))

from altr_stream.supervisor.supervisor import main

if __name__ == "__main__":
    main()
