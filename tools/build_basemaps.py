"""Build small, local OSM vector basemaps for Metro Atlas.

Requires Python 3.12+ and `pip install osmium`. Downloads city/state extracts
from Geofabrik, clips to the playable rail/demand area plus a 10 km margin,
then writes compressed city JSON files that Godot can bundle directly.
"""

from __future__ import annotations

import gzip
import hashlib
import json
import math
import re
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import osmium


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data" / "basemap"
SOURCE_DIR = ROOT / ".tools" / "osm-source"
CITIES = ROOT / "data" / "cities.json"
MARGIN_M = 10_000.0
CHUNK_DEGREES = 0.05
EXTRACTS = {
    "shanghai": "https://download.geofabrik.de/asia/china/shanghai-latest.osm.pbf",
    "beijing": "https://download.geofabrik.de/asia/china/beijing-latest.osm.pbf",
    "guangzhou": "https://download.geofabrik.de/asia/china/guangdong-latest.osm.pbf",
    "shenzhen": "https://download.geofabrik.de/asia/china/guangdong-latest.osm.pbf",
    "chengdu": "https://download.geofabrik.de/asia/china/sichuan-latest.osm.pbf",
}
ROAD_CLASSES = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential"}
GREEN_TAGS = {"forest", "grass", "meadow", "recreation_ground", "village_green", "greenfield"}


def feature_bbox(points: list[list[float]]) -> list[float]:
    lats = [point[0] for point in points]
    lons = [point[1] for point in points]
    return [min(lats), min(lons), max(lats), max(lons)]


def simplify(points: list[list[float]], tolerance_m: float) -> list[list[float]]:
    if len(points) <= 2:
        return points
    lat0 = math.radians(sum(point[0] for point in points) / len(points))
    scale_x = 111_320.0 * math.cos(lat0)
    scale_y = 111_132.0
    xy = [(point[1] * scale_x, point[0] * scale_y) for point in points]
    keep = {0, len(points) - 1}
    pending = [(0, len(points) - 1)]
    tolerance2 = tolerance_m * tolerance_m
    while pending:
        first, last = pending.pop()
        ax, ay = xy[first]
        bx, by = xy[last]
        dx, dy = bx - ax, by - ay
        divisor = dx * dx + dy * dy
        best_index = -1
        best_distance2 = tolerance2
        for index in range(first + 1, last):
            px, py = xy[index]
            t = 0.0 if divisor == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / divisor))
            qx, qy = ax + t * dx, ay + t * dy
            distance2 = (px - qx) ** 2 + (py - qy) ** 2
            if distance2 > best_distance2:
                best_index, best_distance2 = index, distance2
        if best_index >= 0:
            keep.add(best_index)
            pending.extend(((first, best_index), (best_index, last)))
    return [points[index] for index in sorted(keep)]


