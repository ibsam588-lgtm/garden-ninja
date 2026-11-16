"""Prepare locally rendered Duo screenshots and existing native gameplay video."""
import json
from pathlib import Path
import shutil
import subprocess

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    base = ROOT / 'store-assets/apple'
    groups = []
    for name, dimensions in [('DUO_OUTER', (1398, 2034)), ('DUO_INNER', (2007, 2853))]:
        sources = sorted((ROOT / 'build/apple-store-captures' / name).glob('*.png'))
        if len(sources) != 4:
            raise ValueError(f'Capture all four {name} screens locally first')
        destination = base / 'screenshots/en-US' / name
        destination.mkdir(parents=True, exist_ok=True)
        files = []
        for source in sources:
            with Image.open(source) as image:
                if image.size != dimensions:
                    raise ValueError(f'Incorrect Duo size: {source.name}')
                output = destination / f'{source.stem}.jpg'
                image.convert('RGB').save(output, quality=95, subsampling=0)
                files.append(output.relative_to(base).as_posix())
        # Apple requires 886x1920 portrait previews for BOTH Duo displays.
        # Reuse the already captured native gameplay; never stretch its aspect.
        source = base / 'previews/en-US/iphone-gameplay.mp4'
        probe = json.loads(subprocess.check_output([
            shutil.which('ffprobe'), '-v', 'error', '-show_streams', '-show_format',
            '-of', 'json', str(source)]))
        video = next(s for s in probe['streams'] if s['codec_type'] == 'video')
        audio = next(s for s in probe['streams'] if s['codec_type'] == 'audio')
        if (video['width'], video['height']) != (886, 1920) or video['codec_name'] != 'h264':
            raise ValueError('Native gameplay must meet the Apple Duo preview resolution')
        if audio['codec_name'] != 'aac' or audio['channels'] != 2:
            raise ValueError('Native gameplay must have AAC stereo audio')
        if not 15 <= float(probe['format']['duration']) <= 30:
            raise ValueError('Apple previews must be 15 to 30 seconds')
        preview = base / f'previews/en-US/{name.lower()}-gameplay.mp4'
        shutil.copyfile(source, preview)
        groups.append({'display': name, 'dimensions': dimensions, 'screenshots': files,
                       'preview': preview.relative_to(base).as_posix(),
                       'preview_dimensions': [886, 1920]})
    (base / 'duo-manifest.json').write_text(json.dumps({
        'locale': 'en-US', 'capture': 'Local Flutter renderer using shipped widgets and assets',
        'preview_source': 'Existing native iOS gameplay recording, copied without resampling',
        'groups': groups}, indent=2) + '\n')
    print('Prepared 8 opaque Duo screenshots and 2 accepted-resolution gameplay previews locally.')


if __name__ == '__main__':
    main()
