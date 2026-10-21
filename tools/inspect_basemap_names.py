"""Inspect bundled basemap features by visible name for content QA."""
import gzip
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / "data/basemap/manifest.json").read_text(encoding="utf-8"))
city_id = sys.argv[1]
queries = sys.argv[2:] or ["龙吴路", "东川路", "江川东路", "紫龙路", "放鹤路", "元江路", "澄江路", "景东路", "墨江路", "沪闵路", "虹梅南路"]
package = manifest["cities"][city_id]
seen = set()
for chunk_name in package.get("chunks", []):
    path = root / "data/basemap" / package.get("path", city_id) / chunk_name
    try:
        payload = json.loads(gzip.decompress(path.read_bytes()))
    except Exception:
        continue
    for feature in payload.get("features", []):
        name = str(feature.get("name", ""))
        if not name or not any(query in name for query in queries):
            continue
        key = (feature.get("id"), name, tuple(feature.get("bbox", [])))
        if key in seen:
            continue
        seen.add(key)
        print(json.dumps({
            "id": feature.get("id"), "name": name,
            "kind": feature.get("kind"), "bbox": feature.get("bbox"),
            "point_count": len(feature.get("points", [])),
            "points_sample": feature.get("points", [])[:3],
        }, ensure_ascii=False))
