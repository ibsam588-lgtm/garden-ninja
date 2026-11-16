"""Release routing is a user-facing guarantee: one native directory, one store."""
from fnmatch import fnmatchcase
from pathlib import Path
import re
import unittest


def trigger_paths(filename, event):
    root = Path(__file__).resolve().parents[2]
    text = (root / ".github/workflows" / filename).read_text()
    trigger = text.split(f"  {event}:\n", 1)[1].split("  workflow_dispatch:", 1)[0]
    section = re.search(r"    paths:\n((?:      - .+\n)+)", trigger)
    return [line.strip().removeprefix("- ").strip("'\"") for line in section[1].splitlines()]


class ReleasePathTests(unittest.TestCase):
    workflows = (
        ("deploy-google-play.yml", "deploy-app-store.yml", "push"),
        ("android-build.yml", "ios-build.yml", "pull_request"),
    )

    def test_platform_specific_and_shared_changes(self):
        cases = {
            "android/app/build.gradle.kts": (True, False),
            "android/app/src/main/kotlin/MainActivity.kt": (True, False),
            "fastlane/android/Fastfile": (True, False),
            "fastlane/Appfile": (True, False),
            "fastlane/metadata/android/en-US/changelogs/default.txt": (True, False),
            "android/release-trigger.txt": (True, False),
            ".github/workflows/deploy-google-play.yml": (False, False),
            ".github/workflows/android-build.yml": (False, False),
            "ios/Runner/AppDelegate.swift": (False, True),
            "ios/Podfile": (False, True),
            "fastlane/ios/Fastfile": (False, True),
            "tooling/ios_release_config.py": (False, True),
            "ios/release-trigger.txt": (False, True),
            ".github/workflows/deploy-app-store.yml": (False, False),
            ".github/workflows/ios-build.yml": (False, False),
            "third_party/unity_levelplay_mediation/android/build.gradle": (True, False),
            "third_party/unity_levelplay_mediation/ios/Classes/Plugin.m": (False, True),
            "third_party/unity_levelplay_mediation/lib/plugin.dart": (False, False),
            "third_party/unity_levelplay_mediation/pubspec.yaml": (False, False),
            "lib/src/garden/harvest_garden.dart": (False, False),
            "assets/images/splash/home.png": (False, False),
            "pubspec.yaml": (False, False),
            "pubspec.lock": (False, False),
            "fastlane/Fastfile": (False, False),
            "Gemfile": (False, False),
            "Gemfile.lock": (False, False),
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
        for android_file, ios_file, event in self.workflows:
            android = trigger_paths(android_file, event)
            ios = trigger_paths(ios_file, event)
            for path, expected in cases.items():
                with self.subTest(event=event, path=path):
                    actual = (any(fnmatchcase(path, p) for p in android),
                              any(fnmatchcase(path, p) for p in ios))
                    self.assertEqual(actual, expected)

    def test_shared_files_require_an_explicit_platform_selection(self):
        shared = ["lib/src/app.dart", "assets/images/home.png", "pubspec.lock"]
        cases = (
            (shared, (False, False)),
            (shared + ["ios/release-trigger.txt"], (False, True)),
            (shared + ["android/release-trigger.txt"], (True, False)),
            (shared + ["ios/Runner/AppDelegate.swift"], (False, True)),
            (shared + ["android/app/build.gradle.kts"], (True, False)),
            (shared + ["ios/release-trigger.txt", "android/release-trigger.txt"],
             (True, True)),
            ([".github/workflows/ios-build.yml",
              ".github/workflows/android-build.yml",
              ".github/workflows/deploy-app-store.yml",
              ".github/workflows/deploy-google-play.yml"], (False, False)),
        )
        for android_file, ios_file, event in self.workflows:
            android = trigger_paths(android_file, event)
            ios = trigger_paths(ios_file, event)
            for changed, expected in cases:
                with self.subTest(event=event, changed=changed):
                    actual = (any(fnmatchcase(path, p) for path in changed for p in android),
                              any(fnmatchcase(path, p) for path in changed for p in ios))
                    self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
