"""Sync corrected operator orders to map references, preserving player bodies.

Only explicitly reviewed lines are changed. This does not certify any city's
whole inventory or replace the separate official completeness checks.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION='2026.10.24.27'


def main():
    data=read('data/campaigns.json');cities=read('data/cities.json');official=read('data/official_targets_2026-10-01.json')
    for cid,route_id,line_id in [
        ('shanghai','shanghai-r9','shanghai-line9-9'),
        ('chengdu','chengdu-r16','chengdu-line30-16'),
        ('chengdu','chengdu-r14','chengdu-line19-14')]:
        city=next(c for c in cities['cities'] if c['id']==cid);lookup={s['id']:s['name'] for s in city['stations']}
        route=next(r for r in city['lines'] if r['id']==route_id)
        expected=next(g for g in official['cities'][cid]['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])==line_id)
        cutoff=next(c for c in data['cities'][cid]['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
        actual=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==line_id)
        by_name={actual.get('stationNames',{}).get(s,lookup[s]):s for s in actual['stationIds']}
        ids=[by_name[n] for n in expected['stationNames']]
        route['stationIds']=ids
        for i,direction in enumerate(route.get('directions',[])):
            direction['stationIds']=ids.copy() if i==0 else list(reversed(ids))
        route['stationOrderReviewedAt']='2026-10-24'
        route['stationOrderSource']=actual.get('stationOrderSource',official['cities'][cid]['cutoffNetwork'].get('source',''))
        route['orderPrecisionNote']='按独立运营方站序修复离线关系成员遗漏与未开放站；地理轨迹仍为近似参考，不是历史隧道测绘。'
    # The western 2020 section belonged to 17 then, and to 19 after the 2023
    # reorganisation. Its physical reference therefore spans today's two maps.
    cd=data['cities']['chengdu']
    old=next(g for c in cd['chapters'] if c['id']=='chengdu-network-milestone-2020-12-18' for g in c['lineGroups'] if g['historicalLineId']=='chengdu-line17-12')
    old['additionalMapRouteSources']={'chengdu-r14':'https://news.chengdu.cn/2023/0904/2371119.shtml'}
    old['geographicLineageNote']='2020年17号线西段部分于2023年划归19号线；使用当代17/19地理参照，历史线路身份不变。'
    data['contentRevision']=REVISION
    data['contentRevisionNote']='修复已独立核对的上海9号线、成都19/30号线地图成员清单；保留2020年17号线的跨现状线路地理来源。'
    baseline=read('data/network_baselines_2026-10-01.json');generated=build(cities,data)
    for cid,row in baseline['cities'].items():
        for key in ['routes','mapRouteEntryCount','mapRouteStopOccurrenceCount','mapUniqueStationCount']:
            row[key]=deepcopy(generated['cities'][cid][key])
        # Keep reviewed project inventories and history. Do not rerun old
        # scaffolding over hand-authored corrections merely to refresh counts.
        for project in row.get('projectsAtCutoff',[]):
            project.setdefault('status',project.get('statusAtCutoff','项目范围见来源'))
            project.setdefault('note',project.get('playabilityNote','范围、任务与独立审核结果分别记录；不以分类豁免必做建设。'))
            project.setdefault('sourceCheckedAt','2026-10-24')
        refresh_schedule(cid,row,data['cities'][cid],'2026-10-01')
    baseline['compiledAt']='2026-10-24'
    write('data/campaigns.json',data);write('data/cities.json',cities);write('data/network_baselines_2026-10-01.json',baseline)
    print('Reviewed map memberships updated; player body IDs, geometry and prior milestones are not moved')


if __name__=='__main__':main()
