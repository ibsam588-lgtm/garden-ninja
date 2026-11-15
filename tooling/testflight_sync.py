"""Attach processed builds, preserve Apple's review queue, and invite approved testers."""

import argparse
import os
from pathlib import Path
import sys

from apple_api import AppleAPI, AppleError, BUNDLE_ID, relation

REVIEWING = {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW"}
AVAILABLE = {"IN_BETA_TESTING", "BETA_APPROVED", "READY_FOR_BETA_TESTING"}


def sync(api, app_id, group_id, allowed_emails, emit=print, apply=True):
    app = api.request("GET", f"/v1/apps/{app_id}")["data"]
    if app["attributes"]["bundleId"] != BUNDLE_ID:
        raise ValueError("Refusing to change a different Apple app")
    groups = api.all(f"/v1/apps/{app_id}/betaGroups?limit=200")
    group = next((g for g in groups if g["id"] == group_id), None)
    if not group or group["attributes"].get("isInternalGroup"):
        raise ValueError("The configured external group must belong to Garden Ninja")
    builds = api.all(f"/v1/apps/{app_id}/builds?limit=200")
    builds = sorted((b for b in builds if not b["attributes"].get("expired")
                     and b["attributes"]["processingState"] == "VALID"),
                    key=lambda b: b["attributes"]["uploadedDate"], reverse=True)
    if not builds:
        emit("No processed, unexpired builds yet; the next sync will retry.")
        return
    attached = {b["id"] for b in api.all(f"/v1/betaGroups/{group_id}/builds?limit=200")}
    details = {b["id"]: api.request("GET", f"/v1/builds/{b['id']}/buildBetaDetail")["data"] for b in builds}
    latest = builds[0]
    bid = latest["id"]
    detail = details[bid]
    state = detail["attributes"]["externalBuildState"]
    emit(f"Latest processed build {latest['attributes']['version']}: {state}.")
    # Notification is Apple's native post-approval handoff, even between syncs.
    if not detail["attributes"].get("autoNotifyEnabled") and apply:
        api.request("PATCH", f"/v1/buildBetaDetails/{detail['id']}", {"data": {
            "type": "buildBetaDetails", "id": detail["id"], "attributes": {"autoNotifyEnabled": True}}})
    if bid not in attached and apply:
        api.request("POST", f"/v1/builds/{bid}/relationships/betaGroups", {
            "data": [{"type": "betaGroups", "id": group_id}]})
        attached.add(bid)
        emit("Attached the latest build to the external playtest group.")
    if state == "READY_FOR_BETA_SUBMISSION":
        reviewing = any(d["attributes"]["externalBuildState"] in REVIEWING for d in details.values())
        if reviewing:
            emit("Apple is reviewing another build. Its queue position is preserved; a later sync will submit this build.")
        elif apply:
            try:
                api.request("POST", "/v1/betaAppReviewSubmissions", {"data": {
                    "type": "betaAppReviewSubmissions", "relationships": {"build": relation("builds", bid)}}})
                emit("Submitted the processed build for external TestFlight review.")
            except AppleError as error:
                # Handle only Apple's explicit race with an existing submission.
                if error.status == 422 and "another build" in str(error).lower() and "review" in str(error).lower():
                    emit("Another build entered beta review first; the next sync will retry.")
                else:
                    raise
    eligible = any(b["id"] in attached and details[b["id"]]["attributes"]["externalBuildState"] in AVAILABLE for b in builds)
    if not eligible:
        emit("No approved external build yet. Invitations wait for Apple's approval.")
        return
    # Group-scoped state is authoritative; the global tester resource returns null.
    testers = api.all(f"/v1/betaGroups/{group_id}/betaTesters?limit=200")
    for tester in testers:
        attrs = tester["attributes"]
        if attrs.get("email", "").lower() not in allowed_emails:
            continue
        if attrs.get("state") == "NOT_INVITED" and apply:
            api.request("POST", "/v1/betaTesterInvitations", {"data": {
                "type": "betaTesterInvitations", "relationships": {
                    "app": relation("apps", app_id), "betaTester": relation("betaTesters", tester["id"])}}})
            emit("Sent the approved tester's first TestFlight invitation.")
        else:
            emit(f"Approved tester invitation state: {attrs.get('state')}; no duplicate invitation sent.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    messages = []
    def emit(message):
        print(message)
        messages.append(message)
    sync(AppleAPI(), os.environ["APP_STORE_ID"], os.environ["IOS_TESTFLIGHT_GROUP_ID"],
         {e.strip().lower() for e in os.environ.get("IOS_TESTFLIGHT_TESTER_EMAILS", "").split(",") if e.strip()},
         emit=emit, apply=not args.dry_run)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as output:
            output.write("\n".join(messages) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
