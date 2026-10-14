"""Afet gazetesi resimleri (0.0.181): düz renkli, köşeli çizim dili.

    python tools/make_disaster_art.py   -> assets/disasters/<tür>.png (336x456)

Kart resimleriyle aynı tarz: sınırlı palet, kalın koyu kontur yok, büyük
geometrik biçimler. Her tür tek bir okunur sahne.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 336, 456
OUT = Path(__file__).resolve().parent.parent / "assets" / "disasters"
INK = (16, 13, 34)


def sky(d, top, bottom):
    for y in range(H):
        k = y / H
        c = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(3))
        d.line([(0, y), (W, y)], fill=c)


def house(d, x, y, w, h, wall, roof, tilt=0.0):
    def rot(px, py):
        cx, cy = x + w / 2, y + h
        dx, dy = px - cx, py - cy
        c, s = math.cos(tilt), math.sin(tilt)
        return (cx + dx * c - dy * s, cy + dx * s + dy * c)
    body = [rot(x, y), rot(x + w, y), rot(x + w, y + h), rot(x, y + h)]
    d.polygon(body, fill=wall)
    d.polygon([rot(x - 6, y), rot(x + w / 2, y - h * 0.55), rot(x + w + 6, y)], fill=roof)
    for wx in (0.2, 0.6):
        d.polygon([rot(x + w * wx, y + h * 0.25), rot(x + w * (wx + 0.2), y + h * 0.25),
                   rot(x + w * (wx + 0.2), y + h * 0.5), rot(x + w * wx, y + h * 0.5)], fill=(255, 214, 102))


def sel():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky(d, (58, 70, 110), (120, 140, 170))
    for i in range(40):  # yağmur
        x, y = random.randint(0, W), random.randint(0, 260)
        d.line([(x, y), (x - 6, y + 18)], fill=(200, 215, 240), width=2)
    house(d, 40, 210, 90, 80, (230, 220, 200), (200, 60, 50))
    house(d, 190, 230, 100, 70, (210, 200, 230), (80, 80, 160))
    d.rectangle([0, 280, W, H], fill=(40, 110, 200))
    for row in range(8):
        y = 290 + row * 22
        pts = []
        for x in range(0, W + 20, 20):
            pts.append((x, y + (6 if (x // 20 + row) % 2 else -6)))
        d.line(pts, fill=(140, 200, 255), width=4)
    d.polygon([(130, 300), (180, 300), (175, 312), (135, 312)], fill=(120, 80, 40))  # sürüklenen sandal
    return img


def deprem():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky(d, (90, 60, 50), (200, 140, 90))
    d.rectangle([0, 300, W, H], fill=(110, 80, 60))
    house(d, 30, 200, 80, 100, (220, 210, 190), (160, 60, 40), tilt=-0.18)
    house(d, 200, 170, 90, 130, (200, 190, 210), (90, 70, 140), tilt=0.22)
    d.rectangle([120, 240, 180, 300], fill=(180, 170, 160))
    # yarık
    pts = [(150, 300), (140, 330), (165, 355), (135, 385), (160, 420), (145, 456)]
    d.line(pts, fill=INK, width=12)
    d.line([(150, 300), (110, 315)], fill=INK, width=6)
    d.line([(165, 355), (220, 370)], fill=INK, width=6)
    for i in range(30):  # toz
        x, y = random.randint(0, W), random.randint(250, 310)
        r = random.randint(6, 16)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(170, 140, 110))
    return img


def yangin():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky(d, (60, 20, 30), (230, 110, 40))
    d.rectangle([0, 330, W, H], fill=(50, 35, 30))
    for i, x in enumerate(range(10, W, 46)):
        base = 340 + (i % 2) * 8
        d.rectangle([x + 16, base - 30, x + 24, base], fill=(60, 40, 30))
        d.polygon([(x, base - 30), (x + 20, base - 120), (x + 40, base - 30)], fill=(30, 60, 40))
        # alev
        fh = random.randint(70, 130)
        d.polygon([(x - 2, base - 40), (x + 10, base - fh), (x + 20, base - fh * 0.7),
                   (x + 30, base - fh - 20), (x + 42, base - 40)], fill=(255, 120, 30))
        d.polygon([(x + 8, base - 45), (x + 20, base - fh * 0.6), (x + 32, base - 45)], fill=(255, 210, 80))
    for i in range(14):  # duman
        x, y = random.randint(0, W), random.randint(20, 160)
        r = random.randint(18, 40)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(80, 60, 70))
    return img


def heyelan():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky(d, (90, 110, 140), (170, 180, 190))
    d.polygon([(0, 120), (W, 300), (W, H), (0, H)], fill=(70, 120, 60))
    d.polygon([(40, 150), (200, 230), (W, 360), (W, H), (120, H), (60, 300)], fill=(140, 95, 55))
    for i in range(16):
        x, y = random.randint(60, W - 20), random.randint(230, 420)
        r = random.randint(8, 20)
        d.polygon([(x - r, y), (x - r * 0.3, y - r), (x + r, y - r * 0.4), (x + r * 0.6, y + r * 0.6)], fill=(100, 80, 70))
    d.line([(0, 400), (W, 380)], fill=(60, 60, 70), width=22)  # yol
    d.line([(0, 400), (W, 380)], fill=(240, 220, 120), width=2)
    house(d, 220, 300, 70, 60, (220, 210, 190), (170, 60, 40), tilt=0.3)
    return img


def cig():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    sky(d, (70, 110, 170), (180, 210, 235))
    d.polygon([(-40, 380), (140, 80), (330, 380)], fill=(110, 120, 150))
    d.polygon([(90, 170), (140, 80), (190, 170), (165, 160), (140, 185), (115, 160)], fill=(245, 250, 255))
    d.polygon([(140, 120), (W + 40, 260), (W + 40, 420), (150, 330)], fill=(230, 240, 250))
    for i in range(24):  # kar bulutu
        x, y = random.randint(150, W), random.randint(260, 420)
        r = random.randint(14, 34)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(250, 252, 255))
    d.rectangle([0, 400, W, H], fill=(235, 240, 248))
    house(d, 30, 330, 80, 70, (180, 120, 80), (120, 40, 40))
    for x in range(140, 190, 18):  # çam
        d.polygon([(x, 410), (x + 9, 370), (x + 18, 410)], fill=(30, 80, 60))
    return img


def main():
    random.seed(1950)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in [("sel", sel), ("deprem", deprem), ("yangin", yangin), ("heyelan", heyelan), ("cig", cig)]:
        fn().save(OUT / f"{name}.png")
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
