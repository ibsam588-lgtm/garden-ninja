"""Regenerate the approved Slicer animation sheets with Pillow."""
import math
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


ART = Path(__file__).resolve().parents[1] / "assets" / "images"
OUT = ART / "sprites" / "slicer"

# Positions refer to the visible art, above the transparent frame padding.
# The eyes, jaw, foliage and roots are driven separately for each character.
RIGS = {
    "thorn": dict(file="weed_thorn_sprout", eyes=((.405, .585), (.577, .585)),
                  jaw=(.485, .743, .185, .115), crown=(.40, .13), arms=.145, roots=.067, stem=.025),
    "gobbler": dict(file="weed_vine_gobbler", eyes=((.52, .239), (.735, .236)),
                    jaw=(.570, .385, .320, .144), crown=(.24, .055), arms=.050, roots=.025, stem=.185),
    "bramble": dict(file="weed_bramble_bulb", eyes=((.29, .566), (.545, .586)),
                    jaw=(.394, .714, .177, .091), crown=(.44, .117), arms=.072, roots=.047, stem=.022),
    "seed": dict(file="weed_seed_chomper", eyes=((.468, .433), (.727, .466)),
                 jaw=(.528, .625, .295, .122), crown=(.32, .115), arms=.100, roots=.095, stem=.025),
    "leaf": dict(file="weed_leaf", eyes=((.294, .605), (.474, .624)),
                 jaw=(.42, .769, .160, .103), crown=(.46, .173), arms=.106, roots=.040, stem=.032),
    "spike": dict(file="weed_spike", eyes=((.468, .51), (.712, .497)),
                  jaw=(.603, .714, .198, .131), crown=(.38, .095), arms=.07, roots=.031, stem=.047),
    "purple": dict(file="weed_vine", eyes=((.526, .346), (.764, .367)),
                   jaw=(.61, .549, .261, .167), crown=(.43, .118), arms=.105, roots=.057, stem=.104),
    "daisy": dict(file="flower_daisy", eyes=((.477, .361), (.631, .361)),
                  jaw=None, crown=(.38, .050), arms=.036, roots=0, stem=.083),
    "shield": dict(file="flower_shield", eyes=(), jaw=None,
                   crown=(.44, .018), arms=.024, roots=0, stem=.018),
}


def clamp(value, min_value=0.0, max_value=1.0):
    return max(min_value, min(value, max_value))


def falloff(value, center, radius):
    return max(0, 1 - ((value - center) / radius) ** 2) ** 2


def squeeze(value, center, radius, scale):
    """Inverse vertical squash. The edges stay fixed and the mapping stays monotonic."""
    distance = abs(value - center) / radius
    if distance >= 1:
        return value
    core = .43 * scale
    source = distance / scale if distance <= core else .43 + .57 * (distance - core) / (1 - core)
    return center + math.copysign(source * radius, value - center)


def smoothstep(p):
    p = clamp(p)
    return p * p * (3 - 2 * p)


def gait(cycle):
    """A long planted step and a quicker lift, swing, and return."""
    phase = cycle % 1
    if phase <= .63:
        return .5 - phase / .63, 0
    swing = (phase - .63) / .37
    return -.5 + smoothstep(swing), math.sin(math.pi * swing)


