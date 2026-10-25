"""Restore Line 3's dated airport extension, infill and eastern extension.

Keep old event identities and player geometry. The modern OSM route omitted
the closed Airport South station and incorrectly entered a 2018 task whole.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import make_event_chapter,refresh_schedule

REVISION='2026.10.25.23'
LINE='guangzhou-line3-3'
SOUTH='guangzhou-h3-airport-south'
MEE='https://www.mee.gov.cn/gkml/sthjbgw/spwj1/201501/t20150116_294299.htm'
NORTH='https://news.sina.com.cn/o/2010-10-30/160518308188s.shtml?from=wap'
GAO='https://kgw.gz.gov.cn/xxgk/rddbjyhzxta/content/post_3108006.html'
T2='https://gzw.gz.gov.cn/zt/gzgz/content/post_2781834.html'
EAST='https://www.gz.gov.cn/attachment/7/7808/7808439/10246836.pdf'
FIRST='广州东站 燕塘 梅花园 京溪南方医院 同和 永泰 白云大道北 嘉禾望岗 龙归 人和 机场南'.split()
INFILL='人和 高增 机场南'.split()
AIRPORT='机场南 机场北'.split()
EASTERN='番禺广场 傍江 石碁南 海涌路 海傍'.split()
EXISTING_MAIN='广州东站 林和西 体育西路 珠江新城 广州塔 客村 大塘 沥滘 厦滘 大石 汉溪长隆 市桥 番禺广场'.split()
EXISTING_BRANCH='天河客运站 五山 华师 岗顶 石牌桥 体育西路'.split()


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json');cities=read('data/cities.json')
    city=data['cities']['guangzhou'];row=baseline['cities']['guangzhou'];target=official['cities']['guangzhou']
    geography=next(c for c in cities['cities'] if c['id']=='guangzhou')
    if not any(s['id']==SOUTH for s in geography['stations']):
        geography['stations'].append(dict(id=SOUTH,name='机场南',latlng=[23.3887083,113.297575],osmIds=[5444544490],
                                         historicalOnly=True,source='https://www.openstreetmap.org/node/5444544490',
                                         positionPrecision='approximate_station_area',sourceCheckedAt='2026-10-25',
                                         note='现代地理站址参考；2010开放事实另据生态环境部验收，2026暂停服务后仍保留实体。'))
    historical=next(s for s in geography['stations'] if s['id']==SOUTH)
    historical.update(historicalLineId=LINE,historicalOpeningSource=MEE)
    names={s['id']:s['name'] for s in geography['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    templates=[g for g in cutoff['lineGroups'] if g['historicalLineId']==LINE]
    ids_by_name={names[s]:s for g in templates for s in g['stationIds']};ids_by_name['机场南']=SOUTH
    instances={s:g.get('stationInstances',{}).get(s,s) for g in templates for s in g['stationIds']}
    instances.update({s:city.get('stationInstanceAliases',{}).get(LINE+'|'+s,instances.get(s,s)) for s in ids_by_name.values()})
    def group(order,key,title,source,replace=False):
        ids=[ids_by_name[n] for n in order]
        g=deepcopy(templates[0]);g.update(taskId=key,coverageGroupId=key,name=title,stationIds=ids,
             stationNames=dict(zip(ids,order)),stationInstances={s:instances.get(s,s) for s in ids},
             stationOrderSource=source,replaceExistingService=replace,servicePathRevision=36,
             precisionNote='按本期开放站序复现；现代站址及近似走廊作地理参考，不是历史隧道测绘。')
        for old in ['sourceStationIds','sourceStationInstances','constructionScopeNote','retainDocumentedFutureService']:g.pop(old,None)
        if SOUTH in ids:g['historicalStationSources']={SOUTH:MEE}
        return g
    old=next(c for c in city['chapters'] if c['id']=='guangzhou-network-milestone-2018-12-28')
    deferred_pairs={t['name']:deepcopy(t) for t in old.get('requiredTransfers',[]) if set(t['lineIds']) in ({LINE,'guangzhou-line2-2'},{LINE,'guangzhou-line9-9'})}
    old['requiredTransfers']=[t for t in old.get('requiredTransfers',[]) if t['id'] not in {p['id'] for p in deferred_pairs.values()}]
    old['lineGroups']=[g for g in old['lineGroups'] if g['historicalLineId']!=LINE]
    old.update(title='广佛线南延、14号线一期及21号线首通段开通',scopeRevision=REVISION,requiresScopeRecheck=True)
    old['story']['opening']='2018年12月28日，继续建设广佛线南延、14号线一期及21号线首通段。3号线机场北已于4月开放，东延四站则属于2024年。'
    for event in row['documentedMilestones']:
        if event.get('chapterId')==old['id']:
            event['routeIds']=[r for r in event.get('routeIds',[]) if r!='guangzhou-r3']
            event['targetLineGroups']=deepcopy(old['lineGroups']);event['title']=old['title']
    changes=[
        ('guangzhou-line3-airport-opening-2010','2010-10-30','亚运机场联系：广州东站至机场南',FIRST,MEE,'2015-01-16'),
        ('guangzhou-line3-airport-north-2018','2018-04-26','T2启用：机场南接至机场北',AIRPORT,T2,'2018-05-14'),
        ('guangzhou-line3-east-opening-2024','2024-11-01','3号线东延：番禺广场至海傍',EASTERN,EAST,None),
    ]
    for chapter_id,date,title,order,source,published in changes:
        key='opening:'+chapter_id
        g=group(order,key,title,source)
        event_id=chapter_id+'-event'
        event=dict(id=event_id,date=date,title=title,status='opened_or_completed',source=source,
                   sourcePublicationDate=published,routeIds=['guangzhou-r3'],targetLineGroups=[g],chapterId=chapter_id,
                   scope='本期开放站序：'+'—'.join(order))
        if chapter_id.endswith('2010'):event['additionalSources']=[NORTH]
        ch=next((c for c in city['chapters'] if c['id']==chapter_id),None)
        if ch is None:ch=make_event_chapter('guangzhou',date,[event],[]);city['chapters'].append(ch)
        ch.update(id=chapter_id,lineGroups=[g],historicalEventIds=[event_id],scopeRevision=REVISION,requiresScopeRecheck=True,
                  sourcePublicationDate=published,sourceCheckedAt='2026-10-25',eventOnly=False,operationType='dated_station_segment')
        ch['story']['purpose']='只建设本期开放范围，复用既有端点。未开放车站留到其真实历史节点。'
        if chapter_id.endswith('2010'):ch['additionalSources']=[dict(url=NORTH,note='2010年10月30日开通现场报道；生态环境部资料明确高增、机场北当时未开放。')]
        existing=next((e for e in row['documentedMilestones'] if e['id']==event_id),None)
        if existing:existing.update(event)
        else:row['documentedMilestones'].append(event)
        expected=dict(chapterId=chapter_id,date=date,source=source,sourcePublicationDate=published,
                      groups=[dict(id=key,historicalLineId=LINE,stationNames=order,scopeType='stations',allowReverse=True,matchScope='contiguous_subsequence')])
        if published is None:expected['bibliographicCitation']=dict(kind='official_yearbook',edition='2024年广州市交通发展年度报告',locator='附录，第34页：11月1日三号线东延段开通')
        if chapter_id.endswith('2010'):
            expected['existingScopes']=[dict(id='gz3-existing-main-before-airport',historicalLineId=LINE,stationNames=EXISTING_MAIN,scopeType='stations',allowReverse=True,matchScope='contiguous_subsequence'),
                                        dict(id='gz3-existing-branch-before-airport',historicalLineId=LINE,stationNames=EXISTING_BRANCH,scopeType='stations',allowReverse=True,matchScope='contiguous_subsequence')]
            expected['additionalSources']=[NORTH,'https://apis.gzmtr.com/app-map/metroweb/linestation']
        target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId']!=chapter_id]+[expected]
    # High-zeng was a reserved station in the 2010 opening. Its physical
    # infill and independent Line 9 body become usable together in 2017.
    high=next(c for c in city['chapters'] if c['date']=='2017-12-28')
    key='opening:guangzhou-line3-gaozeng-2017'
    high['lineGroups']=[g for g in high['lineGroups'] if g.get('taskId')!=key]+[group(INFILL,key,'3号线高增站开放',GAO)]
    high.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    high_expected=dict(chapterId=high['id'],date=high['date'],source=GAO,sourcePublicationDate='2019-09-10',
                       additionalSources=['https://www.xinhuanet.com/politics/2017-12/30/c_129779216.htm'],
                       groups=[dict(id=key,historicalLineId=LINE,stationNames=INFILL,scopeType='stations',allowReverse=True,matchScope='contiguous_subsequence')])
    target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId']!=high['id']]+[high_expected]
    for name,chapter_id,date,source in [('嘉禾望岗','guangzhou-line3-airport-opening-2010','2010-10-30',MEE),('高增',high['id'],'2017-12-28',GAO)]:
        # Recover the stable pair on repeated authoring runs after it has
        # already moved out of the former, wrongly dated 2018 chapter.
        pairing=deferred_pairs.get(name)
        if pairing is None:
            pairing=next(deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers',[]) if t['name']==name and LINE in t['lineIds'] and ('guangzhou-line2-2' if name=='嘉禾望岗' else 'guangzhou-line9-9') in t['lineIds'])
        pairing.update(effectiveDate=date,openingSource=source)
        ch=next(c for c in city['chapters'] if c['id']==chapter_id)
        ch['requiredTransfers']=[t for t in ch.get('requiredTransfers',[]) if t['id']!=pairing['id']]+[pairing]
        for milestone in target['historicalMilestones']:
            if milestone['chapterId']==chapter_id and pairing['id'] not in milestone.setdefault('transfers',[]):milestone['transfers'].append(pairing['id'])
    eastern=next(c for c in city['chapters'] if c['id']=='guangzhou-line3-east-opening-2024')
    g4=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='guangzhou-line4-4')
    old_id=next(s for s in g4['stationIds'] if names[s]=='海傍')
    old_instance=city.get('stationInstanceAliases',{}).get('guangzhou-line4-4|'+old_id,g4.get('stationInstances',{}).get(old_id,old_id))
    new_id=ids_by_name['海傍']
    def canonical(sid):
        seen=set()
        while sid in city.get('stationComplexAliases',{}) and sid not in seen:seen.add(sid);sid=city['stationComplexAliases'][sid]
        return sid
    if canonical(new_id)!=canonical(old_id):
        city.setdefault('stationComplexAliases',{})[canonical(new_id)]=canonical(old_id)
        city.setdefault('stationComplexAliasSources',{})[new_id]=dict(source=EAST,sourceCheckedAt='2026-10-25',note='海傍3、4号线换乘站区；独立站体不移动。')
    pairing=dict(id='historic-transfer-gz3-east-haibang-4',name='海傍',complexId=canonical(old_id),lineIds=['guangzhou-line4-4',LINE],
                 stationInstanceIds=[old_instance,instances.get(new_id,new_id)],source=EAST,effectiveDate='2024-11-01',precision='schematic')
    eastern['requiredTransfers']=[pairing]
    for milestone in target['historicalMilestones']:
        if milestone['chapterId']==eastern['id']:milestone['transfers']=[pairing['id']]
    if not any(t['id']==pairing['id'] for t in cutoff.get('requiredTransfers',[])):cutoff.setdefault('requiredTransfers',[]).append(deepcopy(pairing))
    if pairing['id'] not in target['cutoffNetwork'].setdefault('transfers',[]):target['cutoffNetwork']['transfers'].append(pairing['id'])
    # Persist only authored content. No save or already-built physical object
    # is deleted when a formerly wrong modern snapshot is removed from 2018.
    city['chapters'].sort(key=lambda c:c['date'])
    row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('guangzhou',row,city,'2026-10-01')
    for doc in [data,baseline]:
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='广州3号线机场北延、高增增站、T2及东延恢复独立日期；补回历史机场南实体。换乘及全历史复核继续。'
    write('data/cities.json',cities);write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('GZ3: 2010 airport, 2017 Gaozeng, 2018 T2, 2024 east scopes authored; fresh replay required')


if __name__=='__main__':main()
