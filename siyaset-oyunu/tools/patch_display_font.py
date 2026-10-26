"""Lilita One'a Türkçe harfleri (İ Ş ş Ğ ğ) ekler. OFL: 'Lilita' ayrılmış ad,
bu yüzden değişmiş font 'Siyaset Display' adını taşır.
Nokta Lilita'nın i'sinden, çengel Lilita'nın cedilla'sından, kısa işareti
(breve) Paytone One'dan alınır."""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib.tables._g_l_y_f import GlyphComponent

src, paytone, out = sys.argv[1:4]
L = TTFont(src)
P = TTFont(paytone)
glyf = L['glyf']
hmtx = L['hmtx']
gs = L.getGlyphSet()

def bbox(name):
    g = glyf[name]
    g.recalcBounds(glyf)
    return g.xMin, g.yMin, g.xMax, g.yMax

def add_simple(name, draw_fn):
    pen = TTGlyphPen(None)
    draw_fn(pen)
    glyf[name] = pen.glyph()
    L.getGlyphOrder()
    order = L.getGlyphOrder()
    if name not in order:
        order.append(name)
        L.setGlyphOrder(order)
    glyf[name].recalcBounds(glyf)
    hmtx[name] = (0, glyf[name].xMin)

# --- nokta: i'nin üstteki konturu ---
rec = RecordingPen()
gs['i'].draw(rec)
contours, cur = [], []
for op, args in rec.value:
    cur.append((op, args))
    if op in ('closePath', 'endPath'):
        contours.append(cur); cur = []
def ymax(c):
    return max(p[1] for op, args in c for p in args if p is not None)
dot = max(contours, key=ymax)
def draw_dot(pen):
    for op, args in dot:
        getattr(pen, op)(*args)
add_simple('tr_dot', draw_dot)

# --- kısa işareti: Paytone'dan ---
pgs = P.getGlyphSet()
def draw_from_paytone(name):
    def f(pen):
        pgs[name].draw(pen)
    return f
add_simple('tr_breve', draw_from_paytone('uni0306'))
add_simple('tr_breve_case', draw_from_paytone('uni0306.case'))

def composite(name, base, mark, dx, dy):
    from fontTools.ttLib.tables._g_l_y_f import Glyph
    g = Glyph()
    g.numberOfContours = -1
    comps = []
    for gname, x, y in [(base, 0, 0), (mark, dx, dy)]:
        c = GlyphComponent()
        c.glyphName = gname; c.x = int(round(x)); c.y = int(round(y)); c.flags = 0
        comps.append(c)
    comps[0].flags = 0x0200  # USE_MY_METRICS
    g.components = comps
    glyf[name] = g
    order = L.getGlyphOrder()
    if name not in order:
        order.append(name); L.setGlyphOrder(order)
    hmtx[name] = hmtx[base]
    glyf[name].recalcBounds(glyf)

def center_x(name):
    x0, y0, x1, y1 = bbox(name)
    return (x0 + x1) / 2

capH = L['OS/2'].sCapHeight
xH = L['OS/2'].sxHeight
# İ: nokta, i'deki gibi ama büyük harf yüksekliğine taşınır.
d = bbox('tr_dot')
gap = d[1] - xH
composite('Idotaccent', 'I', 'tr_dot', center_x('I') - (d[0] + d[2]) / 2, capH + gap * 0.85 - d[1])
# Ş ş: çengel harfin altına ortalı (Ç'deki gibi).
c = bbox('cedilla')
cc = bbox('Ccedilla')
cy = cc[1] - c[1]
composite('Scedilla', 'S', 'cedilla', center_x('S') - (c[0] + c[2]) / 2, cy)
composite('scedilla', 's', 'cedilla', center_x('s') - (c[0] + c[2]) / 2, cy)
# Ğ ğ: kısa işareti harfin üstüne ortalı.
b = bbox('tr_breve'); bc = bbox('tr_breve_case')
composite('gbreve', 'g', 'tr_breve', center_x('g') - (b[0] + b[2]) / 2, xH + 70 - b[1])
composite('Gbreve', 'G', 'tr_breve_case', center_x('G') - (bc[0] + bc[2]) / 2, capH + 60 - bc[1])

for t in L['cmap'].tables:
    if t.isUnicode():
        t.cmap.update({0x130: 'Idotaccent', 0x15E: 'Scedilla', 0x15F: 'scedilla', 0x11E: 'Gbreve', 0x11F: 'gbreve'})
L['maxp'].numGlyphs = len(L.getGlyphOrder())
# Ad: OFL ayrılmış ad 'Lilita' kullanılmaz.
for rec in L['name'].names:
    if rec.nameID in (1, 16):
        rec.string = 'Siyaset Display'
    elif rec.nameID == 4:
        rec.string = 'Siyaset Display Regular'
    elif rec.nameID == 6:
        rec.string = 'SiyasetDisplay-Regular'
    elif rec.nameID == 3:
        rec.string = 'Siyaset Display; based on Lilita One'
if 'DSIG' in L:
    del L['DSIG']
L.save(out)
print('ok', len(L.getGlyphOrder()))
