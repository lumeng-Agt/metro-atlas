"""Validate non-passenger engineering scope, without inventing station targets."""
import math


def positive_finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) and value > 0


def coordinate_valid(point):
    return (isinstance(point, list) and len(point) == 2
            and all(isinstance(p, (int, float)) and not isinstance(p, bool) and math.isfinite(p) for p in point)
            and abs(point[0]) <= 90 and abs(point[1]) <= 180)


def definition_errors(group, known_station_ids=None):
    errors = []
    if group.get('taskKind') != 'engineering_track': errors.append('engineering task kind missing')
    if not group.get('source'): errors.append('engineering scope evidence missing')
    endpoints = group.get('engineeringEndpoints', [])
    sections = group.get('engineeringSegments', [])
    if not isinstance(endpoints, list) or not isinstance(sections, list): return errors + ['engineering lists invalid']
    ids = set()
    for endpoint in endpoints:
        if not isinstance(endpoint, dict): errors.append('invalid engineering endpoint'); continue
        id_ = endpoint.get('id')
        if not id_ or id_ in ids: errors.append('empty or duplicate engineering endpoint id')
        ids.add(id_)
        if not endpoint.get('name'): errors.append('engineering endpoint name missing')
        if 'stationId' in endpoint:
            if known_station_ids is not None and endpoint['stationId'] not in known_station_ids: errors.append('unknown engineering anchor station')
            if not endpoint.get('stationInstanceId'): errors.append('engineering anchor physical body missing')
        else:
            if not coordinate_valid(endpoint.get('latlng')): errors.append('invalid engineering endpoint coordinate')
            if not positive_finite(endpoint.get('toleranceM')): errors.append('engineering endpoint tolerance missing')
    if len(ids) < 2 or not sections: errors.append('engineering task has no physical section')
    for section in sections:
        if not isinstance(section, dict): errors.append('invalid engineering section'); continue
        if section.get('fromId') not in ids or section.get('toId') not in ids or section.get('fromId') == section.get('toId'): errors.append('invalid engineering section endpoints')
        points = section.get('points', [])
        if not isinstance(points, list) or len(points) < 2 or not all(coordinate_valid(p) for p in points): errors.append('invalid engineering corridor')
        if not positive_finite(section.get('corridorToleranceM')): errors.append('engineering corridor tolerance missing')
    anchors = {e.get('stationId') for e in endpoints if isinstance(e, dict) and 'stationId' in e}
    if any(s not in anchors for s in group.get('newStationIds', [])): errors.append('new engineering station is not a documented station anchor')
    if known_station_ids is not None:
        if any(s not in known_station_ids for s in group.get('stationIds', [])): errors.append('unknown engineering anchor target')
    return errors


def coverage_errors(group, expected):
    errors = definition_errors(group)
    if errors: return errors
    if sorted(group.get('newStationIds', [])) != sorted(expected.get('newStationIds', [])): errors.append('new engineering station scope differs')
    endpoints = {e['id']: e for e in expected.get('engineeringEndpoints', [])}
    anchors = sorted({e['stationId'] for e in endpoints.values() if 'stationId' in e})
    if sorted(group.get('stationIds', [])) != anchors: errors.append('engineering anchor scope differs; passenger stations cannot replace interfaces')
    if len(group.get('engineeringEndpoints', [])) != len(endpoints): errors.append('engineering endpoint count differs')
    for endpoint in group.get('engineeringEndpoints', []):
        required = endpoints.get(endpoint.get('id'))
        if required is None: errors.append('unexpected engineering endpoint'); continue
        for key in ['name', 'stationId', 'stationInstanceId', 'latlng', 'toleranceM', 'side', 'depthM']:
            if endpoint.get(key) != required.get(key): errors.append(f'engineering endpoint {required["id"]}: {key} differs')
    sections = {(s['fromId'], s['toId']): s for s in expected.get('engineeringSegments', [])}
    actual = group.get('engineeringSegments', [])
    if len(actual) != len(sections): errors.append('engineering section count differs')
    for key, required in sections.items():
        matches = [s for s in actual if (s.get('fromId'), s.get('toId')) == key]
        if len(matches) != 1: errors.append('required engineering section missing or duplicated'); continue
        if any(matches[0].get(k) != required.get(k) for k in ['points', 'corridorToleranceM']): errors.append('engineering corridor differs from independent requirement')
    return errors
