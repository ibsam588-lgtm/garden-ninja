"""Backport Flutter's upstream arm64e false-positive fix to the pinned SDK.

https://github.com/flutter/flutter/pull/184057
IronSourceAdQuality excludes arm64e, not arm64. Flutter 3.44.2's substring
check incorrectly turns that into an Intel-only simulator app. Keep real arm64
exclusions effective. Run only against an explicitly selected Flutter SDK.
"""
import argparse
from pathlib import Path

OLD = "RegExp('EXCLUDED_ARCHS.*arm64')"
FIXED = r"RegExp(r'EXCLUDED_ARCHS.*\barm64\b')"


def patch_sdk(root):
    source = root / 'packages/flutter_tools/lib/src/xcode_project.dart'
    text = source.read_text(encoding='utf-8')
    if OLD not in text:
        if FIXED in text:
            return False
        raise ValueError('Unknown Flutter architecture check; inspect before patching')
    if text.count(OLD) != 1:
        raise ValueError('Unexpected Flutter SDK layout; refusing an ambiguous patch')
    source.write_text(text.replace(OLD, FIXED), encoding='utf-8')
    # Flutter otherwise executes the previously compiled tool snapshot.
    for name in ('flutter_tools.snapshot', 'flutter_tools.stamp'):
        (root / 'bin/cache' / name).unlink(missing_ok=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-root', type=Path, required=True)
    args = parser.parse_args()
    changed = patch_sdk(args.flutter_root.resolve())
    print('Applied upstream Flutter arm64e detection fix' if changed else
          'Flutter already distinguishes arm64 from arm64e')


if __name__ == '__main__':
    main()
