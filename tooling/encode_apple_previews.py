"""Encode native Apple gameplay recordings to App Store Preview specifications."""

import argparse
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iphone', type=Path, required=True)
    parser.add_argument('--ipad', type=Path, required=True)
    parser.add_argument('--trim-start', type=float, default=4.0,
                        help='Remove the simulator capture warm-up before gameplay')
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    parser.add_argument('--ffprobe', default=shutil.which('ffprobe'))
    args = parser.parse_args()
    if not args.ffmpeg or not args.ffprobe:
        raise ValueError('Install FFmpeg or provide its executable paths')
    if args.trim_start < 0:
        raise ValueError('The capture trim must be nonnegative')
    directory = ROOT / 'store-assets/apple'
    specs = [('iphone', args.iphone, 886, 1920), ('ipad', args.ipad, 1200, 1600)]
    music = ROOT / 'assets/audio/music/ninja_bloom.m4a'
    for name, source, width, height in specs:
        info = json.loads(subprocess.check_output([args.ffprobe, '-v', 'error', '-show_format', '-of', 'json', str(source)]))
        duration = min(28.0, float(info['format']['duration']) - args.trim_start - .25)
        if duration < 15:
            raise ValueError('Native gameplay recordings must contain at least 15 seconds')
        out = directory / f'previews/en-US/{name}-gameplay.mp4'
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
            '-i', str(source), '-stream_loop', '-1', '-i', str(music),
            '-map', '0:v:0', '-map', '1:a:0', '-t', str(duration),
            '-vf', f'fps=30:start_time=0,trim=start={args.trim_start},setpts=PTS-STARTPTS,scale={width}:{height}:force_original_aspect_ratio=decrease:force_divisible_by=2,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x102716,setsar=1,format=yuv420p',
            '-c:v', 'libx264', '-preset', 'medium', '-profile:v', 'high', '-level:v', '4.0',
            '-b:v', '11M', '-maxrate', '12M', '-bufsize', '24M',
            '-c:a', 'aac', '-b:a', '256k', '-ac', '2', '-ar', '48000',
            '-movflags', '+faststart', str(out),
        ], check=True)
        data = json.loads(subprocess.check_output([args.ffprobe, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(out)]))
        video = next(s for s in data['streams'] if s['codec_type'] == 'video')
        audio = next(s for s in data['streams'] if s['codec_type'] == 'audio')
        assert (video['width'], video['height']) == (width, height)
        assert video['codec_name'] == 'h264' and video['pix_fmt'] == 'yuv420p'
        assert float(video['start_time']) < .05
        assert audio['codec_name'] == 'aac' and audio['channels'] == 2
        assert 15 <= float(data['format']['duration']) <= 30
        assert out.stat().st_size < 500_000_000
        print(f'{name}: {width}x{height}, {data["format"]["duration"]}s, H.264/AAC stereo')
    manifest_path = directory / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['previews'] = [
        {'locale': 'en-US', 'display_type': 'IPHONE_61', 'files': ['previews/en-US/iphone-gameplay.mp4']},
        {'locale': 'en-US', 'display_type': 'IPHONE_67', 'files': ['previews/en-US/iphone-gameplay.mp4']},
        {'locale': 'en-US', 'display_type': 'IPAD_PRO_3GEN_129', 'files': ['previews/en-US/ipad-gameplay.mp4']},
    ]
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
