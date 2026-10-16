// Siyaset Oyunu tanıtım sitesi.
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const PARTY = ["#a33bd6", "#f2c230", "#9dc94b", "#2569cf", "#e8202a", "#e8458f", "#27c9c9", "#f27e1f"];

  // --- En güncel sürüm: GitHub'daki builds/version.json (website/publish.py yazar).
  // Dosyalar da oradan iner; GitHub'a ulaşılamazsa sitedeki yedek bilgi kullanılır.
  const RAW = "https://raw.githubusercontent.com/TriQue06/siyaset_oyunu_test_experimental/main/builds/";
  const mb = (bytes) => (bytes / 1048576).toFixed(0) + " MB";
  const getJson = (url) => fetch(url, { cache: "no-cache" }).then((r) => (r.ok ? r.json() : Promise.reject(r.status)));
  getJson(RAW + "version.json")
    .catch(() => getJson("/version.json"))
    .then((v) => {
      const set = (sel, text) => document.querySelectorAll(sel).forEach((el) => (el.textContent = text));
      if (v.apk) {
        document.querySelectorAll('#dl-apk, [data-mirror="apk"]').forEach((a) => (a.href = v.apk.url));
        set("#meta-apk, [data-meta='apk']", `Sürüm ${v.version} · ${mb(v.apk.size)}`);
      }
      if (v.exe) {
        document.querySelectorAll('#dl-exe, [data-mirror="exe"]').forEach((a) => (a.href = v.exe.url));
        set("#meta-exe, [data-meta='exe']", `Sürüm ${v.version} · zip · ${mb(v.exe.size)}`);
      }
      set("#band-version", `Sürüm ${v.version}`);
      set("#foot-version", `Son sürüm ${v.version} · ${v.date}`);
    })
    .catch(() => {
      // Dosyalar henüz yüklenmediyse butonlar pasif görünür.
      document.querySelectorAll(".dl").forEach((a) => a.setAttribute("aria-disabled", "true"));
      document.querySelectorAll("#meta-apk, #meta-exe").forEach((el) => (el.textContent = "Yakında"));
    });

  // --- Kaydırınca beliren bölümler ---
  document.documentElement.classList.add("js-reveal");
  const fanCards = [...document.querySelectorAll(".fan img")];
  const spreadFan = (open) => {
    const n = fanCards.length;
    fanCards.forEach((img, i) => {
      const t = i - (n - 1) / 2;
      const angle = open ? t * 9 : 0;
      const x = open ? t * Math.min(110, window.innerWidth / 9) : 0;
      img.style.transform = `translateX(calc(-50% + ${x}px)) translateY(${open ? Math.abs(t) * 10 : 0}px) rotate(${angle}deg)`;
      img.style.transitionDelay = open ? `${i * 60}ms` : "0ms";
      img.style.zIndex = String(i);
    });
  };
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("in");
      if (e.target.dataset.reveal === "fan") spreadFan(true);
      e.target.querySelectorAll("[data-count]").forEach(countUp);
      if (e.target.dataset.count !== undefined) countUp(e.target);
      io.unobserve(e.target);
    }
  }, { threshold: 0.25 });
  document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));
  window.addEventListener("resize", () => {
    if (document.querySelector(".fan.in")) spreadFan(true);
  });

  function countUp(el) {
    const target = Number(el.dataset.count);
    if (reduce || !target) return;
    const start = performance.now();
    const dur = 900;
    const step = (now) => {
      const k = Math.min(1, (now - start) / dur);
      el.textContent = String(Math.round(target * (1 - Math.pow(1 - k, 3))));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // --- Giriş arka planı: sandıkları açılan altıgen harita ---
  const map = document.getElementById("hero-map");
  const parl = document.getElementById("hero-parl");
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  let cells = [];
  let seeds = [];
  let visible = true;
  new IntersectionObserver((es) => (visible = es[0].isIntersecting)).observe(map);

  // Türkiye haritası (oyundaki altıgen veri, /data/turkiye.json); gelmezse rastgele kıta.
  let turkey = null;
  fetch("/data/turkiye.json").then((r) => r.json()).then((d) => { turkey = d; rebuild(); }).catch(() => {});

  function buildMap() {
    const w = map.clientWidth, h = map.clientHeight;
    map.width = w * dpr; map.height = h * dpr;
    cells = [];
    if (turkey) {
      // Haritayı ekrana sığdır: geniş ekranda genişliğin %92'si, dar ekranda yüksekliğe göre.
      const r = Math.min((w * 0.92) / (Math.sqrt(3) * (turkey.cols + 0.5)), (h * 0.8) / (1.5 * turkey.rows + 0.5));
      const cw = Math.sqrt(3) * r;
      const ox = (w - cw * (turkey.cols + 0.5)) / 2, oy = (h - 1.5 * r * turkey.rows) / 2;
      seeds = turkey.seats.map(() => ({ c: PARTY[(Math.random() * PARTY.length) | 0] }));
      turkey.cells.forEach((p, i) => {
        if (p < 0) return;
        const col = i % turkey.cols, row = (i / turkey.cols) | 0;
        const x = ox + cw * (col + 0.5 * (row & 1) + 0.5), y = oy + 1.5 * r * row + r;
        const nx = (x / w - 0.5) * 2, ny = (y / h - 0.5) * 2;
        cells.push({ x, y, r, seed: seeds[p], at: Math.random() * 2500 + Math.hypot(nx, ny) * 3000 });
      });
      return;
    }
    const r = Math.max(9, Math.min(16, w / 90));
    const cw = Math.sqrt(3) * r;
    seeds = Array.from({ length: 22 }, () => ({ x: Math.random() * w, y: Math.random() * h, c: PARTY[(Math.random() * PARTY.length) | 0] }));
    for (let row = 0, y = r; y < h + r; row++, y += r * 1.5) {
      for (let x = (row % 2 ? cw / 2 : 0); x < w + cw; x += cw) {
        // Kıta silueti: kenarlara doğru seyrelir.
        const nx = (x / w - 0.5) * 2, ny = (y / h - 0.5) * 2;
        if (nx * nx * 0.9 + ny * ny * 1.6 + Math.sin(x * 0.01) * 0.12 > 1.05) continue;
        let best = seeds[0], bd = Infinity;
        for (const s of seeds) { const d = (s.x - x) ** 2 + (s.y - y) ** 2; if (d < bd) { bd = d; best = s; } }
        cells.push({ x, y, r, seed: best, at: Math.random() * 6000 + Math.hypot(nx, ny) * 2500 });
      }
    }
  }

  function hex(ctx, x, y, r) {
    ctx.beginPath();
    for (let i = 0; i < 6; i++) {
      const a = Math.PI / 180 * (60 * i - 30);
      ctx.lineTo(x + r * Math.cos(a), y + r * Math.sin(a));
    }
    ctx.closePath();
  }

  // Meclis yarım dairesi: 600 nokta, partilere bölünmüş, soldan sağa dolar.
  const SEATS = [164, 128, 116, 107, 53, 30, 2];
  const TOTAL = SEATS.reduce((a, b) => a + b, 0);
  let slots = [];
  function buildParl() {
    const w = parl.clientWidth, h = parl.clientHeight;
    parl.width = w * dpr; parl.height = h * dpr;
    const rows = 11, inner = w * 0.16, outer = w * 0.48;
    const radii = Array.from({ length: rows }, (_, i) => inner + (outer - inner) * i / (rows - 1));
    const sum = radii.reduce((a, b) => a + b, 0);
    const counts = radii.map((rr) => Math.round(TOTAL * rr / sum));
    counts[rows - 1] += TOTAL - counts.reduce((a, b) => a + b, 0);
    slots = [];
    radii.forEach((rr, ri) => { for (let j = 0; j < counts[ri]; j++) slots.push({ a: Math.PI * (1 - (j + 0.5) / counts[ri]), rr }); });
    slots.sort((p, q) => q.a - p.a);
    let k = 0;
    SEATS.forEach((n, p) => { for (let i = 0; i < n && k < slots.length; i++) slots[k++].c = PARTY[p]; });
  }

  let t0 = performance.now();
  function frame(now) {
    const t = now - t0;
    if (visible) {
      const ctx = map.getContext("2d");
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, map.width, map.height);
      for (const c of cells) {
        const lit = reduce || t > c.at;
        hex(ctx, c.x, c.y, c.r * 0.9);
        ctx.fillStyle = lit ? c.seed.c : "#2b2352";
        ctx.globalAlpha = lit ? 0.75 : 0.55;
        ctx.fill();
      }
      ctx.globalAlpha = 1;
      // Ara sıra bir bölge el değiştirir (sayım sürüyor).
      if (!reduce && Math.random() < 0.01) {
        const s = seeds[(Math.random() * seeds.length) | 0];
        s.c = PARTY[(Math.random() * PARTY.length) | 0];
      }
      const pc = parl.getContext("2d");
      const w = parl.clientWidth, h = parl.clientHeight;
      pc.setTransform(dpr, 0, 0, dpr, 0, 0);
      pc.clearRect(0, 0, w, h);
      const shown = reduce ? slots.length : Math.min(slots.length, Math.floor(t / 7));
      const dot = w / 155;
      for (let i = 0; i < slots.length; i++) {
        const s = slots[i];
        pc.beginPath();
        pc.arc(w / 2 + s.rr * Math.cos(s.a), h - 6 - s.rr * Math.sin(s.a), dot, 0, Math.PI * 2);
        pc.fillStyle = i < shown ? s.c : "#2b2352";
        pc.fill();
      }
    }
    if (!reduce) requestAnimationFrame(frame);
  }

  function rebuild() { buildMap(); buildParl(); if (reduce) frame(performance.now()); }
  rebuild();
  let resizeTimer;
  window.addEventListener("resize", () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(rebuild, 200); });
  if (!reduce) requestAnimationFrame(frame);
})();
