"""Replace the late modern snapshot with six dated construction scopes.

Literal orders are transcribed from dated operator announcements, contemporary
reporting and the district archive. Geography and physical IDs are looked up
from the bundled map; the old chapter is not the historical answer.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write

REVISION = '2026.10.24.25'
ARCHIVE = 'https://www.songjiang.gov.cn/sjsz/sjdfls/sj70n/files/basic-html/page154.html'
YISHAN = 'https://news.sohu.com/20081228/n261461461.shtml'
SECOND = 'https://news.sina.com.cn/c/2009-12-31/022919371947.shtml'
YANGGAO = 'https://news.sohu.com/20100405/n271320480.shtml'
EAST = 'https://www.cnr.cn/shanghai/tt/20171227/t20171227_524078638.shtml'
RENAME = 'https://www.shanghai.gov.cn/nw4411/20240922/f5fd81dbfe9244a298fd13806c993ca3.html'
FIRST = '松江新城 松江大学城 洞泾 佘山 泗泾 九亭 中春路 七宝 星中路 合川路 漕河泾开发区 桂林路'.split()
CENTRE = '宜山路 徐家汇 肇嘉浜路 嘉善路 打浦桥 马当路 陆家浜路 小南门 商城路 世纪大道'.split()
SOUTH = '松江南站 醉白池 松江体育中心 松江新城'.split()
EAST_NAMES = '杨高中路 芳甸路 蓝天路 台儿庄路 金桥 金吉路 金海路 顾唐路 民雷路 曹路'.split()


def main():
    data = read('data/campaigns.json'); official = read('data/official_targets_2026-10-01.json')
    city = data['cities']['shanghai']; target = official['cities']['shanghai']
    chapters = {c['id']: c for c in city['chapters']}
    cutoff = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == 'shanghai-line9-9'))
    catalog = {s['id']: s['name'] for c in read('data/cities.json')['cities'] if c['id'] == 'shanghai' for s in c['stations']}
    lookup = {catalog[s]: s for s in template['stationIds']}; lookup['松江南站'] = lookup['上海松江站']
    # Preserve recorded transfers before replacing the incorrectly late group.
    pool = {t['id']: deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers', []) if 'shanghai-line9-9' in t['lineIds']}
    old_id = 'shanghai-network-milestone-2019-12-30'
    old = chapters.get(old_id)
    if old is not None:
        old['lineGroups'] = [g for g in old['lineGroups'] if g['historicalLineId'] != 'shanghai-line9-9']
        if not old['lineGroups']:
            chapters.pop(old_id)
    sample = deepcopy(chapters['shanghai-network-milestone-2011-04-12'])
    scopes = [
        ('shanghai-network-milestone-2007-12-29', '2007-12-29', '9号线一期首开', FIRST, FIRST, ARCHIVE, None, 'opening:sh9-first', True),
        ('shanghai-line9-yishan-2008', '2008-12-28', '9号线接入宜山路', ['桂林路', '宜山路'], FIRST + ['宜山路'], YISHAN, '2008-12-28', 'opening:sh9-yishan', False),
        ('shanghai-line9-second-2009', '2009-12-31', '9号线跨江至世纪大道', CENTRE, FIRST + CENTRE, SECOND, '2009-12-31', 'opening:sh9-second', False),
        ('shanghai-line9-yanggao-2010', '2010-04-07', '9号线杨高中路站开放', ['世纪大道', '杨高中路'], FIRST + CENTRE + ['杨高中路'], YANGGAO, '2010-04-05', 'opening:sh9-yanggao', False),
        ('shanghai-line9-south-2012', '2012-12-30', '9号线南延连接松江老城', SOUTH, SOUTH[:-1] + FIRST + CENTRE + ['杨高中路'], ARCHIVE, None, 'opening:sh9-south', False),
        ('shanghai-network-milestone-2017-12-30', '2017-12-30', '9号线东延与17号线成网', EAST_NAMES, SOUTH[:-1] + FIRST + CENTRE + EAST_NAMES, EAST, '2017-12-27', 'route:shanghai-r9', False),
        ('shanghai-songjiang-rename-2024', '2024-09-21', '松江南站更名上海松江站', ['上海松江站', '醉白池'], ['上海松江站'] + SOUTH[1:-1] + FIRST + CENTRE + EAST_NAMES, RENAME, '2024-09-22', 'rename:sh9-songjiang', False),
    ]
    for cid, date, title, names, expected, source, pub, task, replace in scopes:
        chapter = chapters.get(cid)
        if chapter is None:
            chapter = deepcopy(sample)
            chapter.update(id=cid, date=date, title=title, lineGroups=[], requiredTransfers=[], scopeCorrections=[],
                           serviceTransitions=[], historicalEventIds=[cid + ':event'], eventOnly=False,
                           chapterScope='dated_opening_ranges', operationType='extension', routeTargetCount=1)
            chapters[cid] = chapter
        ids = [lookup[n] for n in names]; group = deepcopy(template)
        group.update(taskId=task, coverageGroupId=task, stationIds=ids, stationNames=dict(zip(ids, names)),
                     stationInstances={s: template.get('stationInstances', {}).get(s, s) for s in ids},
                     stationOrderSource=source, replaceExistingService=replace, reconfirmLaterServices=True,
                     servicePathRevision=7, loop=False,
                     precisionNote='按当期首开和延伸范围复现；地理站区与隧道为近似参考。既有接头复用，不提前建设后期站序。')
        chapter['lineGroups'] = [g for g in chapter['lineGroups'] if g['historicalLineId'] != 'shanghai-line9-9'] + [group]
        chapter.update(scopeRevision=REVISION, requiresScopeRecheck=True)
        if cid not in ['shanghai-network-milestone-2007-12-29', 'shanghai-network-milestone-2017-12-30']:
            text = f'{date}，{title}。本期范围：' + '—'.join(names) + '。'
            chapter.update(source=source, sourcePublicationDate=pub, sourceTitle='同期开放公告／官方地方史与运营方发布资料', eventText=text)
            chapter['story'] = dict(opening=text, purpose='沿真实时期的站序，复用既有站体并完成本期变化。',
                outcome='本期与前期线路相接，后期范围仍保留为后续建设；不把现代整线倒灌到早期节点。',
                eventKind='station_rename' if task.startswith('rename:') else 'network_expansion',
                planVersions=[], steps=deepcopy(sample['story']['steps']), beats=[])
        if task.startswith('rename:'):
            chapter['operationType'] = 'rename'
            chapter['story']['purpose'] = '在既有车站详情确认名称，保持同一物理站体与轨道；铁路站更名日期不代替地铁更名日期。'
        milestone = next((m for m in target.get('historicalMilestones', []) if m['chapterId'] == cid), None)
        if milestone is None:
            milestone = dict(chapterId=cid, date=date, source=source, sourcePublicationDate=pub, groups=[])
            target.setdefault('historicalMilestones', []).append(milestone)
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId', g['id']) != 'shanghai-line9-9'] + [
            dict(id=task, historicalLineId='shanghai-line9-9', scopeType='stations', stationNames=expected, allowReverse=True, fullServiceOrder=True)]
        milestone['groups'][-1]['constructionStationNames'] = names
        if pub is None:
            milestone['publicationDateNote'] = '官方地方史书页，事件日期见正文；不伪造书页发布日期。'
            milestone['bibliographicCitation'] = dict(kind='official_yearbook', edition='松江70年', locator='第154页：9号线首开、二期与南延伸的实际开放日期')
    available = set(); placed = set()
    for chapter in sorted(chapters.values(), key=lambda c: c['date']):
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if t['id'] not in pool]
        for group in chapter.get('lineGroups', []):
            available.update((group['historicalLineId'], group.get('stationInstances', {}).get(s, s)) for s in group['stationIds'])
        for id_, transfer in pool.items():
            if id_ not in placed and all(p in available for p in zip(transfer['lineIds'], transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer)); placed.add(id_)
    first = chapters[scopes[0][0]]
    allowed = {template.get('stationInstances', {}).get(lookup[n], lookup[n]) for n in FIRST}
    first['scopeCorrections'] = [c for c in first.get('scopeCorrections', []) if not c['id'].startswith('defer-sh9-')]
    for transfer in pool.values():
        body = next(b for l, b in zip(transfer['lineIds'], transfer['stationInstanceIds']) if l == 'shanghai-line9-9')
        if body not in allowed:
            first['scopeCorrections'].append(dict(id='defer-sh9-' + transfer['id'], taskId='opening:sh9-first',
                transferId=transfer['id'], oldStationInstanceIds=transfer['stationInstanceIds'], oldLineIds=transfer['lineIds'],
                source=ARCHIVE, description='此站不属于9号线2007首开范围，保留既有建设，按后续实际开站节点重新确认。'))
    city['chapters'] = sorted(chapters.values(), key=lambda c: c['date'])
    cutoff_expected = dict(id='shanghai-line9-cutoff', historicalLineId='shanghai-line9-9', scopeType='stations',
                           stationNames=scopes[-1][4], allowReverse=True, fullServiceOrder=True)
    target['cutoffNetwork']['groups'] = [g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId', g['id']) != 'shanghai-line9-9'] + [cutoff_expected]
    target['cutoffNetwork'].setdefault('temporalEvidence', []).append(dict(source=EAST, effectiveDate='2017-12-30', scope='9号线曹路延伸九站，包含金吉路；2024年更名不改变站序。'))
    data['contentRevision'] = REVISION
    data['contentRevisionNote'] = '上海9号线恢复2007—2017逐期首开、增站与南北延伸，补金吉路；2024地铁松江南站更名单列。'
    # Remove the obsolete event-directory entries too. Keeping their nonexistent
    # chapter IDs made the timeline unusable even after construction was fixed.
    baseline = read('data/network_baselines_2026-10-01.json'); row = baseline['cities']['shanghai']
    reviewed_lines = {'shanghai-line6-6', 'shanghai-line9-9'}
    obsolete = [e for e in row['documentedMilestones'] if e.get('routeIds') in [['shanghai-r6'], ['shanghai-r9']]]
    archive = row.setdefault('supersededDocumentedMilestones', [])
    for event in obsolete:
        if not any(a['id'] == event['id'] for a in archive):
            archive.append(dict(event, supersededReason='旧目录把现代全线误放到晚期节点；由实际分期事件替代，原记录仅作追溯。'))
    row['documentedMilestones'] = [e for e in row['documentedMilestones'] if e not in obsolete and not e['id'].startswith('reviewed-sh6-9:')]
    old_event_ids = {e['id'] for e in obsolete}
    for chapter in city['chapters']:
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds', []) if e not in old_event_ids and not e.startswith('reviewed-sh6-9:')]
    for milestone in target['historicalMilestones']:
        for expected_group in milestone['groups']:
            if expected_group.get('historicalLineId') not in reviewed_lines:
                continue
            chapter = next(c for c in city['chapters'] if c['id'] == milestone['chapterId'])
            event_id = 'reviewed-sh6-9:' + milestone['chapterId'] + ':' + expected_group['id']
            chapter['historicalEventIds'].append(event_id)
            row['documentedMilestones'].append(dict(id=event_id, date=milestone['date'], title=chapter['title'],
                status='operated', chapterId=chapter['id'], routeIds=['shanghai-r6' if expected_group['historicalLineId']=='shanghai-line6-6' else 'shanghai-r9'],
                source=milestone['source'], sourcePublicationDate=milestone.get('sourcePublicationDate'),
                targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['historicalLineId']==expected_group['historicalLineId']]))
    row['documentedMilestones'].sort(key=lambda e:(e['date'],e['id']))
    row['documentedMilestoneCount'] = len(row['documentedMilestones'])
    from expand_historical_event_chapters import refresh_schedule
    refresh_schedule('shanghai',row,city,'2026-10-01')
    write('data/campaigns.json', data); write('data/official_targets_2026-10-01.json', official)
    write('data/network_baselines_2026-10-01.json', baseline)
    print('Shanghai9: 12/13/22/23/26/35 opened stops across six real construction phases; 2024 rename retains body')


if __name__ == '__main__':
    main()
