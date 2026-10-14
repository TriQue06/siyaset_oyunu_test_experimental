"""PIKSEL ARAYÜZ DOKULARI (Konsept C).

Oyunun bütün panel/buton zeminleri buradan üretilir. Kural değişmedi: Godot
tarafında prosedürel çizim yok, görünen her şey bir PNG. Burası o PNG'lerin
TEK kaynağı; renkleri değiştirmek için PALETTE'i düzenleyip yeniden çalıştır:

    python tools/make_ui_art.py

Tarz: 3 piksel koyu dış çizgi, içeride üstten açık / alttan koyu pah (bevel),
düz dolgu. 16x16 üretilir, Godot 9-slice ile her boyuta esnetir; kenarlar
esnemediği için çizgiler her boyutta tam 3 piksel kalır.
"""

import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets" / "ui"

# --- PALET (scripts/ui_theme.gd ile aynı olmalı) ---------------------------
INK = (0x10, 0x0D, 0x22)          # dış çizgi / sert gölge
PANEL = (0x2B, 0x23, 0x52)        # panel dolgusu
PANEL_LIGHT = (0x4A, 0x3F, 0x7A)  # üst-sol pah
PANEL_SHADE = (0x1C, 0x17, 0x38)  # alt-sağ pah
DARK = (0x1C, 0x17, 0x38)         # koyu panel dolgusu
DARK_LIGHT = (0x34, 0x2C, 0x5E)
SLOT = (0x10, 0x0D, 0x22)         # oyuk (kart yuvası) dolgusu
BUTTON = (0x4A, 0x3F, 0x7A)
BUTTON_LIGHT = (0x6B, 0x5F, 0xA8)
BUTTON_SHADE = (0x2E, 0x26, 0x52)
BUTTON_HOVER = (0x5E, 0x51, 0xA0)
BUTTON_HOVER_LIGHT = (0x82, 0x72, 0xBE)
BUTTON_PRESSED = (0x3A, 0x31, 0x63)
BUTTON_OFF = (0x24, 0x1E, 0x45)
BUTTON_OFF_LIGHT = (0x2E, 0x27, 0x52)
GOLD = (0xFF, 0xC9, 0x3C)
GREEN = (0x4B, 0xE0, 0x8A)
GREEN_DARK = (0x25, 0x8F, 0x53)
RED = (0xE8, 0x40, 0x2A)
RED_DARK = (0x8E, 0x22, 0x15)
GREY = (0x4A, 0x3F, 0x7A)
GREY_DARK = (0x2E, 0x26, 0x52)
WHITE = (0xF2, 0xEF, 0xFF)
TEXT_DIM = (0x6B, 0x62, 0xA0)


def write_png(path: Path, pixels, width: int, height: int) -> None:
    """pixels: (r, g, b, a) dörtlülerinden oluşan satır listesi."""
    raw = b""
    for y in range(height):
        raw += b"\x00"
        for x in range(width):
            raw += bytes(pixels[y][x])

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


def blank(width: int, height: int):
    return [[(0, 0, 0, 0) for _ in range(width)] for _ in range(height)]


def fill(px, color, x0, y0, x1, y1):
    """[x0, x1) x [y0, y1) dikdörtgenini boyar."""
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[y][x] = (color[0], color[1], color[2], 255)


def beveled(size, outline, body, light, shade, border=3, bevel=2, inset=False):
    """Dış çizgi + pah + dolgu. inset=True: pah ters (basılı/oyuk görünüm)."""
    px = blank(size, size)
    fill(px, outline, 0, 0, size, size)
    fill(px, body, border, border, size - border, size - border)
    top, bottom = (shade, light) if inset else (light, shade)
    # üst ve sol
    fill(px, top, border, border, size - border, border + bevel)
    fill(px, top, border, border, border + bevel, size - border)
    # alt ve sağ
    fill(px, bottom, border, size - border - bevel, size - border, size - border)
    fill(px, bottom, size - border - bevel, border, size - border, size - border)
    return px


def ring(size, color, width=3):
    """Sadece çerçeve (içi saydam) — hedef vurgusu için."""
    px = blank(size, size)
    fill(px, color, 0, 0, size, size)
    for y in range(width, size - width):
        for x in range(width, size - width):
            px[y][x] = (0, 0, 0, 0)
    return px


def stamp(px, color, points, ox=0, oy=0, thick=2):
    """Verilen (x, y) noktalarını thick x thick kare olarak basar (piksel çizim)."""
    for (x, y) in points:
        fill(px, color, ox + x, oy + y, ox + x + thick, oy + y + thick)


## Onay işareti (evet) ve çarpı (hayır). 24x24 dokunun ORTASINA, 3 piksel
## kalınlığında. Buton dokuyu esnettiği için işaret ortada dursun diye
## koordinatlar simetrik seçildi.
CHECK = [(5, 11), (7, 13), (9, 15), (11, 13), (13, 11), (15, 9), (17, 7)]
CROSS = [(6, 6), (8, 8), (10, 10), (12, 12), (14, 14), (16, 16),
         (16, 6), (14, 8), (12, 10), (10, 12), (8, 14), (6, 16)]


