#!/usr/bin/env python3
"""Make the Android app icons for E.D.I.T.H.

Run from the edith_app folder:

    pip install pillow            (only if Pillow is missing)
    python3 tools/make_icons.py                  # draws the neon "E"
    python3 tools/make_icons.py app_icon.jpg     # uses YOUR picture

It writes:
  - android/app/src/main/res/mipmap-*/ic_launcher.png            (old style)
  - android/app/src/main/res/mipmap-*/ic_launcher_foreground.png (adaptive)
  - android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  - android/app/src/main/res/values/ic_launcher_background.xml
Correct sizes: mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192
(adaptive foreground: 108, 162, 216, 324, 432).
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

BG = (11, 15, 20)          # #0B0F14
CYAN = (47, 224, 255)      # #2FE0FF
CORE = (200, 248, 255)

RES = os.path.join('android', 'app', 'src', 'main', 'res')
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
S = 1024


def neon_e_layer():
    """Transparent 1024x1024 layer with a glowing neon E."""
    bars = [(322, 287, 402, 737), (322, 287, 702, 367),
            (322, 472, 642, 552), (322, 657, 702, 737)]
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    for b in bars:
        d.rounded_rectangle(b, radius=40, fill=CYAN + (255,))
    core = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    dc = ImageDraw.Draw(core)
    for x0, y0, x1, y1 in bars:
        dc.rounded_rectangle((x0 + 22, y0 + 22, x1 - 22, y1 - 22),
                             radius=18, fill=CORE + (255,))
    wide = base.filter(ImageFilter.GaussianBlur(34))
    tight = base.filter(ImageFilter.GaussianBlur(11))
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for layer in (wide, wide, tight, base, core):
        out = Image.alpha_composite(out, layer)
    return out


def picture_layer(path):
    im = Image.open(path).convert('RGB')
    w, h = im.size
    side = min(w, h)
    im = im.crop(((w - side) // 2, (h - side) // 2,
                  (w + side) // 2, (h + side) // 2)).resize((S, S), Image.LANCZOS)
    return im


def rounded_mask(size, radius_frac=0.22):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1),
                                        radius=int(size * radius_frac), fill=255)
    return m


def main():
    pic = sys.argv[1] if len(sys.argv) > 1 else None
    if pic:
        photo = picture_layer(pic)
        bg_color = photo.getpixel((6, 6))
        legacy_src = photo.convert('RGBA')
        # Adaptive foreground: the picture, scaled into the safe zone.
        fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        inner = photo.resize((int(S * 0.64), int(S * 0.64)), Image.LANCZOS)
        fg.paste(inner, ((S - inner.width) // 2, (S - inner.height) // 2))
    else:
        bg_color = BG
        legacy_src = Image.new('RGBA', (S, S), BG + (255,))
        legacy_src = Image.alpha_composite(legacy_src, neon_e_layer())
        fg = neon_e_layer()

    for density, px in LEGACY.items():
        folder = os.path.join(RES, 'mipmap-' + density)
        os.makedirs(folder, exist_ok=True)
        icon = legacy_src.resize((px, px), Image.LANCZOS)
        icon.putalpha(ImageChops.multiply(icon.getchannel('A'), rounded_mask(px)))
        icon.save(os.path.join(folder, 'ic_launcher.png'))

    for density, px in ADAPTIVE.items():
        folder = os.path.join(RES, 'mipmap-' + density)
        os.makedirs(folder, exist_ok=True)
        fg.resize((px, px), Image.LANCZOS).save(
            os.path.join(folder, 'ic_launcher_foreground.png'))

    any_dir = os.path.join(RES, 'mipmap-anydpi-v26')
    os.makedirs(any_dir, exist_ok=True)
    with open(os.path.join(any_dir, 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    values = os.path.join(RES, 'values')
    os.makedirs(values, exist_ok=True)
    hexcol = '#%02X%02X%02X' % tuple(bg_color[:3])
    with open(os.path.join(values, 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">%s</color>\n'
                '</resources>\n' % hexcol)
    print('Icons written. Background colour', hexcol)


if __name__ == '__main__':
    main()
