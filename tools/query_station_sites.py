"""Read-only local OSM candidate lookup; authors must review every match.

No coordinate inference or automatic chapter updates are performed. Coordinates
of ways are vertex averages for discovery, never surveyed station centres.
"""
import argparse
import json
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('region', choices=['shanghai', 'beijing', 'guangdong', 'sichuan'])
    parser.add_argument('names', nargs='+')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    names = {name.removesuffix('站') for name in args.names}
    rows = []
    processor = osmium.FileProcessor(str(ROOT / '.tools/osm-source' / f'{args.region}-latest.osm.pbf')).with_locations()
    for obj in processor.with_filter(osmium.filter.KeyFilter('name', 'old_name', 'construction:name')):
        tags = dict(obj.tags)
        labels = {part.removesuffix('站') for key in ['name', 'old_name', 'construction:name'] for part in tags.get(key, '').split(';')}
        if not names.intersection(labels):
            continue
        if isinstance(obj, osmium.osm.Node):
            points = [(obj.location.lat, obj.location.lon)] if obj.location.valid() else []
        elif isinstance(obj, osmium.osm.Way):
            points = [(n.lat, n.lon) for n in obj.nodes if n.location.valid()]
        else:
            continue
        if not points:
            continue
        rows.append({'type': 'node' if isinstance(obj, osmium.osm.Node) else 'way', 'osmId': obj.id,
                     'name': tags.get('name', ''), 'tags': tags,
                     'latlng': [round(sum(p[i] for p in points) / len(points), 7) for i in (0, 1)]})
    args.output.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{len(rows)} candidates; review names, railway tags and official siting before use: {args.output}')


if __name__ == '__main__':
    main()
