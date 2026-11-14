import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from ios_release_config import release_config


class AppleReleaseConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.env = {
            "APP_STORE_ID": "1234567890",
            "APPLE_TEAM_ID": "ABCDEFGHIJ",
            "APP_STORE_CONNECT_ISSUER_ID": "11111111-2222-3333-4444-555555555555",
            "APP_STORE_CONNECT_KEY_IDENTIFIER": "123456ABCD",
            "APP_STORE_CONNECT_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nFAKE_API_KEY_FOR_TEST\n-----END PRIVATE KEY-----",
            "CERTIFICATE_PRIVATE_KEY": "-----BEGIN RSA PRIVATE KEY-----\nFAKE_CERT_KEY_FOR_TEST\n-----END RSA PRIVATE KEY-----",
        }
        self.pubspec = "name: garden_ninja\nversion: 1.1.7+10050\n"

    def config(self, mode="upload"):
        return release_config(self.env, self.pubspec, mode)

    def test_release_files_never_contain_private_keys(self):
        result = self.config()
        text = json.dumps(result)
        self.assertNotIn("FAKE_API_KEY", text)
        self.assertNotIn("FAKE_CERT_KEY", text)
        self.assertEqual(result["version"], "1.1.7")

    def test_apple_identity_matches_game_and_release_workflow(self):
        root = Path(__file__).resolve().parents[2]
        bundle = self.config()["bundle_id"]
        self.assertEqual(bundle, "com.corsairlabs.gardenNinja")
        project = (root / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {bundle};"), 3)
        workflow = (root / ".github/workflows/deploy-app-store.yml").read_text()
        self.assertIn(f"IOS_BUNDLE_ID: {bundle}", workflow)

    def test_missing_settings_fail_without_exposing_present_secrets(self):
        del self.env["APP_STORE_ID"]
        with self.assertRaises(ValueError) as error:
            self.config()
        self.assertIn("APP_STORE_ID", str(error.exception))
        self.assertNotIn("FAKE_API_KEY", str(error.exception))

    def test_upload_requires_signing_key_but_review_does_not(self):
        del self.env["CERTIFICATE_PRIVATE_KEY"]
        with self.assertRaisesRegex(ValueError, "CERTIFICATE_PRIVATE_KEY"):
            self.config()
        self.env.update(REQUESTED_IOS_VERSION="1.1.7", REQUESTED_IOS_BUILD="3")
        self.assertEqual(self.config("submit")["build_number"], "3")

    def test_review_cannot_accidentally_choose_latest_build(self):
        with self.assertRaisesRegex(ValueError, "exact tested"):
            self.config("submit")
        self.env["REQUESTED_IOS_VERSION"] = "1.1.7"
        with self.assertRaisesRegex(ValueError, "exact tested"):
            self.config("submit")

    def test_untrusted_workflow_inputs_are_rejected(self):
        for value in ("1.1.7; echo secret", "$(env)", "1.2\n3.4.5"):
            with self.subTest(value=value):
                self.env["REQUESTED_IOS_VERSION"] = value
                with self.assertRaises(ValueError):
                    self.config()
        self.env.update(REQUESTED_IOS_VERSION="1.1.7", REQUESTED_IOS_BUILD="1; whoami")
        with self.assertRaises(ValueError):
            self.config("submit")

    def test_android_ad_settings_never_enable_ios_ads(self):
        self.env.update(LEVELPLAY_APP_KEY="android-app", LEVELPLAY_TEST_SUITE="true")
        config = self.config()
        self.assertFalse(config["ads_enabled"])
        self.assertNotIn("LEVELPLAY_APP_KEY", config["dart_defines"])
        self.assertEqual(config["dart_defines"]["LEVELPLAY_TEST_SUITE"], "false")

    def test_partial_or_reused_ad_units_block_the_release(self):
        self.env["LEVELPLAY_IOS_APP_KEY"] = "ios-app"
        with self.assertRaisesRegex(ValueError, "all four"):
            self.config()
        for name in ("BANNER", "INTERSTITIAL", "REWARDED"):
            self.env[f"LEVELPLAY_IOS_{name}_AD_UNIT_ID"] = "same-id"
        with self.assertRaisesRegex(ValueError, "distinct"):
            self.config()
        for name in ("BANNER", "INTERSTITIAL", "REWARDED"):
            self.env[f"LEVELPLAY_IOS_{name}_AD_UNIT_ID"] = "ios-" + name.lower()
        self.assertTrue(self.config()["ads_enabled"])


if __name__ == "__main__":
    unittest.main()
