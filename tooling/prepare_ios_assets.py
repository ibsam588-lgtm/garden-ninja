"""Resize the existing store icon for Xcode; run from the repository root."""

import json
from pathlib import Path

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[1]
    icon = Image.open(root / "fastlane/metadata/android/en-US/images/icon.png").convert("RGB")
    catalog = root / "ios/Runner/Assets.xcassets"
    app_icons = catalog / "AppIcon.appiconset"
    entries = json.loads((app_icons / "Contents.json").read_text())["images"]
    for entry in entries:
        size = round(float(entry["size"].split("x")[0]) * float(entry["scale"][:-1]))
        icon.resize((size, size), Image.Resampling.LANCZOS).save(app_icons / entry["filename"])
    for scale in (1, 2, 3):
        suffix = "" if scale == 1 else f"@{scale}x"
        icon.resize((160 * scale, 160 * scale), Image.Resampling.LANCZOS).save(
            catalog / "LaunchImage.imageset" / f"LaunchImage{suffix}.png"
        )
    print(f"Prepared {len(entries)} opaque app icons and 3 launch images.")


if __name__ == "__main__":
    main()
