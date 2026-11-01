// Siyaset Oyunu tanıtım sitesi.
(() => {
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // Oyundaki parti renk paletinden (PartyPresets.COLORS).
  const PARTY = ["#f2132a", "#2b4bab", "#f2741f", "#40c754", "#b435de", "#f2d31f", "#209fe3", "#a63260"];

  // --- En güncel sürüm: GitHub'daki builds/version.json (website/publish.py yazar).
  // Dosya da oradan iner; GitHub'a ulaşılamazsa sitedeki yedek bilgi kullanılır.
  const RAW = "https://raw.githubusercontent.com/TriQue06/siyaset_oyunu_test_experimental/main/builds/";
  const mb = (bytes) => (bytes / 1048576).toFixed(0) + " MB";
  const getJson = (url) => fetch(url, { cache: "no-cache" }).then((r) => (r.ok ? r.json() : Promise.reject(r.status)));
  const set = (sel, text) => document.querySelectorAll(sel).forEach((el) => (el.textContent = text));
  getJson(RAW + "version.json")
    .catch(() => getJson("/version.json"))
    .then((v) => {
      if (v.exe) {
        document.querySelectorAll(".dl-exe").forEach((a) => (a.href = v.exe.url));
        set("[data-meta='exe']", `Sürüm ${v.version} · zip · ${mb(v.exe.size)}`);
      }
      set("#band-version", `Sürüm ${v.version}`);
      set("#foot-version", `Son sürüm ${v.version} · ${v.date}`);
    })
    .catch(() => {
      // Dosya henüz yüklenmediyse düğme pasif görünür.
      document.querySelectorAll(".dl").forEach((a) => a.setAttribute("aria-disabled", "true"));
      set("[data-meta='exe']", "Yakında");
    });

  // --- Kaydırınca beliren parçalar ---
  document.documentElement.classList.add("js");
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add("in");
      e.target.querySelectorAll("[data-count]").forEach(countUp);
      if (e.target.id === "parl" || e.target.querySelector("#parl")) fillParliament();
      io.unobserve(e.target);
    }
  }, { threshold: 0.2 });
  document.querySelectorAll("[data-reveal]").forEach((el) => io.observe(el));

  function countUp(el) {
    const target = Number(el.dataset.count);
    if (reduce || !target) return;
    const start = performance.now();
    const step = (now) => {
      const k = Math.min(1, (now - start) / 900);
      el.textContent = String(Math.round(target * (1 - Math.pow(1 - k, 3))));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  // --- Son bölümdeki meclis: piyonlar soldan sağa partilerin renginde dolar ---
  const parl = document.getElementById("parl");
  const NS = "http://www.w3.org/2000/svg";
  const SEATS = [92, 70, 58, 44, 30, 18];
  const total = SEATS.reduce((a, b) => a + b, 0);
  const rows = 8, inner = 90, outer = 245, cx = 260, cy = 258;
  const radii = Array.from({ length: rows }, (_, i) => inner + (outer - inner) * i / (rows - 1));
  const sum = radii.reduce((a, b) => a + b, 0);
  const counts = radii.map((r) => Math.round(total * r / sum));
  counts[rows - 1] += total - counts.reduce((a, b) => a + b, 0);
  const slots = [];
  radii.forEach((r, ri) => {
    for (let j = 0; j < counts[ri]; j++) slots.push({ a: Math.PI * (1 - (j + 0.5) / counts[ri]), r });
  });
  slots.sort((p, q) => q.a - p.a);
  let k = 0;
  SEATS.forEach((n, p) => { for (let i = 0; i < n && k < slots.length; i++) slots[k++].c = PARTY[p]; });
  const dots = slots.map((s) => {
    const c = document.createElementNS(NS, "circle");
    c.setAttribute("cx", (cx + s.r * Math.cos(s.a)).toFixed(1));
    c.setAttribute("cy", (cy - s.r * Math.sin(s.a)).toFixed(1));
    c.setAttribute("r", "6.4");
    c.setAttribute("fill", "#eadfc4");
    c.setAttribute("stroke", "rgba(0,0,0,.25)");
    c.setAttribute("stroke-width", ".8");
    parl.appendChild(c);
    return c;
  });
  let filled = false;
  function fillParliament() {
    if (filled) return;
    filled = true;
    dots.forEach((d, i) => {
      const paint = () => d.setAttribute("fill", slots[i].c);
      if (reduce) paint(); else setTimeout(paint, 300 + i * 6);
    });
  }
})();
