#!/usr/bin/env python3
"""Paints the UI's placeholder textures: bevelled brass frames, gunmetal
plates, the console strip and the portrait porthole.

Run from the repository root:  python3 tools/generate_ui_textures.py
Writes PNGs to assets/ui/. Needs Pillow. The textures are nine-sliced in
scripts/autoload/ui_theme.gd, so their corner sizes must match MARGINS there.
Human-made art can replace any of these files one for one.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")

BRASS_LIGHT = (246, 214, 140)
BRASS = (196, 146, 70)
BRASS_DARK = (92, 62, 26)
OUTLINE = (12, 9, 6)
GLOW = (92, 234, 224)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def chamfer_distance(x, y, w, h, cut):
    """Distance from (x, y) inside a w*h box with cut corners to its edge, and
    which way that edge faces: -1 (top/left, lit) to 1 (bottom/right, shaded)."""
    edges = [
        (y, -1.0),            # top
        (x, -1.0),            # left
        (h - 1 - y, 1.0),     # bottom
        (w - 1 - x, 1.0),     # right
        ((x + y - cut) / math.sqrt(2), -1.0),                    # top-left cut
        (((w - 1 - x) + y - cut) / math.sqrt(2), 0.0),           # top-right cut
        ((x + (h - 1 - y) - cut) / math.sqrt(2), 0.0),           # bottom-left cut
        (((w - 1 - x) + (h - 1 - y) - cut) / math.sqrt(2), 1.0), # bottom-right cut
    ]
    return min(edges, key=lambda e: e[0])


def metal(rng, base, amount=10):
    n = rng.randint(-amount, amount)
    return tuple(max(0, min(255, c + n)) for c in base[:3]) + base[3:]


def bevel_box(w, h, cut, rim, fill_top, fill_bottom, rim_light, rim_mid, rim_dark,
              inverted=False, glow_alpha=0, seed=1, groove=True):
    """A chamfered plate: a bevelled metal rim around a gradient fill."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            d, facing = chamfer_distance(x, y, w, h, cut)
            if d < 0:
                continue
            if d < 1.0:
                px[x, y] = OUTLINE + (255,)
            elif d < 1.0 + rim:
                # Convex bevel: lit edges bright, shaded edges dark, rounded across the rim.
                t = (d - 1.0) / rim
                light = -facing if not inverted else facing
                curve = math.sin(t * math.pi)
                if light > 0:
                    c = lerp(rim_mid, rim_light, 0.35 + 0.65 * curve)
                elif light < 0:
                    c = lerp(rim_dark, rim_mid, 0.25 + 0.5 * curve)
                else:
                    c = lerp(rim_dark, rim_light, 0.5 * curve + 0.15)
                px[x, y] = metal(rng, c, 6) + (255,)
            elif groove and d < 3.0 + rim:
                px[x, y] = OUTLINE + (235,)
            else:
                t = y / max(h - 1, 1)
                c = lerp(fill_top, fill_bottom, t)
                # Faint horizontal brushing.
                c = metal(rng, c, 3)
                px[x, y] = c
                if glow_alpha and d < 4.5 + rim:
                    px[x, y] = lerp(c, GLOW + (255,), glow_alpha)
    return img


def rivet(draw, cx, cy, r):
    draw.ellipse((cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1), fill=OUTLINE + (255,))
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=BRASS_DARK + (255,))
    draw.ellipse((cx - r, cy - r, cx + r - 1, cy + r - 1), fill=BRASS + (255,))
    draw.ellipse((cx - r + 1, cy - r + 1, cx, cy), fill=BRASS_LIGHT + (255,))


def panel():
    w = h = 96
    img = bevel_box(w, h, 14, 8, (20, 40, 46, 242), (8, 18, 22, 246),
                    BRASS_LIGHT, BRASS, BRASS_DARK, glow_alpha=0.18, seed=2)
    d = ImageDraw.Draw(img)
    for cx, cy in [(15, 15), (w - 16, 15), (15, h - 16), (w - 16, h - 16)]:
        rivet(d, cx, cy, 3)
    img.save(os.path.join(OUT, "frame_panel.png"))


