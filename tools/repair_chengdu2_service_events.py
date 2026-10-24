"""Reconstruct the published temporary closure and actual reopening date."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write,normalize

REVISION='2026.10.24.17'
CLOSE='https://news.chengdu.cn/2025/1215/693f705bdcb7c92ce3d26ad1.shtml?phone=yes'
REOPEN='https://sichuan.scol.com.cn/ggxw/202609/83330005.html'
NAMES='犀浦 天河路 百草路 金周路 金科北路 迎宾大道 茶店子客运站 羊犀立交 一品天下 蜀汉路东 白果林 中医大省医院 通惠门 人民公园 天府广场 春熙路 东门大桥 牛王庙 牛市口 东大路 塔子山公园 成都东客站 成渝立交 惠王陵 洪河 成都行政学院 大面铺 连山坡 界牌 书房 龙平路 龙泉驿'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    cd=data['cities']['chengdu'];target=official['cities']['chengdu']
    cutoff=next(c for c in cd['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='chengdu-line2-2')
    catalog={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='chengdu' for s in c['stations']}
    by_name={normalize(catalog[s]['name']):s for s in template['stationIds']}
    if {normalize(n) for n in NAMES}!=set(by_name):raise ValueError('Line2 geographic inventory differs from independently authored 32-stop order')
    ids=[by_name[normalize(n)] for n in NAMES];boundary=NAMES.index('成都行政学院')
    scopes=[];milestones=[]
    sample=next(c for c in cd['chapters'] if c['id']=='chengdu-opening-line18-tianfu-2023')
    for state,date,source,pub in [('suspended','2025-12-20',CLOSE,'2025-12-15'),('open','2026-09-28',REOPEN,'2026-09-24')]:
        chapter=deepcopy(sample);cid='chengdu-line2-east-'+state
        title='2号线东段：为铁路建设暂停开放' if state=='suspended' else '2号线东段：六座车站恢复开放'
        group=deepcopy(template);group.update(stationIds=ids.copy(),stationNames=dict(zip(ids,NAMES)),
            taskId=cid+':range',coverageGroupId=cid,replaceExistingService=False,stationOrderSource=source)
        text=('因成渝中线高铁及十陵南站建设，大面铺至龙泉驿六站暂停开放。保留已有站轨，线路东端暂至成都行政学院。'
              if state=='suspended' else '2026年9月28日，大面铺至龙泉驿六站恢复开放。复用原站轨；新增铁路枢纽站尚未开放，不提前加入停站范围。')
        transitions=[{'id':'west-operating','historicalLineId':'chengdu-line2-2','stationIds':ids[:boundary+1],
                      'status':'open','source':source},
                     {'id':'east-'+state,'historicalLineId':'chengdu-line2-2','stationIds':ids[boundary:],
                      'status':state,'source':source}]
        chapter.update(id=cid,date=date,title=title,source=source,sourceTitle='运营方／成都发布：2号线东段六站暂停及恢复公告',
            sourcePublicationDate=pub,sourceCheckedAt='2026-10-24',lineGroups=[group],routeTargetCount=1,
            requiredTransfers=[],historicalEventIds=[cid+':service'],eventOnly=False,
            requiresScopeRecheck=True,scopeRevision=REVISION,chapterScope='dated_service_transition',
            serviceTransitions=transitions,requireOpen=False,scopeCorrections=[],eventText=text)
        chapter['story'].update(opening=text,purpose='核对并确认本期开放范围，保留已建路网，不重复建设既有车站。',outcome='服务范围按公告日期记录；列车展示只在已开放区间运行。')
        scopes.append(chapter)
        answer={'chapterId':cid,'date':date,'source':source,'sourcePublicationDate':pub,'groups':[
            {'id':cid,'historicalLineId':'chengdu-line2-2','stationNames':NAMES if state=='open' else NAMES[:boundary+1],
             'scopeType':'stations','matchScope':'contiguous_subsequence','allowReverse':True}]}
        if state=='suspended':answer['closedScopes']=[{'id':cid+':closed-east','historicalLineId':'chengdu-line2-2',
            'stationNames':NAMES[boundary:],'allowReverse':True,'requiredServiceStatus':'suspended'}]
        milestones.append(answer)
    updated={c['id'] for c in scopes}
    cd['chapters']=sorted([c for c in cd['chapters'] if c['id'] not in updated]+scopes,key=lambda c:c['date'])
    target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId'] not in updated]+milestones
    data['contentRevision']=REVISION;data['contentRevisionNote']='成都2号线东段六站2025-12暂停、2026-09恢复按实际范围确认；规划段与暂停段不再参与列车展示。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)
    print('Chengdu2: explicit six-station closure and reopening, no invented railway-station opening')


if __name__=='__main__':main()
