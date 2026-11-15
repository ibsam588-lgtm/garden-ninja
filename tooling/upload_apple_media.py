"""Upload and verify versioned Apple screenshots/previews; leave App Review separate."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import time
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from apple_api import AppleAPI, BUNDLE_ID, relation


def upload_file(api, kind, set_id, path):
    content = path.read_bytes()
    checksum = hashlib.md5(content, usedforsecurity=False).hexdigest()
    filename = f"gn-{path.stem}-{checksum[:10]}{path.suffix}"
    set_kind = "appScreenshotSets" if kind == "appScreenshots" else "appPreviewSets"
    relationship = "appScreenshotSet" if kind == "appScreenshots" else "appPreviewSet"
    existing = api.all(f"/v1/{set_kind}/{set_id}/{kind}?limit=200")
    resource = next((r for r in existing if r["attributes"]["fileName"] == filename), None)
    if resource is None:
        attrs = {"fileName": filename, "fileSize": len(content)}
        if kind == "appPreviews":
            attrs.update(mimeType="video/mp4", previewFrameTimeCode="00:00:05:00")
        resource = api.request("POST", f"/v1/{kind}", {"data": {
            "type": kind, "attributes": attrs, "relationships": {relationship: relation(set_kind, set_id)}}})["data"]
    identifier = resource["id"]
    state = resource["attributes"].get("assetDeliveryState", {}).get("state")
    if state not in {"COMPLETE", "UPLOAD_COMPLETE"}:
        for operation in resource["attributes"].get("uploadOperations", []):
            url = urlparse(operation["url"])
            if url.scheme != "https":
                raise ValueError("Apple returned an insecure asset upload target")
            headers = {h["name"]: h["value"] for h in operation["requestHeaders"]}
            offset, length = operation["offset"], operation["length"]
            request = Request(operation["url"], method=operation["method"],
                              data=content[offset:offset + length], headers=headers)
            # Signed Apple upload URLs receive file bytes, never the API token.
            with urlopen(request, timeout=120) as response:
                response.read()
        resource = api.request("PATCH", f"/v1/{kind}/{identifier}", {"data": {
            "type": kind, "id": identifier, "attributes": {"uploaded": True, "sourceFileChecksum": checksum}}})["data"]
    # Keep prior assets until Apple has accepted the replacement bytes.
    for old in existing:
        if old["id"] != identifier and old["attributes"]["fileName"].startswith(f"gn-{path.stem}-"):
            api.request("DELETE", f"/v1/{kind}/{old['id']}")
    print(f"Uploaded {path.name} ({kind}, {identifier})", flush=True)
    return {"id": identifier, "kind": kind, "file": path.as_posix(), "md5": checksum}


def upload(api, app_id, version, directory):
    if api.request("GET", f"/v1/apps/{app_id}")["data"]["attributes"]["bundleId"] != BUNDLE_ID:
        raise ValueError("Refusing to change a different Apple app")
    query = urlencode({"filter[platform]": "IOS", "filter[versionString]": version, "limit": 20})
    versions = api.all(f"/v1/apps/{app_id}/appStoreVersions?{query}")
    if len(versions) != 1 or versions[0]["attributes"]["appStoreState"] not in {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}:
        raise ValueError("Choose a single editable iOS store version before uploading media")
    locales = {l["attributes"]["locale"]: l["id"] for l in api.all(
        f"/v1/appStoreVersions/{versions[0]['id']}/appStoreVersionLocalizations?limit=200")}
    manifest = json.loads((directory / "manifest.json").read_text())
    uploaded = []
    for category, set_kind, item_kind, display_key in [
        ("screenshots", "appScreenshotSets", "appScreenshots", "screenshotDisplayType"),
        ("previews", "appPreviewSets", "appPreviews", "previewType"),
    ]:
        for group in manifest.get(category, []):
            localization = locales[group["locale"]]
            sets = api.all(f"/v1/appStoreVersionLocalizations/{localization}/{set_kind}?limit=200")
            display = group["display_type"]
            current = next((s for s in sets if s["attributes"][display_key] == display), None)
            if current is None:
                current = api.request("POST", f"/v1/{set_kind}", {"data": {
                    "type": set_kind, "attributes": {display_key: display}, "relationships": {
                        "appStoreVersionLocalization": relation("appStoreVersionLocalizations", localization)}}})["data"]
            paths = []
            for name in group["files"]:
                path = (directory / name).resolve()
                if not path.is_relative_to(directory.resolve()) or not path.is_file():
                    raise ValueError("Asset paths must stay within the Apple media directory")
                paths.append(path)
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda p: upload_file(api, item_kind, current["id"], p), paths))
            uploaded.extend(results)
            # Keep manually added assets; only our same-name versions are replaced.
            current_assets = api.all(f"/v1/{set_kind}/{current['id']}/{item_kind}?limit=200")
            wanted_ids = {r["id"] for r in results}
            ordered = results + [r for r in current_assets if r["id"] not in wanted_ids]
            maximum = 10 if item_kind == "appScreenshots" else 3
            if len(ordered) > maximum:
                raise ValueError(f"{display} exceeds Apple's {maximum}-asset limit; existing manual assets were preserved")
            # Persist requested sequence rather than relying on concurrent upload order.
            api.request("PATCH", f"/v1/{set_kind}/{current['id']}/relationships/{item_kind}", {
                "data": [{"type": item_kind, "id": r["id"]} for r in ordered]})
            print(f"Ordered {len(results)} {display} assets.", flush=True)
    return uploaded


def verify(api, uploaded):
    pending = []
    for asset in uploaded:
        resource = api.request("GET", f"/v1/{asset['kind']}/{asset['id']}")["data"]
        attrs = resource["attributes"]
        delivery = attrs.get("assetDeliveryState", {})
        if delivery.get("state") == "FAILED":
            raise RuntimeError(f"Apple rejected {Path(asset['file']).name}: {delivery.get('errors')}")
        if attrs.get("sourceFileChecksum") != asset["md5"]:
            raise RuntimeError("Apple's stored checksum does not match the uploaded asset")
        asset["state"] = delivery.get("state")
        if asset["state"] != "COMPLETE":
            pending.append(asset)
    return pending


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--directory", type=Path, default=Path("store-assets/apple"))
    parser.add_argument("--report", type=Path, default=Path("build/apple-media-upload.json"))
    args = parser.parse_args()
    api = AppleAPI()
    assets = upload(api, os.environ["APP_STORE_ID"], args.version, args.directory)
    for _ in range(12):
        pending = verify(api, assets)
        if not pending:
            break
        print(f"Apple is processing {len(pending)} assets.", flush=True)
        time.sleep(10)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(assets, indent=2) + "\n")
    print(f"Verified {len(assets) - len(pending)}/{len(assets)} complete assets; {len(pending)} still processing.")


if __name__ == "__main__":
    main()
