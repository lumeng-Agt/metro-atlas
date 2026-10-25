"""Add independently extracted operator paths to the geographic audit only.

Does not mark inventory/history/temporal review complete, move stations,
generate construction or infer historical dates from the modern website.
"""
from repair_chengdu_historical_phases import read,write
from import_gzmtr_station_orders import SOURCE

REVISION='2026.10.25.16'
MAPPING={1:'guangzhou-line1',2:'guangzhou-line2-2',5:'guangzhou-line4-4',6:'guangzhou-line5-5',
         7:'guangzhou-line8-8',8:'guangzhou-foshan-route-20',10:'guangzhou-line6-6',11:'guangzhou-line7-7',
         12:'guangzhou-line9-9',13:'guangzhou-line13-13',16:'guangzhou-line21-16',18:'guangzhou-line18-15',
         19:'guangzhou-line22-17',21:'guangzhou-foshan-line2-18',23:'guangzhou-foshan-line3-19',
         30:'guangzhou-line11-11',32:'guangzhou-line10-10'}
EVIDENCE='data/official_evidence/guangzhou_operator_orders_retrieved2026-10-25.json'


def main():
    evidence=read(EVIDENCE);official=read('data/official_targets_2026-10-01.json')
    target=official['cities']['guangzhou']['cutoffNetwork'];groups=target['groups']
    # Existing sourced service patterns for 3/12/14 preserve their actual
    # through-running/independent branches. A UI selector's line grouping is
    # not permission to silently change these service patterns.
    for line in evidence['lines']:
        line_id=MAPPING.get(line['operatorLineId'])
        if not line_id:continue
        expected=dict(id=line_id,historicalLineId=line_id,scopeType='stations',stationNames=line['stationNames'],
                      allowReverse=True,fullServiceOrder=True,source=SOURCE,sourceRetrievedAt=evidence['retrievedAt'],
                      evidenceFile='res://'+EVIDENCE,operatorLineId=line['operatorLineId'])
        if line['operatorLineId']==30:expected['loop']=True
        groups[:]=[g for g in groups if g.get('historicalLineId',g['id'])!=line_id]+[expected]
    target.update(source=SOURCE,sourceRetrievedAt=evidence['retrievedAt'],inventoryReviewStatus='operator_paths_reviewed_dates_pending',
                  note='23条独立服务路径：本次新增运营方直接查询的17条路径；3/12/14号线分支沿用已有官方资料。时序与全量换乘仍未全部审核，不能以现行接口代替2026年10月1日事实。')
    target.pop('sourcePublicationDate',None)
    sources=target.setdefault('additionalSources',[])
    if not any(s.get('url')==evidence['sourceLanding'] for s in sources):sources.append(dict(url=evidence['sourceLanding']))
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json')
    city=data['cities']['guangzhou']
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    # The original first-line chapter used s298 (a modern Line 22 map point)
    # as its schematic Xilang target. Its existing body belongs to Line 1.
    # Preserve that body and all its tracks. Line 22 now requests its own
    # explicit physical instance at the published reference location.
    instance='guangzhou-s298__line22-17'
    city.setdefault('stationInstanceAliases',{})['guangzhou-line22-17|guangzhou-s298']=instance
    for chapter in city['chapters']+city.get('futurePlans',[]):
        for group in chapter.get('lineGroups',[]):
            if group.get('historicalLineId')=='guangzhou-line22-17' and 'guangzhou-s298' in group.get('stationIds',[]):
                group.setdefault('stationInstances',{})['guangzhou-s298']=instance
                group['stationBodyNote']='西塱22号线独立站体；保留旧1号线站体、坐标及轨道，不以同名或站区别名共用站体。'
                if chapter is cutoff:
                    group.update(replaceExistingService=True,servicePathRevision=32)
    for group in cutoff['lineGroups']:
        for station_id in ['guangzhou-s27','guangzhou-s298']:
            if station_id in group.get('stationIds',[]):
                group.setdefault('stationNames',{})[station_id]='西塱'
                group['stationNamingNote']='截止日运营方现用名称；1997首章西朗历史名保留。仅在玩家预览并提交本期校正时更新，不在读取旧档时改名。'
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    for doc in (data,baseline):
        revision_key=lambda value:tuple(int(p) for p in value.split('.'))
        if revision_key(REVISION)>=revision_key(doc.get('contentRevision','0')):doc['contentRevision']=REVISION
    data['contentRevisionNote']='广州独立现行站序补至23条路径；开放日期与换乘审查继续独立，不改站轨或旧进度。'
    write('data/official_targets_2026-10-01.json',official);write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline)
    print('Guangzhou independent geographic/service-order scopes:',len(groups),'(temporal and transfer completeness not certified)')


if __name__=='__main__':main()
