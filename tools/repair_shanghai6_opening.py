"""Separate the 2007 opening from the later passenger opening at Jiyang Road.

The dated Pudong archive article supplies the boundary/date facts. The literal
station order below is reviewed separately from the existing chapter snapshot.
Existing physical bodies are reused; no player station is moved.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write

REVISION = '2026.10.24.24'
SOURCE = 'https://sghexport.shobserver.com/html/baijiahao/2021/04/12/405700.html'
ORDER_SOURCE = 'https://m.shmetro.com/interface/metromap/metromap.aspx?func=fltime&line=6'
RENAME_SOURCE = 'https://tyj.sh.gov.cn/cmsres/35/358f756058ab4d6dac8ac8244daf1cb8/2dc493da0042bdf20170dfc0e2c3d1fd.pdf'
OPEN_NAME_SOURCE = 'https://www.chinametro.net/index.php?aid=13529&id=539&m=mobilenewscon'
FIRST = '港城路 外高桥保税区北 航津路 外高桥保税区南 洲海路 五洲大道 东靖路 巨峰路 五莲路 博兴路 金桥路 云山路 德平路 北洋泾路 民生路 源深体育中心 世纪大道 浦电路 蓝村路 上海儿童医学中心 临沂新村 高科西路 东明路 高青路 华夏西路 上南路 灵岩南路'.split()


def main():
    data = read('data/campaigns.json'); official = read('data/official_targets_2026-10-01.json')
    city = data['cities']['shanghai']; target = official['cities']['shanghai']
    chapters = {c['id']: c for c in city['chapters']}
    cutoff = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == 'shanghai-line6-6'))
    names = {s['id']: s['name'] for c in read('data/cities.json')['cities'] if c['id'] == 'shanghai' for s in c['stations']}
    lookup = {names[s]: s for s in template['stationIds']}
    phases = [
        ('shanghai-network-milestone-2007-12-29', '2007-12-29', FIRST, 'opening:sh6-first', True),
        ('shanghai-network-milestone-2011-04-12', '2011-04-12', ['灵岩南路', '东方体育中心'], 'route:shanghai-r6', False),
    ]
    for chapter_id, date, order, task, replace in phases:
        chapter = chapters[chapter_id]; group = deepcopy(template)
        ids = [lookup[n] for n in order]
        group.update(taskId=task, coverageGroupId=task, stationIds=ids, stationNames=dict(zip(ids, order)),
                     stationInstances={s: template.get('stationInstances', {}).get(s, s) for s in ids},
                     stationOrderSource=SOURCE, replaceExistingService=replace, reconfirmLaterServices=True,
                     servicePathRevision=6,
                     precisionNote='2007首开港城路—灵岩南路；2011-04-12才开放济阳路站客运。站区为地理参考，隧道为近似走廊。')
        if date == '2011-04-12':
            # The opening name is not its later May name. Same historical body.
            group['stationNames'][lookup['东方体育中心']] = '济阳路'
        chapter['lineGroups'] = [g for g in chapter['lineGroups'] if g['historicalLineId'] != 'shanghai-line6-6'] + [group]
        chapter.update(scopeRevision=REVISION, requiresScopeRecheck=True)
        if date == '2011-04-12':
            chapter.update(title='6号线济阳路站开放', source=SOURCE, sourcePublicationDate='2021-04-12',
                           sourceTitle='浦东档案：6号线首开与东方体育中心开站',
                           eventText='复用既有线路，开放灵岩南路以南的济阳路站。此站后来更名东方体育中心。')
            chapter['story'].update(opening='6号线已在浦东运行，本期补齐南端站的客运开放。',
                                    purpose='接通灵岩南路至济阳路，检查新增一站，而不是重建整条6号线。',
                                    outcome='6号线南端站开始服务。此时线路仍沿用原有27站，本期只增加一个站和相邻区间。')
        else:
            chapter['title'] = '2007年成网：北延、闭环与浦东线首开'
        milestone = next((m for m in target.get('historicalMilestones', []) if m['chapterId'] == chapter_id), None)
        if milestone is None:
            milestone = dict(chapterId=chapter_id, date=date, source=SOURCE, sourcePublicationDate='2021-04-12', groups=[])
            target.setdefault('historicalMilestones', []).append(milestone)
        answer = order if replace else FIRST + ['济阳路']
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId', g['id']) != 'shanghai-line6-6'] + [
            dict(id=task, historicalLineId='shanghai-line6-6', scopeType='stations', stationNames=answer,
                 constructionStationNames=['灵岩南路','济阳路'] if not replace else FIRST,
                 allowReverse=True, fullServiceOrder=True)]
        milestone.setdefault('additionalSources', []).extend([ORDER_SOURCE, OPEN_NAME_SOURCE])
    # Retain only source-recorded transfer pairs; schedule them when both line
    # bodies first exist. Geometric crossings never create transfer relations.
    pool = {t['id']: deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers', [])
            if 'shanghai-line6-6' in t.get('lineIds', [])}
    available = set(); placed = set()
    for chapter in sorted(city['chapters'], key=lambda c: c['date']):
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if t['id'] not in pool]
        for group in chapter.get('lineGroups', []):
            available.update((group['historicalLineId'], group.get('stationInstances', {}).get(s, s)) for s in group['stationIds'])
        for id_, transfer in pool.items():
            if id_ not in placed and all(p in available for p in zip(transfer['lineIds'], transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer)); placed.add(id_)
    first = chapters[phases[0][0]]
    allowed = {template.get('stationInstances', {}).get(lookup[n], lookup[n]) for n in FIRST}
    first['scopeCorrections'] = [c for c in first.get('scopeCorrections', []) if not c['id'].startswith('defer-sh6-')]
    for transfer in pool.values():
        body = next(b for l, b in zip(transfer['lineIds'], transfer['stationInstanceIds']) if l == 'shanghai-line6-6')
        if body not in allowed:
            first['scopeCorrections'].append(dict(id='defer-sh6-' + transfer['id'], taskId='opening:sh6-first',
                transferId=transfer['id'], oldStationInstanceIds=transfer['stationInstanceIds'], oldLineIds=transfer['lineIds'],
                source=SOURCE, description='此站不属于2007年客运首开范围；保留物理建设，稍后按实际开站重新确认。'))
    # Sports Bureau's yearbook independently dates the actual rename to May 7.
    # Reuse the same physical station and track, changing only the required name.
    rename_id = 'shanghai-jiyang-rename-2011'
    rename = deepcopy(chapters[phases[1][0]])
    rename.update(id=rename_id, date='2011-05-07', title='济阳路更名东方体育中心',
                  source=RENAME_SOURCE, sourceTitle='上海体育年鉴2012：5月7日大事记',
                  sourcePublicationDate=None, chapterScope='dated_station_rename', operationType='rename',
                  eventText='2011年5月7日，济阳路站更名东方体育中心。保留站体、位置及轨道，更新此时名称。',
                  requiredTransfers=[], scopeCorrections=[], serviceTransitions=[], historicalEventIds=[rename_id + ':event'])
    rename['lineGroups'][0].update(taskId=rename_id + ':line6', coverageGroupId=rename_id + ':line6',
                                   stationNames={lookup['灵岩南路']: '灵岩南路', lookup['东方体育中心']: '东方体育中心'},
                                   stationOrderSource=RENAME_SOURCE)
    rename['story'].update(opening=rename['eventText'], purpose='选中既有济阳路站，确认历史名称变化，不重复建设。',
                           outcome='东方体育中心名称已采用，原站体及线路连接保留。')
    city['chapters'] = sorted([c for c in city['chapters'] if c['id'] != rename_id] + [rename], key=lambda c: c['date'])
    target['historicalMilestones'] = [m for m in target['historicalMilestones'] if m['chapterId'] != rename_id] + [
        dict(chapterId=rename_id, date='2011-05-07', source=RENAME_SOURCE, sourcePublicationDate=None,
             bibliographicCitation=dict(kind='official_yearbook', edition='上海体育年鉴2012', locator='2011年大事记，5月7日地铁站更名条目'),
             publicationDateNote='年鉴按2011年大事记记载5月7日，不将文件网页更新时间当作事件日期。',
             groups=[dict(id=rename_id + ':line6', historicalLineId='shanghai-line6-6', scopeType='stations',
                          stationNames=FIRST + ['东方体育中心'], allowReverse=True, fullServiceOrder=True)])]
    target['historicalMilestones'][-1]['groups'][0]['constructionStationNames']=['灵岩南路','东方体育中心']
    data['contentRevision'] = REVISION
    data['contentRevisionNote'] = '上海6号线恢复2007年27站首开；2011年只补济阳路一站及区间，保留独立站体和实际换乘。'
    write('data/campaigns.json', data); write('data/official_targets_2026-10-01.json', official)
    print('Shanghai6: 2007 first27 and 2011 one-station opening, independent period-order targets')


if __name__ == '__main__':
    main()
