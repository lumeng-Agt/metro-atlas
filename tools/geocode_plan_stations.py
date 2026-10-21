#!/usr/bin/env python3
"""Suggest station-area points for a project spec, then require human review.

The helper never writes game data. It resolves every station in an explicit
project spec against (1) station points already in the bundled city data and
(2) OpenStreetMap Nominatim name lookups, then keeps only candidates that stay
near the corridor implied by already-verified stations. Every surviving point
is reported with its distance from that corridor so a reviewer can accept,
replace or drop it.

Spec format:
  {"city": "shanghai", "stations": [{"name": "铁通路"}, {"name": "海伦路", "existingId": "shanghai-sXX"}]}

A station may carry explicit "expected": [lat, lon] when a published mileage
table fixes its position along a short corridor between two verified stations;
the lookup is then scored against that point instead of a plain index fraction.

Output: a JSON report on stdout, one row per requested station.
"""
from __future__ import annotations

import json
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE_PATH = ROOT / ".tmp-nominatim-cache.json"
MAX_CORRIDOR_M = 4000


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def distance_m(a: list[float], b: list[float]) -> float:
    lat1, lon1 = math.radians(a[0]), math.radians(a[1])
    lat2, lon2 = math.radians(b[0]), math.radians(b[1])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000.0 * 2 * math.asin(min(1.0, math.sqrt(h)))


def segment_distance_m(point: list[float], start: list[float], end: list[float]) -> float:
    # Local planar projection is accurate enough for corridor screening.
    scale = math.cos(math.radians(point[0]))
    px, py = point[1] * scale, point[0]
    ax, ay = start[1] * scale, start[0]
    bx, by = end[1] * scale, end[0]
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return distance_m(point, start)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    closest = [start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t]
    return distance_m(point, closest)


def corridor_distance_m(point: list[float], corridor: list[list[float]]) -> float:
    if len(corridor) < 2:
        return 0.0
    return min(segment_distance_m(point, corridor[i], corridor[i + 1]) for i in range(len(corridor) - 1))


def interpolate(corridor: list[list[float]], start_index: int, end_index: int, fraction: float) -> list[float]:
    start, end = corridor[start_index], corridor[end_index]
    return [start[0] + (end[0] - start[0]) * fraction, start[1] + (end[1] - start[1]) * fraction]


def nominatim(city_name: str, name: str, cache: dict) -> list[dict]:
    key = f"{city_name}/{name}"
    if key in cache:
        return cache[key]
    results: list[dict] = []
    for query_text in (f"{name}站, {city_name}, 中国", f"{name}, {city_name}, 中国"):
        query = urllib.parse.urlencode({"q": query_text, "format": "jsonv2", "limit": 5, "accept-language": "zh-CN"})
        request = urllib.request.Request(
            f"https://nominatim.openstreetmap.org/search?{query}",
            headers={"User-Agent": "MetroAtlasDesktop/0.25 project-station-review"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                rows = json.loads(response.read().decode("utf-8"))
        except Exception as exc:  # Report and continue; one miss must not stop the batch.
            rows = []
            results.append({"error": str(exc), "query": query_text})
        for row in rows:
            try:
                results.append({
                    "latlng": [round(float(row["lat"]), 7), round(float(row["lon"]), 7)],
                    "label": str(row.get("display_name", ""))[:120],
                    "type": str(row.get("type", "")),
                    "class": str(row.get("class", "")),
                    "query": query_text,
                })
            except (KeyError, TypeError, ValueError):
                continue
        time.sleep(1.1)
    cache[key] = results
    return results


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    spec = load(Path(sys.argv[1]))
    city_id = str(spec["city"])
    cities = load(ROOT / "data/cities.json")
    city = next(row for row in cities["cities"] if row["id"] == city_id)
    by_name: dict[str, list[dict]] = {}
    by_id: dict[str, dict] = {}
    for station in city.get("stations", []):
        by_name.setdefault(str(station.get("name", "")), []).append(station)
        by_id[str(station.get("id", ""))] = station
    cache = load(CACHE_PATH) if CACHE_PATH.exists() else {}

    rows: list[dict] = []
    for entry in spec["stations"]:
        name = str(entry["name"])
        row: dict = {"name": name}
        existing_id = str(entry.get("existingId", ""))
        if existing_id and existing_id in by_id:
            station = by_id[existing_id]
            row.update({"latlng": station.get("latlng"), "method": "existing_station_id", "stationId": existing_id, "corridorM": 0})
        elif name in by_name:
            station = by_name[name][0]
            row.update({"latlng": station.get("latlng"), "method": "existing_station_name", "stationId": str(station.get("id", "")), "corridorM": 0})
        else:
            candidates = [c for c in nominatim(str(city.get("name", city_id)), name, cache) if c.get("latlng")]
            row.update({"candidates": candidates[:6], "method": "nominatim_pending"})
        rows.append(row)

    CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")

    anchors = [(index, row["latlng"]) for index, row in enumerate(rows) if row.get("latlng")]
    if len(anchors) >= 2:
        corridor = [point for _index, point in anchors]
        for index, row in enumerate(rows):
            if not row.get("method") == "nominatim_pending":
                continue
            entry = spec["stations"][index]
            previous = max((a for a in anchors if a[0] < index), default=None, key=lambda a: a[0])
            following = min((a for a in anchors if a[0] > index), default=None, key=lambda a: a[0])
            if entry.get("expected"):
                expected = [float(entry["expected"][0]), float(entry["expected"][1])]
            elif previous and following:
                fraction = (index - previous[0]) / (following[0] - previous[0])
                expected = interpolate(corridor, anchors.index(previous), anchors.index(following), fraction)
            else:
                expected = (previous or following)[1]
            scored = sorted(
                ({"latlng": c["latlng"], "label": c["label"], "type": c["type"], "class": c["class"],
                  "corridorM": round(corridor_distance_m(c["latlng"], corridor)),
                  "expectedM": round(distance_m(c["latlng"], expected))}
                 for c in row.get("candidates", [])),
                key=lambda item: item["corridorM"] + item["expectedM"],
            )
            row["scored"] = scored[:4]
            if scored and scored[0]["corridorM"] <= MAX_CORRIDOR_M:
                row["latlng"] = scored[0]["latlng"]
                row["method"] = "nominatim_corridor_match"
                row["corridorM"] = scored[0]["corridorM"]
            else:
                row["method"] = "needs_manual_point"
                row.pop("latlng", None)
    elif len(anchors) == 1:
        for row in rows:
            if row.get("method") == "nominatim_pending":
                row["method"] = "needs_manual_point"

    report = {"city": city_id, "stations": rows,
              "unresolved": [row["name"] for row in rows if not row.get("latlng")]}
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
