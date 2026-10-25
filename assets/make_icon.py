#!/usr/bin/env python3
"""Generate QuickFlow's placeholder app icon (1024px PNG, transparent corners)."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
R = 232  # macOS-ish squircle radius


def gradient(top, bottom, size=S):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        # ease the blend so the light end holds a little longer
        e = t ** 0.85
        c = tuple(round(a + (b - a) * e) for a, b in zip(top, bottom))
        d.line([(0, y), (size, y)], fill=c)
    return img


def diagonal(img, top, bottom):
    """Overlay a diagonal light-to-dark wash for depth."""
    grad = Image.new("L", (S, S))
    px = grad.load()
    for y in range(S):
        for x in range(0, S, 8):
            v = (x * 0.55 + y * 0.45) / (S - 1)
            for dx in range(8):
                if x + dx < S:
                    px[x + dx, y] = int(255 * min(1, max(0, v)))
    wash = Image.composite(Image.new("RGB", (S, S), bottom), Image.new("RGB", (S, S), top), grad)
    return Image.blend(img, wash, 0.55)


def rounded_mask():
    m = Image.new("L", (S * 4, S * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S * 4 - 1, S * 4 - 1], radius=R * 4, fill=255)
    return m.resize((S, S), Image.Resampling.LANCZOS)


def glow(img, center, radius, strength=40):
    layer = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=strength)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.75))
    white = Image.new("RGB", (S, S), (255, 255, 255))
    return Image.composite(white, img, layer.point(lambda v: int(v * 0.30)))


def mic_icon(arcs=True):
    img = diagonal(gradient((88, 124, 250), (104, 38, 200)), (255, 255, 255), (56, 20, 140))
    img = glow(img, (360, 250), 460)

    d = ImageDraw.Draw(img)
    cw, ch = 232, 356
    cx, cy = S // 2, 392
    d.rounded_rectangle([cx - cw // 2, cy - ch // 2, cx + cw // 2, cy + ch // 2],
                        radius=cw // 2, fill=(255, 255, 255))
    # cradle arc
    aw = 420
    box = [cx - aw // 2, cy - 30, cx + aw // 2, cy + 360]
    d.arc(box, start=8, end=172, fill=(255, 255, 255), width=48)
    # stem + base
    d.rounded_rectangle([cx - 24, cy + 316, cx + 24, cy + 448], radius=24, fill=(255, 255, 255))
    d.rounded_rectangle([cx - 138, cy + 448, cx + 138, cy + 496], radius=24, fill=(255, 255, 255))
    if arcs:
        for i, r in enumerate((66, 116)):
            w = 32 - i * 5
            for sign in (-1, 1):
                x = cx + sign * (cw // 2 + 40 + i * 52)
                d.arc([x - r, cy - r - 40, x + r, cy + r - 40],
                      start=-64 if sign > 0 else 116, end=64 if sign > 0 else 244,
                      fill=(255, 255, 255), width=w)
    return img


def q_icon():
    img = diagonal(gradient((88, 122, 255), (124, 45, 214)), (255, 255, 255), (48, 16, 130))
    img = glow(img, (340, 260), 400)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 700)
    try:
        font.set_variation_by_name("Black")
    except Exception:
        pass
    text = "q"
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    x = (S - tw) / 2 - box[0]
    y = (S - th) / 2 - box[1] - 40
    d.text((x, y), text, font=font, fill=(255, 255, 255))
    # waveform tail: three bars where the q's descender ends
    bx = int(x + tw * 0.60)
    base = int(y + th * 0.74)
    for i, (h, w) in enumerate(((70, 34), (130, 34), (44, 34))):
        left = bx + i * 64
        d.rounded_rectangle([left, base - h, left + w, base + 46], radius=w // 2,
                            fill=(255, 255, 255, 235))
    return img


def compose(img):
    """Inset the squircle into Apple's icon grid and add a soft contact shadow."""
    art = 896
    scaled = img.resize((art, art), Image.Resampling.LANCZOS)
    mask = rounded_mask().resize((art, art), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("L", (art + 80, art + 80), 0)
    shadow.paste(mask, (40, 40))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    shadow_layer = Image.new("RGBA", shadow.size, (20, 12, 60, 0))
    shadow_layer.putalpha(shadow.point(lambda v: int(v * 0.34)))
    canvas.alpha_composite(shadow_layer, ((S - art) // 2 - 40, (S - art) // 2 - 26))
    canvas.alpha_composite(scaled, ((S - art) // 2, (S - art) // 2))
    return canvas


def main():
    variant = sys.argv[1] if len(sys.argv) > 1 else "mic"
    out = sys.argv[2] if len(sys.argv) > 2 else "icon-1024.png"
    if variant == "mic":
        img = mic_icon()
    elif variant == "mic-plain":
        img = mic_icon(arcs=False)
    else:
        img = q_icon()
    img = img.convert("RGBA")
    img.putalpha(rounded_mask())
    compose(img).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
