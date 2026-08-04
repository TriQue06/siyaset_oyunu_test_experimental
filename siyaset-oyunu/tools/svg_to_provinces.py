"""Turkey map SVG (path-based, M/L/C/Z absolute commands) -> provinces.json
for the Godot ProvinceMap system. Flattens cubic beziers into line segments,
keeps one polygon list per <path id="...">, and computes a placement center
(bounding-box center of the LARGEST sub-polygon by area, so seat dots land
on the mainland rather than on a small island exclave).
"""
import re
import json

SRC = r"C:\Users\baris\Desktop\turkey_map.svg"
OUT = r"C:\Users\baris\Documents\GitHub\siyaset_oyunu_test_experimental\siyaset-oyunu\data\provinces.json"

BEZIER_STEPS = 8  # curve flattening resolution
SIMPLIFY_EPSILON = 0.35  # harita birimi (viewBox 1024x500); RDP toleransı


def tokenize(d):
    # command letters and floating point numbers (handles "1.5-2.3" without space/comma)
    return re.findall(r"[MLCZ]|-?\d*\.?\d+(?:e-?\d+)?", d)


def parse_path(d):
    tokens = tokenize(d)
    i = 0
    n = len(tokens)
    subpaths = []  # list of list[(x,y)]
    current = []
    cmd = None
    cur = (0.0, 0.0)
    start = (0.0, 0.0)

    def read_num():
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    while i < n:
        tok = tokens[i]
        if tok in ("M", "L", "C", "Z"):
            cmd = tok
            i += 1
        # else: implicit repeat of previous command

        if cmd == "M":
            x, y = read_num(), read_num()
            if current:
                subpaths.append(current)
            current = [(x, y)]
            cur = (x, y)
            start = (x, y)
            cmd = "L"  # subsequent implicit pairs after M are lineto's
        elif cmd == "L":
            x, y = read_num(), read_num()
            current.append((x, y))
            cur = (x, y)
        elif cmd == "C":
            x1, y1 = read_num(), read_num()
            x2, y2 = read_num(), read_num()
            x, y = read_num(), read_num()
            for s in range(1, BEZIER_STEPS + 1):
                t = s / BEZIER_STEPS
                mt = 1 - t
                bx = (mt**3 * cur[0] + 3 * mt**2 * t * x1 + 3 * mt * t**2 * x2 + t**3 * x)
                by = (mt**3 * cur[1] + 3 * mt**2 * t * y1 + 3 * mt * t**2 * y2 + t**3 * y)
                current.append((bx, by))
            cur = (x, y)
        elif cmd == "Z":
            if current:
                current.append(start)
                subpaths.append(current)
            current = []
            cur = start
        else:
            raise ValueError("unexpected token %r at %d" % (tok, i))

    if current:
        subpaths.append(current)
    return subpaths


def polygon_area(points):
    a = 0.0
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        a += x1 * y2 - x2 * y1
    return abs(a) / 2.0


def bbox_center(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)


def _perp_dist(p, a, b):
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    cx, cy = ax + t * dx, ay + t * dy
    return ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5


def rdp(points, epsilon):
    # Ramer-Douglas-Peucker: bir çizgiye yakın (epsilon'dan yakın) noktaları
    # atar, şekli bozmadan nokta sayısını ciddi şekilde azaltır. Bezier'i
    # 8 alt-bölüme ayırıp sonra bu ölçüde sub-pixel noktaları elemek,
    # ~610 nokta/il ortalamasını görsel kaybı sıfıra yakınken çok düşürür.
    if len(points) < 3:
        return points
    start, end = points[0], points[-1]
    max_dist = -1.0
    max_idx = 0
    for i in range(1, len(points) - 1):
        d = _perp_dist(points[i], start, end)
        if d > max_dist:
            max_dist = d
            max_idx = i
    if max_dist > epsilon:
        left = rdp(points[: max_idx + 1], epsilon)
        right = rdp(points[max_idx:], epsilon)
        return left[:-1] + right
    return [start, end]


def main():
    with open(SRC, encoding="utf-8") as f:
        content = f.read()
    paths = re.findall(r'<path id="([^"]+)" d="([^"]+)"', content)

    result = {}
    for name, d in paths:
        subpaths = parse_path(d)
        subpaths = [sp for sp in subpaths if len(sp) >= 3]
        if not subpaths:
            continue
        largest = max(subpaths, key=polygon_area)
        cx, cy = bbox_center(largest)

        raw_point_count = sum(len(sp) for sp in subpaths)
        simplified = [rdp(sp, SIMPLIFY_EPSILON) for sp in subpaths]
        simplified_point_count = sum(len(sp) for sp in simplified)

        result[name] = {
            "polygons": [[[round(x, 2), round(y, 2)] for x, y in sp] for sp in simplified],
            "center": [round(cx, 2), round(cy, 2)],
        }
        result[name]["_raw_points"] = raw_point_count
        result[name]["_simplified_points"] = simplified_point_count

    total_raw = sum(v.pop("_raw_points") for v in result.values())
    total_simplified = sum(v.pop("_simplified_points") for v in result.values())

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print("provinces:", len(result))
    print("points: %d -> %d (%.1f%% azalma)" % (
        total_raw, total_simplified, 100 * (1 - total_simplified / total_raw)
    ))
    sizes = sorted(((len(v["polygons"]), k) for k, v in result.items()), reverse=True)
    print("most subpaths:", sizes[:5])


if __name__ == "__main__":
    main()
