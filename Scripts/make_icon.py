# -*- coding: utf-8 -*-
"""
生成「云手机」App 图标（全套尺寸），并写好 AppIcon.appiconset/Contents.json。

设计：蓝紫渐变底 + 白色手机轮廓，轮廓内含一朵云。
画布用 4 倍超采样后 LANCZOS 缩小，边缘平滑；输出 RGB 无 alpha（iOS 图标要求）。

用法：python Scripts/make_icon.py
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.stdout.reconfigure(encoding="utf-8")

ICONSET = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..", "Resources", "Assets.xcassets", "AppIcon.appiconset",
)
ICONSET = os.path.normpath(ICONSET)

BASE = 1024          # 设计坐标基准
SS = BASE * 4        # 超采样画布
TOP = (64, 132, 247)      # 顶部蓝
BOTTOM = (116, 58, 226)   # 底部紫


def _lerp(a, b, t):
    return tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3))


def build_master():
    # 1. 竖向渐变底
    img = Image.new("RGB", (SS, SS))
    d = ImageDraw.Draw(img)
    grad = Image.new("RGB", (1, SS))
    gp = grad.load()
    for y in range(SS):
        gp[0, y] = _lerp(TOP, BOTTOM, (y / (SS - 1)) ** 1.08)
    img = grad.resize((SS, SS), Image.NEAREST)
    d = ImageDraw.Draw(img)

    # 2. 左上角柔光，避免大色块发闷
    glow = Image.new("L", (SS, SS), 0)
    ImageDraw.Draw(glow).ellipse(
        [-SS * 0.30, -SS * 0.50, SS * 0.78, SS * 0.52], fill=255
    )
    glow = glow.filter(ImageFilter.GaussianBlur(SS * 0.11)).point(lambda v: int(v * 0.34))
    img = Image.composite(Image.new("RGB", (SS, SS), (255, 255, 255)), img, glow)

    # 3. 白色图形画在单独的蒙版上，再整体合成
    mask = Image.new("L", (SS, SS), 0)
    m = ImageDraw.Draw(mask)
    k = SS / BASE

    def box(x0, y0, x1, y1, r, **kw):
        m.rounded_rectangle(
            [x0 * k, y0 * k, x1 * k, y1 * k], radius=r * k, **kw
        )

    def circle(cx, cy, rad, **kw):
        m.ellipse([(cx - rad) * k, (cy - rad) * k, (cx + rad) * k, (cy + rad) * k], **kw)

    # 手机外框：白色描边 + 极淡的屏幕填充，避免中间发空
    ox, oy, ow = 296, 178, 40
    box(ox, oy, 1024 - ox, 846, 118, outline=255, width=int(ow * k), fill=34)
    # 听筒
    box(466, 240, 558, 258, 9, fill=255)
    # 底部指示条
    box(448, 776, 576, 794, 9, fill=255)

    # 云：底部圆角矩形 + 左右小圆 + 中间大圆（垂直居中于屏幕区）
    box(362, 536, 662, 618, 38, fill=255)
    circle(428, 536, 56, fill=255)
    circle(596, 538, 52, fill=255)
    circle(512, 490, 82, fill=255)

    white = Image.new("RGB", (SS, SS), (255, 255, 255))
    img = Image.composite(white, img, mask)
    return img.resize((BASE, BASE), Image.LANCZOS)


# Contents.json：传统多尺寸写法，兼容所有 Xcode 版本
SPECS = [
    ("iphone", "20x20", "2x", 40),
    ("iphone", "20x20", "3x", 60),
    ("iphone", "29x29", "2x", 58),
    ("iphone", "29x29", "3x", 87),
    ("iphone", "40x40", "2x", 80),
    ("iphone", "40x40", "3x", 120),
    ("iphone", "60x60", "2x", 120),
    ("iphone", "60x60", "3x", 180),
    ("ios-marketing", "1024x1024", "1x", 1024),
]


def main():
    os.makedirs(ICONSET, exist_ok=True)
    master = build_master()

    images = []
    for idiom, size, scale, px in SPECS:
        # 尺寸相同的（如 120px）只落一份文件，Contents.json 里复用
        name = f"icon_{size}_{scale.replace('x', '')}x.png"
        path = os.path.join(ICONSET, name)
        master.resize((px, px), Image.LANCZOS).save(path, "PNG", optimize=True)
        images.append(
            {"idiom": idiom, "size": size, "scale": scale, "filename": name}
        )
        print(f"  {name:<24} {px}x{px}")

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"==> {len(images)} icons written to {ICONSET}")


if __name__ == "__main__":
    main()
