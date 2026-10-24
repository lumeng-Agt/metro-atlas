"""Replace modern snapshots with dated 2020--2025 opening ranges.

This deliberately leaves the 17/19 split for a separate, sourced ownership
transaction. Reviewing the other lines must not certify that unresolved split.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write, normalize

REVISION='2026.10.24.13'
BOND='https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf'
OPEN2020='https://www.chinametro.net/index.php?aid=51326&id=539&m=newscon'
SOURCES={
    'first18':('https://www.thepaper.cn/newsDetail_forward_9355981','2020-09-26'),
    'five':(OPEN2020,'2020-12-18'),
    'airport':('https://tjxzf.gov.cn/xwzx/bmxx/13248491.html','2021-06-21'),
    'futian':('https://sichuan.scol.com.cn/xwtg/202308/58952079.html','2023-08-11'),
    'tianfu':('https://www.chengdurail.com/info/1151/51732.htm','2023-11-27'),
    'eight27':('https://news.chengdu.cn/2024/1218/2459886.shtml','2024-12-18'),
    'ten17':('https://news.chengdu.cn/2025/0916/68c914750c3a9c5be1c4be5c.shtml','2025-09-16'),
    'thirteen30':('https://www.crecg.com/web/xwzx61/gsyw87/2025121815543222258/index.html','2025-12-18'),
    'qingdao':('https://www.thepaper.cn/newsDetail_forward_26937599','2024-04-06'),
    'lujiao':('https://news.chengdu.cn/2025/0819/68a401a754565111d33e7a7f.shtml','2025-08-19'),
}
# Literal expected orders: opening announcements determine the period; current
# operator orders resolve geography only. Joint stations are included once.
SCOPES=[
    ('chengdu-network-milestone-2020-09-27','2020-09-27','18号线首开：火车南站至三岔','18','first18',[
        '火车南站 孵化园 锦城广场东 世纪城 海昌路 西博城 兴隆 三岔']),
    ('chengdu-network-milestone-2020-12-18','2020-12-18','五线成网：按本期范围建设','6','five',[
        '望丛祠 和平街 郫筒 蜀新大道 檬梓 尚锦路 红高路 天宇路 犀浦 兴业北街 梓潼宫 侯家桥 兴盛 青杠 西华大道 金府 星河 西南交大 沙湾 西北桥 人民北路 梁家巷 前锋路 建设北路 新鸿路 玉双路 牛王庙 顺江路 三官堂 东光 琉璃场 琉三路 金石路 金融城东 中和 张家寺 陆肖 观东 新通大道 新川路 龙灯山 蒲草塘 万安 麓山大道 沈阳路 昌公堰 杭州路 天府商务区 西博城 秦皇寺 松林 钓鱼嘴 回龙 兰家沟']),
    ('chengdu-network-milestone-2020-12-18','2020-12-18','五线成网：按本期范围建设','8','five',[
        '十里店 理工大学 东郊记忆 杉板桥 万年路 双桥路 东大路 净居寺 东光 东湖公园 川大望江校区 倪家桥 芳草街 永丰 九兴大道 高朋大道 殷家林 庆安 石羊 三元 顺风 珠江路 川大江安校区 文星 莲花']),
    ('chengdu-network-milestone-2020-12-18','2020-12-18','五线成网：按本期范围建设','9','five',[
        '金融城东 心岛 孵化园 锦城大道 三元 太平寺 华兴 簇桥 武青南路 机投桥 培风 成都西站 黄田坝']),
    ('chengdu-opening-line18-airportnorth-2020','2020-12-18','18号线非首开段：抵达机场北','18','five',[
        '三岔 天府机场北']),
    ('chengdu-opening-line18-terminal-2021','2021-06-27','天府机场启航：航站楼站开放','18','airport',[
        '三岔 天府机场1号2号航站楼 天府机场北']),
    ('chengdu-opening-line18-futian-2023','2023-08-13','18号线福田站开放','18','futian',[
        '三岔 福田 天府机场1号2号航站楼']),
    ('chengdu-opening-line18-tianfu-2023','2023-11-28','天府站开放：接入铁路枢纽','18','tianfu',[
        '兴隆 天府站 三岔']),
    ('chengdu-opening-line6-qingdao-2024','2024-04-08','6号线青岛路站开放','6','qingdao',[
        '沈阳路 青岛路 昌公堰']),
    ('chengdu-opening-eight27-2024','2024-12-19','向两端延伸与北部加密','8','eight27',[
        '桂龙路 桂林 同乐 龙潭寺 龙潭立交 圣灯公园 十里店', '莲花 龙港']),
    ('chengdu-opening-eight27-2024','2024-12-19','向两端延伸与北部加密','27','eight27',[
        '石佛 慈义 兴城大道 旃檀寺 石门坎 三圣寺 范家巷 鲤鱼湾 赖家店 韦家碾 双水碾 王贾桥 洞子口 沙河源 新桥 金府 花照壁北 金牛公园 羊犀立交 黄忠 金沙滨河公园 蜀鑫路']),
    ('chengdu-opening-line10-phase3-first-2025','2025-09-17','10号线三期先开武侯祠至太平园','10','ten17',[
        '武侯祠 高升桥 红牌楼 太平园']),
    ('chengdu-opening-line6-lujiao-2025','2025-08-22','6号线芦角站开放','6','lujiao',[
        '松林 芦角 钓鱼嘴']),
    ('chengdu-network-milestone-2025-12-16','2025-12-16','东西与机场走廊：13、30号线首开','13','thirteen30',[
        '瓦窑滩 万家湾 培风 万寿桥 东坡路 光华村 杜甫草堂 青羊宫 小南街 文翁石室 华西坝 新南门 九眼桥站 三官堂 净居寺 四川师大 娇子立交 幸福梅林 三圣花乡 龙华寺 龙安']),
    ('chengdu-network-milestone-2025-12-16','2025-12-16','东西与机场走廊：13、30号线首开','30','thirteen30',[
        '双流机场2航站楼东 寺圣 星月 光明 谢家渡 珠江路 大同 石羊东 新园大道 市一医院 益州大道 金融城北 府城桥 金石路 棬子树 锦逸 娇子立交 海桐街 航天立交 惠王陵 玉石 龙泉驿火车站南']),
]


def main():
    campaigns=read('data/campaigns.json'); official=read('data/official_targets_2026-10-01.json')
    cd=campaigns['cities']['chengdu']; chapters={c['id']:c for c in cd['chapters']}
    cutoff=next(c for c in cd['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    catalog={s['id']:s for s in next(c for c in read('data/cities.json')['cities'] if c['id']=='chengdu')['stations']}
    sample=deepcopy(chapters['chengdu-network-milestone-2014-10-26'])
    edited={}; expected_by_chapter={}
    # Preserve the documented transfer specifications before moving any task.
    transfers={t['id']:deepcopy(t) for c in cd['chapters'] for t in c.get('requiredTransfers',[])}
    for chapter_id,date,title,number,source_key,paths in SCOPES:
        template=next(g for g in cutoff['lineGroups'] if g['historicalLineId'].startswith(f'chengdu-line{number}-'))
        line_id=template['historicalLineId']
        ids_by_name={normalize(catalog[s]['name']):s for s in template['stationIds']}
        source,publication=SOURCES[source_key]
        if chapter_id not in edited:
            c=deepcopy(chapters.get(chapter_id,sample)); is_new=chapter_id not in chapters
            c.update(id=chapter_id,date=date,title=title,lineGroups=[],requireOpen=True,status='operated',
                     source=source,sourcePublicationDate=publication,sourceCheckedAt='2026-10-24',
                     sourceTitle='本期开通公告与运营方逐站资料交叉核对',chapterScope='dated_opening_ranges',
                     requiresScopeRecheck=True,scopeRevision=REVISION,eventOnly=False)
            if is_new:c['historicalEventIds']=[chapter_id+':opening']
            # The 17/19 ownership change has not yet been independently fixed.
            # Retain the task, but do not include it in the reviewed answers.
            if chapter_id=='chengdu-network-milestone-2020-12-18':
                c['lineGroups']=[deepcopy(g) for g in chapters[chapter_id]['lineGroups'] if g['historicalLineId']=='chengdu-line17-12']
                c['unreviewedHistoricalScopes']=['chengdu-line17-12:17/19拆分与早期范围尚待单独事务核对']
            c['requiredTransfers']=[]
            c['eventText']=f'{date}，{title}。只确认当时实际开放范围，后期开站另列事件；现代地理底图不作为当时城市面貌。'
            c['story']['opening']=c['eventText']; c['story']['purpose']='接续所属线路既有站体，复现本期增加或开放的站段。'
            c['story']['outcome']='本期连接已经记录，后续开放与延伸按下一个历史事件处理。'
            edited[chapter_id]=c
            expected_by_chapter[chapter_id]={'chapterId':chapter_id,'date':date,'source':source,
                'sourcePublicationDate':publication,'additionalSources':[{'url':BOND,'title':'运营方历史工程范围表'},
                    {'url':'https://www.chengdurail.com/op/station-time','title':'运营方逐站时刻表，站序转录保存在独立证据文件；开通分期另按有日期公告核对'}], 'groups':[]}
        c=edited[chapter_id]
        for index,path in enumerate(paths):
            names=path.split(); ids=[ids_by_name[normalize(n)] for n in names]
            group=deepcopy(template)
            group.update(stationIds=ids,stationNames=dict(zip(ids,names)),
                stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
                taskId=f'opening:{chapter_id}:line{number}:{index+1}',
                coverageGroupId=f'{line_id}:{chapter_id}:{index+1}',
                replaceExistingService=False,loop=False,stationOrderSource=source,servicePathRevision=4,
                name=f'{number}号线 · '+title,
                precisionNote='本期范围按开通资料分期，站序交叉核对；未开放站不提前加入。现代坐标和隧道均为地理参考。')
            c['lineGroups'].append(group)
            expected_by_chapter[chapter_id]['groups'].append({'id':group['coverageGroupId'],'historicalLineId':line_id,
                'scopeType':'stations','stationNames':names,'allowReverse':True})
    chapters.update(edited)
    for c in edited.values():c['routeTargetCount']=len(c['lineGroups'])
    ordered=sorted(chapters.values(),key=lambda c:c['date'])
    aliases=cd.get('stationComplexAliases',{}); canonical=lambda s:aliases.get(s,s)
    bodies={}
    for g in cutoff['lineGroups']:
        for s in g['stationIds']:
            bodies[(g['historicalLineId'],canonical(s))]=cd.get('stationInstanceAliases',{}).get(
                f'{g["historicalLineId"]}|{s}',g.get('stationInstances',{}).get(s,s))
    first={}
    for c in ordered:
        for g in c.get('lineGroups',[]):
            for s in g['stationIds']:first.setdefault((g['historicalLineId'],canonical(s)),c)
        c['requiredTransfers']=[]
    for transfer in transfers.values():
        keys=[(line,canonical(transfer['complexId'])) for line in transfer['lineIds']]
        if not all(key in first and key in bodies for key in keys):raise ValueError(f'Unresolved transfer {transfer["id"]}: {keys}')
        destination=max((first[key] for key in keys),key=lambda c:c['date'])
        transfer['stationInstanceIds']=[bodies[key] for key in keys]
        destination['requiredTransfers'].append(transfer)
    cd['chapters']=ordered
    target=official['cities']['chengdu']
    target['historicalMilestones']=[m for m in target.get('historicalMilestones',[]) if m['chapterId'] not in edited]+list(expected_by_chapter.values())
    target['historyReviewStatus']='pending'
    campaigns['contentRevision']=REVISION
    campaigns['contentRevisionNote']='分开成都18号线首开、机场北、航站楼、福田、天府开站；纠正8/27及10三期日期，移除6/9重复站与30号线未开放站。17/19重组另行核查，不将其标为已通过。'
    write('data/campaigns.json',campaigns);write('data/official_targets_2026-10-01.json',official)
    print(f'{len(SCOPES)} dated line scopes across {len(edited)} chapters; 17/19 explicitly unresolved')


if __name__=='__main__':main()
