#!/usr/bin/env python3
"""把一张图片处理成 iOS 要求的 1024×1024 无 alpha 图标。

用法: python3 tools/prepare_icon.py <源图> <AppIcon.appiconset 目录>
"""
import json
import os
import sys

from PIL import Image

SIZE = 1024


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: prepare_icon.py <source-image> <output-dir>")
    src, out_dir = sys.argv[1], sys.argv[2]

    im = Image.open(src)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, (255, 255, 255))
        bg.paste(im, mask=im.split()[-1])
        im = bg
    else:
        im = im.convert("RGB")

    # 居中裁成正方形
    w, h = im.size
    side = min(w, h)
    im = im.crop(((w - side) // 2, (h - side) // 2, (w + side) // 2, (h + side) // 2))
    im = im.resize((SIZE, SIZE), Image.LANCZOS)

    os.makedirs(out_dir, exist_ok=True)
    im.save(os.path.join(out_dir, "icon-1024.png"), "PNG", optimize=True)
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
    with open(os.path.join(out_dir, "Contents.json"), "w", encoding="utf-8") as fp:
        json.dump(contents, fp, indent=2, ensure_ascii=False)
        fp.write("\n")
    print("icon prepared from", src, "->", out_dir)


if __name__ == "__main__":
    main()
