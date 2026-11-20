"""Draws APK Sandbox's app icon and writes Sources/Assets.xcassets/AppIcon.appiconset.

    python3 Tools/AppIcon/make_appicon.py      (needs Pillow)
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "Sources", "Assets.xcassets", "AppIcon.appiconset")
S = 1024


def draw():
    img = Image.new("RGB", (S, S))
    top, bottom = (61, 220, 132), (12, 110, 90)
    px = img.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(S):
            px[x, y] = c
    d = ImageDraw.Draw(img)
    # A phone: white body, dark screen, Android-style nav keys.
    body = (300, 150, 724, 874)
    d.rounded_rectangle(body, radius=70, fill=(255, 255, 255))
    screen = (334, 220, 690, 760)
    d.rounded_rectangle(screen, radius=20, fill=(24, 32, 40))
    # Three app "icons" on the screen.
    for i, col in enumerate([(66, 133, 244), (234, 67, 53), (251, 188, 5)]):
        cx = 400 + i * 112
        d.ellipse((cx - 38, 300 - 38, cx + 38, 300 + 38), fill=col)
    # "APK" on the screen.
    font = None
    for name in ["DejaVuSans-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "Arial Bold.ttf"]:
        try:
            font = ImageFont.truetype(name, 150)
            break
        except OSError:
            pass
    if font is None:
        font = ImageFont.load_default()
    text = "APK"
    box = d.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((S - tw) / 2 - box[0], 470 - box[1]), text, font=font, fill=(61, 220, 132))
    # Nav bar: back triangle, home circle, recents square.
    y = 817
    d.polygon([(420, y), (452, y - 20), (452, y + 20)], outline=(60, 60, 60), width=6)
    d.ellipse((492, y - 20, 532, y + 20), outline=(60, 60, 60), width=6)
    d.rectangle((574, y - 18, 610, y + 18), outline=(60, 60, 60), width=6)
    return img


SIZES = [  # (points, scale, idiom)
    (20, 2, "iphone"), (20, 3, "iphone"), (29, 2, "iphone"), (29, 3, "iphone"),
    (40, 2, "iphone"), (40, 3, "iphone"), (60, 2, "iphone"), (60, 3, "iphone"),
    (1024, 1, "ios-marketing"),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    base = draw()
    images = []
    for pt, scale, idiom in SIZES:
        px = int(pt * scale)
        name = "icon-%d.png" % px
        base.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append({"size": "%dx%d" % (pt, pt), "idiom": idiom, "filename": name, "scale": "%dx" % scale})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"version": 1, "author": "xcode"}}, f, indent=2)


main()
