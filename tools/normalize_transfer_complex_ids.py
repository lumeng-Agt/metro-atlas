"""Replace deprecated composite station IDs in transfer requirements.

A transfer requirement names a station complex. Several complexes were split
into line-specific physical bodies later; the old composite ID stayed behind in
`requiredTransfers[].complexId`. The runtime already canonicalises the value, so
this rewrites the stored requirement to the canonical identity instead of
relying on the alias table forever.

Only `complexId` changes. Requirement IDs, physical body IDs, station orders,
alignments and route data keep their historical identity, because the transfer
ID is quoted by the independent target roster and renaming it would silently
detach reviewed coverage.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.28.1'

# Deprecated composite ID -> canonical station complex ID. Values must be
# terminal: a value that is itself an alias key would need another pass.
MAPPING = {
    'shanghai-s305': 'shanghai-s397',
    'shanghai-s83': 'shanghai-s119',
    'beijing-s69': 'beijing-s101',
    'beijing-s219': 'beijing-s357',
    'beijing-s371': 'beijing-s158',
    'beijing-s228': 'beijing-s390',
    'chengdu-s104': 'chengdu-s328',
    'chengdu-s356': 'chengdu-s147',
}

SPEC_FILES = ('tools/project_specs/bj-line13-capacity.json',)


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def rewrite(rows, where, changed):
    for row in rows:
        if not isinstance(row, dict):
            continue
        old = str(row.get('complexId', ''))
        if old in MAPPING:
            row['complexId'] = MAPPING[old]
            changed.append((where, str(row.get('id', '')), old, MAPPING[old]))


def main():
    for city_id, city in read('data/campaigns.json').get('cities', {}).items():
        aliases = city.get('stationComplexAliases', {})
        for key, value in MAPPING.items():
            if key in aliases and aliases[key] != value:
                raise SystemExit(f'{city_id}: alias {key} points at {aliases[key]}, not {value}')
            if value in aliases:
                raise SystemExit(f'{city_id}: canonical value {value} is itself an alias key')

    campaigns = read('data/campaigns.json')
    changed = []
    for city_id, city in campaigns.get('cities', {}).items():
        for phase in ('chapters', 'futurePlans'):
            for plan in city.get(phase, []):
                where = f'{city_id}/{phase}/{plan.get("id", "")}'
                rewrite(plan.get('requiredTransfers', []), where, changed)
                rewrite(plan.get('transfers', []), where, changed)

    specs = []
    for name in SPEC_FILES:
        spec = read(name)
        local = []
        rewrite(spec.get('transfers', []), name, local)
        if local:
            write(name, spec)
            specs.extend(local)

    if not changed and not specs:
        print('ALREADY_CANONICAL no transfer requirement uses a deprecated complex ID')
        return

    campaigns['contentRevision'] = REVISION
    campaigns['contentRevisionNote'] = (
        '把16处换乘要求里的弃用复合站ID改写为规范站区ID（另同步北京13号线扩能项目2处），'
        '并为北京22号线、28号线、M101线一期补入逐对独立换乘结构定义；不改换乘编号、物理站体、站序与线位。')
    write('data/campaigns.json', campaigns)

    print(f'REWROTE_CAMPAIGN_ROWS {len(changed)}')
    for row in changed:
        print('  ', ' -> '.join(row))
    print(f'REWROTE_SPEC_ROWS {len(specs)}')
    for row in specs:
        print('  ', ' -> '.join(row))
    print('CONTENT_REVISION', REVISION)


if __name__ == '__main__':
    main()
