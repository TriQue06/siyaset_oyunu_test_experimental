## Koddaki çevrilecek metinlerden (L.t, çeviri gereken sabitler, sahne metinleri)
## en_source.json'da karşılığı OLMAYANLARI listeler. Yeni metin ekleyince çalıştır,
## eksikleri en_source.json'a ekle, sonra build_po.py.
##   python tools/l10n/check_missing.py
import json, subprocess, sys, tempfile, os
tmp = os.path.join(tempfile.gettempdir(), 'msgids_check.json')
subprocess.run([sys.executable, 'tools/l10n/extract.py', tmp], check=True, stdout=subprocess.DEVNULL)
ids = json.load(open(tmp, encoding='utf-8'))
src = json.load(open('localization/en_source.json', encoding='utf-8'))
missing = [k for k in ids if k not in src]
for k in missing:
    print(json.dumps(k, ensure_ascii=False), '  <-', ids[k])
print(len(missing), 'eksik çeviri')
sys.exit(1 if missing else 0)
