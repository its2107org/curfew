#!/usr/bin/env python3
"""Draws Curfew's icons: the iPhone app (light, dark, tinted) and the Mac helper (all sizes)."""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
IOS = "App/Assets.xcassets/AppIcon.appiconset"
MAC = "Mac/Assets.xcassets/AppIcon.appiconset"


def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def artwork(moon, star, glow=True):
    """A crescent moon with a few stars, on a transparent layer."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    m = ImageDraw.Draw(mask)
    cx, cy, r = 470, 540, 300
    m.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    # Bite out of the top right makes the crescent.
    bx, by, br = cx + 150, cy - 110, 255
    m.ellipse([bx - br, by - br, bx + br, by + br], fill=0)
    solid = Image.new("RGBA", (S, S), moon + (255,))
    layer.paste(solid, (0, 0), mask)
    d = ImageDraw.Draw(layer)
    for x, y, rr in [(700, 300, 26), (800, 470, 16), (640, 450, 12), (850, 600, 18)]:
        # Four-pointed sparkle.
        d.polygon([(x, y - rr * 2.2), (x + rr * 0.5, y - rr * 0.5), (x + rr * 2.2, y), (x + rr * 0.5, y + rr * 0.5),
                   (x, y + rr * 2.2), (x - rr * 0.5, y + rr * 0.5), (x - rr * 2.2, y), (x - rr * 0.5, y - rr * 0.5)],
                  fill=star + (255,))
    if not glow:
        return layer
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(layer.filter(ImageFilter.GaussianBlur(36)))
    out.alpha_composite(layer)
    return out


MOON = (255, 214, 150)
STAR = (255, 240, 214)


def ios():
    os.makedirs(IOS, exist_ok=True)
    for name, top, bottom, moon, star, glow in [
        ("icon-light", (74, 64, 170), (22, 22, 70), MOON, STAR, True),
        ("icon-dark", (30, 26, 64), (6, 6, 16), MOON, STAR, True),
        ("icon-tinted", (24, 24, 24), (0, 0, 0), (236, 236, 236), (200, 200, 200), False),
    ]:
        bg = gradient(S, top, bottom).convert("RGBA")
        bg.alpha_composite(artwork(moon, star, glow))
        bg.convert("RGB").save(f"{IOS}/{name}.png")


def mac():
    """macOS icons sit inside a rounded square with a margin and a soft shadow."""
    os.makedirs(MAC, exist_ok=True)
    inner = 824
    tile = gradient(inner, (74, 64, 170), (22, 22, 70)).convert("RGBA")
    art = artwork(MOON, STAR).resize((inner, inner), Image.LANCZOS)
    tile.alpha_composite(art)
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], radius=185, fill=255)
    big = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([100, 112, 100 + inner, 112 + inner], radius=185, fill=(0, 0, 0, 110))
    big.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
    big.paste(tile, (100, 100), mask)
    images = []
    for points in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            px = points * scale
            name = f"mac-{points}@{scale}x.png"
            big.resize((px, px), Image.LANCZOS).save(f"{MAC}/{name}")
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
    with open(f"{MAC}/Contents.json", "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=1)
    with open("Mac/Assets.xcassets/Contents.json", "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=1)


ios()
mac()
print("Icons written")
