"""Compare documented simulator settings without altering production metadata."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    args = parser.parse_args()
    output = Path('build/ios/destination-probes')
    output.mkdir(parents=True, exist_ok=True)
    project = Path('ios/Runner.xcodeproj/project.pbxproj')
    original_project = project.read_bytes()
    info = plistlib.loads(Path('ios/Runner/Info.plist').read_bytes())
    base = ['xcodebuild', '-showBuildSettings', '-json', '-workspace', 'ios/Runner.xcworkspace',
            '-scheme', 'Runner', '-configuration', 'Debug', '-sdk', 'iphonesimulator',
            '-destination', f'platform=iOS Simulator,id={args.device},arch=arm64',
            'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=NO', 'SUPPORTED_PLATFORMS=iphonesimulator',
            'CODE_SIGNING_ALLOWED=NO']
    results = []

    def probe(name, settings=(), omit_keys=(), without_game_center=False):
        overrides = list(settings)
        if omit_keys:
            candidate = dict(info)
            for key in omit_keys:
                candidate.pop(key, None)
            path = Path(os.environ['RUNNER_TEMP']) / f'ios-{name}.plist'
            path.write_bytes(plistlib.dumps(candidate))
            overrides.append(f'INFOPLIST_FILE={path}')
        try:
            if without_game_center:
                text = original_project.decode()
                old = 'com.apple.GameCenter = { enabled = 1; };'
                if text.count(old) != 1:
                    raise ValueError('Unexpected capability layout; refusing an ambiguous probe')
                project.write_text(text.replace(old, 'com.apple.GameCenter = { enabled = 0; };'))
            process = subprocess.run(base + overrides, capture_output=True, text=True, timeout=90)
            (output / f'{name}.log').write_text(process.stderr, encoding='utf-8')
            results.append({'probe': name, 'success': process.returncode == 0,
                            'exit_code': process.returncode})
            print(json.dumps(results[-1]), flush=True)
        finally:
            project.write_bytes(original_project)

    probe('baseline')
    if results[0]['success']:
        return
    probe('explicit-sdk-root', ['SDKROOT=iphonesimulator'])
    probe('debug-minimum-17', ['IPHONEOS_DEPLOYMENT_TARGET=17.0'])
    probe('without-phone-requirement', omit_keys=('LSRequiresIPhoneOS',))
    probe('without-full-screen', omit_keys=('UIRequiresFullScreen',))
    probe('generated-info', ['GENERATE_INFOPLIST_FILE=YES', 'INFOPLIST_FILE='])
    probe('without-signing-metadata', ['CODE_SIGN_ENTITLEMENTS=', 'DEVELOPMENT_TEAM=', 'CODE_SIGN_STYLE=Manual'])
    probe('without-game-center-capability', ['CODE_SIGN_ENTITLEMENTS='], without_game_center=True)
    (output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
    raise SystemExit('Baseline simulator destination is unavailable; diagnostic variants never bypass validation')


if __name__ == '__main__':
    main()