class ExtractHandler(osmium.SimpleHandler):
    def __init__(self, bounds: list[float]) -> None:
        super().__init__()
        self.south, self.west, self.north, self.east = bounds
        self.features: list[dict] = []

    def way(self, way: osmium.osm.Way) -> None:
        tags = way.tags
        highway = tags.get("highway")
        waterway = tags.get("waterway")
        leisure = tags.get("leisure")
        landuse = tags.get("landuse")
        natural = tags.get("natural")
        is_building = "building" in tags and tags.get("building") != "no"
        important_building = (
            tags.get("building") in {"hospital", "school", "university", "college", "train_station", "transportation", "civic", "public", "stadium", "museum"}
            or tags.get("amenity") in {"university", "college", "school", "hospital", "clinic", "library", "townhall", "courthouse"}
            or tags.get("railway") == "station"
            or tags.get("public_transport") == "station"
            or tags.get("aeroway") == "terminal"
            or tags.get("tourism") in {"attraction", "museum"}
        )
        road_kind = None
        if highway in ROAD_CLASSES:
            road_kind = "road_major" if highway in {"motorway", "trunk"} else "road_primary" if highway == "primary" else "road_secondary" if highway in {"secondary", "tertiary", "unclassified"} else "road_local"
        water_kind = "water_line" if waterway in {"river", "canal", "stream"} else None
        park_kind = "park" if leisure == "park" or landuse in GREEN_TAGS else None
        water_area = (natural == "water" or tags.get("water") is not None or landuse == "reservoir") and way.is_closed()
        if not any((road_kind, water_kind, park_kind, water_area, (is_building or important_building) and way.is_closed())):
            return
        points: list[list[float]] = []
        try:
            for node in way.nodes:
                if not node.location.valid():
                    continue
                lat, lon = node.location.lat, node.location.lon
                if self.south - 0.02 <= lat <= self.north + 0.02 and self.west - 0.02 <= lon <= self.east + 0.02:
                    points.append([round(lat, 6), round(lon, 6)])
                else:
                    points.append([round(lat, 6), round(lon, 6)])
        except (RuntimeError, osmium.InvalidLocationError):
            return
        if len(points) < 2:
            return
        box = feature_bbox(points)
        if box[2] < self.south or box[0] > self.north or box[3] < self.west or box[1] > self.east:
            return
        if road_kind:
            kind = road_kind
        elif water_kind:
            kind = water_kind
        elif water_area:
            kind = "water_area"
        elif park_kind:
            kind = "park"
        elif important_building:
            kind = "building_major"
        else:
            kind = "building"
        tolerance = {"road_major": 5.0, "road_primary": 4.0, "road_secondary": 3.0, "road_local": 2.0, "water_line": 3.0, "water_area": 5.0, "park": 5.0, "building": 2.0, "building_major": 1.5}[kind]
        points = simplify(points, tolerance)
        if len(points) < 2:
            return
        self.features.append({
            "id": f"way/{way.id}",
            "kind": kind,
            "name": tags.get("name:zh") or tags.get("name", ""),
            "bbox": feature_bbox(points),
            "points": points,
        })


def download(url: str, destination: Path, previous_manifest: dict) -> dict:
    if destination.exists():
        payload = destination.read_bytes()
        old_city = next((entry for entry in previous_manifest.get("cities", {}).values() if entry.get("source") == url), {})
        return {"bytes": len(payload), "sha256": old_city.get("sourceSha256", hashlib.sha256(payload).hexdigest()), "lastModified": old_city.get("sourceModified", "unknown")}
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "MetroAtlasDesktop/0.10 (offline basemap build)"})
    digest = hashlib.sha256()
    total = 0
    with urllib.request.urlopen(request, timeout=180) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
            total += len(chunk)
        return {"bytes": total, "sha256": digest.hexdigest(), "lastModified": response.headers.get("Last-Modified", "unknown")}


def playable_bounds(city: dict) -> list[float]:
    points = [item.get("latlng", []) for item in city.get("stations", []) + city.get("demand", [])]
    points = [point for point in points if len(point) >= 2]
    if not points:
        return city["dataBbox"]
    south, north = min(float(point[0]) for point in points), max(float(point[0]) for point in points)
    west, east = min(float(point[1]) for point in points), max(float(point[1]) for point in points)
    center_lat = (south + north) * 0.5
    lat_margin = MARGIN_M / 111_132.0
    lon_margin = MARGIN_M / (111_320.0 * math.cos(math.radians(center_lat)))
    south, north = south - lat_margin, north + lat_margin
    west, east = west - lon_margin, east + lon_margin
    return [south, west, north, east]


