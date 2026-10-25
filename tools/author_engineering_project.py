"""Author a reviewed, non-passenger track project from explicit scope data.

The spec is reviewed source material, not inferred from chapters. This tool
cannot mark a city complete, change player progress, or invent a station.
"""
import argparse
import copy
import json
from pathlib import Path

from engineering_scope import definition_errors

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def apply(spec):
    campaigns = read(ROOT / 'data/campaigns.json')
    baseline = read(ROOT / 'data/network_baselines_2026-10-01.json')
    targets = read(ROOT / 'data/official_targets_2026-10-01.json')
    cities = read(ROOT / 'data/cities.json')
    city_id = spec['cityId']
    city = next(c for c in cities['cities'] if c['id'] == city_id)
    group = copy.deepcopy(spec['construction'])
    errors = definition_errors(group, {s['id'] for s in city['stations']})
    if errors:
        raise ValueError(errors)
    if spec['officialTarget'].get('reviewStatus') != 'verified':
        raise ValueError('Authoring requires explicit reviewed scope, not an unreviewed candidate')
    anchors = {e['stationId'] for e in group['engineeringEndpoints'] if 'stationId' in e}
    if set(group.get('stationIds', [])) != anchors:
        raise ValueError('Passenger station targets may only be existing engineering anchors')
    plan = copy.deepcopy(spec['chapter'])
    plan.update(lineGroups=[group], requiredTransfers=[], requireOpen=False,
                dataStatus='blueprint_ready', requiresScopeRecheck=True,
                scopeRevision=spec['contentRevision'])
    expected = copy.deepcopy(spec['officialTarget'])
    if expected['id'] not in plan['projectIds']:
        raise ValueError('Independent project and task identity differ')
    plans = campaigns['cities'][city_id]['futurePlans']
    old_index = next((i for i, p in enumerate(plans) if p['id'] == plan['id']), len(plans))
    if old_index == len(plans):
        plans.append(plan)
    else:
        plans[old_index] = plan
    requirements = targets['cities'][city_id]['projects']
    requirements[:] = [p for p in requirements if p['id'] != expected['id']] + [expected]
    project = next(p for p in baseline['cities'][city_id]['projectsAtCutoff'] if p['id'] == expected['id'])
    project.update(playabilityStatus='playable_build_task', source=plan['source'], sourceTitle=plan['sourceTitle'],
                   sourceCheckedAt=plan['sourceCheckedAt'], note=plan['description'],
                   playabilityNote='明确站端至工程接口的实体轨道任务；新站体仅限已公布站点，不虚构边界车站或运营线路。')
    campaigns['contentRevision'] = spec['contentRevision']
    baseline['contentRevision'] = spec['contentRevision']
    # Do not copy construction groups into the answer. Both were authored
    # separately in the reviewed spec, including endpoint and corridor checks.
    for name, value in [('campaigns.json', campaigns), ('network_baselines_2026-10-01.json', baseline),
                        ('official_targets_2026-10-01.json', targets)]:
        write(ROOT / 'data' / name, value)
    print('AUTHORED_ENGINEERING_PROJECT', city_id, expected['id'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec', type=Path)
    args = parser.parse_args()
    apply(read(args.spec))
