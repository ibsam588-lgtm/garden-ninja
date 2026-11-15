"""Release routing is a user-facing guarantee: one native directory, one store."""
from fnmatch import fnmatchcase
from pathlib import Path
import re
import unittest


def push_paths(filename):
    root = Path(__file__).resolve().parents[2]
    text = (root / ".github/workflows" / filename).read_text()
    push = text.split("  push:\n", 1)[1].split("  workflow_dispatch:", 1)[0]
    section = re.search(r"    paths:\n((?:      - .+\n)+)", push)
    return [line.strip().removeprefix("- ").strip("'\"") for line in section[1].splitlines()]


class ReleasePathTests(unittest.TestCase):
    def test_platform_specific_and_shared_changes(self):
        android = push_paths("deploy-google-play.yml")
        ios = push_paths("deploy-app-store.yml")
        cases = {
            "android/app/build.gradle.kts": (True, False),
            "android/app/src/main/kotlin/MainActivity.kt": (True, False),
            "fastlane/android/Fastfile": (True, False),
            "fastlane/Appfile": (True, False),
            "fastlane/metadata/android/en-US/changelogs/default.txt": (True, False),
            ".github/workflows/deploy-google-play.yml": (True, False),
            "ios/Runner/AppDelegate.swift": (False, True),
            "ios/Podfile": (False, True),
            "fastlane/ios/Fastfile": (False, True),
            "tooling/ios_release_config.py": (False, True),
            ".github/workflows/deploy-app-store.yml": (False, True),
            "third_party/unity_levelplay_mediation/android/build.gradle": (True, False),
            "third_party/unity_levelplay_mediation/ios/Classes/Plugin.m": (False, True),
            "third_party/unity_levelplay_mediation/lib/plugin.dart": (True, True),
            "third_party/unity_levelplay_mediation/pubspec.yaml": (True, True),
            "lib/src/garden/harvest_garden.dart": (True, True),
            "assets/images/splash/home.png": (True, True),
            "pubspec.yaml": (True, True),
            "pubspec.lock": (True, True),
            "fastlane/Fastfile": (True, True),
            "Gemfile": (True, True),
            "Gemfile.lock": (True, True),
            "README.md": (False, False),
            "docs/ios-release.md": (False, False),
            "test/widget_test.dart": (False, False),
            "tooling/testflight_sync.py": (False, False),
            "tooling/apple_api.py": (False, False),
            ".github/workflows/testflight-distribution.yml": (False, False),
            "store-assets/apple/en-US/APP_IPHONE_67/01-home.jpg": (False, False),
            "fastlane/metadata/android/en-US/images/phoneScreenshots/01.png": (False, False),
            "public/app-version.json": (False, False),
        }
        for path, expected in cases.items():
            with self.subTest(path=path):
                actual = (any(fnmatchcase(path, p) for p in android),
                          any(fnmatchcase(path, p) for p in ios))
                self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
