// assets/maps/turkey_map.png değiştikçe elle bana sormana gerek kalmadan
// data/province_pixel_map.json'ı yeniden üretmek için: tools/refresh_map.bat
// (çift tıkla) ya da `node tools/refresh_map.js` çalıştır.
//
// Renk -> il eşleşmesi tools/pixel_art_province_colors.csv'ye göre yapılır.
// Siyah (#000000) ve palette'te olmayan HER RENK (dekoratif doku vb.)
// otomatik olarak "il değil" sayılır, hiçbir ile atanmaz/dokunulmaz.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.join(__dirname, '..');
const PNG_PATH = path.join(ROOT, 'assets/maps/turkey_map.png');
const CSV_PATH = path.join(ROOT, 'tools/pixel_art_province_colors.csv');
const OUT_PATH = path.join(ROOT, 'data/province_pixel_map.json');

function decodePng(buf) {
  function readChunks(buf) {
    let offset = 8; const chunks = [];
    while (offset < buf.length) {
      const len = buf.readUInt32BE(offset);
      const type = buf.toString('ascii', offset + 4, offset + 8);
      const data = buf.slice(offset + 8, offset + 8 + len);
      chunks.push({ type, data }); offset += 12 + len;
    }
    return chunks;
  }
  const chunks = readChunks(buf);
  const ihdr = chunks.find(c => c.type === 'IHDR').data;
  const width = ihdr.readUInt32BE(0), height = ihdr.readUInt32BE(4);
  const colorType = ihdr.readUInt8(9);
  const idat = Buffer.concat(chunks.filter(c => c.type === 'IDAT').map(c => c.data));
  const raw = zlib.inflateSync(idat);
  const bpp = colorType === 6 ? 4 : (colorType === 2 ? 3 : 1);
  const stride = width * bpp;
  const pixels = Buffer.alloc(height * stride);
  function paeth(a, b, c) { const p = a + b - c; const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); if (pa <= pb && pa <= pc) return a; if (pb <= pc) return b; return c; }
  let rawOffset = 0;
  for (let y = 0; y < height; y++) {
    const filterType = raw[rawOffset++];
    const rowStart = y * stride, prevRowStart = (y - 1) * stride;
    for (let x = 0; x < stride; x++) {
      const val = raw[rawOffset++];
      const a = x >= bpp ? pixels[rowStart + x - bpp] : 0;
      const b = y > 0 ? pixels[prevRowStart + x] : 0;
      const c = (y > 0 && x >= bpp) ? pixels[prevRowStart + x - bpp] : 0;
      let recon;
      switch (filterType) {
        case 0: recon = val; break;
        case 1: recon = val + a; break;
        case 2: recon = val + b; break;
        case 3: recon = val + Math.floor((a + b) / 2); break;
        case 4: recon = val + paeth(a, b, c); break;
        default: recon = val;
      }
      pixels[rowStart + x] = recon & 0xff;
    }
  }
  return { width, height, bpp, pixels };
}

function run() {
  if (!fs.existsSync(PNG_PATH)) {
    console.error('BULUNAMADI:', PNG_PATH);
    process.exit(1);
  }
  const { width, height, bpp, pixels } = decodePng(fs.readFileSync(PNG_PATH));

  const csv = fs.readFileSync(CSV_PATH, 'utf8').trim().split('\n');
  const provinceColors = csv.map(l => { const [id, hex] = l.split(','); return [id, hex.trim().toLowerCase()]; });
  const colorToId = {};
  for (const [id, hex] of provinceColors) colorToId[hex] = id;
  // KARS için geçmişte kaynak PNG'de yanlış/typo bir renk (#e57500) kullanılmıştı;
  // boyutu (188px) hep Kars'a uyduğu için bu eşleme kalıcı olarak eklendi.
  // Palette'i tekrar düzeltirsen (Kars'ı doğru #34e575 ile boyarsan) bu satırın
  // hiçbir etkisi kalmaz, zararsızdır.
  colorToId['#e57500'] = 'kars';

  const ids = provinceColors.map(p => p[0]);
  const idIndex = {}; ids.forEach((id, i) => idIndex[id] = i);

  function hexAt(x, y) {
    const i = y * width + x; const o = i * bpp;
    const r = pixels[o], g = pixels[o + 1], b = pixels[o + 2], a = pixels[o + 3];
    if (a < 10) return null;
    return '#' + [r, g, b].map(v => v.toString(16).padStart(2, '0')).join('');
  }

  const grid = new Int16Array(width * height).fill(-1);
  const sumX = {}, sumY = {}, count = {};
  let decorativeCount = 0, blackCount = 0, seaCount = 0;
  const decorativeColors = {};

  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const hex = hexAt(x, y);
      if (hex === null) { seaCount++; continue; }
      if (hex === '#000000') { blackCount++; continue; }
      const id = colorToId[hex];
      if (!id) { decorativeCount++; decorativeColors[hex] = (decorativeColors[hex] || 0) + 1; continue; }
      const idx = idIndex[id];
      grid[y * width + x] = idx;
      sumX[id] = (sumX[id] || 0) + x;
      sumY[id] = (sumY[id] || 0) + y;
      count[id] = (count[id] || 0) + 1;
    }
  }

  const centers = {};
  for (const id of ids) {
    if (count[id]) centers[id] = [sumX[id] / count[id], sumY[id] / count[id]];
  }
  const missing = ids.filter(id => !centers[id]);

  const out = { width, height, ids, grid: Array.from(grid), centers, pixel_counts: count };
  fs.writeFileSync(OUT_PATH, JSON.stringify(out));

  console.log(`OK: ${width}x${height}, ${ids.length - missing.length}/${ids.length} il eşleşti.`);
  console.log(`  deniz/şeffaf: ${seaCount}  siyah: ${blackCount}  dekoratif(dokunulmadı): ${decorativeCount}`);
  if (Object.keys(decorativeColors).length) {
    console.log('  dekoratif renkler:', decorativeColors);
  }
  if (missing.length) {
    console.log('  !! EKSİK İLLER (0 piksel, haritada görünmeyecek):', missing.join(', '));
  }
}

run();
