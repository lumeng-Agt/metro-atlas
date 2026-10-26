"""Keep Chigang out of the 2025 opening; add its real 2026 infill action."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import make_event_chapter,refresh_schedule

REVISION='2026.10.25.26'
LINE='guangzhou-line12-12'
FIRST_SOURCE='https://news.dayoo.com/guangzhou/202506/28/139995_54841356.htm'
OPEN_SOURCE='https://gzdaily.dayoo.com/pc/html/2026-02/13/content_866_904065.htm'
FIRST_EAST='二沙岛 赤岗塔 赤沙北 赤沙 北山 官洲 大学城北 大学城南'.split()
WEST='浔峰岗 浔峰岗北 西洲 聚龙 广州白云站 棠涌 新市墟 白云文化广场 广州体育馆'.split()
EAST='二沙岛 赤岗塔 赤岗 赤沙北 赤沙 北山 官洲 大学城北 大学城南'.split()
INFILL=['赤岗塔','赤岗','赤沙北']
CHAPTER='guangzhou-line12-chigang-2026'


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['guangzhou'];row=baseline['cities']['guangzhou'];target=official['cities']['guangzhou']
    refs={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='guangzhou' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    first=next(c for c in city['chapters'] if c['id']=='guangzhou-network-milestone-2025-06-29')
    template=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==LINE and refs[g['stationIds'][0]]['name']=='二沙岛')
    by_name={refs[s]['name']:s for s in template['stationIds']}
    def group(order,key,title,source,replace):
        ids=[by_name[n] for n in order];g=deepcopy(template)
        g.update(taskId=key,coverageGroupId=key,name=title,stationIds=ids,stationNames=dict(zip(ids,order)),
                 stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
                 stationOrderSource=source,replaceExistingService=replace,servicePathRevision=38,
                 precisionNote='赤岗12号线站体于2026年2月13日才开放；2025东段通过不停车，不提前形成8／12号线换乘。')
        return g
    initial=group(FIRST_EAST,'route:guangzhou-r12-east-open','十二号线东段首开（赤岗暂缓）',FIRST_SOURCE,True)
    initial['constructionScope']='dated_service_patterns'
    initial['reconfirmLaterServices']=True
    first['lineGroups']=[initial if g.get('taskId')=='route:guangzhou-r12-east-open' else g for g in first['lineGroups']]
    for g in first['lineGroups']:
        if g.get('taskId')=='route:guangzhou-r12-west-open':
            g['coverageGroupId']='route:guangzhou-r12-west-open';g['constructionScope']='dated_service_patterns'
    pair=deepcopy(next(t for t in cutoff['requiredTransfers'] if t['name']=='赤岗' and LINE in t['lineIds']))
    pair.update(openingSource=OPEN_SOURCE,effectiveDate='2026-02-13',sourceNote='运营方2026年2月13日开放公告；8、12号线分别保留独立站体，换乘联系不接入列车轨道。')
    first['requiredTransfers']=[t for t in first.get('requiredTransfers',[]) if t['id']!=pair['id']]
    correction=dict(taskId=initial['taskId'],transferId=pair['id'],oldLineIds=pair['lineIds'],oldStationInstanceIds=pair['stationInstanceIds'],
                    source=OPEN_SOURCE,description='2025首开时赤岗尚未开放：保留旧站体，暂存旧版提前建立的换乘，至2026正式节点明确恢复。')
    corrections=first.setdefault('scopeCorrections',[])
    corrections[:]=[c for c in corrections if c.get('transferId')!=pair['id']]+[correction]
    western=next(g for g in first['lineGroups'] if g.get('taskId')=='route:guangzhou-r12-west-open')
    west_bodies={western.get('stationInstances',{}).get(s,s) for s in western['stationIds']}
    # A legacy save may already contain interchanges formed after June 2025.
    # Preserve those actual later links too, without creating them in a fresh
    # earlier chapter: restoration only applies to a connection archived here.
    known_links={t['id']:t for node in city['chapters']+city.get('futurePlans',[]) for t in node.get('requiredTransfers',[])}
    for link in known_links.values():
        if LINE not in link['lineIds'] or link['stationInstanceIds'][link['lineIds'].index(LINE)] not in west_bodies:continue
        correction=dict(taskId=initial['taskId'],restoreAfterTaskId=western['taskId'],transferId=link['id'],
                        oldLineIds=link['lineIds'],oldStationInstanceIds=link['stationInstanceIds'],source=FIRST_SOURCE,
                        description='东、西两段分别核对：西段任务确认后恢复其对应独立站体的原换乘联系。')
        corrections[:]=[c for c in corrections if c.get('transferId')!=link['id']]+[correction]
    first.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    added=group(INFILL,'opening:'+CHAPTER,'十二号线赤岗补站',OPEN_SOURCE,False)
    event=dict(id=CHAPTER+':opening',date='2026-02-13',title='赤岗开放：十二号线东段接入八号线',source=OPEN_SOURCE,
               sourcePublicationDate='2026-02-13',status='opened_or_completed',routeIds=['guangzhou-r12'],targetLineGroups=[added],chapterId=CHAPTER,
               scope='补入赤岗十二号线独立站体，复用赤岗塔、赤沙北，并明确建立8／12号线换乘。')
    chapter=next((c for c in city['chapters'] if c['id']==CHAPTER),None)
    if chapter is None:chapter=make_event_chapter('guangzhou',event['date'],[event],[]);city['chapters'].append(chapter)
    chapter.update(id=CHAPTER,title=event['title'],lineGroups=[added],requiredTransfers=[pair],historicalEventIds=[event['id']],
                   scopeRevision=REVISION,requiresScopeRecheck=True,eventOnly=False,operationType='infill_station',
                   source=OPEN_SOURCE,sourcePublicationDate='2026-02-13',sourceCheckedAt='2026-10-25')
    chapter['story'].update(opening='2026年2月13日，十二号线赤岗站正式开放，东段新增与八号线的换乘。',
                            purpose=event['scope'],outcome='十二号线东段形成九个开放停站，与八号线的换乘经过玩家明确确认。')
    old=next((e for e in row['documentedMilestones'] if e['id']==event['id']),None)
    if old:old.update(event)
    else:row['documentedMilestones'].append(event)
    for old in row['documentedMilestones']:
        if old.get('chapterId')==first['id'] and 'guangzhou-r12' in old.get('routeIds',[]):
            old['targetLineGroups']=[g for g in old.get('targetLineGroups',[]) if g.get('historicalLineId')!=LINE]+[deepcopy(g) for g in first['lineGroups'] if g.get('historicalLineId')==LINE]
    independent_first=dict(chapterId=first['id'],date='2025-06-29',source=FIRST_SOURCE,sourcePublicationDate='2025-06-28',
        groups=[dict(id='route:guangzhou-r12-east-open',historicalLineId=LINE,scopeType='stations',stationNames=FIRST_EAST,fullServiceOrder=True,allowReverse=True),
                dict(id='route:guangzhou-r12-west-open',historicalLineId=LINE,scopeType='stations',stationNames=WEST,fullServiceOrder=True,allowReverse=True)])
    old_first=next((m for m in target['historicalMilestones'] if m['chapterId']==first['id']),None)
    if old_first:
        independent_first['groups']=[g for g in old_first.get('groups',[]) if g.get('historicalLineId',g.get('id'))!=LINE]+independent_first['groups']
    expected=dict(chapterId=CHAPTER,date='2026-02-13',source=OPEN_SOURCE,sourcePublicationDate='2026-02-13',transfers=[pair['id']],
                  groups=[dict(id=added['taskId'],historicalLineId=LINE,scopeType='stations',stationNames=EAST,constructionStationNames=INFILL,fullServiceOrder=True,allowReverse=True)],
                  existingScopes=[dict(id='line12-existing-west',historicalLineId=LINE,scopeType='stations',stationNames=WEST,fullServiceOrder=True,allowReverse=True)])
    target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId'] not in [first['id'],CHAPTER]]+[independent_first,expected]
    evidence=dict(source=OPEN_SOURCE,effectiveDate='2026-02-13',scope='十二号线赤岗站开放，东段九站并增加与八号线换乘。')
    if evidence not in target['cutoffNetwork'].setdefault('temporalEvidence',[]):target['cutoffNetwork']['temporalEvidence'].append(evidence)
    cutoff['requiredTransfers']=[deepcopy(pair) if t['id']==pair['id'] else t for t in cutoff['requiredTransfers']]
    for g in cutoff['lineGroups']:
        if g.get('historicalLineId')==LINE:g['servicePathRevision']=38
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    city['chapters'].sort(key=lambda c:c['date']);row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('guangzhou',row,city,'2026-10-01')
    for doc in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='广州十二号线赤岗恢复2026年2月13日补站及8号线换乘；不再提前计入2025首开。独立时序核对继续。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('GZ12: 2025 east 8 + west 9; 2026 Chigang infill and explicit interchange authored')


if __name__=='__main__':main()
