"""OYUN MASASI ARAYÜZ DOKULARI (board game teması, 0.0.176).

Eski "haber stüdyosu" piksel dokularının (tools/make_ui_art.py) yerine aynı
dosya adlarını üretir; Godot tarafı yine yalnız PNG okur. Eski temaya dönmek
için make_ui_art.py'yi çalıştırmak ve scripts/ui_theme.gd paletini geri almak
yeter (yedek: git dalı tema-haber-studyosu).

Tarz: ceviz ahşap paneller, krem kâğıt, pirinç vurgular, yuvarlak köşeler,
yumuşak gölge; zemin bordo keçe.

    python tools/make_board_art.py      (Pillow gerekir)
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"

# --- PALET (scripts/ui_theme.gd ile aynı olmalı) ---------------------------
INK = (0x1E, 0x12, 0x0A)
WOOD = (0x3B, 0x26, 0x17)
WOOD_LIGHT = (0x5A, 0x3C, 0x24)
WOOD_DARK = (0x2A, 0x1A, 0x10)
SLOT = (0x1A, 0x0F, 0x09)
CREAM = (0xF5, 0xEA, 0xD2)
CREAM_DIM = (0xC9, 0xB4, 0x8F)
BRASS = (0xE4, 0xB4, 0x3C)
BRASS_DARK = (0x9A, 0x74, 0x20)
FELT = (0x5A, 0x2A, 0x30)
FELT_DARK = (0x2E, 0x14, 0x18)
PAPER = (0xEF, 0xE3, 0xC8)
GREEN = (0x6F, 0xC2, 0x7A)
GREEN_DARK = (0x2F, 0x7A, 0x45)
RED = (0xD9, 0x47, 0x3A)
RED_DARK = (0x7E, 0x23, 0x1A)

S = 32        # 9-slice dokuların kenarı
R = 7         # köşe yarıçapı
random.seed(1952)


def rounded(size, radius, outline, body, border=2, light=None, shade=None, grain=0.0, inset=False, alpha=255):
    """Yuvarlak köşeli 9-slice dokusu: dış çizgi + gövde + üst ışık / alt gölge."""
    scale = 4  # kenar yumuşatma için büyük çizip küçült
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius * scale, fill=outline + (alpha,))
    b = border * scale
    d.rounded_rectangle([b, b, big - 1 - b, big - 1 - b], max(1, (radius - border) * scale), fill=body + (alpha,))
    if light or shade:
        top, bottom = (shade, light) if inset else (light, shade)
        band = 2 * scale
        if top:
            d.rounded_rectangle([b, b, big - 1 - b, b + band * 2], max(1, (radius - border) * scale), fill=top + (alpha,))
            d.rectangle([b, b + band, big - 1 - b, b + band * 2], fill=body + (alpha,))
        if bottom:
            d.rounded_rectangle([b, big - 1 - b - band * 2, big - 1 - b, big - 1 - b], max(1, (radius - border) * scale), fill=bottom + (alpha,))
            d.rectangle([b, big - 1 - b - band * 2, big - 1 - b, big - 1 - b - band], fill=body + (alpha,))
    img = img.resize((size, size), Image.LANCZOS)
    if grain > 0:
        px = img.load()
        for y in range(size):
            streak = random.uniform(-grain, grain)
            for x in range(size):
                r, g, bb, a = px[x, y]
                if a == 0:
                    continue
                k = 1.0 + streak + random.uniform(-grain, grain) * 0.4
                px[x, y] = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(bb * k)), a)
    return img


def ring(size, radius, color, width=3):
    img = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius * 4, outline=color + (255,), width=width * 4)
    return img.resize((size, size), Image.LANCZOS)


def save(img, name):
    img.save(OUT / f"{name}.png")
    print("yazildi:", name)


def felt(w=640, h=360):
    """Ekran zemini: ortası açık bordo keçe, kenarlara doğru koyulaşır, ince lif."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx = (x - w * 0.5) / (w * 0.6)
            dy = (y - h * 0.42) / (h * 0.7)
            t = min(1.0, math.sqrt(dx * dx + dy * dy))
            n = random.uniform(-0.035, 0.035)
            c = [int((FELT[i] * (1 - t) + FELT_DARK[i] * t) * (1 + n)) for i in range(3)]
            px[x, y] = tuple(max(0, min(255, v)) for v in c)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def coin(size, face, edge, rim_light):
    """Yuvarlak pirinç düğme (Turu Bitir zili)."""
    sc = 4
    img = Image.new("RGBA", (size * sc, size * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, size * sc - 1, size * sc - 1], fill=edge + (255,))
    m = 5 * sc
    d.ellipse([m, m, size * sc - 1 - m, size * sc - 1 - m], fill=face + (255,))
    m2 = 9 * sc
    d.ellipse([m2, m2, size * sc * 0.62, size * sc * 0.5], fill=rim_light + (110,))
    return img.resize((size, size), Image.LANCZOS)