def with_glyph(px, points, color):
    stamp(px, color, points, thick=3)
    return px


def make(name, px, size):
    write_png(OUT / f"{name}.png", px, size, size)
    print("yazildi:", name)


def main() -> None:
    S = 16
    make("ui_panel", beveled(S, INK, PANEL, PANEL_LIGHT, PANEL_SHADE), S)
    make("ui_panel_dark", beveled(S, INK, DARK, DARK_LIGHT, INK), S)
    make("ui_slot", beveled(S, PANEL_LIGHT, SLOT, INK, PANEL_LIGHT, border=3, bevel=2, inset=True), S)
    make("ui_button_normal", beveled(S, INK, BUTTON, BUTTON_LIGHT, BUTTON_SHADE), S)
    make("ui_button_hover", beveled(S, INK, BUTTON_HOVER, GOLD, BUTTON_SHADE), S)
    make("ui_button_pressed", beveled(S, INK, BUTTON_PRESSED, BUTTON_SHADE, BUTTON_LIGHT, inset=True), S)
    make("ui_button_disabled", beveled(S, INK, BUTTON_OFF, BUTTON_OFF_LIGHT, INK), S)
    # Tema kaynağı olarak da aynı dokular kullanılsın (eski 200x56'lar yerine).
    make("button_normal", beveled(S, INK, BUTTON, BUTTON_LIGHT, BUTTON_SHADE), S)
    make("button_hover", beveled(S, INK, BUTTON_HOVER, GOLD, BUTTON_SHADE), S)
    make("button_pressed", beveled(S, INK, BUTTON_PRESSED, BUTTON_SHADE, BUTTON_LIGHT, inset=True), S)
    make("button_disabled", beveled(S, INK, BUTTON_OFF, BUTTON_OFF_LIGHT, INK), S)
    make("target_highlight", ring(S, GOLD), S)
    # Düz dolgu (beyaz): modulate ile herhangi bir renge boyanır. Çubuk dolgusu,
    # renk yüzeyleri ve ayraçlar bunu kullanır — kodda ColorRect yerine PNG.
    plain = blank(S, S)
    fill(plain, WHITE, 0, 0, S, S)
    make("ui_fill", plain, S)
    # RENKLENDİRİLEBİLİR buton: gövde gri tonlarında, modulate ile istenen renge
    # boyanır (çarpma olduğu için koyu dış çizgi koyu kalır, pah tonları korunur).
    tint = (0xFF, 0xFF, 0xFF)
    body_tone = (0xBF, 0xBF, 0xBF)
    dark_tone = (0x80, 0x80, 0x80)
    make("ui_button_tint_normal", beveled(S, INK, body_tone, tint, dark_tone), S)
    make("ui_button_tint_hover", beveled(S, INK, tint, tint, body_tone), S)
    make("ui_button_tint_pressed", beveled(S, INK, dark_tone, dark_tone, body_tone, inset=True), S)
    # İnce çubuk yuvası: 2 piksel koyu çizgi, içi oyuk.
    track = blank(S, S)
    fill(track, INK, 0, 0, S, S)
    fill(track, (0x24, 0x1E, 0x45), 2, 2, S - 2, S - 2)
    make("ui_track", track, S)
    # Kaydırıcı tutamağı: altın kare, koyu çerçeve.
    G = 14
    grab = blank(G, G)
    fill(grab, INK, 0, 0, G, G)
    fill(grab, GOLD, 2, 2, G - 2, G - 2)
    fill(grab, (0xFF, 0xE2, 0x8A), 2, 2, G - 2, 5)
    write_png(OUT / "ui_grabber.png", grab, G, G)
    print("yazildi: ui_grabber")

    V = 24
    make("vote_yes_normal", with_glyph(beveled(V, INK, GREEN_DARK, GREEN, INK), CHECK, WHITE), V)
    make("vote_yes_hover", with_glyph(beveled(V, INK, GREEN, WHITE, GREEN_DARK), CHECK, INK), V)
    make("vote_yes_pressed", with_glyph(beveled(V, INK, GREEN_DARK, INK, GREEN, inset=True), CHECK, WHITE), V)
    make("vote_yes_disabled", with_glyph(beveled(V, INK, GREY_DARK, GREY, INK), CHECK, TEXT_DIM), V)
    make("vote_no_normal", with_glyph(beveled(V, INK, RED_DARK, RED, INK), CROSS, WHITE), V)
    make("vote_no_hover", with_glyph(beveled(V, INK, RED, WHITE, RED_DARK), CROSS, INK), V)
    make("vote_no_pressed", with_glyph(beveled(V, INK, RED_DARK, INK, RED, inset=True), CROSS, WHITE), V)
    make("vote_no_disabled", with_glyph(beveled(V, INK, GREY_DARK, GREY, INK), CROSS, TEXT_DIM), V)


if __name__ == "__main__":
    main()
