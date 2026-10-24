"""Remove imported route contamination and resolve reviewed stop references.

No city coordinates or player objects are removed. Raw excluded memberships
are archived on the map route for inspection.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from build_network_baseline import build

REVISION='2026.10.24.32'
SCOPES=[('shanghai','shanghai-r3','shanghai-line3-3'),('shanghai','shanghai-r11','shanghai-line11-11'),
        ('shenzhen','shenzhen-r12','shenzhen-line11-12'),('chengdu','chengdu-r6','chengdu-line6-6'),
        ('chengdu','chengdu-r9','chengdu-line9-9'),('chengdu','chengdu-r13','chengdu-line18-13')]


def main():
    data=read('data/campaigns.json');cities=read('data/cities.json');official=read('data/official_targets_2026-10-01.json')
    for cid,route_id,line_id in SCOPES:
        city=next(c for c in cities['cities'] if c['id']==cid);names={s['id']:s['name'] for s in city['stations']}
        chapter=next(c for c in data['cities'][cid]['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
        groups=[g for g in chapter['lineGroups'] if g['historicalLineId']==line_id]
        targets=[g for g in official['cities'][cid]['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])==line_id]
        patterns=[]
        for target in targets:
            group=next(g for g in groups if [g.get('stationNames',{}).get(s,names[s]) for s in g['stationIds']] in [target['stationNames'],list(reversed(target['stationNames']))])
            lookup={group.get('stationNames',{}).get(s,names[s]):s for s in group['stationIds']}
            patterns.append([lookup[n] for n in target['stationNames']])
        assert patterns,(cid,route_id)
        route=next(r for r in city['lines'] if r['id']==route_id)
        old=route['stationIds'].copy();members=list(dict.fromkeys(s for p in patterns for s in p))
        if old!=members:
            route.setdefault('previousRouteMembership',[]).append(dict(stationIds=old,
                reason='公开运营方站序排除跨系统关系污染、同名重复及未开放站；原始地理点保留。',reviewedAt='2026-10-24'))
        route['stationIds']=members
        template=route.get('directions',[{}])[0]
        route['directions']=[]
        for i,pattern in enumerate(patterns):
            for forward in [True,False]:
                direction=deepcopy(template);direction['id']=f'reviewed-{route_id}-{i+1}-'+('out' if forward else 'in')
                direction['stationIds']=pattern.copy() if forward else list(reversed(pattern))
                route['directions'].append(direction)
        route.update(stationOrderReviewedAt='2026-10-24',stationOrderSource=official['cities'][cid]['cutoffNetwork']['source'],
            orderPrecisionNote='成员与运营方完整站序核对；地理轨迹仍为离线近似，不表示隧道测绘。上海11号线仅包含本线跨城花桥段，不含独立运营的苏州3/11号线。')
    baseline=read('data/network_baselines_2026-10-01.json');generated=build(cities,data)
    for cid in {s[0] for s in SCOPES}:
        for key in ['routes','mapRouteEntryCount','mapRouteStopOccurrenceCount','mapUniqueStationCount']:
            baseline['cities'][cid][key]=deepcopy(generated['cities'][cid][key])
    data.update(contentRevision=REVISION,contentRevisionNote='按已核对的独立站序修复上海11号线混入苏州线路、重复站区引用，以及成都18号线未开放机场站成员；保留原地理点与玩家建设。')
    for path,value in [('data/campaigns.json',data),('data/cities.json',cities),('data/network_baselines_2026-10-01.json',baseline)]:write(path,value)
    print('Six reviewed map routes corrected; original geography and excluded raw members retained')


if __name__=='__main__':main()