def published_city_ids() -> list[str] | None:
    """Read the release list from the game, or None to build every city."""
    source = (ROOT / "scripts" / "world_data.gd").read_text(encoding="utf-8")
    match = re.search(r'PUBLISHED_CITY_IDS\s*:?=\s*\[([^\]]*)\]', source)
    if not match:
        raise RuntimeError("Cannot read PUBLISHED_CITY_IDS from scripts/world_data.gd")
    return re.findall(r'"([^"]+)"', match.group(1))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dataset = json.loads(CITIES.read_text(encoding="utf-8"))
    old_manifest_path = OUT_DIR / "manifest.json"
    previous_manifest = json.loads(old_manifest_path.read_text(encoding="utf-8")) if old_manifest_path.exists() else {}
    manifest = {"schemaVersion": 1, "generatedAt": datetime.now(timezone.utc).isoformat(), "license": "ODbL-1.0", "attribution": "© OpenStreetMap contributors", "cities": {}}
    source_metadata: dict[str, dict] = {}
    published = published_city_ids()
    for city in dataset["cities"]:
        city_id = city["id"]
        # Only the cities this build publishes need tiles. The rest stay in
        # cities.json for catalog validation, but shipping their tiles would
        # add tens of megabytes that no code path ever reads.
        if published is not None and city_id not in published:
            continue
        url = EXTRACTS[city_id]
        source_path = SOURCE_DIR / (url.rsplit("/", 1)[-1])
        if url not in source_metadata:
            source_metadata[url] = download(url, source_path, previous_manifest)
        bounds = playable_bounds(city)
        handler = ExtractHandler(bounds)
        handler.apply_file(str(source_path), locations=True, idx="flex_mem")
        result = {
            "cityId": city_id,
            "snapshot": source_metadata[url]["lastModified"],
            "source": url,
            "license": "ODbL-1.0",
            "attribution": "© OpenStreetMap contributors",
            "bbox": bounds,
            "features": handler.features,
        }
        city_dir = OUT_DIR / city_id
        city_dir.mkdir(parents=True, exist_ok=True)
        for stale_chunk in city_dir.glob("*.json.gz"):
            stale_chunk.unlink()
        chunks: dict[str, list[dict]] = {}
        for feature in handler.features:
            box = feature["bbox"]
            row_min = max(math.floor(bounds[0] / CHUNK_DEGREES), math.floor(box[0] / CHUNK_DEGREES))
            row_max = min(math.floor(bounds[2] / CHUNK_DEGREES), math.floor(box[2] / CHUNK_DEGREES))
            col_min = max(math.floor(bounds[1] / CHUNK_DEGREES), math.floor(box[1] / CHUNK_DEGREES))
            col_max = min(math.floor(bounds[3] / CHUNK_DEGREES), math.floor(box[3] / CHUNK_DEGREES))
            for row in range(row_min, row_max + 1):
                for col in range(col_min, col_max + 1):
                    chunk_key = f"{row}_{col}"
                    chunks.setdefault(chunk_key, []).append(feature)
        package_bytes = 0
        chunk_paths: list[str] = []
        chunk_sha256: dict[str, str] = {}
        chunk_uncompressed_bytes: dict[str, int] = {}
        for chunk_key, features in chunks.items():
            chunk_result = {"cityId": city_id, "snapshot": source_metadata[url]["lastModified"], "features": features}
            encoded = json.dumps(chunk_result, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            target = city_dir / f"{chunk_key}.json.gz"
            with target.open("wb") as stream:
                with gzip.GzipFile(fileobj=stream, mode="wb", compresslevel=9, mtime=0) as archive:
                    archive.write(encoded)
            package_bytes += target.stat().st_size
            chunk_paths.append(target.name)
            chunk_sha256[target.name] = hashlib.sha256(target.read_bytes()).hexdigest()
            chunk_uncompressed_bytes[target.name] = len(encoded)
        old_flat = OUT_DIR / f"{city_id}.json.gz"
        if old_flat.exists(): old_flat.unlink()
        manifest["cities"][city_id] = {
            "path": city_id,
            "chunkDegrees": CHUNK_DEGREES,
            "chunks": chunk_paths,
            "chunkSha256": chunk_sha256,
            "chunkUncompressedBytes": chunk_uncompressed_bytes,
            "featureCount": len(handler.features),
            "bounds": bounds,
            "source": url,
            "sourceModified": source_metadata[url]["lastModified"],
            "sourceSha256": source_metadata[url]["sha256"],
            "packageBytes": package_bytes,
        }
        print(f"{city_id}: {len(handler.features):,} features, {len(chunk_paths):,} view chunks, {package_bytes:,} compressed bytes")
    (OUT_DIR / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
