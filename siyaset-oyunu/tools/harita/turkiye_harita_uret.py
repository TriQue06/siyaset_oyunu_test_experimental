"""Türkiye haritası üreticisi -> data/turkiye_altigen.json

Kaynak (projeksiyon_hesaplayici deposu, aynı sahip):
  * TR-adm2-with-city-borders.svg, g#iller: 81 ilin gerçek dış sınırı.
  * koltuk_verisi.json: güncel milletvekili dağılımı (seçim çevresi başına;
    İstanbul/Ankara/İzmir/Bursa çevreleri il olarak toplanır).

Çıktı GameMap biçimindedir (HexGridGenerator.generate ile aynı alanlar):
  {cols, rows, hex_radius, cells, regions[{id, name, seats, coastal, electorate}]}
Altıgen (B): 80 sütunluk "odd-r" ızgara; her altıgen merkezinin düştüğü ile
aittir, altıgen alamayan küçük il merkezine en yakın altıgeni alır.
Harita genişliği rastgele haritayla aynı tutulur (hex_radius küçülür): vekil
noktaları ve simgeler aynı boyda kalır.

Çalıştırma (siyaset-oyunu klasöründen):
  python tools/harita/turkiye_harita_uret.py [projeksiyon_hesaplayici yolu]
"""
import json, math, os, re, sys, html

KAYNAK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', '..', '..', 'projeksiyon_hesaplayici')
SVG = os.path.join(KAYNAK, 'TR-adm2-with-city-borders.svg')
KOLTUK = os.path.join(KAYNAK, 'koltuk_verisi.json')
X0, Y0, W, H = 1.0, 0.0, 1436.0, 629.0
HEDEF_GENISLIK = 771.0  # rastgele haritanın genişliği (44 sütun, yarıçap 10)
KENAR = 2               # haritanın çevresinde deniz halkası (altıgen)
VOTERS_PER_SEAT = 100000
SADELESTIRME = 0.35     # net sınırlar: Douglas-Peucker toleransı (SVG birimi)

svg = open(SVG, encoding='utf-8').read()
iller = svg[svg.find('id="iller"'):]
provs = []
for gid, plaka, ad, govde in re.findall(r'<g id="([^"]+)" iso2="TR-(\d+)" title="([^"]+)">(.*?)</g>', iller, re.S):
    polys = []
    for d in re.findall(r'\sd="([^"]+)"', govde):
        for parca in re.split(r'[Mm]', d):
            sayi = list(map(float, re.findall(r'-?\d+\.?\d*(?:e-?\d+)?', parca)))
            pts = list(zip(sayi[0::2], sayi[1::2]))
            if len(pts) > 2:
                polys.append(pts)
    xs = [x for p in polys for x, _ in p]; ys = [y for p in polys for _, y in p]
    provs.append({'ad': html.unescape(ad), 'plaka': int(plaka), 'polys': polys, 'bb': (min(xs), min(ys), max(xs), max(ys))})
provs.sort(key=lambda p: p['plaka'])
assert len(provs) == 81, len(provs)

koltuk = json.load(open(KOLTUK, encoding='utf-8'))
il_koltuk = {}
for cevre, n in koltuk.items():
    il = re.sub(r'\s*\d+\.\s*Bölge$', '', cevre)
    il_koltuk[il] = il_koltuk.get(il, 0) + int(n)
for p in provs:
    assert p['ad'] in il_koltuk, p['ad']
    p['koltuk'] = il_koltuk[p['ad']]
assert sum(p['koltuk'] for p in provs) == sum(koltuk.values())

def icinde(x, y, poly):
    c = False; j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]; xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c

def sahibi(x, y):
    for k, p in enumerate(provs):
        b = p['bb']
        if b[0] <= x <= b[2] and b[1] <= y <= b[3] and sum(icinde(x, y, q) for q in p['polys']) % 2:
            return k
    return -1

def izgara(sutun):
    r = W / (sutun * math.sqrt(3)); w = math.sqrt(3) * r; dy = 1.5 * r
    cols = sutun + 1 + 2 * KENAR
    rows = int(H / dy) + 2 + 2 * KENAR
    ox, oy = X0 - KENAR * w, Y0 - KENAR * dy
    merkez = lambda c, rw: (ox + w * (c + 0.5 * (rw & 1)), oy + dy * rw)
    cells = []
    for rw in range(rows):
        for c in range(cols):
            cells.append(sahibi(*merkez(c, rw)))
    for k, p in enumerate(provs):
        if k in cells:
            continue
        b = p['bb']; cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        en = min(range(len(cells)), key=lambda i: (merkez(i % cols, i // cols)[0] - cx) ** 2 + (merkez(i % cols, i // cols)[1] - cy) ** 2)
        cells[en] = k
    R = HEDEF_GENISLIK / (math.sqrt(3) * (cols + 0.5))
    s = R / r
    # SVG -> oyun birimi (GameMap.cell_center ile aynı yerleşim).
    donustur = lambda x, y: ((x - ox) * s + math.sqrt(3) * R * 0.5, (y - oy) * s + R)
    return cols, rows, R, cells, donustur

def komsular(i, cols, rows):
    c, rw = i % cols, i // cols
    ofs = [(1, 0), (-1, 0), (1, -1), (0, -1), (1, 1), (0, 1)] if rw & 1 else [(1, 0), (-1, 0), (0, -1), (-1, -1), (0, 1), (-1, 1)]
    for dx, dy in ofs:
        x, y = c + dx, rw + dy
        if 0 <= x < cols and 0 <= y < rows:
            yield y * cols + x

def bolgeler(cells, cols, rows):
    kiyi = [False] * 81
    for i, k in enumerate(cells):
        if k >= 0 and not kiyi[k] and any(cells[n] == -1 for n in komsular(i, cols, rows)):
            kiyi[k] = True
    return [{'id': 'b%02d' % p['plaka'], 'name': p['ad'], 'seats': p['koltuk'], 'coastal': kiyi[k],
             'electorate': p['koltuk'] * VOTERS_PER_SEAT} for k, p in enumerate(provs)]

def sadelestir(pts, tol):
    if len(pts) < 4:
        return pts
    def dp(a, b):
        (x1, y1), (x2, y2) = pts[a], pts[b]
        L = math.hypot(x2 - x1, y2 - y1) or 1e-9
        en, ei = 0.0, -1
        for i in range(a + 1, b):
            d = abs((x2 - x1) * (y1 - pts[i][1]) - (x1 - pts[i][0]) * (y2 - y1)) / L
            if d > en:
                en, ei = d, i
        if en > tol:
            return dp(a, ei)[:-1] + dp(ei, b)
        return [pts[a], pts[b]]
    m = len(pts) // 2
    return dp(0, m)[:-1] + dp(m, len(pts) - 1)

def yaz(ad, veri):
    yol = os.path.join(os.path.dirname(__file__), '..', '..', 'data', ad)
    with open(yol, 'w', encoding='utf-8') as f:
        json.dump(veri, f, ensure_ascii=False, separators=(',', ':'))
    print(ad, os.path.getsize(yol) // 1024, 'KB')

sys.setrecursionlimit(10000)
cols, rows, R, cells, _ = izgara(80)
yaz('turkiye_altigen.json', {'preset': 'turkiye_altigen', 'cols': cols, 'rows': rows, 'hex_radius': round(R, 5),
     'cells': cells, 'regions': bolgeler(cells, cols, rows)})
print('altıgen:', cols, 'x', rows, sum(1 for c in cells if c >= 0), 'kara altıgeni')