def mesh_frame(source, bounds, rig, frame, count):
    left, top, w, h = bounds
    cycle = frame / count
    phase = math.tau * cycle
    blink = falloff(cycle, .785, .108)
    # Ease the jaw open, hold a beat, then close quickly on the snap.
    chew = 1 - smoothstep((cycle - .05) / .43) + smoothstep((cycle - .60) / .14)
    if rig["file"] == "weed_bramble_bulb":
        chew *= .52
    stride_left, lift_left = gait(cycle)
    stride_right, lift_right = gait(cycle + .5)

    def sample(px, py):
        x, y = (px - left) / w, (py - top) / h
        side = x - .5
        edge = clamp((abs(side) - .17) / .30)
        side_sign = math.copysign(1, side)
        bottom = smoothstep((y - .77) / .23)
        stride, lift = (stride_left, lift_left) if x < .5 else (stride_right, lift_right)
        foot = bottom * smoothstep(abs(side) / .16)
        crown_limit, crown_amplitude = rig["crown"]
        crown = clamp((crown_limit - y) / crown_limit) ** .84
        vine = (1 - clamp(y)) ** .9 * math.sin(phase + y * 4.7)
        arm = edge * falloff(y, .65, .39)
        source_x = x - crown_amplitude * crown * math.sin(phase + y * 2.1)
        source_x -= rig["stem"] * vine
        source_x -= arm * side_sign * .048 * math.cos(phase + side_sign)
        source_x -= rig["roots"] * foot * .58 * stride * side_sign

        source_y = y - rig["arms"] * arm * math.sin(phase + side_sign * 1.22)
        source_y -= rig["roots"] * foot * (stride - lift * .72)
        source_y -= crown * .027 * math.cos(phase + x * 2.8)
        if rig["jaw"]:
            cx, cy, rx, ry = rig["jaw"]
            jaw = falloff(x, cx, rx * 1.45)
            source_y += jaw * (squeeze(y, cy, ry * 1.45, 1 - .68 * chew) - y)
        for cx, cy in rig["eyes"]:
            eye = falloff(x, cx, .132)
            source_y += eye * (squeeze(y, cy, .094, 1 - .92 * blink) - y)
        return (left + source_x * w, top + source_y * h)

    step = 4
    size = source.width
    grid = [[sample(x, y) for x in range(0, size + 1, step)]
            for y in range(0, size + 1, step)]
    mesh = []
    for row in range(size // step):
        for col in range(size // step):
            x, y = col * step, row * step
            mesh.append(((x, y, x + step, y + step),
                         (*grid[row][col], *grid[row + 1][col],
                          *grid[row + 1][col + 1], *grid[row][col + 1])))
    return source.transform(source.size, Image.Transform.MESH, mesh, Image.Resampling.BICUBIC)


def sprite_sheet(key, rig):
    # Frame layout matches SlicerPlantKind in slicer_plant_art.dart.
    size, count, cols = {
        "thorn": (148, 16, 8), "gobbler": (148, 16, 8), "bramble": (148, 16, 8),
        "daisy": (112, 10, 5), "shield": (120, 1, 1),
    }.get(key, (120, 12, 6))
    anchor = round(size * .899)
    original = Image.open(ART / "sprites" / (rig["file"] + ".png")).convert("RGBA")
    if rig["file"] == "weed_vine":
        # Trim the small detached fragment at the left edge of the source art.
        original.paste((0, 0, 0, 0), (0, 0, 45, original.height))
    bounds = original.getchannel("A").point(lambda a: 255 if a > 18 else 0).getbbox()
    sprite = original.crop(bounds)
    sprite.thumbnail((round(size * .762), round(size * .783)), Image.Resampling.LANCZOS)
    alpha = sprite.getchannel("A")
    color = ImageEnhance.Color(sprite.convert("RGB")).enhance(.91 if key == "purple" else .86)
    color = color.filter(ImageFilter.UnsharpMask(radius=.75, percent=62, threshold=3))
    sprite = color.convert("RGBA")
    sprite.putalpha(alpha)
    w, h = sprite.size
    left, top = (size - w) // 2, anchor - h
    padded = Image.new("RGBA", (size, size))
    padded.paste(sprite, (left, top))
    if count == 1:
        return padded
    padded = padded.convert("RGBa")
    sheet = Image.new("RGBA", (size * cols, size * (count // cols)))
    for index in range(count):
        frame = mesh_frame(padded, (left, top, w, h), rig, index, count).convert("RGBA")
        sheet.paste(frame, ((index % cols) * size, (index // cols) * size))
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, rig in RIGS.items():
        destination = OUT / (rig["file"] + ".webp")
        sprite_sheet(key, rig).save(
            destination, "WebP", quality=70 if key in {"thorn", "gobbler", "bramble"} else 68, method=6,
        )
        print(f"{destination.name}: {destination.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
