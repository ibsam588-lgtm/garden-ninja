"""Keep one automatic release entry and prohibit runner-created store media."""
from pathlib import Path
import re
import unittest

WORKFLOWS = Path(__file__).resolve().parents[2] / '.github/workflows'


class ReleaseWorkflowTests(unittest.TestCase):
    def test_only_mobile_release_handles_pr_events(self):
        automatic = []
        for path in WORKFLOWS.glob('*.yml'):
            text = path.read_text()
            if re.search(r'(?m)^  (pull_request|push|workflow_run):', text):
                automatic.append(path.name)
        self.assertEqual(automatic, ['mobile-release.yml'])
        parent = (WORKFLOWS / 'mobile-release.yml').read_text()
        self.assertIn('branches: [main, master]', parent)
        self.assertIn('unlabeled, closed]', parent)
        self.assertNotIn('    paths:', parent)

    def test_platform_workers_are_called_with_exact_revision(self):
        parent = (WORKFLOWS / 'mobile-release.yml').read_text()
        for worker in ('ios-build.yml', 'android-build.yml',
                       'deploy-app-store.yml', 'deploy-google-play.yml'):
            self.assertIn(f'uses: ./.github/workflows/{worker}', parent)
            text = (WORKFLOWS / worker).read_text()
            self.assertIn('  workflow_call:', text)
            self.assertIn('ref: ${{ inputs.checkout_ref }}', text)
            self.assertNotRegex(text, r'(?m)^  (workflow_dispatch|pull_request|push):')
        for helper in ('ios-build.yml', 'android-build.yml'):
            text = (WORKFLOWS / helper).read_text()
            for command in ('flutter analyze', 'flutter test', 'python -m unittest discover'):
                self.assertIn(command, text)

    def test_store_media_is_never_captured_on_github_runners(self):
        for path in WORKFLOWS.glob('*.yml'):
            text = path.read_text()
            with self.subTest(workflow=path.name):
                self.assertNotIn('CAPTURE_APPLE_STORE=true', text)
                self.assertNotRegex(text, r'simctl\s+io\b.*\b(screenshot|recordVideo)\b')
        self.assertFalse((WORKFLOWS / 'capture-apple-media.yml').exists())

    def test_testflight_followup_is_inside_the_upload_run(self):
        parent = (WORKFLOWS / 'deploy-app-store.yml').read_text()
        helper = (WORKFLOWS / 'testflight-distribution.yml').read_text()
        self.assertIn('needs: upload-testflight', parent)
        self.assertIn('uses: ./.github/workflows/testflight-distribution.yml', parent)
        self.assertIn('  workflow_call:', helper)
        self.assertNotIn('  workflow_run:', helper)
        self.assertIn('  schedule:', helper)


if __name__ == '__main__':
    unittest.main()
