"""Reconcile the internal map inventory with the independent operator capture.

This updates internal object IDs, never generates official expected answers
from playable chapter data. Retrieval after the cutoff remains a separate
unpassed temporal audit.
"""
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE='https://www.chengdurail.com/op/station-time'
RESERVED30='https://infosharingp2-oss.camet.org.cn/resources/manual/2026/01/04/759313381470277.pdf'


def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def write(path,value):(ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def normalized(name):return name.replace('·','').removesuffix('站')


def main():
    baseline=read('data/network_baselines_2026-10-01.json')
    city=next(c for c in read('data/cities.json')['cities'] if c['id']=='chengdu')
    campaign=read('data/campaigns.json')['cities']['chengdu']
    evidence=read('data/official_evidence/chengdu_operator_orders_retrieved2026-10-23.json')
    aliases=campaign.get('stationComplexAliases',{})
    names={}
    for s in city['stations']:names.setdefault(normalized(s['name']),set()).add(aliases.get(s['id'],s['id']))
    # Evidence file metadata is separate from the immutable per-line capture.
    lines=evidence.get('lines',evidence.get('routes',{}))
    if not lines:raise ValueError(f'No independently captured orders: {evidence.keys()}')
    row=baseline['cities']['chengdu'];all_ids=set();occurrences=0
    for route in row['routes']:
        number=re.search(r'\d+',route['ref']).group()
        documented=lines[number]['orders']
        original_ids=route.get('mapStationIds',route['cutoffStationIds'])
        line_references={aliases.get(s,s) for s in original_ids}
        ordered=[]
        for branch in documented:
            for name in branch:
                candidates=names.get(normalized(name),set())
                if len(candidates)>1 and len(candidates & line_references)==1:
                    candidates=candidates & line_references
                if len(candidates)!=1:raise ValueError(f'{number}/{name}: ambiguous station identity {candidates}')
                identity=next(iter(candidates))
                if identity not in ordered:ordered.append(identity)
        old=route.get('mapStationIds',route['cutoffStationIds']).copy()
        route.setdefault('mapStationIds',old)
        route['cutoffStationIds']=ordered
        route['stationOrderSource']=SOURCE
        route['stationOrderEvidence']='data/official_evidence/chengdu_operator_orders_retrieved2026-10-23.json'
        route['sourceRetrievedAt']='2026-10-23'
        route['cutoffTemporalReviewStatus']='pending'
        route['cutoffStationCount']=len(ordered)
        if number=='30':
            route['excludedStations']=[{'id':'chengdu-s363','name':'玉虹路','reason':'已建暂缓开放','source':RESERVED30},
                                       {'id':'chengdu-s364','name':'分水','reason':'已建暂缓开放','source':RESERVED30}]
        if number in ['18','19']:
            route['excludedStations']=[{'id':'chengdu-s311','name':'天府机场3号4号航站楼','reason':'预留未开放','source':SOURCE}]
        occurrences+=len(ordered);all_ids.update(ordered)
    row['cutoffStopOccurrenceCount']=occurrences
    row['cutoffUniqueStationComplexCount']=len(all_ids)
    row['inventoryNote']='原始地图计数和对象另存；截止日目标使用独立运营站序对应的稳定站区身份。取回日期晚于截止日，逐站开放时间仍需独立有日期资料审核。'
    write('data/network_baselines_2026-10-01.json',baseline)
    print(f'16 internal route inventories reconciled, {occurrences} stop occurrences, {len(all_ids)} complexes; temporal gate remains pending')


if __name__=='__main__':main()
