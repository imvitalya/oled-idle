#!/usr/bin/env python3
"""No application launch, blackout, or changes to user preferences."""
from pathlib import Path
import subprocess
import shutil
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='oled-idle-tests-') as temporary:
    shutil.copytree(root / 'oled-idle-app/Resources', temporary, dirs_exist_ok=True)
    for name, sources in [
        ('policy', ['oled-idle-app/IdlePolicy.swift', 'tests/OLEDIdlePolicyTests.swift']),
        ('preferences', ['oled-idle-app/Preferences.swift', 'oled-idle-app/Shortcut.swift', 'oled-idle-app/Localization.swift', 'tests/OLEDPreferencesTests.swift']),
        ('shortcut-language', ['oled-idle-app/Shortcut.swift', 'oled-idle-app/Localization.swift', 'tests/OLEDShortcutLanguageTests.swift']),
        ('app-model', [str(p.relative_to(root)) for p in sorted((root / 'oled-idle-app').glob('*.swift'))
                       if p.name not in ['Main.swift', 'BuildIcon.swift']] + ['tests/OLEDAppModelTests.swift']),
    ]:
        output = Path(temporary) / name
        subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                        *[str(root / item) for item in sources], '-o', str(output)], check=True)
        subprocess.run([str(output)], check=True)
