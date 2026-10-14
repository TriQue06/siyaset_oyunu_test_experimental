## Çeviri kaynağından (localization/en_source.json: Türkçe -> İngilizce)
## localization/en.po üretir; biçim belirteçlerinin (%s, %d, %.1f ...) sırası
## ve sayısı kaynakla uyuşmuyorsa durur. Godot "%" biçimlendirmesinde argüman
## sırası değiştirilemez: İngilizce cümle değerleri Türkçedeki sırayla almalı.
##   python tools/l10n/build_po.py
import json, re, sys

src = json.load(open('localization/en_source.json', encoding='utf-8'))
SPEC = re.compile(r'%(?:%|[-+0-9.]*[sdfx])')
bad = 0
for k, v in src.items():
    a = [s for s in SPEC.findall(k) if s != '%%']
    b = [s for s in SPEC.findall(v) if s != '%%']
    if a != b:
        print('UYUMSUZ:', json.dumps(k, ensure_ascii=False), '->', json.dumps(v, ensure_ascii=False))
        bad += 1
if bad:
    sys.exit(1)


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


out = ['msgid ""', 'msgstr ""', '"Content-Type: text/plain; charset=UTF-8\\n"', '"Language: en\\n"', '']
n = 0
for k, v in src.items():
    if k != v:  # aynı kalan (özel ad, düğüm adı) yazılmaz
        out += ['msgid "%s"' % esc(k), 'msgstr "%s"' % esc(v), '']
        n += 1
open('localization/en.po', 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print(n, 'çeviri yazıldı')
