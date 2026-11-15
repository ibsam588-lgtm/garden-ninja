import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from upload_apple_media import verify


class FakeAppleAsset:
    def __init__(self, state, checksum="expected"):
        self.state = state
        self.checksum = checksum

    def request(self, method, path):
        assert method == "GET"
        return {"data": {"attributes": {
            "sourceFileChecksum": self.checksum,
            "assetDeliveryState": {"state": self.state, "errors": ["Invalid dimensions"]},
        }}}


class AppleMediaVerificationTests(unittest.TestCase):
    def asset(self):
        return {"kind": "appScreenshots", "id": "image", "file": "game.jpg", "md5": "expected"}

    def test_success_requires_apple_processing_and_matching_bytes(self):
        asset = self.asset()
        self.assertEqual(verify(FakeAppleAsset("COMPLETE"), [asset]), [])
        self.assertEqual(asset["state"], "COMPLETE")

    def test_uploaded_video_is_not_reported_as_processed(self):
        asset = self.asset()
        self.assertEqual(verify(FakeAppleAsset("UPLOAD_COMPLETE"), [asset]), [asset])

    def test_wrong_remote_checksum_fails_verification(self):
        with self.assertRaisesRegex(RuntimeError, "checksum"):
            verify(FakeAppleAsset("COMPLETE", checksum="different"), [self.asset()])

    def test_apple_rejected_asset_fails_with_actionable_reason(self):
        with self.assertRaisesRegex(RuntimeError, "Invalid dimensions"):
            verify(FakeAppleAsset("FAILED"), [self.asset()])


if __name__ == "__main__":
    unittest.main()
