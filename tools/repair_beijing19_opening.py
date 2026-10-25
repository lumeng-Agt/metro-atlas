"""Restore 19-line six-stop opening and the four delayed stations."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import refresh_schedule

REVISION='2026.10.25.2'
OPEN='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202201/t20220103_2581472.html'
INFILL='https://jtw.beijing.gov.cn/xxgk/xwfbh/202207/t20220729_2781907.html'
ORDER='https://www.bjmoa.cn/metroLineList.html?sline=16'
FULL='牡丹园 北太平庄 积水潭 平安里 太平桥 牛街 景风门 草桥 新发地 新宫'.split()
FIRST='牡丹园 积水潭 牛街 草桥 新发地 新宫'.split()
LINE='beijing-line19-19'


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json');baseline=read('data/network_baselines_2026-10-01.json')
    city=data['cities']['beijing'];target=official['cities']['beijing'];chapters={c['id']:c for c in city['chapters']}
    names={s['id']:s['name'] for c in read('data/cities.json')['cities'] if c['id']=='beijing' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId']==LINE));lookup={names[s]:s for s in template['stationIds']}
    first=chapters['beijing-network-milestone-2021-12-31'];id_='beijing-line19-infill-2022'
    infill=chapters.get(id_)
    if infill is None:
        infill=dict(id=id_,phase='history',date='2022-07-30',title='19号线四座暂缓站开放',lineGroups=[],requiredTransfers=[],
            scopeCorrections=[],requireOpen=True,eventOnly=False,precision='station_areas',geometryStatus='station_area_approximation',
            operationType='infill',chapterScope='dated_opening_ranges',historicalEventIds=[id_+':event'],routeTargetCount=1,
            story=dict(opening='2022年7月30日，19号线北太平庄、平安里、太平桥、景风门四站开放。',
                purpose='复用首开六站，补齐四座暂缓站，并分别确认新增换乘。',outcome='19号线10站全部投入试运营，平安里与景风门新增换乘。',
                eventKind='network_expansion',steps=deepcopy(first['story']['steps']),beats=[],planVersions=[]))
        chapters[id_]=infill
    for chapter,order,task,source,publication in [(first,FIRST,'route:beijing-r19',OPEN,'2022-01-03'),
            (infill,FULL,'opening:bj19-infill',INFILL,'2022-07-29')]:
        ids=[lookup[n] for n in order];group=deepcopy(template)
        group.update(taskId=task,coverageGroupId=task,stationIds=ids,stationNames=dict(zip(ids,order)),
            stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},stationOrderSource=ORDER,
            source=source,replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=19,defaultServiceStatus='trial',
            precisionNote='2021年首开六站，北太平庄／平安里／太平桥／景风门于2022-07-30才开放；站区为近似参考，未开放不算停站。')
        chapter['lineGroups']=[g for g in chapter.get('lineGroups',[]) if g['historicalLineId']!=LINE]+[group]
        chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        if chapter is infill:chapter.update(source=source,sourcePublicationDate=publication,sourceTitle='交通委：19号线剩余四站7月30日起试运营',sourceCheckedAt='2026-10-25',
            sourceType='government_dated_opening_notice',status='trial_operation',eventText=infill['story']['opening'],
            alignmentNote='运营方逐站站序独立核对；地理位置及隧道为近似参考，不冒充工程测绘。')
        milestone=next((m for m in target['historicalMilestones'] if m['chapterId']==chapter['id']),None)
        if milestone is None:
            milestone=dict(chapterId=chapter['id'],date=chapter['date'],source=source,sourcePublicationDate=publication,groups=[]);target['historicalMilestones'].append(milestone)
        milestone['groups']=[g for g in milestone['groups'] if g.get('historicalLineId',g['id'])!=LINE]+[
            dict(id=task,historicalLineId=LINE,scopeType='stations',stationNames=order,allowReverse=True,fullServiceOrder=True,requiredServiceStatus='trial')]
        milestone['additionalSources']=list(dict.fromkeys(milestone.get('additionalSources',[])+[source,ORDER]))
    pool={t['id']:deepcopy(t) for c in chapters.values() for t in c.get('requiredTransfers',[]) if LINE in t['lineIds']}
    for transfer in pool.values():
        if transfer['name']=='新宫':transfer['source']=INFILL
    available=set();placed=set()
    for chapter in sorted(chapters.values(),key=lambda c:c['date']):
        chapter['requiredTransfers']=[t for t in chapter.get('requiredTransfers',[]) if t['id'] not in pool]
        for group in chapter.get('lineGroups',[]):available.update((group['historicalLineId'],group.get('stationInstances',{}).get(s,s)) for s in group['stationIds'])
        for id_,transfer in pool.items():
            if id_ not in placed and all(pair in available for pair in zip(transfer['lineIds'],transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer));placed.add(id_)
    # Preserve the explicit dated transfer requirements in the independent
    # answer as well. Source notice distinguishes the new 4/6 and 14 links.
    for chapter in [first,infill]:
        milestone=next(m for m in target['historicalMilestones'] if m['chapterId']==chapter['id'])
        milestone['transfers']=list(dict.fromkeys(milestone.get('transfers',[])+[t['id'] for t in chapter['requiredTransfers'] if t['id'] in pool]))
    target['cutoffNetwork']['groups']=[g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])!=LINE]+[
        dict(id=LINE,historicalLineId=LINE,scopeType='stations',stationNames=FULL,allowReverse=True,fullServiceOrder=True,
             lastPhysicalOpeningDate='2022-07-30',lastPhysicalOpeningSource=INFILL)]
    city['chapters']=sorted(chapters.values(),key=lambda c:c['date'])
    row=baseline['cities']['beijing'];old=[e for e in row['documentedMilestones'] if e.get('routeIds')==['beijing-r19']]
    for event in old:
        if not any(e['id']==event['id'] for e in row.setdefault('supersededDocumentedMilestones',[])):
            row['supersededDocumentedMilestones'].append(dict(event,supersededReason='首开六站与剩余四站不能在2021年一次开放。'))
    old_ids={e['id'] for e in old};row['documentedMilestones']=[e for e in row['documentedMilestones'] if e not in old and not e['id'].startswith('reviewed-bj19:')]
    for chapter in city['chapters']:chapter['historicalEventIds']=[e for e in chapter.get('historicalEventIds',[]) if e not in old_ids and not e.startswith('reviewed-bj19:')]
    for chapter,key,source,pub in [(first,'first',OPEN,'2022-01-03'),(infill,'infill',INFILL,'2022-07-29')]:
        event='reviewed-bj19:'+key;chapter['historicalEventIds'].append(event)
        row['documentedMilestones'].append(dict(id=event,date=chapter['date'],title='19号线首开六站' if key=='first' else '19号线四站开放',status='trial_operation',
            chapterId=chapter['id'],routeIds=['beijing-r19'],source=source,sourcePublicationDate=pub,
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['historicalLineId']==LINE]))
    row['documentedMilestones'].sort(key=lambda e:(e['date'],e['id']));row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('beijing',row,city,'2026-10-01')
    data.update(contentRevision=REVISION,contentRevisionNote='北京19号线恢复2021年六站首开、2022年四站增站与按期换乘，独立检查实际试运营范围。')
    for path,value in [('data/campaigns.json',data),('data/official_targets_2026-10-01.json',official),('data/network_baselines_2026-10-01.json',baseline)]:write(path,value)
    print('Beijing19: six trial stops in2021, ten in2022; later interchanges no longer open prematurely')


if __name__=='__main__':main()
