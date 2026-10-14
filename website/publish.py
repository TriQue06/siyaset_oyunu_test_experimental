"""Siteye en güncel oyun dosyalarını koyar ve (istenirse) Firebase'e yükler.

  python publish.py            -> en yeni APK + EXE'yi public/downloads'a kopyalar,
                                  public/downloads/version.json'ı yazar
  python publish.py --deploy   -> ayrıca "firebase deploy --only hosting" çalıştırır

Dosyalar build.bat'ın ürettiği klasörden alınır (SiyasetOyunu-<sürüm>.apk/.exe);
sürümü en yüksek olan çift seçilir. İndirme adresleri sabittir
(/downloads/SiyasetOyunu.apk ve .exe), site sürümü ve boyutu version.json'dan okur.
"""
import datetime
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

BUILD_DIR = Path(r"C:\Users\baris\Desktop\Siyaset Oyunu Build")
HERE = Path(__file__).resolve().parent
OUT = HERE / "public" / "downloads"
PATTERN = re.compile(r"SiyasetOyunu-(\d+)\.(\d+)\.(\d+)\.(apk|exe)$")


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
    OUT.mkdir(parents=True, exist_ok=True)
    apk, exe = newest("apk"), newest("exe")
    if apk is None and exe is None:
        sys.exit(f"Build klasöründe dosya yok: {BUILD_DIR}")
    info = {"date": datetime.date.today().strftime("%d.%m.%Y")}
    versions = []
    for kind, found in (("apk", apk), ("exe", exe)):
        if found is None:
            print(f"UYARI: {kind} bulunamadı, sitede pasif görünecek.")
            continue
        key, src = found
        target = OUT / f"SiyasetOyunu.{kind}"
        shutil.copy2(src, target)
        info[kind] = {"url": f"/downloads/SiyasetOyunu.{kind}", "size": target.stat().st_size,
                      "file": src.name}
        versions.append(key)
        print(f"{kind}: {src.name} ({target.stat().st_size / 1048576:.0f} MB)")
    if apk and exe and apk[0] != exe[0]:
        print("UYARI: APK ve EXE sürümleri farklı:", apk[1].name, exe[1].name)
    info["version"] = ".".join(str(x) for x in max(versions))
    (OUT / "version.json").write_text(json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8")
    print("version.json yazıldı:", info["version"])
    if "--deploy" in sys.argv:
        subprocess.run("firebase deploy --only hosting", cwd=HERE, shell=True, check=True)


if __name__ == "__main__":
    main()
