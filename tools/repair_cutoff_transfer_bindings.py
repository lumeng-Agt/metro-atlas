"""Correct explicit transfer references against reviewed cutoff platform bindings.

Only relationship references change. Physical station/track coordinates are never
edited. Existing saves receive guarded, task-scoped proposals, not load-time edits.
Run with --write to materialize the reviewed proposals in the content package.
"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('city')
    parser.add_argument('--write', action='store_true')
    parser.add_argument('--legacy-save', type=Path, help='Read-only old-save fixture for guarded migration proposals')
    args = parser.parse_args()
    path = ROOT / 'data/campaigns.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    city = data['cities'][args.city]
    chapter = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    aliases = city.get('stationComplexAliases', {})

    def canonical(identity):
        seen = set()
        while identity in aliases and identity not in seen:
            seen.add(identity)
            identity = aliases[identity]
        return identity

    bindings = {}
    owners = {}
    for group in chapter['lineGroups']:
        for identity in group['stationIds']:
            key = (group['historicalLineId'], canonical(identity))
            body = city.get('stationInstanceAliases', {}).get(group['historicalLineId'] + '|' + identity,
                                                             group.get('stationInstances', {}).get(identity, identity))
            if key in bindings and bindings[key] != body:
                raise ValueError(f'Conflicting physical bindings: {key}')
            bindings[key] = body
            owners.setdefault(key, group['taskId'])
    count = 0
    entries = city['chapters'] + city.get('futurePlans', [])
    if args.legacy_save:
        legacy = json.loads(args.legacy_save.read_text(encoding='utf-8'))
        if legacy.get('cityId') != args.city:
            raise ValueError('Legacy fixture belongs to another city')
        entries = entries + [{'requiredTransfers': [r for r in legacy.get('transferConnections', []) if r.get('status', 'active') == 'active']}]
    for entry in entries:
        for relation in entry.get('requiredTransfers', []):
            for index, line in enumerate(relation['lineIds']):
                key = (line, canonical(relation['complexId']))
                if key not in bindings:
                    continue
                old = relation['stationInstanceIds'][index]
                new = bindings[key]
                if old == new:
                    continue
                correction = {
                    'taskId': owners[key], 'transferId': relation['id'],
                    'oldLineIds': relation['lineIds'].copy(),
                    'bodyRebindings': [{'index': index, 'oldStationInstanceId': old, 'newStationInstanceId': new}],
                    'description': f"{relation['name']}：更正{line}对应的独立站体引用，保留另一侧站体和已建站轨。",
                    'source': chapter['source'],
                }
                corrections = chapter.setdefault('scopeCorrections', [])
                if correction not in corrections:
                    corrections.append(correction)
                relation['stationInstanceIds'][index] = new
                count += 1
                print(f"{relation['id']}: {old} -> {new}")
    if args.write:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'{count} reference corrections; physical objects unchanged; write={args.write}')


if __name__ == '__main__':
    main()
