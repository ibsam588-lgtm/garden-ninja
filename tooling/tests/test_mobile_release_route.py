import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mobile_release_route import route

SHA = 'a' * 40
MERGE = 'b' * 40


def event(labels=(), merged=False, action='synchronize', branch='main'):
    return {'repository': {'default_branch': branch}, 'action': action,
            'pull_request': {'base': {'ref': branch}, 'merged': merged,
                             'merge_commit_sha': MERGE,
                             'labels': [{'name': name} for name in labels]}}


class MobileReleaseRouteTests(unittest.TestCase):
    def test_each_label_validates_and_uploads_only_its_platform(self):
        for platform in ['ios', 'android']:
            for branch in ['main', 'master']:
                pr = event([f'release:{platform}'], branch=branch)
                result = route('pull_request', pr, 'refs/pull/1/merge', SHA)
                self.assertEqual((result['platform'], result['operation'], result['revision']),
                                 (platform, 'validate', SHA))
                pr = event([f'release:{platform}'], True, 'closed', branch)
                result = route('pull_request', pr, f'refs/heads/{branch}', SHA)
                self.assertEqual((result['platform'], result['operation'], result['revision']),
                                 (platform, 'upload', MERGE))

    def test_shared_files_never_infer_two_platforms(self):
        for files in [['lib/src/app.dart'], ['assets/a.png', 'pubspec.lock'], ['ios/a', 'android/b']]:
            pr = event(['release:ios'], True, 'closed')
            pr['changed_files'] = files
            self.assertEqual(route('pull_request', pr, 'refs/heads/main', SHA)['platform'], 'ios')
        self.assertEqual(route('pull_request', event(), 'refs/pull/1/merge', SHA)['operation'], 'skip')

    def test_both_labels_fail_instead_of_building_both(self):
        with self.assertRaisesRegex(ValueError, 'exactly one'):
            route('pull_request', event(['release:ios', 'release:android'], True, 'closed'),
                  'refs/heads/main', SHA)

    def test_closed_unmerged_and_post_merge_label_changes_do_not_upload(self):
        for merged, action in [(False, 'closed'), (True, 'labeled'), (True, 'unlabeled')]:
            self.assertEqual(route('pull_request', event(['release:ios'], merged, action),
                                   'refs/heads/main', SHA)['operation'], 'skip')

    def test_manual_store_actions_require_the_default_branch_and_correct_platform(self):
        for platform, operation in [('ios', 'upload'), ('ios', 'submit_for_review'),
                                    ('android', 'upload'), ('android', 'promote_production')]:
            data = {'repository': {'default_branch': 'main'},
                    'inputs': {'platform': platform, 'operation': operation}}
            self.assertEqual(route('workflow_dispatch', data, 'refs/heads/main', SHA)['platform'], platform)
            with self.assertRaisesRegex(ValueError, 'default release branch'):
                route('workflow_dispatch', data, 'refs/heads/feature', SHA)
        with self.assertRaises(ValueError):
            route('workflow_dispatch', {'inputs': {'platform': 'ios', 'operation': 'promote_production'}},
                  'refs/heads/main', SHA)

    def test_missing_merge_commit_and_non_release_branch_are_safe(self):
        pr = event(['release:ios'], True, 'closed')
        pr['pull_request']['merge_commit_sha'] = None
        with self.assertRaisesRegex(ValueError, 'immutable'):
            route('pull_request', pr, 'refs/heads/main', SHA)
        pr['pull_request']['base']['ref'] = 'develop'
        self.assertEqual(route('pull_request', pr, 'refs/heads/develop', SHA)['operation'], 'skip')
