import sys
from pathlib import Path
import plistlib
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_apple_sdk import main, validate


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

    def test_built_framework_is_checked_after_flutter_migrates_the_template(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / 'ios/Runner.xcodeproj/project.pbxproj'
            project.parent.mkdir(parents=True)
            project.write_text('IPHONEOS_DEPLOYMENT_TARGET = 15.0;')
            template = root / 'ios/Flutter/AppFrameworkInfo.plist'
            template.parent.mkdir(parents=True)
            template.write_bytes(plistlib.dumps({}))
            app = root / 'Runner.app/Info.plist'
            framework = app.parent / 'Frameworks/App.framework/Info.plist'
            framework.parent.mkdir(parents=True)
            app.write_bytes(plistlib.dumps({'MinimumOSVersion': '15.0', 'DTPlatformVersion': '27.1'}))
            framework.write_bytes(plistlib.dumps({'MinimumOSVersion': '15.0'}))
            with patch('check_apple_sdk.ROOT', root), patch.object(sys, 'argv', [
                    'check_apple_sdk.py', '--sdk-version', '27.1', '--app-plist', str(app)]):
                main()
                framework.write_bytes(plistlib.dumps({'MinimumOSVersion': '13.0'}))
                with self.assertRaisesRegex(ValueError, 'framework'):
                    main()
