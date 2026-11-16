import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from testflight_sync import sync
from apple_api import AppleError


class FakeApple:
    def __init__(self, states, attached=None, tester_state="NOT_INVITED"):
        self.states = states
        self.attached = set(states) if attached is None else set(attached)
        self.tester_state = tester_state
        self.mutations = []

    def request(self, method, path, payload=None):
        if method != "GET":
            self.mutations.append((method, path, payload))
            return {}
        if path == "/v1/apps/app":
            return {"data": {"attributes": {"bundleId": "com.corsairlabs.gardenNinja"}}}
        bid = path.split("/")[3]
        return {"data": {"id": bid, "attributes": {
            "externalBuildState": self.states[bid], "autoNotifyEnabled": True}}}

    def all(self, path):
        if "/apps/app/betaGroups" in path:
            return [{"id": "group", "attributes": {"isInternalGroup": False}}]
        if "/apps/app/builds" in path:
            # The API's response order is intentionally oldest-first.
            return [{"id": b, "attributes": {"version": b, "expired": False,
                     "processingState": "VALID", "uploadedDate": f"2026-11-{int(b):02}T00:00:00Z"}}
                    for b in self.states]
        if "/betaTesters" in path:
            return [{"id": "tester", "attributes": {"email": "approved@example.com", "state": self.tester_state}},
                    {"id": "other", "attributes": {"email": "someoneelse@example.com", "state": "NOT_INVITED"}}]
        return [{"id": b} for b in self.attached]


class TestFlightSyncTests(unittest.TestCase):
    def run_sync(self, api, **kwargs):
        sync(api, "app", "group", {"approved@example.com"}, emit=lambda _: None, **kwargs)

    def test_preserves_pending_older_build_and_does_not_invite(self):
        api = FakeApple({"1": "WAITING_FOR_BETA_REVIEW", "3": "READY_FOR_BETA_SUBMISSION"})
        self.run_sync(api)
        self.assertEqual(api.mutations, [])

    def test_submits_latest_by_upload_date_after_queue_is_free(self):
        api = FakeApple({"1": "IN_BETA_TESTING", "3": "READY_FOR_BETA_SUBMISSION"}, attached={"1"})
        self.run_sync(api)
        self.assertEqual(api.mutations[0][1], "/v1/builds/3/relationships/betaGroups")
        submission = api.mutations[1]
        self.assertEqual(submission[1], "/v1/betaAppReviewSubmissions")
        self.assertEqual(submission[2]["data"]["relationships"]["build"]["data"]["id"], "3")
        self.assertEqual(api.mutations[2][1], "/v1/betaTesterInvitations")
        self.assertEqual(api.mutations[2][2]["data"]["relationships"]["betaTester"]["data"]["id"], "tester")

    def test_only_invites_when_an_attached_build_is_approved(self):
        api = FakeApple({"1": "IN_BETA_TESTING", "3": "IN_BETA_REVIEW"}, attached={"3"})
        self.run_sync(api)
        self.assertEqual(api.mutations, [])

    def test_already_invited_tester_does_not_get_duplicate_email(self):
        for state in ["INVITED", "ACCEPTED", "INSTALLED"]:
            api = FakeApple({"3": "IN_BETA_TESTING"}, tester_state=state)
            self.run_sync(api)
            self.assertEqual(api.mutations, [])

    def test_dry_run_has_no_external_mutations(self):
        api = FakeApple({"3": "READY_FOR_BETA_SUBMISSION"}, attached=set())
        self.run_sync(api, apply=False)
        self.assertEqual(api.mutations, [])

    def test_wrong_external_group_fails_before_any_changes(self):
        api = FakeApple({"3": "IN_BETA_TESTING"})
        with self.assertRaisesRegex(ValueError, "belong to Garden Ninja"):
            sync(api, "app", "wrong-group", set(), emit=lambda _: None)
        self.assertEqual(api.mutations, [])

    def test_transient_review_response_defers_without_inviting_or_claiming_submission(self):
        class DeferredApple(FakeApple):
            def request(self, method, path, payload=None):
                if method == "POST" and path == "/v1/betaAppReviewSubmissions":
                    raise AppleError(422, "Please try again later.")
                return super().request(method, path, payload)

        api = DeferredApple({"3": "READY_FOR_BETA_SUBMISSION"})
        messages = []
        sync(api, "app", "group", {"approved@example.com"}, emit=messages.append)
        self.assertTrue(any("Submission is not confirmed" in m for m in messages))
        self.assertFalse(any("Submitted the processed build" in m for m in messages))
        self.assertEqual(api.mutations, [])

    def test_other_review_errors_are_not_treated_as_temporary_deferrals(self):
        for status, detail in ((422, "Missing review contact"), (403, "Not authorized")):
            class RejectedApple(FakeApple):
                def request(self, method, path, payload=None):
                    if method == "POST" and path == "/v1/betaAppReviewSubmissions":
                        raise AppleError(status, detail)
                    return super().request(method, path, payload)

            with self.subTest(status=status, detail=detail):
                with self.assertRaises(AppleError):
                    self.run_sync(RejectedApple({"3": "READY_FOR_BETA_SUBMISSION"}))


if __name__ == "__main__":
    unittest.main()
