#!/usr/bin/env python3
"""Real macOS integration checks. --blackout briefly covers screens (auto-dismisses)."""
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='oled-idle-system-') as temporary:
    shutil.copytree(root / 'oled-idle-app/Resources', temporary, dirs_exist_ok=True)
    output = Path(temporary) / 'system-tests'
    sources = sorted(p for p in (root / 'oled-idle-app').glob('*.swift') if p.name not in ['Main.swift', 'BuildIcon.swift'])
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    *map(str, sources), str(root / 'tests/OLEDSystemTests.swift'), '-o', str(output)], check=True)
    subprocess.run([str(output), *sys.argv[1:]], check=True, timeout=20)
