"""Replace Garden Ninja's Play screenshots and trailer without changing listing copy.

Google's images API covers phone and tablet sets. Foldables are uploaded in
Play Console. All changes use a single edit, so a failed upload can be retried.
"""

import base64
import hashlib
import json
import os
from pathlib import Path
import re

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account


PACKAGE = "com.gardenninja.garden_ninja"
HOST = "https://androidpublisher.googleapis.com"
EDITS = f"/androidpublisher/v3/applications/{PACKAGE}/edits"
METADATA = Path(__file__).resolve().parents[1] / "fastlane/metadata/android"
TYPES = ("phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots")


def read_sets():
    sets = {}
    for listing in sorted(METADATA.iterdir()):
        if not (listing / "images").is_dir():
            continue
        for kind in TYPES:
            folder = listing / "images" / kind
            if not folder.exists() and kind != "phoneScreenshots":
                continue
            files = sorted(path for path in folder.iterdir()
                           if path.suffix.lower() in {".jpg", ".jpeg", ".png"})
            if not 2 <= len(files) <= 8:
                raise ValueError(f"Expected 2–8 screenshots in {folder}, found {len(files)}")
            if any(not 0 < path.stat().st_size <= 8_000_000 for path in files):
                raise ValueError(f"Invalid screenshot size in {folder}")
            sets[listing.name, kind] = files
    for kind in TYPES:
        if ("en-US", kind) not in sets:
            raise ValueError(f"Missing English {kind}")
    return sets


def request(session, method, path, **kwargs):
    response = session.request(method, HOST + path, timeout=100, **kwargs)
    if not response.ok:
        raise RuntimeError(f"Play {method} {path}: {response.status_code} {response.text[:900]}")
    return response.json() if response.content else {}


def matches(image, data):
    digest = hashlib.sha256(data)
    checksum = image.get("sha256", "")
    return checksum.lower() == digest.hexdigest() or checksum.rstrip("=") in {
        base64.b64encode(digest.digest()).decode().rstrip("="),
        base64.urlsafe_b64encode(digest.digest()).decode().rstrip("="),
    }


def replace_set(session, path, files):
    content = [file.read_bytes() for file in files]
    current = request(session, "GET", path).get("images", [])
    if len(current) == len(files) and all(matches(img, data) for img, data in zip(current, content)):
        return
    if current:
        request(session, "DELETE", path)
    for file, data in zip(files, content):
        mime = "image/png" if file.suffix.lower() == ".png" else "image/jpeg"
        request(session, "POST", "/upload" + path, params={"uploadType": "media"},
                headers={"Content-Type": mime}, data=data)
    uploaded = request(session, "GET", path).get("images", [])
    if len(uploaded) != len(content) or not all(matches(img, data) for img, data in zip(uploaded, content)):
        raise RuntimeError(f"Uploaded screenshot order or checksums differ for {path}")


def main():
    video_id = os.environ["YOUTUBE_VIDEO_ID"]
    if not re.fullmatch(r"[A-Za-z0-9_-]{11}", video_id):
        raise ValueError("Expected an 11-character YouTube video ID")
    video = f"https://www.youtube.com/watch?v={video_id}"
    sets = read_sets()
    credentials = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"]),
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    with AuthorizedSession(credentials) as session:
        edit = request(session, "POST", EDITS, json={})["id"]
        path = f"{EDITS}/{edit}"
        try:
            listings = {listing["language"]: listing for listing in
                        request(session, "GET", path + "/listings").get("listings", [])}
            for locale in sorted({locale for locale, _ in sets}):
                if locale not in listings:
                    raise ValueError(f"Missing live listing for {locale}")
                listing_path = f"{path}/listings/{locale}"
                for kind in TYPES:
                    files = sets.get((locale, kind))
                    if files is None:
                        # An empty translated slot inherits the default tablet art.
                        if not request(session, "GET", f"{listing_path}/{kind}").get("images"):
                            continue
                        files = sets["en-US", kind]
                    replace_set(session, f"{listing_path}/{kind}", files)
                    print(f"Verified {locale} {kind}: {len(files)}", flush=True)
                if listings[locale].get("video") != video:
                    updated = request(session, "PATCH", listing_path, json={"video": video})
                    if updated.get("video") != video:
                        raise RuntimeError(f"Could not verify trailer for {locale}")
            request(session, "POST", path + ":validate")
            result = request(session, "POST", path + ":commit", params={
                "changesNotSentForReview": "true", "changesInReviewBehavior": "ERROR_IF_IN_REVIEW",
            })
            print(f"Committed Play listing edit {result['id']} with trailer {video}")
        except Exception:
            # Discard only our own incomplete transaction. The live assets remain intact.
            session.delete(HOST + path, timeout=30)
            raise


if __name__ == "__main__":
    main()
