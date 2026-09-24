#!/usr/bin/env python3
"""Host-level supervisor executable script for Altr Stream."""

import sys
from pathlib import Path

# Add project root src to sys.path so it can run directly on host
src_dir = Path(__file__).resolve().parent.parent / "src"
if str(src_dir) not in sys.path:
    sys.path.insert(0, str(src_dir))

from altr_stream.supervisor.supervisor import main

if __name__ == "__main__":
    main()
