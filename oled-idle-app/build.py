#!/usr/bin/env python3
"""Build the native app, run its policy checks, and optionally install it."""
import argparse
import datetime
import hashlib
import pathlib
import platform
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parent
BUNDLE_ID = 'local.oled-idle'
VERSION = '2.1.0'


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def replace_own_bundle(source, destination, backup_root=None):
    if destination.exists():
        info = destination / 'Contents/Info.plist'
        if not info.is_file() or plistlib.loads(info.read_bytes()).get('CFBundleIdentifier') != BUNDLE_ID:
            raise RuntimeError(f'Refusing to replace an unrelated app: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    staged = destination.parent / f'.oled-idle-new-{uuid.uuid4().hex}.app'
    previous = destination.parent / f'.oled-idle-old-{uuid.uuid4().hex}.app'
    try:
        shutil.copytree(source, staged, symlinks=True)
        if destination.exists():
            if backup_root:
                backup_root.mkdir(parents=True, exist_ok=True)
                stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
                backup = backup_root / f'OLED Idle-{stamp}-{uuid.uuid4().hex[:6]}.app'
                shutil.copytree(destination, backup, symlinks=True)
                print(f'Previous app backed up: {backup}')
            destination.rename(previous)
        try:
            staged.rename(destination)
        except BaseException:
            if previous.exists():
                previous.rename(destination)
            raise
        if previous.exists():
            shutil.rmtree(previous)
    finally:
        if staged.exists():
            shutil.rmtree(staged)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--universal', action='store_true', help='Build for Apple Silicon and Intel')
    parser.add_argument('--archive', action='store_true', help='Create a ZIP and SHA256SUMS in dist')
    options = parser.parse_args()
    if options.install and subprocess.run(['/usr/bin/pgrep', '-x', 'OLEDIdle'], stdout=subprocess.DEVNULL).returncode == 0:
        raise RuntimeError('Quit OLED Idle from its menu before replacing the installed application.')
    sdk = subprocess.check_output(['/usr/bin/xcrun', '--show-sdk-path'], text=True).strip()
    target = f'{platform.machine()}-apple-macos13.0'
    flags = ['-swift-version', '5', '-target', target, '-sdk', sdk]
    with tempfile.TemporaryDirectory(prefix='oled-idle-build-') as temporary:
        work = pathlib.Path(temporary)
        run('/usr/bin/python3', ROOT.parent / 'tests/run-native-tests.py')
        app = work / 'OLED Idle.app'
        contents = app / 'Contents'
        resources = contents / 'Resources'
        binary = contents / 'MacOS/OLEDIdle'
        resources.mkdir(parents=True)
        binary.parent.mkdir()
        architectures = ['arm64', 'x86_64'] if options.universal else [platform.machine()]
        slices = []
        for architecture in architectures:
            arch_binary = work / f'OLEDIdle-{architecture}'
            run('/usr/bin/xcrun', 'swiftc', '-O', '-parse-as-library', '-swift-version', '5',
                '-target', f'{architecture}-apple-macos13.0', '-sdk', sdk,
                '-framework', 'AppKit', '-framework', 'IOKit', '-framework', 'Carbon', '-framework', 'ServiceManagement',
                *sorted(path for path in ROOT.glob('*.swift') if path.name != 'BuildIcon.swift'), '-o', arch_binary)
            slices.append(arch_binary)
        if len(slices) > 1:
            run('/usr/bin/lipo', '-create', *slices, '-output', binary)
        else:
            shutil.copy2(slices[0], binary)
        shutil.copytree(ROOT / 'Resources', resources, dirs_exist_ok=True)
        info = {
            'CFBundleName': 'OLED Idle', 'CFBundleDisplayName': 'OLED Idle',
            'CFBundleIdentifier': BUNDLE_ID, 'CFBundleExecutable': 'OLEDIdle',
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '3',
            'CFBundleShortVersionString': VERSION, 'CFBundleIconFile': 'AppIcon',
            'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'ru'],
            'LSMinimumSystemVersion': '13.0', 'LSUIElement': True,
            'LSMultipleInstancesProhibited': True, 'NSHighResolutionCapable': True,
            'NSAppleEventsUsageDescription': 'In Caffeine mode, OLED Idle checks whether Caffeine is active. Standalone mode does not need this permission.',
        }
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        iconset = work / 'AppIcon.iconset'
        run('/usr/bin/xcrun', 'swift', *flags, ROOT / 'BuildIcon.swift', iconset)
        run('/usr/bin/iconutil', '-c', 'icns', iconset, '-o', resources / 'AppIcon.icns')
        entitlements = work / 'entitlements.plist'
        entitlements.write_bytes(plistlib.dumps({'com.apple.security.automation.apple-events': True}))
        run('/usr/bin/codesign', '--force', '--sign', '-', '--entitlements', entitlements, app)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
        output = ROOT / 'dist/OLED Idle.app'
        output.parent.mkdir(exist_ok=True)
        replace_own_bundle(app, output)
        shutil.copyfile(iconset / 'icon_512x512@2x.png', output.parent / 'AppIcon.png')
        if options.archive:
            architecture = 'universal' if options.universal else platform.machine()
            archive = output.parent / f'OLED-Idle-{VERSION}-{architecture}.zip'
            if archive.exists():
                archive.unlink()
            run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', output, archive)
            checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
            (output.parent / 'SHA256SUMS').write_text(f'{checksum}  {archive.name}\n')
            print(f'Archive: {archive}')
        if options.install:
            destination = pathlib.Path('/Applications/OLED Idle.app')
            backups = pathlib.Path.home() / 'Library/Application Support/OLED Idle/Backups'
            replace_own_bundle(app, destination, backups)
            run('/usr/bin/codesign', '--verify', '--deep', '--strict', destination)
            print(f'Installed: {destination}')
        print(f'Built: {output}')


if __name__ == '__main__':
    main()
