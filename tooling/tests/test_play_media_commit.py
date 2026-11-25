import sys
import unittest
from pathlib import Path
from unittest.mock import call, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from upload_play_media import commit_media


class PlayMediaCommitTests(unittest.TestCase):
    auto = {"changesInReviewBehavior": "ERROR_IF_IN_REVIEW"}
    draft = {**auto, "changesNotSentForReview": "true"}
    validate = call(None, "POST", "/edit/1:validate")

    def test_draft_is_used_on_the_first_and_only_commit(self):
        with patch("upload_play_media.request", return_value={"id": "1"}) as send:
            self.assertEqual(commit_media(None, "/edit/1", True), ("1", True))
        self.assertEqual(send.call_args_list, [self.validate, call(None, "POST", "/edit/1:commit", params=self.draft)])

    def test_auto_commits_for_review(self):
        with patch("upload_play_media.request", return_value={"id": "1"}) as send:
            self.assertEqual(commit_media(None, "/edit/1", False), ("1", False))
        self.assertEqual(send.call_args_list, [self.validate, call(None, "POST", "/edit/1:commit", params=self.auto)])

    def test_auto_reports_draft_if_play_requires_manual_submission(self):
        manual = RuntimeError("Changes cannot be sent for review automatically.")
        with patch("upload_play_media.request", side_effect=[{}, manual, {"id": "1"}]) as send:
            self.assertEqual(commit_media(None, "/edit/1", False), ("1", True))
        self.assertEqual(send.call_args_list, [
            self.validate,
            call(None, "POST", "/edit/1:commit", params=self.auto),
            call(None, "POST", "/edit/1:commit", params=self.draft),
        ])

    def test_manual_submission_requirement_at_validation_goes_directly_to_draft_commit(self):
        manual = RuntimeError("Changes cannot be sent for review automatically. Please set the query parameter "
                              "changesNotSentForReview to true. Once committed, the changes in this edit "
                              "can be sent for review from the Google Play Console UI.")
        for draft in (True, False):
            with self.subTest(draft=draft), patch("upload_play_media.request",
                                                  side_effect=[manual, {"id": "1"}]) as send:
                self.assertEqual(commit_media(None, "/edit/1", draft), ("1", True))
                self.assertEqual(send.call_args_list, [
                    self.validate, call(None, "POST", "/edit/1:commit", params=self.draft),
                ])

    def test_unrelated_validation_error_prevents_commit(self):
        for draft in (True, False):
            with self.subTest(draft=draft), patch("upload_play_media.request",
                                                  side_effect=RuntimeError("already in review")) as send:
                with self.assertRaisesRegex(RuntimeError, "already in review"):
                    commit_media(None, "/edit/1", draft)
                self.assertEqual(send.call_args_list, [self.validate])

    def test_both_modes_propagate_a_review_conflict_at_commit(self):
        for draft in (True, False):
            with self.subTest(draft=draft), patch("upload_play_media.request",
                                                  side_effect=[{}, RuntimeError("already in review")]) as send:
                with self.assertRaisesRegex(RuntimeError, "already in review"):
                    commit_media(None, "/edit/1", draft)
                self.assertEqual(send.call_args_list, [
                    self.validate, call(None, "POST", "/edit/1:commit", params=self.draft if draft else self.auto),
                ])
