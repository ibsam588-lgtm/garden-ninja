from pathlib import Path
import re
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fix_flutter_simulator_arch import patch_sdk


class FlutterSimulatorArchTests(unittest.TestCase):
    def test_arm64e_dependency_does_not_disable_arm64_and_real_exclusions_still_do(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'packages/flutter_tools/lib/src/xcode_project.dart'
            source.parent.mkdir(parents=True)
            source.write_text("return !settings.contains(RegExp('EXCLUDED_ARCHS.*arm64'));")
            cache = root / 'bin/cache/flutter_tools.snapshot'
            cache.parent.mkdir(parents=True)
            cache.write_text('old compiled tool')
            self.assertTrue(patch_sdk(root))
            pattern = re.search(r"RegExp\(r'(.+)'\)", source.read_text())[1]
            self.assertIsNone(re.search(pattern, 'EXCLUDED_ARCHS = arm64e armv7 armv7s'))
            self.assertIsNotNone(re.search(pattern, 'EXCLUDED_ARCHS = i386 arm64'))
            self.assertFalse(cache.exists())
            cache.write_text('fixed compiled tool')
            self.assertFalse(patch_sdk(root))
            self.assertTrue(cache.exists())

    def test_unknown_sdk_is_not_modified(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / 'packages/flutter_tools/lib/src/xcode_project.dart'
            source.parent.mkdir(parents=True)
            source.write_text('different SDK implementation')
            with self.assertRaises(ValueError):
                patch_sdk(root)
            self.assertEqual(source.read_text(), 'different SDK implementation')
