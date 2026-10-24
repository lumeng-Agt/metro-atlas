"""Restore the delayed Gangxia North opening; retain old physical works.

Literal station orders below were checked against the operator's 2020 opening
notice and 2022 hub announcement, independently of the chapter generator.
"""
from copy import deepcopy
from itertools import combinations
from repair_chengdu_historical_phases import read, write
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.24.28'
FIRST_SOURCE = 'https://www.szmc.net/home/xinwenzhongxin/gongsixinwen/202008/83235.html'
HUB_SOURCE = 'https://www.szmc.net/home/xinwenzhongxin/gongsixinwen/202210/101706.html'
ORDER_SOURCE = 'https://fgw.sz.gov.cn/zwgk/qt/tzgg/content/post_12849099.html'
FULL = '福田口岸 福民 岗厦 岗厦北 莲花村 冬瓜岭 孖岭 雅宝 南坑 光雅园 五和 坂田北 贝尔路 华为 岗头 雪象 甘坑 凉帽山 上李朗 木古 华南城 禾花 平湖 双拥街'.split()
FIRST = [n for n in FULL if n != '岗厦北']
LINE = 'shenzhen-line10-11'


def main():
    data = read('data/campaigns.json'); official = read('data/official_targets_2026-10-01.json')
    cities = read('data/cities.json'); city = data['cities']['shenzhen']; target = official['cities']['shenzhen']
    map_city = next(c for c in cities['cities'] if c['id'] == 'shenzhen')
    names = {s['id']: s['name'] for s in map_city['stations']}
    chapters = {c['id']: c for c in city['chapters']}
    cutoff = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE))
    lookup = {names[s]: s for s in template['stationIds']}
    first = chapters['shenzhen-network-milestone-2020-08-18']
    hub = chapters['shenzhen-network-milestone-2022-10-28']
    scopes = [(first, FIRST, FIRST_SOURCE, '2020-08-18', 'route:shenzhen-r11'),
              (hub, FULL, HUB_SOURCE, '2022-10-28', 'opening:sz10-gangxia-north')]
    for chapter, order, source, date, task in scopes:
        ids = [lookup[n] for n in order]; group = deepcopy(template)
        group.update(taskId=task, coverageGroupId=task, stationIds=ids, stationNames=dict(zip(ids, order)),
                     stationInstances={s: template['stationInstances'].get(s, s) for s in ids},
                     stationOrderSource=source, replaceExistingService=True, reconfirmLaterServices=True,
                     servicePathRevision=10, scopeRevision=REVISION,
                     precisionNote='10号线2020年开放23站，岗厦北2022年才开放；站点使用独立线路站体，区间为近似地理参考。')
        chapter['lineGroups'] = [g for g in chapter['lineGroups'] if g['historicalLineId'] != LINE] + [group]
        chapter.update(scopeRevision=REVISION, requiresScopeRecheck=True)
        expected = dict(id=task, historicalLineId=LINE, scopeType='stations', stationNames=order,
                        fullServiceOrder=True, allowReverse=True)
        milestone = next((m for m in target['historicalMilestones'] if m['chapterId'] == chapter['id']), None)
        if milestone is None:
            milestone = dict(chapterId=chapter['id'], date=date, source=source, sourcePublicationDate=date, groups=[])
            target['historicalMilestones'].append(milestone)
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId', g['id']) != LINE] + [expected]
    first.update(title='6、10号线首开：岗厦北暂不开放', source=FIRST_SOURCE, sourcePublicationDate='2020-08-18')
    first['story'].update(opening='2020年8月18日，6、10号线开门迎客。10号线24个已建站中，岗厦北暂不开放。',
                          purpose='先复现10号线23个开放站，保留岗厦北后续开站节点。',
                          outcome='10号线沿福田口岸—双拥街运行，岗厦北不提前计入客运停站。')
    hub.update(title='两线三枢纽：岗厦北四线换乘', source=HUB_SOURCE, sourcePublicationDate='2022-10-28')
    hub['story'].update(opening='2022年10月28日，14号线、11号线福岗区间及三大枢纽开放。',
                        purpose='补开10号线岗厦北，分别接通2、10、11、14号线站体，再确认四线换乘。',
                        outcome='岗厦北形成四线换乘，线路各走自己的轨道；不提前加入远期1号线换乘。')
    # Four actual line bodies, with explicit pedestrian links. No track edge is
    # added between them. Future line 1 shown by the notice is not operational.
    bodies = {'shenzhen-line2-2': 'shenzhen-s103__line2-2', LINE: 'shenzhen-s103__line10-11',
              'shenzhen-line11-12': 'shenzhen-s103', 'shenzhen-line14-15': 'shenzhen-s103__line14-15'}
    transfers = []
    for left, right in combinations(bodies, 2):
        transfers.append(dict(id='sz-gangxia-north:' + left + ':' + right, name='岗厦北', complexId='shenzhen-s103',
                              lineIds=[left, right], stationInstanceIds=[bodies[left], bodies[right]],
                              source=HUB_SOURCE, precision='schematic',
                              sourceNote='运营方2022-10-28公告明确2、10、11、14号线；仅保存换乘关系，不推测站内通道结构。'))
    prefix = 'sz-gangxia-north:'
    for chapter in city['chapters']:
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if not t['id'].startswith(prefix)]
    hub['requiredTransfers'].extend(transfers)
    milestone = next(m for m in target['historicalMilestones'] if m['chapterId'] == hub['id'])
    milestone['transfers'] = [t['id'] for t in transfers]
    target['cutoffNetwork']['transfers'] = list(dict.fromkeys(target['cutoffNetwork'].get('transfers', []) + milestone['transfers']))
    # The local relation contained a second, phantom terminal named Gangxia
    # North after Shuangyong Street. Correct the map membership, not geography.
    route = next(r for r in map_city['lines'] if r['id'] == 'shenzhen-r11')
    route['stationIds'] = [lookup[n] for n in FULL]
    for i, direction in enumerate(route.get('directions', [])):
        direction['stationIds'] = route['stationIds'].copy() if i == 0 else list(reversed(route['stationIds']))
    route.update(stationOrderReviewedAt='2026-10-24', stationOrderSource=ORDER_SOURCE)
    # Replace the obsolete dated inventory record as well, preserving it for
    # provenance rather than allowing a modern snapshot to reappear in 2020.
    baseline = read('data/network_baselines_2026-10-01.json'); row = baseline['cities']['shenzhen']
    obsolete = [e for e in row['documentedMilestones'] if e.get('routeIds') == ['shenzhen-r11']]
    archive = row.setdefault('supersededDocumentedMilestones', [])
    for event in obsolete:
        if not any(e['id'] == event['id'] for e in archive):
            archive.append(dict(event, supersededReason='2020年岗厦北未开放，原关系还重复包含同名终点。'))
    removed = {e['id'] for e in obsolete}
    row['documentedMilestones'] = [e for e in row['documentedMilestones'] if e not in obsolete and not e['id'].startswith('reviewed-sz10:')]
    for chapter in city['chapters']:
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds', []) if e not in removed and not e.startswith('reviewed-sz10:')]
    for chapter, order, source, date, task in scopes:
        event_id = 'reviewed-sz10:' + task; chapter['historicalEventIds'].append(event_id)
        row['documentedMilestones'].append(dict(id=event_id, date=date, title=chapter['title'], status='operated',
            chapterId=chapter['id'], routeIds=['shenzhen-r11'], source=source, sourcePublicationDate=date,
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['historicalLineId'] == LINE]))
    row['documentedMilestones'].sort(key=lambda e: (e['date'], e['id']))
    row['documentedMilestoneCount'] = len(row['documentedMilestones'])
    generated = build(cities, data)['cities']['shenzhen']
    for key in ['routes', 'mapRouteEntryCount', 'mapRouteStopOccurrenceCount', 'mapUniqueStationCount']:
        row[key] = deepcopy(generated[key])
    refresh_schedule('shenzhen', row, city, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='深圳10号线恢复2020年23站首开、2022年岗厦北增站与四线独立站体换乘；移除地图成员中的重复同名终点。')
    for path, value in [('data/campaigns.json', data), ('data/cities.json', cities),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]:
        write(path, value)
    print('Shenzhen10: first23, hub24; six explicit four-line interchange links, no future line1')


if __name__ == '__main__': main()
