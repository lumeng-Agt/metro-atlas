"""Load every city's official station roster into one shape.

Four of the five cities publish their station tables in four different JSON
shapes, so the alignment code cannot read them directly. This module normalises
them to `{line label: [pattern, ...]}` where a pattern is one published service
order (a line may publish several: a main line and a branch, or two directions).
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SOURCES = {
    'shenzhen': ('data/official_evidence/shenzhen_2026-06-28_station_orders.json', 'stationOrders'),
    'shanghai': ('data/official_evidence/shanghai_operator_orders_retrieved2026-10-23.json', 'shanghai'),
    'beijing': ('data/official_evidence/beijing_operator_distance_tables_retrieved2026-10-25.json', 'beijing'),
    'guangzhou': ('data/official_evidence/guangzhou_operator_orders_retrieved2026-10-25.json', 'guangzhou'),
    'chengdu': ('data/official_evidence/chengdu_operator_orders_retrieved2026-10-23.json', 'chengdu'),
}


def _read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def _patterns(value):
    """Accept a bare order, a list of orders, or a dict holding either."""
    if isinstance(value, dict):
        for key in ('orders', 'stationNames', 'stationOrders'):
            if key in value:
                return _patterns(value[key])
        return []
    if not value:
        return []
    if isinstance(value[0], str):
        return [list(value)]
    return [list(pattern) for pattern in value if pattern]


def _shenzhen(document):
    return {label: _patterns(order) for label, order in document['stationOrders'].items()}


def _shanghai(document):
    return {f'{key}号线': _patterns(entry.get('orders')) for key, entry in document['lines'].items()}


def _chengdu(document):
    out = {}
    for key, entry in document['lines'].items():
        label = entry.get('name') or f'{key}号线'
        out[label] = _patterns(entry.get('orders'))
    return out


def _guangzhou(document):
    out = {}
    for entry in document['lines']:
        label = entry.get('lineName') or f'{entry.get("lineCode")}号线'
        out[label] = _patterns(entry.get('stationNames'))
        code = str(entry.get('lineCode', ''))
        if code:
            out.setdefault(f'{code}号线', out[label])
    return out


def _beijing(document):
    out = {}
    for entry in document['lines']:
        label = entry.get('line', '')
        patterns = []
        for direction in entry.get('directions', []):
            names = direction.get('stationNames') or []
            if names:
                patterns.append(list(names))
                if direction.get('loop') and names[0] == names[-1]:
                    patterns.append(list(names[:-1]))
        if patterns:
            out[label] = patterns
    return out


LOADERS = {'shenzhen': _shenzhen, 'shanghai': _shanghai, 'beijing': _beijing,
           'guangzhou': _guangzhou, 'chengdu': _chengdu}


def load(city_id):
    """Return `{line label: [pattern, ...]}` plus the source document metadata."""
    name, _ = SOURCES[city_id]
    document = _read(name)
    rosters = LOADERS[city_id](document)
    return rosters, document


def flat(rosters):
    """All patterns flattened, keyed by a stable 'label#index' identity."""
    out = {}
    for label, patterns in rosters.items():
        for index, pattern in enumerate(patterns):
            out[f'{label}#{index}'] = pattern
    return out


if __name__ == '__main__':
    for city in SOURCES:
        rosters, document = load(city)
        total = sum(len(p) for p in rosters.values())
        print(f'{city}: {len(rosters)} lines, {total} patterns, keys={sorted(rosters)[:6]}')
