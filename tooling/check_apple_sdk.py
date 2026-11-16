"""Fail early if an Apple build falls below SDK 27 or deployment target iOS 15."""
import argparse
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]


def version(value):
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', value):
        raise ValueError('A numeric Apple version is required')
    return tuple(map(int, value.split('.')))


def validate(sdk, project, framework, app=None):
    if version(sdk) < (27,):
        raise ValueError('Apple builds require the iOS 27 SDK or newer')
    targets = re.findall(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);', project)
    if not targets or any(version(t) < (15,) for t in targets):
        raise ValueError('Every app deployment configuration must target iOS 15 or newer')
    if version(framework['MinimumOSVersion']) < (15,):
        raise ValueError('Flutter app framework must target iOS 15 or newer')
    if app is not None:
        if version(app['MinimumOSVersion']) < (15,):
            raise ValueError('The archived app targets an unsupported iOS version')
        if version(app['DTPlatformVersion']) < (27,):
            raise ValueError('The archived app was not built with SDK 27 or newer')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-version', required=True)
    parser.add_argument('--app-plist', type=Path)
    args = parser.parse_args()
    framework = plistlib.loads((ROOT / 'ios/Flutter/AppFrameworkInfo.plist').read_bytes())
    app = plistlib.loads(args.app_plist.read_bytes()) if args.app_plist else None
    validate(args.sdk_version, (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text(), framework, app)
    print(f'Apple SDK {args.sdk_version}: deployment targets and archive meet the SDK 27 / iOS 15 minimums.')


if __name__ == '__main__':
    main()
