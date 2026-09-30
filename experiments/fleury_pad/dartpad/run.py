"""Run the adapted DartPad service with its process watchdog."""
import os
from pathlib import Path
import subprocess
import sys
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from config import dart_sdk
if not (HERE / '.dart_tool/package_config.json').exists():
    raise SystemExit('Run dartpad/setup.py first.')
os.chdir(HERE)
os.environ['DART_SDK'] = str(dart_sdk())
os.execv(sys.executable, [sys.executable, str(HERE / 'supervise.py')])
