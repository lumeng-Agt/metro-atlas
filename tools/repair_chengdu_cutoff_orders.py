"""Apply reviewed Chengdu operator paths to cutoff tasks, preserving old bodies.

This is a geographic/service-order repair. It does not certify opening dates or
rewrite the scope of earlier milestones. Six missing line-30 station areas are
explicit OSM subway nodes, not inferred intermediate points.
"""
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.23.46'
SOURCE = 'https://www.chengdurail.com/op/station-time'
EXPLICIT_SITES = {
    '府城桥': (13380485910, [30.5912769, 104.0731875]),
    '金融城北': (13380485918, [30.5910068, 104.0672093]),
    '益州大道': (13380485921, [30.5910484, 104.0579647]),
    '新园大道': (13380485923, [30.5904794, 104.0372783]),
    '石羊东': (13380485924, [30.586455, 104.0306541]),
    '大同': (13380485925, [30.5752522, 104.0146206]),
}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def normalize(name):
    return name.replace('·', '').removesuffix('站')


def main():
    data = read('data/campaigns.json')
    cities = read('data/cities.json')
    targets = read('data/official_targets_2026-10-01.json')
    evidence = read('data/official_evidence/chengdu_operator_orders_retrieved2026-10-23.json')
    campaign = data['cities']['chengdu']
    campaign.setdefault('stationComplexAliases', {})['chengdu-s329'] = 'chengdu-s25'
    campaign['stationComplexAliases'].update({'chengdu-s330':'chengdu-s67', 'chengdu-s375':'chengdu-s318', 'chengdu-s170':'chengdu-s9'})
    campaign.setdefault('stationInstanceAliases', {}).update({
        'chengdu-line8-8|chengdu-s274':'chengdu-s274__line8-8',
        'chengdu-line13-11|chengdu-s321':'chengdu-s321__line13-11',
        'chengdu-line18-13|chengdu-s303':'chengdu-s303__line18-13',
    })
    city = next(c for c in cities['cities'] if c['id'] == 'chengdu')
    catalog = {s['id']: s for s in city['stations']}
    for name, (node, point) in EXPLICIT_SITES.items():
        if not any(s['name'] == name for s in city['stations']):
            identity = f'chengdu-official-l30-n{node}'
            row = {'id': identity, 'name': name, 'latlng': point,
                   'coordinateSource': 'existing_station',
                   'coordinateNote': f'运营方站序存在、旧地图库遗漏；OSM地铁站节点{node}，现代站区参考，不代表隧道测绘。',
                   'source': SOURCE, 'osmNodeId': node}
            city['stations'].append(row)
            catalog[identity] = row
    chapter = next(c for c in campaign['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    old = {g['name'].replace('号线', ''): g for g in chapter['lineGroups']}
    groups, expected = [], []
    for number, line in evidence['lines'].items():
        template = old[number]
        # Prefer each route's existing stable identity over a global name match.
        identities = {normalize(catalog[s]['name']): s for s in template['stationIds']}
        for s, row in catalog.items():
            identities.setdefault(normalize(row['name']), s)
        if number == '6':
            # The old extract appended a second OSM Xipu identity to this
            # route; preserve the already-connected line-6 platform identity.
            identities['犀浦'] = 'chengdu-s25'
        if number == '9':
            identities[normalize('成都西站')] = 'chengdu-s67'
        if number == '30':
            identities['娇子立交'] = 'chengdu-s318'
        orders = sorted(line['orders'], key=len, reverse=True) if number == '1' else line['orders']
        for branch, names in enumerate(orders):
            group = deepcopy(template)
            ids = [identities[normalize(name)] for name in names]
            group['stationIds'] = ids
            group['stationNames'] = dict(zip(ids, names))
            group['stationInstances'] = {s: template.get('stationInstances', {}).get(s, s) for s in ids}
            if number == '1':
                for identity in ['chengdu-s24', 'chengdu-s158', 'chengdu-s164']:
                    if identity in ids:
                        group['stationInstances'][identity] = identity + '__line1'
            if number == '6':
                group['stationInstances']['chengdu-s25'] = 'chengdu-s25__line6-6'
            if number == '9':
                group['stationInstances']['chengdu-s67'] = 'chengdu-s67__line9-9'
                group['stationReferenceIds'] = {'chengdu-s67':'chengdu-s330'}
            if number == '30':
                group['stationInstances']['chengdu-s318'] = 'chengdu-s318__line30-16'
                group['stationReferenceIds'] = {'chengdu-s318':'chengdu-s375'}
            if number == '18':
                group['stationInstances']['chengdu-s304'] = 'chengdu-s304__line18-13'
            group['taskId'] = f"route:{template['mapRouteId']}" + (f':branch-{branch+1}' if len(line['orders']) > 1 else '')
            scope_id = template['historicalLineId'] + (f':branch-{branch+1}' if len(line['orders']) > 1 else '')
            group['coverageGroupId'] = scope_id
            group['replaceExistingService'] = branch == 0
            group['loop'] = number == '7'
            group['stationOrderSource'] = SOURCE
            group['precisionNote'] = '站序按成都轨道交通运营方逐站时刻表核对；1号线两条分支独立保存，7号线闭环。站区和地下区间为现代地理参考，历史开放日期另据公告核对。'
            group['servicePathRevision'] = 2
            groups.append(group)
            expected.append({'id': scope_id, 'historicalLineId': template['historicalLineId'],
                             'scopeType': 'stations', 'stationNames': names,
                             'allowReverse': True, 'loop': number == '7'})
    chapter['lineGroups'] = groups
    closed_relation = 'historic-transfer-chengdu-s311-line18-13-line19-14'
    for row in campaign['chapters']:
        row['requiredTransfers'] = [t for t in row.get('requiredTransfers', []) if t.get('id') != closed_relation]
    correction = {
        'taskId':'route:chengdu-r13', 'transferId':closed_relation,
        'oldLineIds':['chengdu-line18-13','chengdu-line19-14'],
        'oldStationInstanceIds':['chengdu-s311__line18-13','chengdu-s311__line19-14'],
        'description':'机场3号4号航站楼为未开放预留站，撤销旧版提前生成的18/19换乘；原站体和轨道保留。',
        'source':SOURCE,
    }
    if correction not in chapter.setdefault('scopeCorrections', []):
        chapter['scopeCorrections'].append(correction)
    chapter['contentRevision'] = REVISION
    chapter['requiresScopeRecheck'] = True
    targets['cities']['chengdu']['cutoffNetwork'] = {
        'chapterId': chapter['id'], 'date': '2026-10-01', 'source': SOURCE,
        'sourceRetrievedAt': '2026-10-23', 'temporalReviewStatus': 'pending',
        'note': '运营方独立站序，取得时间晚于截止日。开放事实及历史分期仍需有日期的官方公告；不据此放行整城。30号线玉虹路、分水暂缓开放，18/19号线不含机场3/4航站楼预留站。',
        'groups': expected}
    data['contentRevision'] = max(data.get('contentRevision', ''), REVISION)
    write('data/campaigns.json', data)
    write('data/cities.json', cities)
    write('data/official_targets_2026-10-01.json', targets)
    print(f'Chengdu cutoff: {len(groups)} actual branch paths; historical date audit remains separate')


if __name__ == '__main__':
    main()