def plaque(w, h, face, edge, light):
    """Pirinç plaka (Turu Bitir): kapsül biçimi, üstte parlama."""
    sc = 4
    img = Image.new("RGBA", (w * sc, h * sc), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = h * sc // 2
    d.rounded_rectangle([0, 0, w * sc - 1, h * sc - 1], r, fill=edge + (255,))
    m = 3 * sc
    d.rounded_rectangle([m, m, w * sc - 1 - m, h * sc - 1 - m], r - m, fill=face + (255,))
    d.rounded_rectangle([m * 3, m * 2, w * sc - 1 - m * 3, h * sc * 0.42], r // 2, fill=light + (90,))
    return img.resize((w, h), Image.LANCZOS)


def main() -> None:
    save(rounded(S, R, INK, WOOD, light=WOOD_LIGHT, shade=WOOD_DARK, grain=0.05), "ui_panel")
    save(rounded(S, R, INK, WOOD_DARK, light=WOOD, shade=SLOT, grain=0.05), "ui_panel_dark")
    save(rounded(S, R, WOOD_LIGHT, SLOT, light=SLOT, shade=WOOD_LIGHT, inset=True), "ui_slot")
    normal = rounded(S, R, CREAM_DIM, WOOD_LIGHT, light=(0x7A, 0x55, 0x36), shade=WOOD, grain=0.04)
    hover = rounded(S, R, BRASS, (0x6B, 0x48, 0x2C), light=(0x8A, 0x62, 0x3E), shade=WOOD, grain=0.04)
    pressed = rounded(S, R, BRASS, WOOD, light=WOOD_DARK, shade=WOOD_LIGHT, inset=True)
    disabled = rounded(S, R, (0x5A, 0x48, 0x38), WOOD_DARK, light=WOOD, shade=SLOT, alpha=235)
    for prefix in ("ui_button", "button"):
        save(normal, f"{prefix}_normal")
        save(hover, f"{prefix}_hover")
        save(pressed, f"{prefix}_pressed")
        save(disabled, f"{prefix}_disabled")
    save(ring(S, R, BRASS), "target_highlight")
    plain = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    save(plain, "ui_fill")
    # RENKLENDİRİLEBİLİR JETON (hamle ve oy düğmeleri): gri gövde + açık kenar;
    # modulate ile istenen renge boyanır, kenar o rengin açık tonu kalır.
    white = (0xFF, 0xFF, 0xFF)
    body = (0xC8, 0xC8, 0xC8)
    dark = (0x8C, 0x8C, 0x8C)
    save(rounded(S, 12, white, body, border=3, light=(0xE6, 0xE6, 0xE6), shade=dark), "ui_button_tint_normal")
    save(rounded(S, 12, white, white, border=3, light=white, shade=body), "ui_button_tint_hover")
    save(rounded(S, 12, white, dark, border=3, light=dark, shade=body, inset=True), "ui_button_tint_pressed")
    track = rounded(S, 6, INK, SLOT, border=2)
    save(track, "ui_track")
    g = Image.new("RGBA", (14 * 4, 14 * 4), (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse([0, 0, 55, 55], fill=BRASS_DARK + (255,))
    ImageDraw.Draw(g).ellipse([6, 6, 49, 49], fill=BRASS + (255,))
    save(g.resize((14, 14), Image.LANCZOS), "ui_grabber")
    # Yeni dokular: keçe zemin, kâğıt (harita paftası, meclis kartı), pirinç zil.
    save(felt(), "board_felt")
    save(rounded(S, 4, (0xB8, 0xA5, 0x80), PAPER, border=1, grain=0.02), "board_paper")
    save(plaque(64, 52, BRASS, BRASS_DARK, (0xFF, 0xF0, 0xB8)), "board_plaque")
    save(plaque(64, 52, (0xF2, 0xC8, 0x5A), BRASS_DARK, (0xFF, 0xFA, 0xD8)), "board_plaque_hover")
    save(plaque(64, 52, BRASS_DARK, (0x6B, 0x4F, 0x17), BRASS), "board_plaque_pressed")
    save(plaque(64, 52, (0x6E, 0x5A, 0x3A), (0x4A, 0x3A, 0x26), (0x8A, 0x76, 0x56)), "board_plaque_disabled")
    save(coin(96, BRASS, BRASS_DARK, (0xFF, 0xF0, 0xB8)), "board_bell")
    save(coin(96, (0xF2, 0xC8, 0x5A), BRASS_DARK, (0xFF, 0xFA, 0xD8)), "board_bell_hover")
    save(coin(96, BRASS_DARK, (0x6B, 0x4F, 0x17), BRASS), "board_bell_pressed")
    save(coin(96, (0x6E, 0x5A, 0x3A), (0x4A, 0x3A, 0x26), (0x8A, 0x76, 0x56)), "board_bell_disabled")


if __name__ == "__main__":
    main()
