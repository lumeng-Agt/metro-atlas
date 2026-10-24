"""Independently sourced requirements, never generated from playable chapters."""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET_PATH = ROOT / 'data/official_targets_2026-10-01.json'
CITIES = ('shenzhen', 'shanghai', 'beijing', 'guangzhou', 'chengdu')


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def check_project(target, plans, names, *, historical_construction=False):
    errors = []
    if target.get('optional', False):
        return errors
    matched = [p for p in plans if target['id'] in p.get('projectIds', [])]
    if target.get('reviewStatus') != 'verified':
        errors.append('official requirements not independently reviewed')
    if target.get('transferReviewStatus', 'verified') != 'verified':
        errors.append('independent transfer coverage incomplete')
    bibliography = target.get('bibliographicCitation', {})
    archival_evidence = (historical_construction and bibliography.get('kind') == 'official_yearbook'
                         and bibliography.get('edition') and bibliography.get('locator'))
    if not target.get('source') or (not target.get('sourcePublicationDate') and not archival_evidence):
        errors.append('dated official evidence missing')
    if not matched:
        return errors + ['required project has no playable task']
    groups = [g for p in matched for g in p.get('lineGroups', [])]
    wanted_groups = target.get('groups', [])
    if not wanted_groups:
        errors.append('independent construction requirements missing')
    for expected in wanted_groups:
        group_id = expected['id']
        candidates = [g for g in groups if g.get('coverageGroupId', g.get('historicalLineId')) == group_id]
        if len(candidates) != 1:
            errors.append(f'{group_id}: expected one group, got {len(candidates)}')
            continue
        group = candidates[0]
        actual = [group.get('stationNames', {}).get(s, names.get(s, s)) for s in group.get('stationIds', [])]
        service_order = expected.get('stationNames', [])
        wanted = expected.get('constructionStationNames', service_order) if historical_construction else service_order
        if historical_construction and 'constructionStationNames' in expected:
            # A task may add two stations to an existing 28-stop service. The
            # runtime audit still checks all 28; static construction coverage
            # checks the explicitly reviewed new subsection. It cannot refer
            # to an unrelated stretch or waive a project station requirement.
            if not expected.get('fullServiceOrder') or not station_order_matches(service_order, wanted, dict(matchScope='contiguous_subsequence', allowReverse=True)):
                errors.append(f'{group_id}: construction scope is not part of the reviewed full service')
        if expected.get('scopeType') == 'corridor':
            if not expected.get('unpublishedStationOrderEvidence'):
                errors.append(f'{group_id}: unsupported corridor exception')
            if any(s not in actual for s in expected.get('requiredPlaces', [])):
                errors.append(f'{group_id}: required corridor places missing')
        elif not wanted or not station_order_matches(actual, wanted, expected):
            errors.append(f'{group_id}: station order differs; missing={[n for n in wanted if n not in actual]}, unexpected={[n for n in actual if n not in wanted]}, expected={len(wanted)}, actual={len(actual)}')
        if bool(group.get('loop', False)) != bool(expected.get('loop', False)):
            errors.append(f'{group_id}: loop closure requirement differs')
    for transfer in target.get('transfers', []):
        if not any(t.get('id') == transfer for p in matched for t in p.get('requiredTransfers', [])):
            errors.append(f'{transfer}: required transfer missing')
    return errors


def station_order_matches(actual, wanted, expected):
    candidates = [wanted]
    if expected.get('allowReverse'):
        candidates.append(list(reversed(wanted)))
    if expected.get('matchScope') == 'contiguous_subsequence':
        return any(actual[start:start + len(wanted)] in candidates for start in range(len(actual) - len(wanted) + 1))
    return actual in candidates


def cutoff_evidence_errors(network, cutoff_date):
    if not network or not network.get('groups'):
        return ['independent cutoff station orders missing']
    errors = []
    if network.get('date') != cutoff_date:
        errors.append('independent network has a different cutoff date')
    if network.get('temporalReviewStatus') != 'verified':
        errors.append('cutoff opening status not independently reviewed')
    evidence = network.get('temporalEvidence', [])
    if not evidence:
        errors.append('dated cutoff opening evidence missing')
    for item in evidence:
        if not item.get('source') or not item.get('effectiveDate') or item['effectiveDate'] > cutoff_date:
            errors.append('invalid or post-cutoff opening evidence')
    return errors


def audit(campaigns=None, cities=None, targets=None):
    campaigns = campaigns if campaigns is not None else read(ROOT / 'data/campaigns.json')
    cities = cities if cities is not None else read(ROOT / 'data/cities.json')
    targets = targets if targets is not None else read(TARGET_PATH)
    city_data = {c['id']: c for c in cities['cities']}
    result = {'cutoffDate': targets.get('cutoffDate'), 'contentRevision': campaigns.get('contentRevision'), 'ok': True, 'cities': {}}
    for city_id in CITIES:
        target = targets.get('cities', {}).get(city_id, {})
        campaign = campaigns['cities'][city_id]
        errors = []
        for field in ('inventoryReviewStatus', 'historyReviewStatus'):
            if target.get(field) != 'verified':
                errors.append(f'{field}: independent review incomplete')
        if not target.get('historicalMilestones'):
            errors.append('independent milestone requirements missing')
        errors.extend(cutoff_evidence_errors(target.get('cutoffNetwork', {}), targets.get('cutoffDate', '2026-10-01')))
        names = {s['id']: s['name'] for s in city_data[city_id]['stations']}
        projects = []
        for project in target.get('projects', []):
            issues = check_project(project, campaign.get('futurePlans', []), names)
            projects.append({'id': project['id'], 'ok': not issues, 'errors': issues})
            errors.extend(f"{project['id']}: {issue}" for issue in issues)
        for project_id in target.get('requiredProjectIds', []):
            if not any(p['id'] == project_id and not p.get('optional', False) for p in target.get('projects', [])):
                errors.append(f'{project_id}: independent project requirements missing')
        for milestone in target.get('historicalMilestones', []):
            entries = [c for c in campaign.get('chapters', []) if c.get('id') == milestone['chapterId']]
            if len(entries) != 1:
                errors.append(f"{milestone['chapterId']}: chapter missing or duplicated")
                continue
            if entries[0].get('date') != milestone.get('date'):
                errors.append(f"{milestone['chapterId']}: event date differs")
            for group in milestone.get('groups', []):
                fake_target = dict(id='milestone', reviewStatus='verified', source=milestone.get('source'), sourcePublicationDate=milestone.get('sourcePublicationDate'), bibliographicCitation=milestone.get('bibliographicCitation', {}), groups=[group])
                errors.extend(check_project(fake_target, [dict(projectIds=['milestone'], lineGroups=entries[0].get('lineGroups', []))], names, historical_construction=True))
        result['cities'][city_id] = {'ok': not errors, 'errors': errors, 'projects': projects}
        result['ok'] = result['ok'] and not errors
    return result
