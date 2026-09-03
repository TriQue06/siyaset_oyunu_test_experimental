// GEÇİCİ pixel-art placeholder üretici.
//
// Amaç: her görünür arayüz ögesinin DÜZENLENEBİLİR bir PNG'si olsun. Godot
// tarafında prosedürel çizim (StyleBoxFlat, ColorRect vb.) kullanılmıyor;
// görünen her şey buradaki PNG'lerden geliyor. Bu dosyaların üzerine kendi
// pixel-art'ını çizdiğinde kod hiç değişmeden yeni görsel devreye girer.
//
// Kullanım:  node tools/make_placeholder_art.js
// Var olan bir dosyanın ÜZERİNE YAZMAZ (kendi çizdiklerin korunur).
// Hepsini sıfırdan yeniden üretmek için:  node tools/make_placeholder_art.js --force

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = path.join(__dirname, '..', 'assets', 'ui');
const CARDS = path.join(__dirname, '..', 'assets', 'cards');
const FORCE = process.argv.includes('--force');

// --- minik PNG yazici ---------------------------------------------------
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = c ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crcBuf]);
}
function writePng(file, W, H, px) {
  const raw = Buffer.alloc(H * (1 + W * 4));
  for (let y = 0; y < H; y++) {
    raw[y * (1 + W * 4)] = 0;
    px.copy(raw, y * (1 + W * 4) + 1, y * W * 4, (y + 1) * W * 4);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0);
  ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
}

// --- kucuk cizim yardimcilari -------------------------------------------
const made = [];
const skipped = [];

function hex(c) {
  c = c.replace('#', '');
  return [
    parseInt(c.slice(0, 2), 16),
    parseInt(c.slice(2, 4), 16),
    parseInt(c.slice(4, 6), 16),
    c.length > 6 ? parseInt(c.slice(6, 8), 16) : 255,
  ];
}

function Canvas(W, H) {
  const px = Buffer.alloc(W * H * 4); // tamami saydam baslar
  const api = {
    W, H, px,
    set(x, y, c) {
      if (x < 0 || y < 0 || x >= W || y >= H) return api;
      const rgba = hex(c);
      const o = (y * W + x) * 4;
      px[o] = rgba[0]; px[o + 1] = rgba[1]; px[o + 2] = rgba[2]; px[o + 3] = rgba[3];
      return api;
    },
    rect(x, y, w, h, c) {
      for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) api.set(i, j, c);
      return api;
    },
    border(x, y, w, h, c) {
      for (let i = x; i < x + w; i++) { api.set(i, y, c); api.set(i, y + h - 1, c); }
      for (let j = y; j < y + h; j++) { api.set(x, j, c); api.set(x + w - 1, j, c); }
      return api;
    },
    // satir satir desen; bosluk karakteri saydam birakir
    art(x, y, rows, map) {
      rows.forEach(function (row, j) {
        Array.from(row).forEach(function (ch, i) {
          if (map[ch]) api.set(x + i, y + j, map[ch]);
        });
      });
      return api;
    },
    save(file) {
      if (!FORCE && fs.existsSync(file)) { skipped.push(path.basename(file)); return; }
      writePng(file, W, H, px);
      made.push(path.basename(file));
    },
  };
  return api;
}

// --- palet (mevcut ahsap/pixel-art tonlariyla uyumlu) --------------------
const P = {
  ink: '#1c1e21',
  dark: '#7b4e3d',
  mid: '#926f62',
  light: '#ab7c6a',
  greenD: '#1f6b32',
  green: '#3fa34d',
  greenL: '#6ed07a',
  redD: '#8c2118',
  red: '#c0392b',
  redL: '#e5705f',
  greyD: '#33373b',
  grey: '#55595e',
  greyL: '#7b8085',
  gold: '#f7c10c',
  paper: '#d8c7a8',
  white: '#ffffff',
};

// 9-slice kutu: 1px koyu dis cizgi + ic dolgu + sol/ust acik vurgu.
// 16x16 uretilir, Godot tarafinda 5px kenar payiyla 9-slice esnetilir.
function box(W, H, fill, edge, hi) {
  const c = Canvas(W, H);
  c.rect(0, 0, W, H, fill);
  c.border(0, 0, W, H, edge);
  for (let i = 1; i < W - 1; i++) c.set(i, 1, hi);
  for (let j = 1; j < H - 1; j++) c.set(1, j, hi);
  return c;
}

