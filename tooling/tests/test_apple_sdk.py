import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_apple_sdk import validate


class AppleSDKTests(unittest.TestCase):
    def test_sdk_and_every_deployment_configuration_are_enforced(self):
        project = 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;\n' * 3
        validate('27.2', project, {'MinimumOSVersion': '15.0'})
        with self.assertRaisesRegex(ValueError, 'SDK'):
            validate('26.3', project, {'MinimumOSVersion': '15.0'})
        with self.assertRaisesRegex(ValueError, 'Every app'):
            validate('27.2', project + 'IPHONEOS_DEPLOYMENT_TARGET = 13.0;', {'MinimumOSVersion': '15.0'})
        with self.assertRaisesRegex(ValueError, 'framework'):
            validate('27.2', project, {'MinimumOSVersion': '13.0'})

    def test_archive_metadata_must_match_the_required_sdk_and_target(self):
        project = 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;'
        validate('27.2', project, {'MinimumOSVersion': '15.0'},
                 {'MinimumOSVersion': '15.0', 'DTPlatformVersion': '27.2'})
        for app in [{'MinimumOSVersion': '15.0', 'DTPlatformVersion': '26.3'},
                    {'MinimumOSVersion': '13.0', 'DTPlatformVersion': '27.2'}]:
            with self.assertRaises(ValueError):
                validate('27.2', project, {'MinimumOSVersion': '15.0'}, app)
