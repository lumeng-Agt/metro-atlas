"""Extract station order from the operator's public first/last train API.

The raw responses are independent of game data. This is a current geographic
cross-check, not proof of historical opening dates. Review the dated opening
notices separately before applying a cutoff or any historical milestone.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import urllib.request

ENDPOINT = 'https://m.shmetro.com/interface/metromap/metromap.aspx?func=fltime&line='


def extract(rows, line=None):
    groups = {}
    for row in rows:
        # Arrival-only terminus records still carry the official station name.
        if not row.get('name') or not row.get('first_time'):
            continue
        # The reverse-direction label on line 5 combines both branches in
        # one unordered list. Its two outward labels are separate paths.
        if line == 5 and row.get('direction') != 1:
            continue
        key = (row.get('direction'), row.get('description'))
        names = groups.setdefault(key, [])
        name = row['name'].strip()
        if name not in names:
            names.append(name)
    orders = []
    for names in groups.values():
        if len(names) < 2 or any(set(names) < set(other) for other in groups.values()):
            continue
        if names not in orders and list(reversed(names)) not in orders:
            orders.append(names)
    return orders


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.cache_dir.mkdir(parents=True, exist_ok=True)

    def fetch(line):
        path = args.cache_dir / f'line-{line}.json'
        if not path.exists():
            request = urllib.request.Request(ENDPOINT + str(line), headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(request, timeout=35) as response:
                path.write_bytes(response.read())
        raw = path.read_bytes()
        rows = json.loads(raw)
        if not isinstance(rows, list) or not rows:
            raise ValueError(f'line {line}: no operator records')
        orders = extract(rows, line)
        if not orders:
            raise ValueError(f'line {line}: no usable station orders')
        return str(line), {'source': ENDPOINT + str(line), 'sha256': hashlib.sha256(raw).hexdigest(), 'orders': orders}

    with ThreadPoolExecutor(max_workers=4) as executor:
        lines = dict(executor.map(fetch, range(1, 19)))
    result = {'source': 'https://service.shmetro.com/hcskb/index.htm',
              'retrievedAt': '2026-10-23', 'reviewStatus': 'current_station_order_crosscheck_only',
              'note': '后取的现状站序不单独证明2026-10-01或之前各时期的开放范围；须与有日期的官方开通公告分别核对。未从游戏章节生成。',
              'lines': lines}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for line, value in lines.items():
        print(line, [len(order) for order in value['orders']])


if __name__ == '__main__':
    main()
