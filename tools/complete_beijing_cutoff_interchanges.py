"""Repair reviewed stop sequences and author explicit independent-body contacts.

Old geographic objects remain available for save recovery. Replacing an old
service and rebinding a known contact are explicit task transactions, never
load-time station moves or edits to an unknown player-created relationship.
"""
from copy import deepcopy
import itertools
from repair_chengdu_historical_phases import read,write
from review_beijing_cutoff_interchanges import EVIDENCE,ORDERS,LINES,NAME_ALIASES,LINE14_NAMES,LINE14
from build_network_baseline import build
from expand_historical_event_chapters import make_event_chapter,refresh_schedule

REVISION='2026.10.26.5'
TONGYUN='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202606/t20260630_4738884.html'
RING2='https://www.beijing.gov.cn/zhengce/zfwj/zfwj/bgtwj/201905/t20190523_73700.html'


def main():
    data=read('data/campaigns.json');cities=read('data/cities.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['beijing'];target=official['cities']['beijing'];geography=next(c for c in cities['cities'] if c['id']=='beijing')
    refs={s['id']:s for s in geography['stations']};evidence=read(EVIDENCE)
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    # These are separate OSM physical anchors in the correct line's position,
    # not merged halls. Preserve the other anchors for old files/other lines.
    duplicate={'beijing-line6-6':('beijing-s66','beijing-s343'),
               'beijing-line8-8':('beijing-s52','beijing-s134'),
               'beijing-line14-14':('beijing-s117','beijing-s295')}
    orders=read(ORDERS);by_number={l['line'].removesuffix('号线'):l for l in orders['lines']}
    desired={LINES['6']:by_number['6']['directions'][0]['stationNames'],
             LINES['8']:by_number['8']['directions'][0]['stationNames'],LINES['14']:LINE14_NAMES}
    templates={g['historicalLineId']:deepcopy(g) for g in cutoff['lineGroups']}
    # The previous two extension fragments stopped one physical interval
    # short of closing the ring. Reuse the original six southern bodies and
    # require the actual last-to-first rail, not just 18 nearby stations.
    ring_template=deepcopy(templates[LINES['2']]);ring_names=by_number['2']['directions'][0]['stationNames']
    ring_lookup={refs[s]['name']:s for s in ring_template['stationIds']};ring_ids=[ring_lookup[n] for n in ring_names]
    ring_chapter=next(c for c in city['chapters'] if c['id']=='beijing-network-milestone-1987-12-28')
    existing=next(g for g in ring_chapter['lineGroups'] if g['historicalLineId']==LINES['2'])
    ring_group=deepcopy(ring_template);ring_group.update(taskId=existing.get('taskId','opening:bj2-ring-1987'),
        coverageGroupId='beijing-ring2-1987',stationIds=ring_ids,stationNames=dict(zip(ring_ids,ring_names)),
        stationInstances={s:ring_template.get('stationInstances',{}).get(s,s) for s in ring_ids},
        loop=True,replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=40,
        stationOrderSource=RING2,name='环线成环：复用南段并闭合18站',constructionScope='dated_service_patterns')
    ring_chapter['lineGroups']=[g for g in ring_chapter['lineGroups'] if g['historicalLineId']!=LINES['2']]+[ring_group]
    ring_chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    ring_chapter['story']['purpose']='1987年12月28日按规划成环；复用早期南段，检查实际闭环轨道，不以18个站点的排列代替连接。'
    for node,identity in [(ring_chapter,'bj2-ring-open-1987'),(cutoff,'bj2-cutoff-open-ring')]:
        transition=dict(id=identity,historicalLineId=LINES['2'],stationIds=ring_ids,includeClosingSegment=True,status='open',source=RING2,
            description='确认18站完整闭环开放，包含复用一期的南段和真实闭环区间；不是新建十八座站。')
        node['serviceTransitions']=[t for t in node.get('serviceTransitions',[]) if t.get('id')!=identity]+[transition]
    for g in cutoff['lineGroups']:
        if g['historicalLineId']==LINES['2']:
            g.update(stationIds=ring_ids,stationNames=dict(zip(ring_ids,ring_names)),loop=True,replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=40,stationOrderSource=RING2)
    ring_route=next(r for r in geography['lines'] if r['id']=='beijing-r2')
    ring_route.update(stationIds=ring_ids,loop=True,stationOrderSource=RING2)
    for i,d in enumerate(ring_route.get('directions',[])):
        d['stationIds']=ring_ids.copy() if i==0 else ring_ids[::-1];d['stationIds'].append(d['stationIds'][0])
    for line,names in desired.items():
        template=templates[line];old_duplicate,correct=duplicate[line]
        lookup={NAME_ALIASES.get(refs[s]['name'],refs[s]['name']):s for s in template['stationIds'] if s!=old_duplicate}
        ids=[lookup[n] for n in names]
        if correct not in ids or len(set(ids))!=len(names):raise ValueError('Reviewed unique body disappeared')
        route=next(r for r in geography['lines'] if r['id']==template['mapRouteId'])
        if route['stationIds']!=ids:
            route.setdefault('previousRouteMembership',[]).append(dict(stationIds=route['stationIds'].copy(),source='previous_bundled_map',
                supersededReason='同线重复站区或预留站误作开放停站；保留原始地理对象和旧存档实体。'))
        route.update(stationIds=ids,stationOrderSource=LINE14 if line==LINES['14'] else by_number[line.split('-')[-1]]['source'],stationOrderCheckedAt='2026-10-26')
        for i,direction in enumerate(route.get('directions',[])):direction['stationIds']=ids.copy() if i==0 else ids[::-1]
        for chapter in city['chapters']:
            for g in chapter.get('lineGroups',[]):
                if g.get('historicalLineId')!=line:continue
                actual_ids=ids.copy();actual_names=names.copy()
                if line==LINES['6'] and chapter['date']<'2026-06-30':
                    actual_ids=[s for s in ids if refs[s]['name']!='通运门'];actual_names=[n for n in names if n!='通运门']
                g.update(stationIds=actual_ids,stationNames=dict(zip(actual_ids,actual_names)),
                         stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in actual_ids},
                         sourceStationIds=ids.copy(),replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=39,
                         stationOrderSource=route['stationOrderSource'],precisionNote='已核对开放停站与独立站体；不把重复地理锚点、红庙预留位置当作额外开放车站。')
                chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        # Both identities belong to one logical interchange, while their
        # physical instances stay different and keep their own coordinates.
        city.setdefault('stationComplexAliases',{})[correct]=old_duplicate
        city.setdefault('stationComplexAliasSources',{})[correct]=dict(source=evidence['source'],sourceCheckedAt='2026-10-26',
            note='同名站区的线路物理锚点；只统一换乘身份，不挪动或合并站体。')
    # Add the real 2026 infill, rather than opening it with the 2025 snapshot.
    line=LINES['6'];full=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==line)
    name_to_id={n:s for s,n in full['stationNames'].items()};names=['通州北关','通运门','北运河西'];ids=[name_to_id[n] for n in names]
    added=deepcopy(full);key='opening:beijing-line6-tongyunmen-2026'
    added.update(taskId=key,coverageGroupId=key,stationIds=ids,stationNames=dict(zip(ids,names)),
                 stationInstances={s:full['stationInstances'][s] for s in ids},replaceExistingService=False,
                 stationOrderSource=TONGYUN,name='6号线通运门开放',constructionScope='new_contiguous_range')
    cid='beijing-line6-tongyunmen-2026';event=dict(id=cid+':opening',date='2026-06-30',title='通运门站开放',source=TONGYUN,
        sourcePublicationDate='2026-06-30',routeIds=['beijing-r6'],targetLineGroups=[added],chapterId=cid,status='opened_or_completed')
    chapter=next((c for c in city['chapters'] if c['id']==cid),None)
    if chapter is None:chapter=make_event_chapter('beijing',event['date'],[event],[]);city['chapters'].append(chapter)
    chapter.update(id=cid,title='通运门开放：补齐副中心停站',lineGroups=[added],requiredTransfers=[],historicalEventIds=[event['id']],
        source=TONGYUN,sourcePublicationDate='2026-06-30',sourceCheckedAt='2026-10-26',scopeRevision=REVISION,requiresScopeRecheck=True,eventOnly=False)
    chapter['story'].update(opening='2026年6月30日，通运门站正式投入运营。',
        purpose='复用通州北关、北运河西，在两站之间加入通运门；先前通过不停车的区间不等于车站已经开放。',
        outcome='通运门成为6号线开放停站，既有线路与其他车站保留。')
    row=baseline['cities']['beijing'];previous=next((e for e in row['documentedMilestones'] if e['id']==event['id']),None)
    if previous:previous.update(event)
    else:row['documentedMilestones'].append(event)
    for milestone in row['documentedMilestones']:
        original=next((c for c in city['chapters'] if c['id']==milestone.get('chapterId')),None)
        if milestone.get('chapterId')==ring_chapter['id'] and 'beijing-r2' in milestone.get('routeIds',[]):
            milestone['targetLineGroups']=[g for g in milestone.get('targetLineGroups',[]) if g.get('historicalLineId')!=LINES['2']]+[deepcopy(ring_group)]
            milestone.update(source=RING2,sourcePublicationDate='1988-01-23')
        if original:
            for g in milestone.get('targetLineGroups',[]):
                actual=next((x for x in original['lineGroups'] if x.get('taskId')==g.get('taskId') and x.get('historicalLineId') in desired),None)
                if actual:g.update(deepcopy(actual))
    # Independent full stop orders are captured above, not inferred from the
    # repaired chapter. Existing separately dated Line 1/4/17/... answers stay.
    network=target['cutoffNetwork'];known={g.get('historicalLineId',g['id']) for g in network['groups']}
    for label,number in [(l['line'],l['line'].removesuffix('号线').removesuffix('线')) for l in orders['lines']]:
        if number not in LINES or LINES[number] in known:continue
        names=next(l['directions'][0]['stationNames'] for l in orders['lines'] if l['line']==label)
        if number=='14':names=LINE14_NAMES
        if number=='房山':names='东管头南 首经贸 花乡东桥 白盆窑'.split()+names
        if number=='首都机场':names=[{'T3航站楼':'首都机场3号航站楼','T2航站楼':'首都机场2号航站楼'}.get(n,n) for n in names]
        answer=dict(id=LINES[number],historicalLineId=LINES[number],scopeType='stations',stationNames=names,allowReverse=True,fullServiceOrder=True,
                    source=LINE14 if number=='14' else next(l['source'] for l in orders['lines'] if l['line']==label))
        if number=='2':answer['loop']=True
        if number=='14':answer['forbiddenStationNames']=['红庙','陶然桥','高家园','南八里庄']
        if number=='房山':answer['additionalSources']=[evidence['orderCorrections'][0]['source']]
        network['groups'].append(answer)
    # The game already disambiguates the two Muxidi physical bodies in their
    # labels. Preserve those labels; this is not a claimed historical rename.
    muxidi=next(g for g in network['groups'] if g['historicalLineId']==LINES['16'])
    muxidi['stationNames']=['木樨地（16号线）' if n=='木樨地' else n for n in muxidi['stationNames']]
    muxidi['stationNamesNote']='括号仅区分游戏中1／16号线独立物理站体；官方名称仍为木樨地。'
    ring_milestone=next((m for m in target['historicalMilestones'] if m['chapterId']==ring_chapter['id']),None)
    if ring_milestone is None:
        ring_milestone=dict(chapterId=ring_chapter['id'],date='1987-12-28',source=RING2,sourcePublicationDate='1988-01-23',groups=[])
        target['historicalMilestones'].append(ring_milestone)
    ring_milestone.update(source=RING2,sourcePublicationDate='1988-01-23')
    ring_expected=dict(id='beijing-ring2-1987',historicalLineId=LINES['2'],scopeType='stations',stationNames=ring_names,allowReverse=True,loop=True,fullServiceOrder=True)
    ring_milestone['groups']=[g for g in ring_milestone['groups'] if g.get('historicalLineId',g['id'])!=LINES['2']]+[ring_expected]
    # 2021 and 2025 are still only their explicitly represented scopes, not
    # certification of the missing earlier history, which remains a gate.
    for node_id,line,names in [('beijing-network-milestone-2021-12-31',LINES['8'],desired[LINES['8']]),
                              ('beijing-network-milestone-2021-12-31',LINES['14'],LINE14_NAMES),
                              ('beijing-network-milestone-2025-12-27',LINES['6'],[n for n in desired[LINES['6']] if n!='通运门']),
                              (cid,LINES['6'],desired[LINES['6']])]:
        milestone=next((m for m in target['historicalMilestones'] if m['chapterId']==node_id),None)
        if milestone is None:
            original=next(c for c in city['chapters'] if c['id']==node_id)
            milestone=dict(chapterId=node_id,date=original['date'],source=TONGYUN,sourcePublicationDate='2026-06-30',groups=[]);target['historicalMilestones'].append(milestone)
        original=next(c for c in city['chapters'] if c['id']==node_id)
        actual=next(g for g in original['lineGroups'] if g['historicalLineId']==line)
        expected=dict(id=actual.get('coverageGroupId',actual['historicalLineId']),historicalLineId=line,scopeType='stations',stationNames=names,fullServiceOrder=True,allowReverse=True)
        if node_id==cid:expected['constructionStationNames']=['通州北关','通运门','北运河西']
        milestone['groups']=[g for g in milestone.get('groups',[]) if g.get('historicalLineId',g['id'])!=line]+[expected]
    temporal=dict(source=TONGYUN,effectiveDate='2026-06-30',scope='通运门补站；不能由6月25日图或2025全线任务推断提前开放。')
    if temporal not in network.setdefault('temporalEvidence',[]):network['temporalEvidence'].append(temporal)
    aliases=city.setdefault('stationComplexAliases',{})
    def canonical(sid):
        seen=set()
        while sid in aliases:
            if sid in seen:raise ValueError('complex alias cycle')
            seen.add(sid);sid=aliases[sid]
        return sid
    def body(line,name):
        result=set()
        for g in cutoff['lineGroups']:
            if g['historicalLineId']!=line:continue
            for sid in g['stationIds']:
                n=g.get('stationNames',{}).get(sid,refs[sid]['name'])
                if NAME_ALIASES.get(n,n)==name:result.add((sid,city.get('stationInstanceAliases',{}).get(line+'|'+sid,g.get('stationInstances',{}).get(sid,sid))))
        if len(result)!=1:raise ValueError(f'{line}/{name}: ambiguous physical body {result}')
        return next(iter(result))
    known=[t for node in city['chapters'] for t in node.get('requiredTransfers',[]) if t.get('status','active')=='active'];pairs=[];new_count=0;rebindings=[]
    for station in evidence['stations']:
        for na,nb in itertools.combinations(station['lineNumbers'],2):
            a,b=sorted([LINES[na],LINES[nb]]);name=station['stationName'];sa,ia=body(a,name);sb,ib=body(b,name)
            if ia==ib:raise ValueError('A transfer requires two physical bodies')
            if canonical(sa)!=canonical(sb):
                old=canonical(sb);aliases[old]=canonical(sa)
                city.setdefault('stationComplexAliasSources',{})[old]=dict(source=station['source'],sourceCheckedAt='2026-10-26',note='已核对站区身份；实体位置和轨道不合并。')
            previous=next((t for t in known if set(t.get('lineIds',[]))=={a,b} and canonical(t.get('complexId',''))==canonical(sa)),None)
            if previous:
                pair=deepcopy(previous)
                wanted=[ia if line==a else ib for line in pair['lineIds']]
                if pair['stationInstanceIds']!=wanted:
                    rebindings.append((deepcopy(previous),wanted))
                    pair['stationInstanceIds']=wanted
            else:
                new_count+=1;pair=dict(id='bj-cutoff-xfer-'+canonical(sa)+'-'+a+'-'+b,name=name,complexId=canonical(sa),lineIds=[a,b],stationInstanceIds=[ia,ib],precision='schematic',source=station['source'])
            pair.update(transferKind=station['transferKind'],cutoffEvidence='res://data/official_evidence/beijing_interchanges_reviewed2026-10-26.json')
            pairs.append(pair)
    # Rebind the exact old pair at its construction owner and cutoff. An
    # unknown/custom contact fails rather than being silently overwritten.
    for old,wanted in rebindings:
        for node in city['chapters']:
            if node is not cutoff and not any(t['id']==old['id'] for t in node.get('requiredTransfers',[])):continue
            for line in old['lineIds']:
                g=next((g for g in node['lineGroups'] if g['historicalLineId']==line),None)
                if g is None:continue
                correction=dict(taskId=g['taskId'],transferId=old['id'],oldLineIds=old['lineIds'],oldStationInstanceIds=old['stationInstanceIds'],
                    newStationInstanceIds=wanted,source=evidence['source'],description=old['name']+'：更正至所属线路的实际独立站体，保留旧物件、另一侧站体与轨道。')
                corrections=node.setdefault('scopeCorrections',[])
                corrections[:]=[c for c in corrections if not(c.get('taskId')==g['taskId'] and c.get('transferId')==old['id'])]+[correction]
            for t in node.get('requiredTransfers',[]):
                if t['id']==old['id']:t['stationInstanceIds']=wanted.copy()
            node.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    for node in city['chapters']:
        for t in node.get('requiredTransfers',[]):
            updated=next((p for p in pairs if p['id']==t['id']),None)
            if updated:t['transferKind']=updated['transferKind']
    cutoff.update(requiredTransfers=pairs,scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['story']['purpose']='核对25项地铁服务的实际停站和122组线路联系；木樨地、大钟寺为出闸换乘，不能误称站内通道已开放。'
    network.update(transfers=[p['id'] for p in pairs],transferEvidence='res://data/official_evidence/beijing_interchanges_reviewed2026-10-26.json')
    generated=build(cities,data)['cities']['beijing']
    for key in ['routes','mapRouteEntryCount','mapRouteStopOccurrenceCount','mapUniqueStationCount']:row[key]=generated[key]
    city['chapters'].sort(key=lambda c:c['date']);row['documentedMilestoneCount']=len(row['documentedMilestones']);refresh_schedule('beijing',row,city,'2026-10-01')
    for doc in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='北京更正6／8／14重复站序、14号线预留站及换乘站体，通运门按2026补站；补齐122组明确联系。各时期全量核验继续。'
    for path,doc in [('data/campaigns.json',data),('data/cities.json',cities),('data/network_baselines_2026-10-01.json',baseline),('data/official_targets_2026-10-01.json',official)]:write(path,doc)
    print('BEIJING: 122 transfer actions; new identities',new_count,'guarded pair rebindings',len(rebindings),'cutoff orders',len(network['groups']))


if __name__=='__main__':main()
