"""Pinned toolchain configuration for the Fleury Pad experiment."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
BUILD = ROOT / '.build'
SDK_VERSION = '3.12.2'


def dart_sdk():
    configured = os.environ.get('DART_SDK')
    if configured:
        sdk = Path(configured).expanduser().resolve()
    else:
        executable = shutil.which('dart')
        if not executable:
            raise SystemExit('Set DART_SDK to a Dart 3.12.2 SDK directory.')
        sdk = Path(executable).resolve().parent.parent
        if (sdk / 'bin/cache/dart-sdk').is_dir():
            sdk = sdk / 'bin/cache/dart-sdk'
    result = subprocess.run([str(sdk / 'bin/dart'), '--version'], capture_output=True, text=True, check=True)
    if f'Dart SDK version: {SDK_VERSION} ' not in result.stdout + result.stderr:
        raise SystemExit(f'This proof is pinned to Dart {SDK_VERSION}; set DART_SDK to that SDK.')
    return sdk
