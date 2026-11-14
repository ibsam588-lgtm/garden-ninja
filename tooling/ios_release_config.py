"""Validate iOS release inputs without logging or persisting signing secrets."""

import argparse
import json
import os
from pathlib import Path
import re
import sys
import uuid


BUNDLE_ID = "com.corsairlabs.gardenNinja"
AD_KEYS = (
    "LEVELPLAY_IOS_APP_KEY",
    "LEVELPLAY_IOS_BANNER_AD_UNIT_ID",
    "LEVELPLAY_IOS_INTERSTITIAL_AD_UNIT_ID",
    "LEVELPLAY_IOS_REWARDED_AD_UNIT_ID",
)


def release_config(env, pubspec, mode):
    if mode not in ("upload", "submit"):
        raise ValueError("Unknown iOS release operation")
    required = [
        "APP_STORE_ID", "APPLE_TEAM_ID", "APP_STORE_CONNECT_ISSUER_ID",
        "APP_STORE_CONNECT_KEY_IDENTIFIER", "APP_STORE_CONNECT_PRIVATE_KEY",
    ]
    if mode == "upload":
        required.append("CERTIFICATE_PRIVATE_KEY")
    missing = [name for name in required if not env.get(name, "").strip()]
    if missing:
        raise ValueError("Missing Apple settings: " + ", ".join(missing))
    if not re.fullmatch(r"[0-9]+", env["APP_STORE_ID"]):
        raise ValueError("APP_STORE_ID must be Apple's numeric app ID")
    for name in ("APPLE_TEAM_ID", "APP_STORE_CONNECT_KEY_IDENTIFIER"):
        if not re.fullmatch(r"[A-Z0-9]{10}", env[name]):
            raise ValueError(name + " must contain 10 uppercase letters/digits")
    try:
        uuid.UUID(env["APP_STORE_CONNECT_ISSUER_ID"])
    except ValueError:
        raise ValueError("APP_STORE_CONNECT_ISSUER_ID must be a UUID") from None
    if "-----BEGIN PRIVATE KEY-----" not in env["APP_STORE_CONNECT_PRIVATE_KEY"]:
        raise ValueError("APP_STORE_CONNECT_PRIVATE_KEY must contain the downloaded .p8 PEM key")
    if mode == "upload" and not re.search(
        r"-----BEGIN (?:RSA )?PRIVATE KEY-----", env["CERTIFICATE_PRIVATE_KEY"]
    ):
        raise ValueError("CERTIFICATE_PRIVATE_KEY must contain the distribution certificate's PEM private key")

    requested_version = env.get("REQUESTED_IOS_VERSION", "").strip()
    requested_build = env.get("REQUESTED_IOS_BUILD", "").strip()
    if mode == "submit" and (not requested_version or not requested_build):
        raise ValueError("App Review requires the exact tested version and build number")
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$", pubspec, re.M)
    version = requested_version or (match[1] if match else "")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("The iOS version must have three numeric components, such as 1.1.7")
    if requested_build and not re.fullmatch(r"[1-9][0-9]*", requested_build):
        raise ValueError("The tested iOS build number must be a positive integer")

    defines = {"APP_STORE_ID": env["APP_STORE_ID"]}
    ads = {key: env.get(key, "").strip() for key in AD_KEYS}
    if any(ads.values()) and not all(ads.values()):
        raise ValueError("Configure all four iOS LevelPlay values, or leave all four empty")
    if all(ads.values()):
        if len(set(ads[key] for key in AD_KEYS[1:])) != 3:
            raise ValueError("iOS banner, interstitial and rewarded ad-unit IDs must be distinct")
        defines.update(ads)
    child_directed = env.get("LEVELPLAY_CHILD_DIRECTED", "false").strip() or "false"
    if child_directed not in ("true", "false"):
        raise ValueError("LEVELPLAY_CHILD_DIRECTED must be true or false")
    defines["LEVELPLAY_CHILD_DIRECTED"] = child_directed
    defines["LEVELPLAY_TEST_SUITE"] = "false"
    return {
        "bundle_id": BUNDLE_ID,
        "version": version,
        "build_number": requested_build,
        "team_id": env["APPLE_TEAM_ID"],
        "app_store_id": env["APP_STORE_ID"],
        "ads_enabled": all(ads.values()),
        "dart_defines": defines,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("upload", "submit"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    args = parser.parse_args()
    try:
        config = release_config(os.environ, args.pubspec.read_text(), args.mode)
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "release.json").write_text(json.dumps(config, indent=2))
    (args.output / "dart-defines.json").write_text(json.dumps(config["dart_defines"]))
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
        output.write(f"IOS_VERSION={config['version']}\n")
        if config["build_number"]:
            output.write(f"IOS_BUILD_NUMBER={config['build_number']}\n")
    print(f"Apple release settings validated for {BUNDLE_ID}, version {config['version']}")
    if not config["ads_enabled"]:
        print("::notice::iOS ad inventory is not configured; this iOS build will have ads disabled.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
