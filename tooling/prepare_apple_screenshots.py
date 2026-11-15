"""Package actual Flutter captures as opaque JPEGs at Apple's exact dimensions."""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = ROOT / "build/apple-store-captures"
    destination = ROOT / "store-assets/apple"
    sets = []
    for display in sorted(source.iterdir()):
        files = []
        dimensions = None
        for capture in sorted(display.glob("*.png")):
            with Image.open(capture) as image:
                dimensions = list(image.size)
                out = destination / "screenshots/en-US" / display.name / (capture.stem + ".jpg")
                out.parent.mkdir(parents=True, exist_ok=True)
                image.convert("RGB").save(out, quality=95, subsampling=0, optimize=True)
            files.append(out.relative_to(destination).as_posix())
        if files:
            sets.append({"locale": "en-US", "display_type": display.name,
                         "dimensions": dimensions, "files": files})
    manifest = {"youtube_trailer": "https://www.youtube.com/watch?v=fLmL-XDmO8c",
                "screenshots": sets, "previews": []}
    path = destination / "manifest.json"
    # Preserve preview mappings if a later screenshot recapture is packaged.
    if path.exists():
        manifest["previews"] = json.loads(path.read_text()).get("previews", [])
    path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {sum(len(s['files']) for s in sets)} screenshots in {len(sets)} device sizes.")


if __name__ == "__main__":
    main()
