"""Author the independently dated Line 6 openings, without moving old saves.

The literal stop orders are reviewed separately from modern geographic IDs.
Later infill replaces the earlier non-stop section through formal construction.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from expand_historical_event_chapters import make_event_chapter,refresh_schedule

REVISION='2026.10.25.25'
LINE='guangzhou-line6-6'
FIRST_SOURCE='https://gd.people.com.cn/GB/123947/357429/index.html'
YIDE_SOURCE='https://news.sina.com.cn/o/2015-01-28/125931453474.shtml?from=wap'
PHASE_SOURCE='https://gd.sina.com.cn/news/bm/2016-12-27/detail-ifxyxury8790145.shtml?from=gd_ydph'
OPERATOR_REVIEW='https://td.gd.gov.cn/attachment/0/549/549734/4425054.pdf'
GARDEN_SOURCE='https://www.cnr.cn/gd/gdkx/20170622/t20170622_523813655.shtml'
SHAHE_SOURCE='https://ep.ycwb.com/epaper/ycwb/html/2024-12/26/content_3_683272.htm'
WEST='浔峰岗 横沙 沙贝 河沙 坦尾 如意坊 黄沙 文化公园 一德路 海珠广场 北京路 团一大广场 东湖 东山口 区庄 黄花岗 沙河顶 沙河 天平架 燕塘 天河客运站 长湴'.split()
EAST='植物园 龙洞 柯木塱 高塘石 黄陂 金峰 暹岗 苏元 萝岗 香雪'.split()
FIRST=[n for n in WEST if n not in ('一德路','沙河')]
YIDE=[n for n in WEST if n!='沙河']
SECOND=YIDE+[n for n in EAST if n not in ('植物园','柯木塱')]
GARDENS=YIDE+EAST
FINAL=WEST+EAST


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    city=data['cities']['guangzhou'];row=baseline['cities']['guangzhou'];target=official['cities']['guangzhou']
    refs={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='guangzhou' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==LINE)
    # The final full pattern replaces obsolete non-stop directions left by
    # compatibility backfills; it is not another parallel operating branch.
    template.update(replaceExistingService=True,servicePathRevision=37)
    if tuple(map(int,REVISION.split('.')))>=tuple(map(int,cutoff.get('scopeRevision','0').split('.'))):cutoff['scopeRevision']=REVISION
    cutoff['requiresScopeRecheck']=True
    by_name={refs[s]['name']:s for s in template['stationIds']}
    def group(order,key,title,source):
        ids=[by_name[n] for n in order];result=deepcopy(template)
        result.update(taskId=key,coverageGroupId=key,name=title,stationIds=ids,
                      stationNames=dict(zip(ids,order)),stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
                      stationOrderSource=source,replaceExistingService=False,servicePathRevision=37,
                      precisionNote='站序按本期实际开放范围；未开放站不进入停站，线位为现代地理参考近似走廊。')
        return result
    specs=[
        ('guangzhou-line6-first-2013','2013-12-28','六号线首开：浔峰岗至长湴',FIRST,FIRST,FIRST_SOURCE,'2013-12-25',
         '首期开通20座车站。一德路、沙河暂缓，不能把现代全线提前建成2013年的成果。'),
        ('guangzhou-line6-yide-2015','2015-01-28','一德路开放：补入老城中间站',['文化公园','一德路','海珠广场'],YIDE,YIDE_SOURCE,'2015-01-28',
         '在既有文化公园—海珠广场之间补入一德路，保留线路其余已开放范围。'),
        ('guangzhou-network-milestone-2016-12-28','2016-12-28','六号线东延、七号线首开与广佛线二期',
         ['长湴']+[n for n in EAST if n not in ('植物园','柯木塱')],SECOND,PHASE_SOURCE,'2016-12-27',
         '六号线东延至香雪；植物园、柯木塱暂缓，沙河仍未开放。其他同期线路保留各自任务。'),
        ('guangzhou-line6-gardens-2017','2017-06-28','植物园、柯木塱两站开放',
         ['长湴','植物园','龙洞','柯木塱','高塘石'],GARDENS,GARDEN_SOURCE,'2017-06-22',
         '补入两座延后开放的中间站，复用长湴、龙洞和高塘石。沙河仍留到2024年。'),
        ('guangzhou-line11-ring-opening-2024','2024-12-28','环线开通与六号线沙河开放',
         ['沙河顶','沙河','天平架'],FINAL,SHAHE_SOURCE,'2024-12-26',
         '六号线沙河与十一号线同日开放，分别建设两条线路站体，再明确建立换乘。'),
    ]
    for cid,date,title,construction,service,source,published,text in specs:
        key='route:guangzhou-r6' if cid=='guangzhou-network-milestone-2016-12-28' else 'opening:'+cid+':line6'
        authored=group(construction,key,'六号线本期开放范围',source)
        chapter=next((c for c in city['chapters'] if c['id']==cid),None)
        event_id='guangzhou-opening-guangzhou-r6-2016-12-28' if cid=='guangzhou-network-milestone-2016-12-28' else cid+':line6-opening'
        event=dict(id=event_id,date=date,title=title,routeIds=['guangzhou-r6'],source=source,status='opened_or_completed',
                   targetLineGroups=[deepcopy(authored)],chapterId=cid,scope='本期站序：'+'—'.join(construction))
        if published:event['sourcePublicationDate']=published
        else:event['sourceDateNote']='省交通运输厅公开的运营方线路介绍回顾2013／2016开通；页面发布日期未在附件正文声明。'
        if chapter is None:
            chapter=make_event_chapter('guangzhou',date,[event],[]);city['chapters'].append(chapter)
        chapter['lineGroups']=[g for g in chapter.get('lineGroups',[]) if g.get('historicalLineId')!=LINE]+[authored]
        chapter.update(id=cid,eventOnly=False,scopeRevision=REVISION,requiresScopeRecheck=True)
        if cid!='guangzhou-line11-ring-opening-2024':
            chapter.update(source=source,sourcePublicationDate=published,sourceCheckedAt='2026-10-25',operationType='dated_station_segment')
        if cid!='guangzhou-line11-ring-opening-2024':chapter['title']=title
        chapter.setdefault('story',{}).update(purpose=text)
        chapter.setdefault('historicalEventIds',[])
        if event_id not in chapter['historicalEventIds']:chapter['historicalEventIds'].append(event_id)
        existing=next((e for e in row['documentedMilestones'] if e['id']==event_id),None)
        if existing:existing.update(event)
        else:row['documentedMilestones'].append(event)
        expected=dict(id=key,historicalLineId=LINE,scopeType='stations',stationNames=service,
                      fullServiceOrder=True,constructionStationNames=construction,allowReverse=True)
        milestone=next((m for m in target['historicalMilestones'] if m['chapterId']==cid),None)
        if milestone is None:
            milestone=dict(chapterId=cid,date=date,source=source,sourcePublicationDate=published,groups=[])
            target['historicalMilestones'].append(milestone)
        if cid=='guangzhou-network-milestone-2016-12-28':
            milestone.update(source=source,sourcePublicationDate=published)
            milestone.setdefault('additionalSources',[])
            if OPERATOR_REVIEW not in milestone['additionalSources']:milestone['additionalSources'].append(OPERATOR_REVIEW)
        milestone['groups']=[g for g in milestone.get('groups',[]) if g.get('historicalLineId',g.get('id'))!=LINE]+[expected]
        if not published:
            # Preserve dated evidence for the shared milestone; the attachment
            # is supplementary, not a made-up publication date.
            milestone.setdefault('additionalSources',[])
            if PHASE_SOURCE not in milestone['additionalSources']:milestone['additionalSources'].append(PHASE_SOURCE)
    # Seven first-phase interchange pairs already have physical IDs. Move only
    # these dated relations; do not infer arbitrary historical transfer dates
    # from the modern operator query.
    first=next(c for c in city['chapters'] if c['id']=='guangzhou-line6-first-2013')
    early_names={'东山口','海珠广场','黄沙','天河客运站','燕塘','区庄','坦尾'}
    early={t['id']:deepcopy(t) for c in city['chapters'] for t in c.get('requiredTransfers',[]) if LINE in t.get('lineIds',[]) and t.get('name') in early_names}
    for chapter in city['chapters']:
        if chapter is cutoff:continue
        chapter['requiredTransfers']=[t for t in chapter.get('requiredTransfers',[]) if t['id'] not in early]
    for relation in early.values():
        relation.update(effectiveDate='2013-12-28',openingSource=FIRST_SOURCE,
                        sourceNote='六号线首期开通的既有线路换乘；独立站体与通道关系分开，不共轨。')
    first['requiredTransfers']=list(early.values())
    first_target=next(m for m in target['historicalMilestones'] if m['chapterId']==first['id'])
    first_target['transfers']=list(early)
    for chapter in city['chapters']:
        if chapter['id']=='guangzhou-network-milestone-2018-12-28':
            chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    city['chapters'].sort(key=lambda c:c['date'])
    row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('guangzhou',row,city,'2026-10-01')
    for document in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,document.get('contentRevision','0').split('.'))):document['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='广州六号线恢复2013首开、2015一德路、2016东延、2017补站和2024沙河开放；独立目标按各期完整停站核对。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('GZ6 five dated scopes authored; first phase',len(FIRST),'second',len(SECOND),'2017',len(GARDENS),'final',len(FINAL),'transfer pairs',len(early))


if __name__=='__main__':main()
