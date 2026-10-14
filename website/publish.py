"""Yeni sürümü yayınlar: build -> GitHub builds/ klasörü -> site.

  python publish.py            -> en yeni APK + EXE'yi depodaki builds/ klasörüne koyar
                                  (EXE GitHub'ın 100 MB dosya sınırı yüzünden zip'lenir),
                                  builds/version.json'ı ve sitedeki yedek sürüm bilgisini yazar
  python publish.py --deploy   -> ayrıca siteyi Firebase'e yükler

Sonra builds/ klasörü git ile commit'lenip push'lanır: sitedeki butonlar dosyaları
GitHub'dan (raw.githubusercontent.com) indirir, sürüm ve boyutu oradaki
version.json'dan okur. Yani site her sürümde yeniden yüklenmese de butonlar
en güncel dosyayı verir.
"""
import datetime
import json
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BUILD_DIR = Path(r"C:\Users\baris\Desktop\Siyaset Oyunu Build")
HERE = Path(__file__).resolve().parent
REPO = HERE.parent
BUILDS = REPO / "builds"
SITE_FALLBACK = HERE / "public" / "version.json"
## Butonların indirdiği adres (depo herkese açık olmalı). Dal değişirse burası ve
## public/app.js'teki RAW sabiti birlikte güncellenir.
RAW = "https://raw.githubusercontent.com/TriQue06/siyaset_oyunu_test_experimental/oyun-duzeltmeleri/builds/"
PATTERN = re.compile(r"SiyasetOyunu-(\d+)\.(\d+)\.(\d+)\.(apk|exe)$")
GITHUB_LIMIT = 100 * 1024 * 1024


def newest(ext: str):
    best = None
    for f in BUILD_DIR.glob(f"SiyasetOyunu-*.{ext}"):
        m = PATTERN.match(f.name)
        if m:
            key = tuple(int(x) for x in m.groups()[:3])
            if best is None or key > best[0]:
                best = (key, f)
    return best


def main() -> None:
    apk, exe = newest("apk"), newest("exe")
    if apk is None or exe is None:
        sys.exit(f"Build klasöründe APK ya da EXE yok: {BUILD_DIR}")
    if apk[0] != exe[0]:
        sys.exit(f"APK ve EXE sürümleri farklı: {apk[1].name} / {exe[1].name}")
    version = ".".join(str(x) for x in apk[0])
    BUILDS.mkdir(exist_ok=True)
    apk_out = BUILDS / "SiyasetOyunu.apk"
    zip_out = BUILDS / "SiyasetOyunu-Windows.zip"
    shutil.copy2(apk[1], apk_out)
    with zipfile.ZipFile(zip_out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(exe[1], "SiyasetOyunu.exe")
    for f in (apk_out, zip_out):
        if f.stat().st_size >= GITHUB_LIMIT:
            sys.exit(f"{f.name} GitHub'ın 100 MB sınırını aşıyor ({f.stat().st_size / 1048576:.0f} MB).")
    info = {
        "version": version,
        "date": datetime.date.today().strftime("%d.%m.%Y"),
        "apk": {"url": RAW + apk_out.name, "size": apk_out.stat().st_size},
        "exe": {"url": RAW + zip_out.name, "size": zip_out.stat().st_size, "zip": True},
    }
    text = json.dumps(info, ensure_ascii=False, indent=2)
    (BUILDS / "version.json").write_text(text, encoding="utf-8")
    SITE_FALLBACK.write_text(text, encoding="utf-8")
    print(f"Sürüm {version}: APK {apk_out.stat().st_size / 1048576:.0f} MB, "
          f"Windows zip {zip_out.stat().st_size / 1048576:.0f} MB -> {BUILDS}")
    print("Sıradaki adım: builds/ klasörünü commit'le ve push'la.")
    if "--deploy" in sys.argv:
        subprocess.run("firebase deploy --only hosting", cwd=HERE, shell=True, check=True)


if __name__ == "__main__":
    main()
