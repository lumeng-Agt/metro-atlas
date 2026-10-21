"""Find candidate station-area coordinates at published street junctions.

Uses bundled modern basemap road features only as geographic reference. It does
not infer engineering alignment or historical road conditions.
"""
import gzip
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def segments(points):
    return list(zip(points, points[1:]))

def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]

def intersection(a, b, c, d):
    # x=longitude, y=latitude; sufficient for short street segments.
    r = (b[1] - a[1], b[0] - a[0])
    s = (d[1] - c[1], d[0] - c[0])
    den = cross(r, s)
    if abs(den) < 1e-14:
        return None
    ca = (c[1] - a[1], c[0] - a[0])
    t = cross(ca, s) / den
    u = cross(ca, r) / den
    if -1e-8 <= t <= 1.00000001 and -1e-8 <= u <= 1.00000001:
        lon = a[1] + t * r[0]
        lat = a[0] + t * r[1]
        return [round(lat, 7), round(lon, 7)]
    return None

def main():
    import sys
    city_id = sys.argv[1]
    requested = sys.argv[2:]
    pairs = []
    if requested:
        for value in requested:
            left, right = value.split("|", 1)
            pairs.append((left, right))
    else:
        pairs = [
            ("龙吴路", "紫龙路"), ("龙吴路", "放鹤路"), ("龙吴路", "元江路"),
            ("龙吴路", "墨江路"), ("龙吴路", "澄江路"), ("龙吴路", "景联路"),
            ("龙吴路", "华泾路"), ("龙吴路", "龙瑞路"), ("龙吴路", "龙启路"),
            ("龙吴路", "沪金高速"), ("龙吴路", "徐浦大桥"),
        ]
    manifest = json.loads((ROOT / "data/basemap/manifest.json").read_text(encoding="utf-8"))
    package = manifest["cities"][city_id]
    roads = {}
    for chunk_name in package.get("chunks", []):
        path = ROOT / "data/basemap" / package.get("path", city_id) / chunk_name
        try:
            rows = json.loads(gzip.decompress(path.read_bytes())).get("features", [])
        except Exception:
            continue
        for feature in rows:
            name = str(feature.get("name", ""))
            if name in {name for pair in pairs for name in pair} and str(feature.get("kind", "")).startswith("road"):
                roads.setdefault(name, {})[str(feature.get("id", ""))] = feature
    for road_a, road_b in pairs:
        candidates = []
        for fa in roads.get(road_a, {}).values():
            for fb in roads.get(road_b, {}).values():
                for a, b in segments(fa.get("points", [])):
                    for c, d in segments(fb.get("points", [])):
                        point = intersection(a, b, c, d)
                        if point:
                            candidates.append({"latlng": point, "a": fa.get("id"), "b": fb.get("id")})
        unique = {tuple(row["latlng"]): row for row in candidates}
        print(json.dumps({"pair": [road_a, road_b], "matches": list(unique.values())[:30]}, ensure_ascii=True))

if __name__ == "__main__":
    main()