// ---- 1) Genel panel + buton kiti ---------------------------------------
box(16, 16, P.mid, P.ink, P.light).save(OUT + '/ui_panel.png');
box(16, 16, P.dark, P.ink, P.mid).save(OUT + '/ui_panel_dark.png');
box(16, 16, P.light, P.ink, P.paper).save(OUT + '/ui_button_normal.png');
box(16, 16, P.paper, P.ink, P.white).save(OUT + '/ui_button_hover.png');
box(16, 16, P.mid, P.ink, P.light).save(OUT + '/ui_button_pressed.png');
box(16, 16, P.grey, P.greyD, P.greyL).save(OUT + '/ui_button_disabled.png');
box(16, 16, P.greyD, P.ink, P.grey).save(OUT + '/ui_slot.png');

// ---- 2) Meclis oylama butonlari (yazisiz, 24x24) -----------------------
const CHECK = [
  '        ',
  '       X',
  '      XX',
  'X    XX ',
  'XX  XX  ',
  ' XXXX   ',
  '  XX    ',
  '        ',
];
const CROSS = [
  '        ',
  ' X    X ',
  ' XX  XX ',
  '  XXXX  ',
  '   XX   ',
  '  XXXX  ',
  ' XX  XX ',
  ' X    X ',
];
function voteButton(fill, edge, hi, glyph, glyphColor) {
  const c = box(24, 24, fill, edge, hi);
  c.art(8, 8, glyph, { X: glyphColor });
  return c;
}
voteButton(P.green, P.ink, P.greenL, CHECK, P.white).save(OUT + '/vote_yes_normal.png');
voteButton(P.greenL, P.ink, P.white, CHECK, P.white).save(OUT + '/vote_yes_hover.png');
voteButton(P.greenD, P.ink, P.green, CHECK, P.white).save(OUT + '/vote_yes_pressed.png');
voteButton(P.grey, P.greyD, P.greyL, CHECK, P.greyD).save(OUT + '/vote_yes_disabled.png');
voteButton(P.red, P.ink, P.redL, CROSS, P.white).save(OUT + '/vote_no_normal.png');
voteButton(P.redL, P.ink, P.white, CROSS, P.white).save(OUT + '/vote_no_hover.png');
voteButton(P.redD, P.ink, P.red, CROSS, P.white).save(OUT + '/vote_no_pressed.png');
voteButton(P.grey, P.greyD, P.greyL, CROSS, P.greyD).save(OUT + '/vote_no_disabled.png');

// ---- 3) Yeni kartlar (72x96 = mevcut kart boyutu) -----------------------
function card(accent, glyph) {
  const c = Canvas(72, 96);
  c.rect(0, 0, 72, 96, P.paper);
  c.border(0, 0, 72, 96, P.ink);
  c.border(3, 3, 66, 90, accent);
  c.rect(6, 6, 60, 26, accent);
  c.art(27, 44, glyph, { X: P.ink });
  return c;
}

// gensoru: asagi ok (hukumeti dusur)
card(P.red, [
  'XXXXXXXXXXXX',
  'XXXXXXXXXXXX',
  '    XXXX    ',
  '    XXXX    ',
  '    XXXX    ',
  'XX  XXXX  XX',
  ' XX XXXX XX ',
  '  XXXXXXXX  ',
  '   XXXXXX   ',
  '    XXXX    ',
  '     XX     ',
]).save(CARDS + '/politic_card_gensoru.png');

// vekil calma: yana ok + guc gostergesi (nokta sayisi)
function stealGlyph(dots) {
  const rows = [
    '     XX     ',
    '     XXXX   ',
    'XXXXXXXXXX  ',
    'XXXXXXXXXXXX',
    'XXXXXXXXXX  ',
    '     XXXX   ',
    '     XX     ',
    '            ',
  ];
  let d = '';
  for (let i = 0; i < 3; i++) d += (i < dots ? 'XXX' : '   ') + ' ';
  rows.push(d.slice(0, 12));
  rows.push(d.slice(0, 12));
  return rows;
}
card(P.gold, stealGlyph(1)).save(CARDS + '/politic_card_steal_weak.png');
card(P.gold, stealGlyph(2)).save(CARDS + '/politic_card_steal_medium.png');
card(P.gold, stealGlyph(3)).save(CARDS + '/politic_card_steal_strong.png');

// ---- 4) Hedef secme vurgusu (vekil calma karti icin) -------------------
const halo = Canvas(16, 16);
halo.border(0, 0, 16, 16, P.gold);
halo.border(1, 1, 14, 14, P.gold);
halo.save(OUT + '/target_highlight.png');

console.log('URETILEN (' + made.length + '):');
made.forEach(function (f) { console.log('  + ' + f); });
if (skipped.length) {
  console.log('');
  console.log('ATLANDI - zaten var, korundu (' + skipped.length + '):');
  console.log('  ' + skipped.join(', '));
  console.log('  (hepsini yeniden uretmek icin --force ekle)');
}
