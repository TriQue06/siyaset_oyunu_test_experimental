import re, glob, json, sys
STR = r'"((?:[^"\\]|\\.)*)"'
LT = re.compile(r'L\.t\(\s*' + STR + r'\s*\)')
ANY = re.compile(STR)
TR = set('çğıöşüÇĞİÖŞÜ')
CONST_BLOCKS = {
    'scripts/card_presets.gd': ['AGENDAS', 'CRISES'],
    'scripts/economy.gd': ['TAX_TITLES'],
    'scripts/economy_panel.gd': ['INQUIRY_TAGS'],
    'scripts/effect_words.gd': ['GOOD', 'BAD', 'AMOUNT'],
    'scripts/election_results.gd': ['FLAVOR'],
    'scripts/game_screen.gd': ['PLAYER_TAB_TITLES', 'PLAYER_TAB_TOOLTIPS', 'PLAYER_TAB_COLUMNS', 'MAP_LAYER_TITLES', 'SIDE_TAB_TITLES'],
    'scripts/government_presets.gd': ['POSTS'],
    'scripts/politician_presets.gd': ['BACKGROUNDS'],
    'scripts/voter_groups.gd': ['GROUPS'],
}

def unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'"}.get(n, '\\' + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)

def wanted(s):
    if len(s) < 2 or re.fullmatch(r'[a-z0-9_:./\-]+', s):
        return False
    return True

ids = {}
def add(s, where):
    s = unescape(s)
    if wanted(s):
        ids.setdefault(s, where)

for f in sorted(glob.glob('scripts/*.gd')):
    f = f.replace('\\', '/')
    text = open(f, encoding='utf-8').read()
    for m in LT.finditer(text):
        add(m.group(1), f)
    for block in CONST_BLOCKS.get(f, []):
        start = re.search(r'^(const|static var|var)\s+' + block + r'\b', text, re.M)
        if not start:
            print('YOK', f, block); continue
        depth = 0
        i = start.start()
        started = False
        while i < len(text):
            ch = text[i]
            if ch == '"':
                m = ANY.match(text, i)
                s = m.group(1)
                if any(c in TR for c in s) or (' ' in s and re.search('[A-Za-z]{2}', s)) or (s[:1].isupper() and len(s) > 2):
                    add(s, f + ':' + block)
                i = m.end(); continue
            if ch == '#':
                i = text.index('\n', i); continue
            if ch in '[{(':
                depth += 1; started = True
            elif ch in ']})':
                depth -= 1
            elif ch == '\n' and started and depth == 0:
                break
            i += 1
for f in glob.glob('scenes/*.tscn'):
    for m in re.finditer(r'^(text|tooltip_text|placeholder_text) = ' + STR, open(f, encoding='utf-8').read(), re.M):
        add(m.group(2), f)
json.dump(ids, open(sys.argv[1], 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
print(len(ids), 'metin')
