"""Check reviewed engineering specs without changing game data or progress."""
import json
from pathlib import Path
from engineering_scope import definition_errors, coverage_errors
from official_coverage import check_project

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    campaigns = read(ROOT / 'data/campaigns.json')
    targets = read(ROOT / 'data/official_targets_2026-10-01.json')
    cities = {c['id']: c for c in read(ROOT / 'data/cities.json')['cities']}
    errors = []
    specs = sorted((ROOT / 'tools/engineering_specs').glob('*.json'))
    for path in specs:
        spec = read(path)
        city_id = spec['cityId']
        known = {s['id'] for s in cities[city_id]['stations']}
        group = spec['construction']
        issues = definition_errors(group, known)
        expected = spec['officialTarget']
        if expected.get('reviewStatus') != 'verified' or not expected.get('sourcePublicationDate'):
            issues.append('engineering scope lacks a dated review')
        if spec['chapter']['date'] > campaigns['cutoffDate']:
            issues.append('post-cutoff project cannot enter this construction edition')
        matches = [p for p in campaigns['cities'][city_id]['futurePlans'] if p['id'] == spec['chapter']['id']]
        services = spec.get('plannedServices', [])
        if len(matches) != 1 or len(matches[0].get('lineGroups', [])) != 1 + len(services):
            issues.append('reviewed engineering task missing or duplicated')
        else:
            issues += coverage_errors(matches[0]['lineGroups'][0], expected['groups'][0])
            if matches[0]['lineGroups'][1:] != services:
                issues.append('planned service differs from reviewed engineering scope')
            for service in services:
                if not service.get('constructionVariant') or not service.get('source') or len(service.get('stationIds', [])) < 2:
                    issues.append('invalid operating or unsourced engineering service variant')
            # Pending platform-arrangement review remains a delivery failure;
            # this local tool checks only materialization of the documented
            # physical works and separately authored service requirements.
            names={s['id']:s['name'] for s in cities[city_id]['stations']}
            service_scope=dict(id=expected['id'],reviewStatus=expected['reviewStatus'],
                               source=expected['source'],sourcePublicationDate=expected['sourcePublicationDate'],
                               groups=expected['groups'][1:])
            if services:
                issues += check_project(service_scope,matches,names)
            if matches[0].get('requiredTransfers'):
                issues.append('engineering track must not invent an active passenger service/transfer')
        answers = [p for p in targets['cities'][city_id]['projects'] if p['id'] == expected['id']]
        if answers != [expected]:
            issues.append('committed independent requirement differs from the reviewed source spec')
        for issue in issues:
            errors.append(f'{path.name}: {issue}')
        print(f'{"FAIL" if issues else "PASS"} {path.name}')
    if errors:
        raise SystemExit('\n'.join(errors))
    print(f'PASS: {len(specs)} engineering scope specs; this is not full-city evidence')


if __name__ == '__main__':
    main()
