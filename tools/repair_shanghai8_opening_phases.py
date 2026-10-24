"""Restore the 8-line openings, including two genuinely delayed stations."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule

REVISION='2026.10.24.26'
FIRST_SOURCE='https://vic.sina.com.cn/20071228/09261146.shtml'
SOUTH_SOURCE='https://www.chinanews.com/expo/news/2009/07-03/1760649.shtml'
INFILL_SOURCE='https://www.chinametro.net/index.php?aid=13529&id=539&m=mobilenewscon'
NAME_SOURCE='https://tyj.sh.gov.cn/cmsres/35/358f756058ab4d6dac8ac8244daf1cb8/2dc493da0042bdf20170dfc0e2c3d1fd.pdf'
ART_SOURCE='https://news.sina.com.cn/o/2012-09-26/145925258090.shtml'
SHENDU_SOURCE='https://news.sina.com.cn/c/2013-08-29/095028078322.shtml'
FIRST='市光路 嫩江路 翔殷路 黄兴公园 延吉中路 黄兴路 江浦路 鞍山新村 四平路 曲阳路 虹口足球场 西藏北路 中兴路 曲阜路 人民广场 大世界 老西门 陆家浜路 西藏南路 耀华路'.split()
SOUTH='耀华路 成山路 杨思 凌兆新村 芦恒路 浦江镇 江月路 联航路 航天博物馆'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['shanghai'];target=official['cities']['shanghai']
    chapters={c['id']:c for c in city['chapters']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='shanghai-line8-8'))
    catalog={s['id']:s['name'] for c in read('data/cities.json')['cities'] if c['id']=='shanghai' for s in c['stations']}
    lookup={catalog[s]:s for s in template['stationIds']}
    lookup['济阳路']=lookup['东方体育中心'];lookup['航天博物馆']=lookup['沈杜公路']
    pool={t['id']:deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers',[]) if 'shanghai-line8-8' in t['lineIds']}
    late=chapters['shanghai-network-milestone-2018-12-30']
    late['lineGroups']=[g for g in late['lineGroups'] if g['historicalLineId']!='shanghai-line8-8']
    late['title']='5号线、12号线本期建设核对'
    late.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    sample=deepcopy(chapters['shanghai-line9-second-2009'])
    old=FIRST+SOUTH[1:]
    jiyang=FIRST+['成山路','杨思','济阳路']+SOUTH[3:]
    renamed=['东方体育中心' if n=='济阳路' else n for n in jiyang]
    art=renamed.copy()
    art.insert(art.index('耀华路'),'中华艺术宫')
    full=['沈杜公路' if n=='航天博物馆' else n for n in art]
    scopes=[
        ('shanghai-network-milestone-2007-12-29','2007-12-29','8号线一期首开20站',FIRST,FIRST,FIRST_SOURCE,'2007-12-28','opening:sh8-first',True),
        ('shanghai-line8-south-2009','2009-07-05','8号线二期：跨越黄浦江南下',SOUTH,old,SOUTH_SOURCE,'2009-07-03','opening:sh8-south',False),
        ('shanghai-network-milestone-2011-04-12','2011-04-12','6、8号线济阳路站开放',jiyang,jiyang,INFILL_SOURCE,'2011-04-12','opening:sh8-jiyang',True),
        ('shanghai-jiyang-rename-2011','2011-05-07','济阳路更名东方体育中心',renamed,renamed,NAME_SOURCE,None,'rename:sh8-jiyang',True),
        ('shanghai-line8-art-2012','2012-09-28','中华艺术宫站开放',art,art,ART_SOURCE,'2012-09-26','opening:sh8-art',True),
        ('shanghai-line8-shendu-2013','2013-08-31','航天博物馆更名沈杜公路',['联航路','沈杜公路'],full,SHENDU_SOURCE,'2013-08-29','rename:sh8-shendu',False),
    ]
    for cid,date,title,names,expected,source,pub,task,replace in scopes:
        chapter=chapters.get(cid)
        if chapter is None:
            chapter=deepcopy(sample)
            chapter.update(id=cid,date=date,title=title,lineGroups=[],requiredTransfers=[],scopeCorrections=[],serviceTransitions=[],
                           historicalEventIds=[cid+':event'],eventOnly=False,routeTargetCount=1,chapterScope='dated_opening_ranges',operationType='extension')
            chapters[cid]=chapter
        ids=[lookup[n] for n in names];group=deepcopy(template)
        group.update(taskId=task,coverageGroupId=task,stationIds=ids,stationNames=dict(zip(ids,names)),
                     stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
                     stationOrderSource=source,replaceExistingService=replace,reconfirmLaterServices=True,servicePathRevision=8,loop=False,
                     precisionNote='按实际开放边界复现；济阳路和周家渡不提前加入停站。站区及隧道为近似地理参考。')
        chapter['lineGroups']=[g for g in chapter['lineGroups'] if g['historicalLineId']!='shanghai-line8-8']+[group]
        chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        if cid!='shanghai-network-milestone-2007-12-29':
            chapter['title']=title
        if cid not in ['shanghai-network-milestone-2007-12-29','shanghai-network-milestone-2011-04-12','shanghai-jiyang-rename-2011']:
            text=f'{date}，{title}。复用既有站轨，只确认本期增加的开放范围或名称变化。'
            chapter.update(eventText=text,source=source,sourceTitle='运营方公开消息的同期现场报道',sourcePublicationDate=pub)
            chapter['story']=dict(opening=text,purpose='济阳路在2011年才开放，中华艺术宫在2012年才开放，不把已建站直接算作客运开站。',
                outcome='本期实际变化已记录；旧站体及未变区间保留。',eventKind='station_rename' if task.startswith('rename:') else 'network_expansion',
                steps=deepcopy(sample['story']['steps']),beats=[],planVersions=[])
        milestone=next((m for m in target.get('historicalMilestones',[]) if m['chapterId']==cid),None)
        if milestone is None:
            milestone=dict(chapterId=cid,date=date,source=source,sourcePublicationDate=pub,groups=[])
            target.setdefault('historicalMilestones',[]).append(milestone)
        milestone['groups']=[g for g in milestone['groups'] if g.get('historicalLineId',g['id'])!='shanghai-line8-8']+[
            dict(id=task,historicalLineId='shanghai-line8-8',scopeType='stations',stationNames=expected,
                 constructionStationNames=names,allowReverse=True,fullServiceOrder=True)]
        milestone.setdefault('additionalSources',[]).append(source)
    available=set();placed=set()
    for chapter in sorted(chapters.values(),key=lambda c:c['date']):
        chapter['requiredTransfers']=[t for t in chapter.get('requiredTransfers',[]) if t['id'] not in pool]
        for group in chapter.get('lineGroups',[]):
            available.update((group['historicalLineId'],group.get('stationInstances',{}).get(s,s)) for s in group['stationIds'])
        for id_,transfer in pool.items():
            if id_ not in placed and all(p in available for p in zip(transfer['lineIds'],transfer['stationInstanceIds'])):
                if set(transfer['lineIds'])=={'shanghai-line6-6','shanghai-line8-8'}:
                    transfer.update(source=INFILL_SOURCE,sourceNote='2011-04-12同时开放6、8号线济阳路站；各线路独立站体，换乘联系不进入轨道图。')
                chapter['requiredTransfers'].append(deepcopy(transfer));placed.add(id_)
    first=chapters[scopes[0][0]]
    allowed={template.get('stationInstances',{}).get(lookup[n],lookup[n]) for n in FIRST}
    first['scopeCorrections']=[c for c in first.get('scopeCorrections',[]) if not c['id'].startswith('defer-sh8-')]
    for transfer in pool.values():
        body=next(b for l,b in zip(transfer['lineIds'],transfer['stationInstanceIds']) if l=='shanghai-line8-8')
        if body not in allowed:
            first['scopeCorrections'].append(dict(id='defer-sh8-'+transfer['id'],taskId='opening:sh8-first',transferId=transfer['id'],
                oldStationInstanceIds=transfer['stationInstanceIds'],oldLineIds=transfer['lineIds'],source=FIRST_SOURCE,
                description='不属于8号线2007首开范围；保留物理站轨，在其所属后续节点重新确认。'))
    city['chapters']=sorted(chapters.values(),key=lambda c:c['date'])
    target['cutoffNetwork']['groups']=[g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])!='shanghai-line8-8']+[
        dict(id='shanghai-line8-cutoff',historicalLineId='shanghai-line8-8',scopeType='stations',stationNames=full,allowReverse=True,fullServiceOrder=True)]
    baseline=read('data/network_baselines_2026-10-01.json');row=baseline['cities']['shanghai']
    obsolete=[e for e in row['documentedMilestones'] if e.get('routeIds')==['shanghai-r8']]
    archive=row.setdefault('supersededDocumentedMilestones',[])
    for event in obsolete:
        if not any(e['id']==event['id'] for e in archive):archive.append(dict(event,supersededReason='现代8号线不应直到2018年才一次加入。'))
    row['documentedMilestones']=[e for e in row['documentedMilestones'] if e not in obsolete and not e['id'].startswith('reviewed-sh8:')]
    old_ids={e['id'] for e in obsolete}
    for chapter in city['chapters']:
        chapter['historicalEventIds']=[e for e in chapter.get('historicalEventIds',[]) if e not in old_ids and not e.startswith('reviewed-sh8:')]
    for cid,date,title,_names,_expected,source,pub,task,_replace in scopes:
        chapter=chapters[cid];event_id='reviewed-sh8:'+task;chapter['historicalEventIds'].append(event_id)
        row['documentedMilestones'].append(dict(id=event_id,date=date,title=title,status='operated',chapterId=cid,
            routeIds=['shanghai-r8'],source=source,sourcePublicationDate=pub,
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['historicalLineId']=='shanghai-line8-8']))
    row['documentedMilestones'].sort(key=lambda e:(e['date'],e['id']));row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('shanghai',row,city,'2026-10-01')
    data['contentRevision']=REVISION;data['contentRevisionNote']='上海8号线恢复2007首开20站、2009南延8站、2011济阳路与2012中华艺术宫开站，保留时期名称及独立换乘。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official);write('data/network_baselines_2026-10-01.json',baseline)
    print('Shanghai8: 20/28/29/30 opened stops, actual delayed infills and dated names; 6/8 interchange moves to2011')


if __name__=='__main__':main()
