from __future__ import annotations

import math
import random
import shutil
import struct
import subprocess
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_MUSIC = ROOT / "assets" / "audio" / "music"
OUT_SFX = ROOT / "assets" / "audio" / "sfx"
SAMPLE_RATE = 44100


def clamp(value: float) -> float:
    return max(-1.0, min(1.0, value))


def note_freq(note: str) -> float:
    names = {
        "C": 0,
        "C#": 1,
        "D": 2,
        "D#": 3,
        "E": 4,
        "F": 5,
        "F#": 6,
        "G": 7,
        "G#": 8,
        "A": 9,
        "A#": 10,
        "B": 11,
    }
    if note[1] == "#":
        name = note[:2]
        octave = int(note[2:])
    else:
        name = note[:1]
        octave = int(note[1:])
    midi = 12 * (octave + 1) + names[name]
    return 440.0 * (2 ** ((midi - 69) / 12))


def envelope(t: float, duration: float, attack: float, decay: float, sustain: float, release: float) -> float:
    if t < 0 or t > duration:
        return 0.0
    if t < attack:
        return t / max(attack, 0.0001)
    if t < attack + decay:
        k = (t - attack) / max(decay, 0.0001)
        return 1.0 + (sustain - 1.0) * k
    if t < duration - release:
        return sustain
    k = (duration - t) / max(release, 0.0001)
    return max(0.0, sustain * k)


def pan(sample: float, pan_value: float) -> tuple[float, float]:
    left = sample * math.cos((pan_value + 1.0) * math.pi / 4.0)
    right = sample * math.sin((pan_value + 1.0) * math.pi / 4.0)
    return left, right


def sine(freq: float, t: float, phase: float = 0.0) -> float:
    return math.sin((2.0 * math.pi * freq * t) + phase)


def triangle(freq: float, t: float) -> float:
    return (2.0 / math.pi) * math.asin(sine(freq, t))


def mix_note(
    buffer: list[list[float]],
    start: float,
    duration: float,
    freq: float,
    amp: float,
    kind: str,
    pan_value: float = 0.0,
) -> None:
    start_i = int(start * SAMPLE_RATE)
    end_i = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    for i in range(start_i, end_i):
        local_t = (i / SAMPLE_RATE) - start
        env = envelope(local_t, duration, 0.01, 0.12, 0.35, 0.16)
        if kind == "flute":
            vibrato = 4.2 * sine(5.1, local_t)
            tone = 0.78 * sine(freq + vibrato, local_t) + 0.16 * sine(freq * 2.0, local_t)
            tone += random.uniform(-0.02, 0.02) * env
        elif kind == "marimba":
            strike = math.exp(-local_t * 8.0)
            tone = sine(freq, local_t) + 0.42 * sine(freq * 2.01, local_t) + 0.18 * sine(freq * 3.92, local_t)
            env *= strike
        elif kind == "pizz":
            strike = math.exp(-local_t * 6.4)
            tone = 0.7 * triangle(freq, local_t) + 0.2 * sine(freq * 2.0, local_t)
            env *= strike
        elif kind == "bell":
            strike = math.exp(-local_t * 3.2)
            tone = sine(freq, local_t) + 0.45 * sine(freq * 2.42, local_t) + 0.28 * sine(freq * 3.01, local_t)
            env *= strike
        elif kind == "bass":
            tone = 0.62 * sine(freq, local_t) + 0.18 * sine(freq * 2.0, local_t)
            env = envelope(local_t, duration, 0.005, 0.08, 0.55, 0.08)
        else:
            tone = sine(freq, local_t)
        left, right = pan(tone * amp * env, pan_value)
        buffer[i][0] += left
        buffer[i][1] += right


def mix_taiko(buffer: list[list[float]], start: float, amp: float = 0.55, freq: float = 82.0) -> None:
    duration = 0.42
    start_i = int(start * SAMPLE_RATE)
    end_i = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    for i in range(start_i, end_i):
        t = (i / SAMPLE_RATE) - start
        drop = freq * (1.0 - 0.42 * min(1.0, t / duration))
        tone = sine(drop, t) * math.exp(-t * 8.0)
        click = random.uniform(-1.0, 1.0) * math.exp(-t * 35.0) * 0.24
        left, right = pan((tone + click) * amp, -0.08)
        buffer[i][0] += left
        buffer[i][1] += right


