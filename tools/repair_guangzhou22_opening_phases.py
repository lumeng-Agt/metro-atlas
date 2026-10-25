"""Separate the four-stop 2022 opening from the four-stop 2025 extension.

Dates/ranges are transcribed from dated government/operator reporting;
the independent modern operator order supplies geographic lookup, not dates.
No save file, physical station or track is changed by this authoring tool.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import refresh_schedule

REVISION='2026.10.25.18'
OPEN='https://ghzyj.gz.gov.cn/xwzx/gzdt/content/post_10615717.html'
ANNOUNCEMENT='https://gzdaily.dayoo.com/pc/html/2025-12/29/content_866_901829.htm'
ORDER='https://apis.gzmtr.com/app-map/metroweb/linestation'
FIRST='陈头岗 广州南站 市广路 番禺广场'.split()
EXTENSION='芳村 西塱 南漖 南浦西 陈头岗'.split()
FULL=EXTENSION+FIRST[1:]
LINE='guangzhou-line22-17'

def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['guangzhou'];row=baseline['cities']['guangzhou'];target=official['cities']['guangzhou']
    names={s['id']:s['name'] for c in read('data/cities.json')['cities'] if c['id']=='guangzhou' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==LINE)
    ids_by_name={names[s]:s for s in template['stationIds']}
    assert [names[s] for s in template['stationIds']]==FULL
    # Same historical complex, separate physical line bodies. These aliases
    # only describe documented interchange locations; none moves a station.
    for old,new in [('guangzhou-s302','guangzhou-s123'),('guangzhou-s282','guangzhou-s123'),('guangzhou-s276','guangzhou-s16')]:
        city.setdefault('stationComplexAliases',{})[old]=new
        city.setdefault('stationComplexAliasSources',{})[old]=dict(source=ORDER,sourceCheckedAt='2026-10-25',note='运营方同站换乘身份，仅统一逻辑站区；独立站体与既有坐标保留。')
    def body(line,name):
        matches=[]
        for g in cutoff['lineGroups']:
            if g['historicalLineId']!=line:continue
            for sid in g['stationIds']:
                if names[sid]==name:matches.append((sid,city.get('stationInstanceAliases',{}).get(line+'|'+sid,g.get('stationInstances',{}).get(sid,sid))))
        assert matches and len(set(matches))==1,(line,name,matches)
        return matches[0]
    def pairing(key,name,other_line,source):
        sid,own=body(LINE,name);_,other=body(other_line,name)
        complex_id=city['stationComplexAliases'].get(sid,sid)
        return dict(id=key,name=name,complexId=complex_id,stationInstanceIds=[own,other],lineIds=[LINE,other_line],
                    precision='schematic',source=source,sourceNote='运营方列明换乘，按各线独立站体建立；站内通道为示意，不连入列车轨道。')
    first=next(c for c in city['chapters'] if c['id']=='guangzhou-network-milestone-2022-03-31')
    def group(order,task):
        g=deepcopy(template);ids=[ids_by_name[n] for n in order]
        g.update(stationIds=ids,stationNames=dict(zip(ids,order)),taskId=task,coverageGroupId=task,
                 stationInstances={s:body(LINE,n)[1] for s,n in zip(ids,order)},
                 replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=33,
                 stationOrderSource=OPEN,precisionNote='开放范围和日期据同期公告及政府回顾；逐站顺序与运营方资料对照，隧道几何为近似参考。')
        return g
    first_group=group(FIRST,first['lineGroups'][0]['taskId'])
    first.update(title='22号线首通：陈头岗至番禺广场',lineGroups=[first_group],scopeRevision=REVISION,requiresScopeRecheck=True,
                 chapterScope='dated_opening_ranges',source=OPEN,sourcePublicationDate='2025-12-30',sourceCheckedAt='2026-10-25',
                 eventText='2022年3月31日，22号线陈头岗至番禺广场4站开放；芳村至南浦西仍为后续建设，不提前出现。')
    first['story'].update(opening=first['eventText'],purpose='建设南站快线首通4站，并明确与既有线路的换乘。',outcome='22号线首通段连成；后通段在2025年任务中接续。')
    first['requiredTransfers']=[pairing('historic-transfer-guangzhou-s276-line22-17-line18-15','番禺广场','guangzhou-line18-15',ORDER)]
    first['requiredTransfers'] += [pairing('historic-transfer-gz22-first-panyu-line3','番禺广场','guangzhou-line3-3',ORDER)]
    for key,line in [('line2','guangzhou-line2-2'),('line7','guangzhou-line7-7'),('foshan2','guangzhou-foshan-line2-18')]:
        first['requiredTransfers'].append(pairing('historic-transfer-gz22-first-south-'+key,'广州南站',line,ORDER))
    later_id='guangzhou-line22-west-opening-2025'
    later=next((c for c in city['chapters'] if c['id']==later_id),deepcopy(first))
    later_group=group(EXTENSION,later_id+':line22')
    # Replacing with the full period service avoids retaining the old modern
    # service in legacy saves, while construction only adds the new subsection.
    later_group.update(stationIds=[ids_by_name[n] for n in FULL],stationNames={ids_by_name[n]:n for n in FULL},
                       stationInstances={ids_by_name[n]:body(LINE,n)[1] for n in FULL})
    later.update(id=later_id,date='2025-12-29',title='22号线后通：连接芳村与西塱',lineGroups=[later_group],
                 historicalEventIds=['guangzhou-line22-west-opening-2025:event'],scopeCorrections=[],
                 operationType='extension',operationGuide='复用陈头岗，补建北侧四站并逐项建立西塱、芳村换乘。',
                 eventText='2025年12月29日，南浦西、南漖、西塱和芳村开放，22号线与原首通段贯通运营。')
    later['story'].update(opening=later['eventText'],purpose='从既有陈头岗接续北侧四站，形成芳村及西塱新换乘关系。',outcome='番禺广场至芳村8站贯通，原首通段复用。')
    fangcun=pairing('historic-transfer-guangzhou-s170-line1-line22-17','芳村','guangzhou-line1',ANNOUNCEMENT)
    # Preserve the original stable relation's side ordering as well as its ID.
    fangcun['lineIds'].reverse();fangcun['stationInstanceIds'].reverse()
    later['requiredTransfers']=[fangcun]
    for key,name,line in [('xilang-line1','西塱','guangzhou-line1'),('xilang-line10','西塱','guangzhou-line10-10'),
                          ('xilang-guangfo','西塱','guangzhou-foshan-route-20'),('fangcun-line11','芳村','guangzhou-line11-11')]:
        later['requiredTransfers'].append(pairing('historic-transfer-gz22-west-'+key,name,line,ANNOUNCEMENT))
    city['chapters']=sorted([c for c in city['chapters'] if c['id']!=later_id]+[later],key=lambda c:c['date'])
    # Literal independent requirements, not inferred from the task's objects.
    for ch,order in [(first,FIRST),(later,FULL)]:
        answer=dict(chapterId=ch['id'],date=ch['date'],source=OPEN,sourcePublicationDate='2025-12-30',
                    additionalSources=[ORDER,ANNOUNCEMENT],groups=[dict(id=ch['lineGroups'][0]['coverageGroupId'],historicalLineId=LINE,
                    scopeType='stations',stationNames=order,fullServiceOrder=True,allowReverse=True)],
                    transfers=[t['id'] for t in ch['requiredTransfers']])
        target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId']!=ch['id']]+[answer]
    # Retain original event identity but correct its actual scope. Add only the
    # new dated event, never replace another line's simultaneous event record.
    for ch in [first,later]:
        eid=ch['historicalEventIds'][0]
        event=next((e for e in row['documentedMilestones'] if e['id']==eid),None)
        if event is None:
            event=dict(id=eid);row['documentedMilestones'].append(event)
        event.update(date=ch['date'],title=ch['title'],status='opened_or_completed',source=OPEN,
                     sourcePublicationDate='2025-12-30',routeIds=['guangzhou-r17'],chapterId=ch['id'],targetLineGroups=deepcopy(ch['lineGroups']),
                     scope=ch['eventText'],dateBasis='independently_reviewed_operator_opening')
    row['documentedMilestoneCount']=len(row['documentedMilestones'])
    evidence=target['cutoffNetwork'].setdefault('temporalEvidence',[])
    for date,scope in [('2022-03-31','陈头岗至番禺广场4站'),('2025-12-29','芳村至南浦西4站，接续陈头岗贯通8站')]:
        if not any(e.get('historicalLineId')==LINE and e.get('effectiveDate')==date for e in evidence):
            evidence.append(dict(historicalLineId=LINE,effectiveDate=date,source=OPEN,sourcePublicationDate='2025-12-30',scope=scope))
    refresh_schedule('guangzhou',row,city,'2026-10-01')
    for doc in [data,baseline]:
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    data['contentRevisionNote']='广州22号线恢复2022首通4站及2025后通4站，新增真实换乘并保留旧站轨，不提前开放现代全线。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('GZ22 two dated openings; 4 then 8 stops, 10 explicit transfer pairings; city-wide review remains incomplete')
if __name__=='__main__':main()
