"""Author the Y-line's dated patterns, not a 2024 modern-network dump."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.24.33'
LINE = 'shanghai-line11-11'
MAIN = '嘉定北 嘉定西 白银路 嘉定新城 马陆 南翔 桃浦新村 武威路 祁连山路 李子园 上海西站 真如 枫桥路 曹杨路 隆德路 江苏路'.split()
SOUTH = '交通大学 徐家汇 上海游泳馆 龙华 云锦路 龙耀路 东方体育中心 三林 三林东 浦三路 御桥 罗山路'.split()
SOURCES = {
    'first': ('https://news.sina.com.cn/c/2009-12-31/163619378128.shtml', '2009-12-31'),
    'branch': ('https://epaper.shautonews.com/content/2010-04/11/029391.html', '2010-04-11'),
    'changji': ('https://sh.sohu.com/20110425/n280401184.shtml', '2011-04-25'),
    'south': ('https://xmwb.xinmin.cn/xmwb/resfile/2013-08-29/A04/A04.pdf', '2013-08-29'),
    'huaqiao': ('https://tjrail.tongji.edu.cn/info/1070/1180.htm', '2013-10-16'),
    'kangxin': ('https://www.thepaper.cn/newsDetail_forward_1459258', '2016-04-21'),
    'disney': ('https://www.thepaper.cn/newsDetail_forward_1459258', '2016-04-21'),
    'chenxiang': ('https://sghexport.shobserver.com/html/baijiahao/2020/09/21/266387.html', '2020-09-21'),
    'kangheng': ('https://www.shanghai.gov.cn/nw4411/20240926/74330e7a5044471e95514cbff23bc086.html', '2024-09-26'),
}


def patterns(stage):
    main = MAIN.copy()
    if stage >= 6: main.insert(main.index('南翔'), '陈翔公路')
    tail = SOUTH.copy() if stage >= 3 else []
    if stage >= 7: tail.insert(tail.index('御桥'), '康恒路')
    if stage >= 4: tail += ['秀沿路', '康新公路']
    if stage >= 5: tail += ['迪士尼']
    result = [main + tail]
    if stage >= 1:
        branch = ['安亭', '上海汽车城'] + (['昌吉东路'] if stage >= 2 else []) + ['上海赛车场']
        if stage >= 3.5: branch = ['花桥', '光明路', '兆丰路'] + branch
        result.append(branch + main[main.index('嘉定新城'):] + tail)
    return result


SCOPES = [
    ('shanghai-line9-second-2009', '2009-12-31', '9号线跨江与11号线首开', 'first', 0),
    ('shanghai-line11-anting-2010', '2010-03-29', '11号线安亭支线：形成Y形路网', 'branch', 1),
    ('shanghai-line11-changji-2011', '2011-04-26', '11号线昌吉东路站开放', 'changji', 2),
    ('shanghai-line8-shendu-2013', '2013-08-31', '11号线二期过江与沈杜公路更名', 'south', 3),
    ('shanghai-line11-huaqiao-2013', '2013-10-16', '11号线跨省延伸至花桥', 'huaqiao', 3.5),
    ('shanghai-line11-kangxin-2015', '2015-12-19', '11号线延伸至康新公路', 'kangxin', 4),
    ('shanghai-line11-disney-2016', '2016-04-26', '11号线迪士尼站开放', 'disney', 5),
    ('shanghai-line11-chenxiang-2020', '2020-08-25', '11号线运营线路增设陈翔公路', 'chenxiang', 6),
    ('shanghai-network-milestone-2024-09-28', '2024-09-28', '11号线康恒路预留站开放', 'kangheng', 7),
]


def main():
    data = read('data/campaigns.json'); official = read('data/official_targets_2026-10-01.json')
    city = data['cities']['shanghai']; target = official['cities']['shanghai']
    catalog = next(c for c in read('data/cities.json')['cities'] if c['id'] == 'shanghai')
    names = {s['id']: s['name'] for s in catalog['stations']}
    chapters = {c['id']: c for c in city['chapters']}
    cutoff = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    templates = [deepcopy(g) for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE]
    lookup = {names[s]: s for g in templates for s in g['stationIds']}
    instances = {s: g.get('stationInstances', {}).get(s, s) for g in templates for s in g['stationIds']}
    sample = deepcopy(chapters['shanghai-line8-shendu-2013'])
    transfer_pool = {t['id']: deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers', []) if LINE in t['lineIds']}
    for cid, date, title, source_key, stage in SCOPES:
        source, publication = SOURCES[source_key]; chapter = chapters.get(cid)
        if chapter is None:
            chapter = deepcopy(sample)
            chapter.update(id=cid, date=date, lineGroups=[], requiredTransfers=[], scopeCorrections=[], serviceTransitions=[],
                           historicalEventIds=[cid + ':event'], chapterScope='dated_opening_ranges', eventOnly=False,
                           operationType='extension', requireOpen=True)
            chapters[cid] = chapter
        chapter.update(title=title, scopeRevision=REVISION, requiresScopeRecheck=True)
        chapter['lineGroups'] = [g for g in chapter.get('lineGroups', []) if g['historicalLineId'] != LINE]
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if t['id'] not in transfer_pool]
        new_groups = []; expected_groups = []
        for i, order in enumerate(patterns(stage)):
            ids = [lookup[n] for n in order]; group = deepcopy(templates[0])
            task = f'opening:sh11-{source_key}:pattern-{i+1}'
            if source_key == 'kangheng': task = 'route:shanghai-r11:branch-' + str(2 if i == 0 else 1)
            group.update(taskId=task, coverageGroupId=task, name=f'11号线 · {order[0]}—{order[-1]}',stationIds=ids, stationNames=dict(zip(ids, order)),
                stationInstances={s: instances[s] for s in ids}, stationOrderSource=source, source=source,
                constructionScope='dated_service_patterns', sourceStationIds=ids.copy(),
                constructionScopeNote='本期有来源的主支线完整站序；复用所有已建站轨，只补本次新增部分。短交路时刻不模拟。',
                replaceExistingService=(i == 0), reconfirmLaterServices=True, servicePathRevision=11, loop=False,
                precisionNote='按对应时期开放站序复现Y形网络，不提前加入昌吉东路、陈翔公路、康恒路或迪士尼；隧道为近似走廊。')
            new_groups.append(group)
            expected_groups.append(dict(id=task, historicalLineId=LINE, scopeType='stations', stationNames=order,
                                        allowReverse=True, fullServiceOrder=True))
        chapter['lineGroups'].extend(new_groups)
        if cid == 'shanghai-line9-second-2009':
            chapter['story'].update(opening='2009年12月31日，9号线二期跨江，11号线主线开通至嘉定北。',
                purpose='在同一成网节点完成9号线新段及11号线16站首开，安亭支线和后期延伸仍不开放。',
                outcome='嘉定首次进入轨交网络；11号线此时只到江苏路，下一步才形成Y形支线。')
        elif cid == 'shanghai-line8-shendu-2013':
            chapter['story'].update(opening='2013年8月31日，11号线二期过江至罗山路，8号线航天博物馆站更名沈杜公路。',
                purpose='复用既有站轨完成11号线二期，并确认8号线名称变化；康恒路仍为未开放预留站。',
                outcome='11号线接入徐汇与浦东，名称沿革保留同一站体身份。')
        if cid not in ['shanghai-line9-second-2009', 'shanghai-line8-shendu-2013']:
            text = f'{date}，{title}。已有线路不重建，补齐这一时期开放的站体与区间。'
            chapter.update(source=source, sourcePublicationDate=publication, sourceTitle='同期运营消息及官方站名资料', eventText=text)
            chapter['story'] = dict(opening=text, purpose='检查主支线、预留站和后期延伸的时间边界。',
                outcome='本期路网已确认，未开放站不会提前加入线路。', eventKind='network_expansion',
                steps=deepcopy(sample['story']['steps']), beats=[], planVersions=[])
        milestone = next((m for m in target['historicalMilestones'] if m['chapterId'] == cid), None)
        if milestone is None:
            milestone = dict(chapterId=cid, date=date, source=source, sourcePublicationDate=publication, groups=[])
            target['historicalMilestones'].append(milestone)
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId',g['id']) != LINE] + expected_groups
        milestone['additionalSources'] = list(dict.fromkeys(milestone.get('additionalSources',[]) + [source,
            'https://jtw.sh.gov.cn/xygl1/20180605/0010-6964.html']))
    # Schedule existing sourced pairs only once both physical line bodies exist.
    available = set(); placed = set()
    for chapter in sorted(chapters.values(), key=lambda c:c['date']):
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers',[]) if t['id'] not in transfer_pool]
        for group in chapter.get('lineGroups',[]):
            available.update((group['historicalLineId'], group.get('stationInstances',{}).get(s,s)) for s in group['stationIds'])
        for id_, transfer in transfer_pool.items():
            if id_ not in placed and all(p in available for p in zip(transfer['lineIds'], transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer)); placed.add(id_)
    # A migrated completed modern save still has its later interchanges.
    # Reconfirming the newly inserted first opening temporarily retires only
    # those exact source-recorded pairs; the later dated tasks restore them.
    # Keep all station bodies, tracks and original connection records.
    first = chapters[SCOPES[0][0]]
    allowed = {instances[lookup[n]] for n in MAIN}
    all_transfers = dict(transfer_pool)
    for plan in city.get('futurePlans',[]):
        for transfer in plan.get('requiredTransfers',[]):
            if LINE in transfer['lineIds']: all_transfers[transfer['id']] = transfer
    first['scopeCorrections'] = [c for c in first.get('scopeCorrections',[]) if not c['id'].startswith('defer-sh11:')]
    for transfer in all_transfers.values():
        body = next(b for line,b in zip(transfer['lineIds'],transfer['stationInstanceIds']) if line==LINE)
        if body not in allowed:
            first['scopeCorrections'].append(dict(id='defer-sh11:'+transfer['id'],taskId='opening:sh11-first:pattern-1',
                transferId=transfer['id'],oldStationInstanceIds=transfer['stationInstanceIds'],oldLineIds=transfer['lineIds'],
                source=SOURCES['first'][0],description='此11号线站体不属于2009年首开范围；保留物理建设及原联系记录，在其对应的后续开放或规划节点重新确认。'))
    city['chapters'] = sorted(chapters.values(), key=lambda c:c['date'])
    baseline = read('data/network_baselines_2026-10-01.json'); row = baseline['cities']['shanghai']
    obsolete = [e for e in row['documentedMilestones'] if e.get('routeIds') == ['shanghai-r11']]
    archive = row.setdefault('supersededDocumentedMilestones',[])
    for event in obsolete:
        if not any(e['id'] == event['id'] for e in archive): archive.append(dict(event, supersededReason='11号线应按2009首开及实际延伸增站分期，不在2024一次加入现代全线。'))
    removed = {e['id'] for e in obsolete}
    row['documentedMilestones'] = [e for e in row['documentedMilestones'] if e not in obsolete and not e['id'].startswith('reviewed-sh11:')]
    for chapter in city['chapters']:
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds',[]) if e not in removed and not e.startswith('reviewed-sh11:')]
    for cid,date,title,key,_stage in SCOPES:
        chapter = chapters[cid]; source,publication = SOURCES[key]; event = 'reviewed-sh11:' + key
        chapter['historicalEventIds'].append(event)
        row['documentedMilestones'].append(dict(id=event,date=date,title=title,status='operated',chapterId=cid,
            routeIds=['shanghai-r11'],source=source,sourcePublicationDate=publication,
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['historicalLineId']==LINE]))
    row['documentedMilestones'].sort(key=lambda e:(e['date'],e['id']));row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('shanghai',row,city,'2026-10-01')
    data.update(contentRevision=REVISION,contentRevisionNote='上海11号线补2009首开、2010支线、2011增站、2013两次延伸、2015/2016南延及2020/2024增站，保留Y形线路独立方向。')
    for path,value in [('data/campaigns.json',data),('data/official_targets_2026-10-01.json',official),('data/network_baselines_2026-10-01.json',baseline)]: write(path,value)
    print('Shanghai11: nine dated stages; 16-stop first opening, Y branches and three delayed stations')


if __name__ == '__main__': main()