def mix_shaker(buffer: list[list[float]], start: float, amp: float = 0.12) -> None:
    duration = 0.08
    start_i = int(start * SAMPLE_RATE)
    end_i = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    for i in range(start_i, end_i):
        t = (i / SAMPLE_RATE) - start
        sample = random.uniform(-1.0, 1.0) * math.exp(-t * 28.0) * amp
        left, right = pan(sample, 0.45)
        buffer[i][0] += left
        buffer[i][1] += right


def mix_sweep(buffer: list[list[float]], start: float, duration: float, amp: float, high: float, low: float) -> None:
    start_i = int(start * SAMPLE_RATE)
    end_i = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    phase = 0.0
    last_t = 0.0
    for i in range(start_i, end_i):
        t = (i / SAMPLE_RATE) - start
        k = t / duration
        freq = high + (low - high) * k
        phase += 2 * math.pi * freq * (t - last_t)
        last_t = t
        noise = random.uniform(-1.0, 1.0)
        sample = (math.sin(phase) * 0.45 + noise * 0.55) * math.exp(-t * 10.0) * amp
        left, right = pan(sample, -0.15 + k * 0.3)
        buffer[i][0] += left
        buffer[i][1] += right


def write_wav(path: Path, buffer: list[list[float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max(0.001, max(max(abs(l), abs(r)) for l, r in buffer))
    gain = 0.92 / peak
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for left, right in buffer:
            frames += struct.pack("<hh", int(clamp(left * gain) * 32767), int(clamp(right * gain) * 32767))
        wav.writeframes(frames)


def write_ogg(path: Path, buffer: list[list[float]], quality: str) -> None:
    wav_path = path.with_suffix(".wav")
    write_wav(wav_path, buffer)
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print(f"ffmpeg not found; left WAV draft at {wav_path}")
        return

    subprocess.run(
        [
            ffmpeg,
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(wav_path),
            "-c:a",
            "libvorbis",
            "-q:a",
            quality,
            str(path),
        ],
        check=True,
    )
    wav_path.unlink()


def blank(seconds: float) -> list[list[float]]:
    return [[0.0, 0.0] for _ in range(int(seconds * SAMPLE_RATE))]


def render_track(name: str, bpm: int, bars: int, pattern: dict[str, object]) -> None:
    random.seed(name)
    beat = 60.0 / bpm
    duration = bars * 4 * beat
    buffer = blank(duration)
    melody = pattern["melody"]
    bass = pattern["bass"]
    instrument = pattern["instrument"]
    harmony = pattern.get("harmony", "pizz")

    for bar in range(bars):
        bar_start = bar * 4 * beat
        for beat_index in range(4):
            now = bar_start + beat_index * beat
            if beat_index in (0, 2) or pattern.get("drums", "light") == "busy":
                mix_taiko(buffer, now, amp=pattern.get("drum_amp", 0.32), freq=pattern.get("drum_freq", 84.0))
            if pattern.get("shaker", True):
                mix_shaker(buffer, now + beat * 0.5, amp=0.09)

        chord = bass[bar % len(bass)]
        mix_note(buffer, bar_start, beat * 3.8, note_freq(chord), 0.17, "bass", -0.2)

        for step in range(8):
            note = melody[(bar * 8 + step) % len(melody)]
            if note:
                inst = instrument if step % 2 == 0 else harmony
                mix_note(buffer, bar_start + step * beat * 0.5, beat * 0.8, note_freq(note), pattern.get("note_amp", 0.24), inst, (step % 4 - 1.5) / 3.5)

    if pattern.get("action_sweeps", False):
        for bar in range(1, bars, 2):
            mix_sweep(buffer, bar * 4 * beat + beat * 3.5, beat * 0.45, 0.14, 1600, 340)

    write_ogg(OUT_MUSIC / f"{name}.ogg", buffer, "5")


def render_sfx_leaf(path: Path, seed: str, variant: str) -> None:
    random.seed(seed)
    duration = {
        "crisp": 0.42,
        "bamboo": 0.46,
        "wet": 0.62,
        "combo": 0.72,
        "ice": 0.86,
    }[variant]
    buffer = blank(duration)

    if variant == "crisp":
        mix_sweep(buffer, 0.02, 0.2, 0.55, 3600, 620)
        mix_note(buffer, 0.16, 0.16, note_freq("G5"), 0.22, "bell", 0.25)
    elif variant == "bamboo":
        mix_sweep(buffer, 0.0, 0.23, 0.7, 5000, 760)
        mix_taiko(buffer, 0.13, 0.34, 180)
        mix_note(buffer, 0.22, 0.12, note_freq("C5"), 0.18, "pizz", -0.15)
    elif variant == "wet":
        mix_sweep(buffer, 0.03, 0.34, 0.48, 1800, 180)
        for start in (0.11, 0.2, 0.29):
            mix_note(buffer, start, 0.22, note_freq("D3"), 0.16, "bass", random.uniform(-0.25, 0.25))
    elif variant == "combo":
        mix_sweep(buffer, 0.0, 0.2, 0.48, 4200, 620)
        for start, note in ((0.1, "E5"), (0.19, "G5"), (0.29, "B5")):
            mix_note(buffer, start, 0.32, note_freq(note), 0.24, "bell", 0.1)
    elif variant == "ice":
        mix_sweep(buffer, 0.02, 0.28, 0.35, 2600, 420)
        for start, note in ((0.05, "C6"), (0.14, "F#6"), (0.24, "A6"), (0.38, "C7")):
            mix_note(buffer, start, 0.34, note_freq(note), 0.2, "bell", random.uniform(-0.4, 0.4))
        for start in (0.33, 0.42, 0.51):
            mix_sweep(buffer, start, 0.08, 0.22, 5200, 1800)

    write_ogg(path, buffer, "6")


def main() -> None:
    tracks = {
        "ninja_bloom": {
            "bpm": 104,
            "bars": 8,
            "instrument": "flute",
            "harmony": "pizz",
            "melody": ["D5", "E5", "G5", None, "A5", "G5", "E5", None, "D5", "G5", "A5", "B5", "A5", None, "G5", None],
            "bass": ["D3", "G3", "C3", "A2"],
            "drum_amp": 0.34,
            "note_amp": 0.24,
        },
        "garden_groove": {
            "bpm": 118,
            "bars": 8,
            "instrument": "marimba",
            "harmony": "pizz",
            "melody": ["C5", "E5", "G5", "A5", "G5", "E5", "D5", None, "E5", "G5", "A5", "C6", "A5", "G5", None, "E5"],
            "bass": ["C3", "F3", "G2", "C3"],
            "drum_amp": 0.25,
            "note_amp": 0.26,
        },
        "blossom_rush": {
            "bpm": 146,
            "bars": 8,
            "instrument": "bell",
            "harmony": "marimba",
            "melody": ["E5", "G5", "A5", "B5", "C6", "B5", "A5", "G5", "E5", "G5", "B5", "D6", "C6", "B5", "A5", "G5"],
            "bass": ["E3", "C3", "D3", "B2"],
            "drums": "busy",
            "shaker": True,
            "drum_amp": 0.31,
            "note_amp": 0.2,
            "action_sweeps": True,
        },
        "moonlit_greenhouse": {
            "bpm": 82,
            "bars": 8,
            "instrument": "flute",
            "harmony": "bell",
            "melody": ["A4", None, "C5", None, "E5", None, "G5", None, "E5", None, "C5", None, "B4", None, "A4", None],
            "bass": ["A2", "F3", "C3", "G2"],
            "drum_amp": 0.13,
            "note_amp": 0.19,
            "shaker": False,
        },
        "weed_invasion": {
            "bpm": 132,
            "bars": 8,
            "instrument": "pizz",
            "harmony": "bell",
            "melody": ["D5", "F5", "G#5", "A5", "G#5", "F5", "D5", None, "D5", "F5", "A5", "C6", "A5", "G#5", "F5", None],
            "bass": ["D2", "D2", "A2", "C3"],
            "drums": "busy",
            "drum_amp": 0.4,
            "note_amp": 0.22,
            "action_sweeps": True,
        },
    }

    for name, config in tracks.items():
        render_track(name, config.pop("bpm"), config.pop("bars"), config)

    sfx = {
        "crisp_leaf_cut": "crisp",
        "bamboo_blade_slice": "bamboo",
        "wet_vine_chop": "wet",
        "combo_spark_slash": "combo",
        "frozen_weed_shatter": "ice",
    }
    for name, variant in sfx.items():
        render_sfx_leaf(OUT_SFX / f"{name}.ogg", name, variant)


if __name__ == "__main__":
    main()
