"""Author Changping's five documented opening scopes, not a 2021 full-line snapshot."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule
from build_network_baseline import build

REVISION = '2026.10.25.3'
LINE = 'beijing-route-20'
ORDER_SOURCE = 'https://www.bjmoa.cn/metroLineList.html?sline=18'
FIRST_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/dtxx/201012/t20101231_335839.html'
NORTH_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/xwfbh/201912/t20191209_1007420.html'
QINGHE_SOURCE = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202201/t20220101_2581335.html'
SOUTH_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/xwfbh/202302/t20230202_2911135.html'
INFILL_SOURCE = 'https://www.beijing.gov.cn/ywdt/gzdt/202412/t20241215_3965616.html'
FIRST = '南邵 沙河高教园 沙河 巩华城 朱辛庄 生命科学园 西二旗'.split()
NORTH = '昌平西山口 十三陵景区 昌平 昌平东关 北邵洼'.split() + FIRST
QINGHE = NORTH + ['清河']
SOUTH = QINGHE + '清河小营桥 学知园 六道口 学院桥 西土城'.split()
FULL = NORTH + '清河 朱房北 清河小营桥 学知园 六道口 学院桥 西土城 蓟门桥'.split()


def main():
    data = read('data/campaigns.json'); cities = read('data/cities.json')
    official = read('data/official_targets_2026-10-01.json'); baseline = read('data/network_baselines_2026-10-01.json')
    city = next(c for c in cities['cities'] if c['id'] == 'beijing')
    campaign = data['cities']['beijing']; target = official['cities']['beijing']; row = baseline['cities']['beijing']
    chapters = {c['id']: c for c in campaign['chapters']}
    cutoff = next(c for c in campaign['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE))
    names = {s['id']: s['name'].removesuffix('站') for s in city['stations']}
    lookup = {names[s]: s for s in template['stationIds']}
    new_id = 'beijing-changping-zhufangbei'
    lookup['朱房北'] = new_id
    if not any(s['id'] == new_id for s in city['stations']):
        city['stations'].append(dict(id=new_id, name='朱房北', latlng=[40.0347054, 116.3259094], osmIds=[13161970243],
            coordinateSource='local_osm_station_node', source=INFILL_SOURCE,
            coordinateNote='本地OSM地铁站节点，仅用于近似站位；官方公告证明2024-12-15开放，不把节点精度冒充测绘精度。'))
    instances = {s: template.get('stationInstances', {}).get(s, s) for s in template['stationIds']}
    instances[new_id] = new_id + '__line20'
    for g in [template, next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE)]:
        ids = [lookup[n] for n in FULL]
        g.update(stationIds=ids, stationNames=dict(zip(ids, FULL)), stationInstances=instances,
                 replaceExistingService=True, reconfirmLaterServices=True, servicePathRevision=20)
    route = next(r for r in city['lines'] if r['id'] == 'beijing-r20')
    route.update(stationIds=[lookup[n] for n in FULL], stationOrderSource=ORDER_SOURCE, stationOrderReviewedAt='2026-10-25')
    for i, direction in enumerate(route['directions']):
        direction['stationIds'] = route['stationIds'].copy() if i == 0 else list(reversed(route['stationIds']))
        direction['name'] = '昌平西山口→蓟门桥' if i == 0 else '蓟门桥→昌平西山口'
    # The old full-line task is retained at its real Qinghe opening date. Other
    # stable identifiers represent the earlier/later construction, never positions.
    stages = [
        ('beijing-network-milestone-2010-12-30', '2010-12-30', '昌平线一期七站试运营', FIRST, FIRST,
         'opening:bj-changping-first', FIRST_SOURCE, '2010-12-31'),
        ('beijing-changping-north-2015', '2015-12-26', '昌平线二期进入昌平城区', NORTH[:6], NORTH,
         'opening:bj-changping-north', NORTH_SOURCE, '2015-12-28'),
        ('beijing-network-milestone-2021-12-31', '2021-12-31', '昌平线南延至清河', ['西二旗', '清河'], QINGHE,
         'route:beijing-r20', QINGHE_SOURCE, '2022-01-01'),
        ('beijing-changping-south-2023', '2023-02-04', '昌平线南延一期首开五站', SOUTH[12:], SOUTH,
         'opening:bj-changping-south', SOUTH_SOURCE, '2023-02-02'),
        ('beijing-network-milestone-2024-12-15', '2024-12-15', '朱房北与蓟门桥开放', FULL, FULL,
         'opening:bj-changping-infill', INFILL_SOURCE, '2024-12-15'),
    ]
    sample = chapters['beijing-line19-infill-2022']
    for cid, date, title, construction, service, task, source, pub in stages:
        chapter = chapters.get(cid)
        if chapter is None:
            chapter = deepcopy(sample)
            chapter.update(id=cid, date=date, title=title, lineGroups=[], requiredTransfers=[], scopeCorrections=[],
                           serviceTransitions=[], historicalEventIds=[], eventOnly=False, operationType='extension',
                           chapterScope='dated_opening_ranges', routeTargetCount=1, source=source, sourcePublicationDate=pub,
                           sourceTitle=title, sourceCheckedAt='2026-10-25', status='trial_operation',
                           eventText=title, alignmentNote='官方分期开通范围，近似地理参考，不宣称精确隧道中心线。')
            chapter['story'] = dict(opening=title+'。', purpose='复用既有线路，仅建设并确认本期新增范围。',
                outcome='保留下一阶段蓝图，不提前开放后期站点。', eventKind='network_expansion',
                steps=deepcopy(sample['story']['steps']), beats=[], planVersions=[])
            chapters[cid] = chapter
        ids = [lookup[n] for n in construction]; group = deepcopy(template)
        group.update(taskId=task, coverageGroupId=task, name=title, stationIds=ids,
            stationNames=dict(zip(ids, construction)), stationInstances={s: instances[s] for s in ids},
            stationOrderSource=source, source=source, replaceExistingService=(construction == service),
            reconfirmLaterServices=True, servicePathRevision=20, defaultServiceStatus='trial',
            precisionNote='按公开分期站序建设；朱房北仅在2024-12-15开放，站位及地下走向为近似参考。')
        chapter['lineGroups'] = [g for g in chapter.get('lineGroups', []) if g['historicalLineId'] != LINE] + [group]
        if not str(chapter.get('operationGuide','')).strip():chapter['operationGuide']=f'复用既有站轨，补齐{construction[0]}至{construction[-1]}的本期建设范围，检查与既有段连接后确认本期开放；不提前开放后期站。'
        chapter.update(scopeRevision=REVISION, requiresScopeRecheck=True)
        milestone = next((m for m in target['historicalMilestones'] if m['chapterId'] == cid), None)
        if milestone is None:
            milestone = dict(chapterId=cid, date=date, source=source, sourcePublicationDate=pub, groups=[])
            target['historicalMilestones'].append(milestone)
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId', g['id']) != LINE] + [
            dict(id=task, historicalLineId=LINE, scopeType='stations', stationNames=service,
                 constructionStationNames=construction, fullServiceOrder=True, allowReverse=True, requiredServiceStatus='trial')]
        milestone['additionalSources'] = list(dict.fromkeys(milestone.get('additionalSources', []) + [source, ORDER_SOURCE]))
    # Reassign sourced transfer pairs to the first period when both physical
    # line bodies are available. This cannot invent an earlier 8/13-line opening.
    pool = {t['id']: deepcopy(t) for c in chapters.values() for t in c.get('requiredTransfers', []) if LINE in t['lineIds']}
    for transfer in pool.values():
        if transfer['name'] in ['西土城', '六道口']: transfer['source'] = SOUTH_SOURCE
        elif transfer['name'] == '蓟门桥': transfer['source'] = INFILL_SOURCE
        elif transfer['name'] in ['清河', '清河站']: transfer['source'] = QINGHE_SOURCE
        elif transfer['name'] == '西二旗': transfer['source'] = FIRST_SOURCE
    available = set(); placed = set()
    for chapter in sorted(chapters.values(), key=lambda c: c['date']):
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if t['id'] not in pool]
        for group in chapter.get('lineGroups', []):
            available.update((group['historicalLineId'], group.get('stationInstances', {}).get(s, s)) for s in group['stationIds'])
        for tid, transfer in pool.items():
            if tid not in placed and all(pair in available for pair in zip(transfer['lineIds'], transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer)); placed.add(tid)
    for milestone in target['historicalMilestones']:
        milestone['transfers'] = [t for t in milestone.get('transfers', []) if t not in pool]
        chapter = chapters.get(milestone['chapterId'], {})
        milestone['transfers'] += [t['id'] for t in chapter.get('requiredTransfers', []) if t['id'] in pool]
    target['cutoffNetwork']['groups'] = [g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId', g['id']) != LINE] + [
        dict(id=LINE, historicalLineId=LINE, scopeType='stations', stationNames=FULL, allowReverse=True, fullServiceOrder=True,
             lastPhysicalOpeningDate='2024-12-15', lastPhysicalOpeningSource=INFILL_SOURCE)]
    campaign['chapters'] = sorted(chapters.values(), key=lambda c: c['date'])
    old = [e for e in row['documentedMilestones'] if e.get('routeIds') == ['beijing-r20']]
    for event in old:
        if not any(e['id'] == event['id'] for e in row.setdefault('supersededDocumentedMilestones', [])):
            row['supersededDocumentedMilestones'].append(dict(event, supersededReason='昌平线现代19站快照错误提前到2021年，且遗漏朱房北。'))
    old_ids = {e['id'] for e in old}
    row['documentedMilestones'] = [e for e in row['documentedMilestones'] if e not in old and not e['id'].startswith('reviewed-changping:')]
    for chapter in campaign['chapters']:
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds', []) if e not in old_ids and not e.startswith('reviewed-changping:')]
    for cid, date, title, construction, service, task, source, pub in stages:
        event = 'reviewed-changping:' + task; chapter = chapters[cid]; chapter['historicalEventIds'].append(event)
        row['documentedMilestones'].append(dict(id=event, date=date, title=title, status='trial_operation',
            chapterId=cid, routeIds=['beijing-r20'], source=source, sourcePublicationDate=pub,
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['taskId'] == task]))
    row['documentedMilestones'].sort(key=lambda e: (e['date'], e['id'])); row['documentedMilestoneCount'] = len(row['documentedMilestones'])
    generated = build(cities, data)['cities']['beijing']
    for key in ['routes', 'mapRouteEntryCount', 'mapRouteStopOccurrenceCount', 'mapUniqueStationCount']: row[key] = deepcopy(generated[key])
    refresh_schedule('beijing', row, campaign, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='补齐昌平线朱房北，恢复2010／2015／2021／2023／2024五期建设，换乘按两侧站体可用时间出现。')
    for path, value in [('data/cities.json', cities), ('data/campaigns.json', data),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('Changping: 7 / 12 / 13 / 18 / 20 stops, with separate dated construction and explicit interchanges')


if __name__ == '__main__': main()
