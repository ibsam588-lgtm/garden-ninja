"""Record a native simulator integration-test session, without capturing boot screens."""

import argparse
from pathlib import Path
import signal
import subprocess
import time

BUNDLE_ID = 'com.corsairlabs.gardenNinja'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 600
    data = None
    while time.monotonic() < deadline:
        result = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.device, BUNDLE_ID, 'data'], capture_output=True, text=True)
        if result.returncode == 0:
            data = Path(result.stdout.strip()) / 'tmp'
            if (data / 'garden_ninja_preview_ready').exists():
                break
        time.sleep(1)
    else:
        raise RuntimeError('The native game never signaled that its preview was ready')
    recorder = subprocess.Popen(['xcrun', 'simctl', 'io', args.device, 'recordVideo', '--codec=h264', str(args.output)])
    try:
        deadline = time.monotonic() + 100
        while time.monotonic() < deadline:
            if (data / 'garden_ninja_preview_done').exists():
                break
            if recorder.poll() is not None:
                raise RuntimeError('The simulator recorder exited before gameplay completed')
            time.sleep(.25)
        else:
            raise RuntimeError('The native gameplay session did not finish')
    finally:
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
            recorder.wait(timeout=120)
    if not args.output.exists() or args.output.stat().st_size < 100_000:
        raise RuntimeError('The simulator did not produce a usable recording')


if __name__ == '__main__':
    main()
