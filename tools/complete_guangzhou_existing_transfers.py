"""Add omitted existing-network interchange actions at their dated openings.

Operator pairs supply the independent identities. Dated opening records supply
the event boundary; this does not certify the remaining full historical review.
No player-save geometry is moved or rewritten.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import make_event_chapter,refresh_schedule

REVISION='2026.10.25.24'
ORDER='https://apis.gzmtr.com/app-map/metroweb/linestation'
RING='https://www.gz.gov.cn/attachment/7/7808/7808439/10246836.pdf'
NEW='https://huacheng.gz-cmc.com/pages/2025/06/29/87f0668b98b345f3bf47f4cf3c11062d.html'
LINE=lambda number:f'guangzhou-line{number}-{number}' if number!=1 else 'guangzhou-line1'
ALIASES={18:'guangzhou-line18-15',21:'guangzhou-line21-16','GF':'guangzhou-foshan-route-20'}


def line(number):return ALIASES.get(number,LINE(number))


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['guangzhou'];target=official['cities']['guangzhou'];row=baseline['cities']['guangzhou']
    geography=next(c for c in read('data/cities.json')['cities'] if c['id']=='guangzhou')
    names={s['id']:s['name'] for s in geography['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    def body(line_id,name):
        found=set()
        for group in cutoff['lineGroups']:
            if group['historicalLineId']!=line_id:continue
            for sid in group['stationIds']:
                if group.get('stationNames',{}).get(sid,names.get(sid))!=name:continue
                instance=city.get('stationInstanceAliases',{}).get(line_id+'|'+sid,group.get('stationInstances',{}).get(sid,sid))
                found.add((sid,instance))
        assert len(found)==1,(line_id,name,found)
        return next(iter(found))
    def canonical(sid):
        seen=set();aliases=city.get('stationComplexAliases',{})
        while sid in aliases and sid not in seen:seen.add(sid);sid=aliases[sid]
        return sid
    batches=[
        ('guangzhou-network-milestone-2019-12-20',21,[('黄村',4)],'https://gzw.gz.gov.cn/qy/qydt/content/post_5464442.html'),
        ('guangzhou-network-milestone-2022-09-28',18,[('南村万博',7),('番禺广场',3),('磨碟沙',8)],'https://huacheng.gz-cmc.com/pages/2021/09/28/e19c773c32a14bccb3b5cb0db5a15d8e.html'),
        ('guangzhou-network-milestone-2023-12-28',7,[('大沙东',5)],'https://www.gz.gov.cn/zwgk/fggw/szfgz/content/post_10694346.html'),
        ('guangzhou-line11-ring-opening-2024',11,[('中山八',5),('华师',3),('员村',5),('大塘',3),('如意坊',6),('彩虹桥',8),('江泰路',2),('沙河',6),('沙涌','GF'),('燕岗','GF'),('琶洲',8),('芳村',1),('龙潭',18)],RING),
        ('guangzhou-network-milestone-2025-06-29',10,[('五羊邨',5)],NEW),
        ('guangzhou-network-milestone-2025-06-29',12,[('浔峰岗',6),('白云文化广场',2),('赤沙',11)],NEW),
    ]
    added=[]
    for chapter_id,new_line,stops,opening_source in batches:
        chapter=next(c for c in city['chapters'] if c['id']==chapter_id)
        changed=False
        for name,old_line in stops:
            a,ai=body(line(old_line),name);b,bi=body(line(new_line),name)
            ca=canonical(a);cb=canonical(b)
            if ca!=cb:
                city.setdefault('stationComplexAliases',{})[cb]=ca
                city.setdefault('stationComplexAliasSources',{})[cb]=dict(source=ORDER,sourceCheckedAt='2026-10-25',note='同站换乘身份；保留两线独立站体、坐标、朝向及轨道。')
            key='historic-transfer-gz-reviewed-'+b+'-'+str(old_line)+'-'+str(new_line)
            transfer=dict(id=key,name=name,complexId=ca,lineIds=[line(old_line),line(new_line)],stationInstanceIds=[ai,bi],
                          source=ORDER,openingSource=opening_source,effectiveDate=chapter['date'],precision='schematic',
                          note='站体身份按运营方换乘查询核对；通道结构为示意，不表示共用站厅或共轨。')
            previous=next((t for t in chapter.get('requiredTransfers',[]) if t['id']==key),None)
            if previous:
                if previous!=transfer:previous.update(transfer);changed=True
            else:chapter.setdefault('requiredTransfers',[]).append(transfer);changed=True
            if not any(t['id']==key for t in cutoff.get('requiredTransfers',[])):
                cutoff.setdefault('requiredTransfers',[]).append(deepcopy(transfer))
            added.append(key)
            for milestone in target['historicalMilestones']:
                if milestone['chapterId']==chapter_id and key not in milestone.setdefault('transfers',[]):milestone['transfers'].append(key)
        if changed:chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        # Keep the dated event's task payload in sync, not just its menu.
        for event in row['documentedMilestones']:
            if event.get('chapterId')==chapter_id:event['targetTransfers']=chapter['requiredTransfers']
    # This is a real construction milestone with no new rail: the paid-area
    # pedestrian passage joined the four independent line bodies in 2024.
    # Do not model it as a train edge or a shared station hall.
    passage_id='guangzhou-south-paid-passage-2024'
    event_id=passage_id+'-event'
    event=dict(id=event_id,date='2024-01-21',title='广州南站：跨城换乘通道启用',status='opened_or_completed',
               source=RING,chapterId=passage_id,scope='佛山2号线与广州2、7、22号线实现站内付费区换乘；各线路站体及实体轨道保留独立。')
    passage=next((c for c in city['chapters'] if c['id']==passage_id),None)
    if passage is None:
        passage=make_event_chapter('guangzhou','2024-01-21',[event],[]);city['chapters'].append(passage)
    passage.update(id=passage_id,eventOnly=False,lineGroups=[],operationType='transfer_connection',
                   historicalEventIds=[event_id],requiredTransfers=[],scopeRevision=REVISION,requiresScopeRecheck=True,
                   sourceCheckedAt='2026-10-25',sourceTitle='《2024年广州市交通发展年度报告》·广州南站换乘通道',
                   chapterScope='pedestrian_transfer_opening',geometryStatus='existing_station_bodies_transfer_links',
                   operationGuide='逐一预览并确认下面的换乘联系；无需新建站体或连接列车轨道。',
                   alignmentNote='既有站体位置作地理参考；通道关系为示意，不重建共用站厅或列车轨道。')
    passage['story'].update(opening=event['scope'],purpose='查看广州南站两侧的独立线路站体，确认佛山2号线与广州2、7号线的换乘联系。已有22号线联系保留。',
                            outcome='跨城地铁在本站形成完整换乘关系；通道只连接站体，不连接列车轨道。',
                            eventKind='transfer_opening',
                            steps=[dict(id='intro',action='read_context'),dict(id='transfer',action='establish_transfer'),dict(id='check',action='validate_official_scope'),dict(id='outcome',action='continue_story')])
    for number in [2,7]:
        a,ai=body(line(number),'广州南站');b,bi=body('guangzhou-foshan-line2-18','广州南站')
        key='historic-transfer-gz-south-passage-foshan2-to-line'+str(number)
        transfer=dict(id=key,name='广州南站',complexId='guangzhou-s123',lineIds=[line(number),'guangzhou-foshan-line2-18'],
                      stationInstanceIds=[ai,bi],source=RING,effectiveDate='2024-01-21',precision='schematic',
                      note='2024年1月21日付费区换乘通道启用；各线独立站体，非共轨。')
        passage['requiredTransfers'].append(transfer);added.append(key)
        if not any(t['id']==key for t in cutoff['requiredTransfers']):cutoff['requiredTransfers'].append(deepcopy(transfer))
    existing=next((e for e in row['documentedMilestones'] if e['id']==event_id),None)
    if existing:existing.update(event)
    else:row['documentedMilestones'].append(event)
    target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId']!=passage_id]+[
        dict(chapterId=passage_id,date='2024-01-21',source=RING,bibliographicCitation=dict(kind='official_yearbook',edition='2024年广州市交通发展年度报告',locator='附录第30页：1月21日广州南站换乘通道正式启用'),
             groups=[],transfers=['historic-transfer-gz-south-passage-foshan2-to-line2','historic-transfer-gz-south-passage-foshan2-to-line7'])]
    city['chapters'].sort(key=lambda c:c['date'])
    row['documentedMilestoneCount']=len(row['documentedMilestones'])
    required=target['cutoffNetwork'].setdefault('transfers',[])
    for key in added:
        if key not in required:required.append(key)
    target['cutoffNetwork']['transferReviewStatus']='partial_operator_pairs_dated_actions_added'
    # Replacing the first branch briefly removes service on the second. Keep
    # the real transfer body, then explicitly restore its relation after the
    # corresponding branch task; never leave a live link to an absent service.
    for number in (3,12,14):
        line_id=line(number)
        paths=[g for g in cutoff['lineGroups'] if g.get('historicalLineId')==line_id]
        if len(paths)!=2:continue
        first,second=paths
        first_bodies=set(first.get('stationInstances',{}).get(s,s) for s in first['stationIds'])
        second_bodies=set(second.get('stationInstances',{}).get(s,s) for s in second['stationIds'])
        for transfer in cutoff['requiredTransfers']:
            if transfer['id'] not in added or line_id not in transfer['lineIds']:continue
            body_id=transfer['stationInstanceIds'][transfer['lineIds'].index(line_id)]
            if body_id not in second_bodies-first_bodies:continue
            correction=dict(taskId=first['taskId'],restoreAfterTaskId=second['taskId'],transferId=transfer['id'],
                            oldLineIds=transfer['lineIds'],oldStationInstanceIds=transfer['stationInstanceIds'],
                            description='先核对第一条路径，第二条路径确认后恢复对应独立站体换乘。',source=ORDER)
            if correction not in cutoff.setdefault('scopeCorrections',[]):cutoff['scopeCorrections'].append(correction)
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    refresh_schedule('guangzhou',row,city,'2026-10-01')
    for document in [data,baseline]:
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,document.get('contentRevision','0').split('.'))):document['contentRevision']=REVISION
    data['contentRevisionNote']='广州补24组明确换乘操作及2024年广州南站通道里程碑；独立全量时序核对继续，完整性门槛不放行。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('GZ_EXISTING_TRANSFER_ACTIONS',len(added),'(full city/date review remains incomplete)')


if __name__=='__main__':main()