def buttons():
    w, h = 64, 40
    states = {
        "normal": dict(fill_top=(36, 66, 72, 255), fill_bottom=(12, 26, 30, 255),
                       rim=(BRASS_LIGHT, BRASS, BRASS_DARK)),
        "hover": dict(fill_top=(46, 96, 104, 255), fill_bottom=(16, 44, 50, 255),
                      rim=((255, 232, 170), (222, 174, 96), (120, 84, 36)), glow_alpha=0.35),
        "pressed": dict(fill_top=(8, 30, 34, 255), fill_bottom=(24, 70, 74, 255),
                        rim=(BRASS_LIGHT, BRASS, BRASS_DARK), inverted=True, glow_alpha=0.6),
        "disabled": dict(fill_top=(26, 30, 32, 255), fill_bottom=(14, 16, 18, 255),
                         rim=((120, 112, 98), (82, 76, 66), (44, 40, 34))),
    }
    for name, s in states.items():
        light, mid, dark = s["rim"]
        img = bevel_box(w, h, 7, 3, s["fill_top"], s["fill_bottom"], light, mid, dark,
                        inverted=s.get("inverted", False), glow_alpha=s.get("glow_alpha", 0),
                        seed=sum(map(ord, name)))
        # A highlight along the top of raised plates.
        if not s.get("inverted"):
            d = ImageDraw.Draw(img)
            d.line((8, 6, w - 9, 6), fill=(255, 255, 255, 40))
        img.save(os.path.join(OUT, "button_%s.png" % name))


def console():
    """The bottom console: a riveted brass band over brushed gunmetal. Tiles
    horizontally, so it is drawn to repeat seamlessly every 128 px."""
    w, h = 128, 64
    rng = random.Random(7)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    band = 16
    for y in range(h):
        for x in range(w):
            if y == 0:
                c = OUTLINE
            elif y < band:
                t = (y - 1) / (band - 2)
                c = lerp(BRASS_LIGHT, BRASS_DARK, t) if t > 0.5 else lerp(BRASS, BRASS_LIGHT, 1 - t * 2)
                c = metal(rng, c, 5)
            elif y < band + 2:
                c = OUTLINE
            elif y == band + 2:
                c = lerp((14, 30, 34), GLOW, 0.45)
            else:
                t = (y - band) / (h - band)
                c = metal(rng, lerp((26, 38, 42), (10, 16, 19), t), 4)
                # Machined grooves.
                if (y - band) % 14 == 0:
                    c = lerp(c, (0, 0, 0), 0.5)
                elif (y - band) % 14 == 1:
                    c = lerp(c, (90, 110, 112), 0.15)
            px[x, y] = c + (250,)
    d = ImageDraw.Draw(img)
    for cx in (16, 80):
        rivet(d, cx, band // 2, 3)
    img.save(os.path.join(OUT, "console.png"))


def porthole():
    """A riveted brass porthole ring for the unit portrait; transparent inside."""
    size = 176
    scale = 4
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = big / 2
    outer, inner = c - 2 * scale, c - 22 * scale
    rng = random.Random(3)
    # Ring shaded by angle: lit from the top left.
    steps = 360
    for i in range(steps):
        a0 = 2 * math.pi * i / steps
        a1 = 2 * math.pi * (i + 1.5) / steps
        light = (math.cos(a0 - math.radians(225)) + 1) / 2
        col = lerp(BRASS_DARK, BRASS_LIGHT, light ** 1.3)
        col = metal(rng, col, 4)
        pts = [(c + outer * math.cos(a0), c + outer * math.sin(a0)),
               (c + outer * math.cos(a1), c + outer * math.sin(a1)),
               (c + inner * math.cos(a1), c + inner * math.sin(a1)),
               (c + inner * math.cos(a0), c + inner * math.sin(a0))]
        d.polygon(pts, fill=col + (255,))
    for r, col, width in [(outer, OUTLINE, 2), (inner, OUTLINE, 3), (inner - 3 * scale, GLOW, 1),
                          (c - 12 * scale, BRASS_DARK, 1)]:
        d.ellipse((c - r, c - r, c + r, c + r), outline=col + (255,), width=width * scale)
    img = img.resize((size, size), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    for i in range(12):
        a = 2 * math.pi * i / 12 + math.pi / 12
        rivet(d, int(size / 2 + (size / 2 - 12) * math.cos(a)), int(size / 2 + (size / 2 - 12) * math.sin(a)), 3)
    img.save(os.path.join(OUT, "porthole.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    panel()
    buttons()
    console()
    porthole()
    print("wrote UI textures to", os.path.normpath(OUT))
