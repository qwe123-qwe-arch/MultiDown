#!/usr/bin/env python3
"""生成 MultiDown 的 1024×1024 App 图标（无 alpha，iOS 要求）。
由 CI 在 xcodebuild 之前调用，写入 Assets.xcassets/AppIcon.appiconset/。
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4                      # 超采样倍数
W = 1024 * S
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def make_background(size):
    """对角线渐变 + 两块柔光，避免纯色平板感。"""
    top = (74, 163, 255)
    bottom = (6, 52, 168)
    base = Image.new("RGB", (64, 64))
    px = base.load()
    for y in range(64):
        for x in range(64):
            t = (x * 0.35 + y * 0.65) / 63.0
            px[x, y] = lerp(top, bottom, t)
    bg = base.resize((size, size), Image.BICUBIC)

    glow = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(glow)
    d.ellipse([-size * 0.35, -size * 0.45, size * 0.85, size * 0.55], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.18))
    bg = Image.composite(Image.new("RGB", (size, size), (125, 195, 255)), bg, glow)

    dark = Image.new("L", (size, size), 0)
    d2 = ImageDraw.Draw(dark)
    d2.ellipse([size * 0.35, size * 0.45, size * 1.35, size * 1.35], fill=120)
    dark = dark.filter(ImageFilter.GaussianBlur(size * 0.2))
    return Image.composite(Image.new("RGB", (size, size), (4, 32, 120)), bg, dark)


def draw_icon():
    img = make_background(W)

    # 白色前景画在单独的透明层
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(fg)

    k = W / 1024.0
    # 三条竖条 = 三条线程，作为箭头的“杆”
    bar_w, gap = 118, 46
    bar_top, bar_bottom = 236, 586
    radius = bar_w / 2
    total = bar_w * 3 + gap * 2
    left = (1024 - total) / 2
    for i in range(3):
        x0 = left + i * (bar_w + gap)
        d.rounded_rectangle(
            [x0 * k, bar_top * k, (x0 + bar_w) * k, bar_bottom * k],
            radius=radius * k,
            fill=(255, 255, 255, 255),
        )

    # 箭头三角
    tip = (512 * k, 812 * k)
    left_pt = ((512 - 252) * k, 520 * k)
    right_pt = ((512 + 252) * k, 520 * k)
    d.polygon([left_pt, right_pt, tip], fill=(255, 255, 255, 255))

    # 底部托盘线
    d.rounded_rectangle(
        [272 * k, 880 * k, 752 * k, 926 * k],
        radius=23 * k,
        fill=(255, 255, 255, 255),
    )

    # 不做投影：iOS 图标在小尺寸下要干净，投影会糊成一圈灰边
    img = img.convert("RGBA")
    img.alpha_composite(fg)

    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main():
    icon = draw_icon()
    icon.save(os.path.join(OUT_DIR, "icon-1024.png"), "PNG", optimize=True)
    contents = {
        "images": [
            {
                "filename": "icon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, indent=2, ensure_ascii=False)
        fp.write("\n")
    print("icon written to", OUT_DIR)


if __name__ == "__main__":
    main()
