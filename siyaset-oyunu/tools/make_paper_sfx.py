"""Gazete çarpma sesi (assets/audio/ui/paper_slap.wav) — sentez, harici dosya yok.

Kısa filtrelenmiş gürültü patlaması (kâğıt şaplaması) + alçak bir tok vuruş;
uzun kuyruk yok (~0,18 sn). python tools/make_paper_sfx.py
"""
import math, random, struct, wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "ui"
random.seed(7)

def slap(length=0.18):
    n = int(RATE * length)
    out = []
    lp = 0.0
    for i in range(n):
        t = i / RATE
        noise = random.uniform(-1, 1)
        lp += 0.35 * (noise - lp)          # yumuşak alçak geçiren: hışırtı tonu
        crack = (noise - lp) * math.exp(-t * 55) * 0.55
        body = lp * math.exp(-t * 26) * 0.9
        thump = math.sin(2 * math.pi * (110 - 260 * t) * t) * math.exp(-t * 32) * 0.55
        v = (crack + body + thump) * min(1.0, i / 40.0)
        out.append(max(-1.0, min(1.0, v * 0.8)))
    return out

def write(name, samples):
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(s * 32000)) for s in samples))
    print("yazildi:", name)

write("paper_slap.wav", slap())
