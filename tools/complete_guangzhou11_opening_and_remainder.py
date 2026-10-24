"""Make the ring actually close and separate the two deferred station events."""
import subprocess
import sys
from copy import deepcopy
from repair_chengdu_historical_phases import ROOT,read,write

REVISION='2026.10.24.22'
ORDER='https://www.gz.gov.cn/attachment/7/7792/7792257/10198995.pdf'
FIRST='https://ghzyj.gz.gov.cn/attachment/7/7806/7806901/10233239.pdf'
EAST='https://zfcj.gz.gov.cn/zjdt/zjxw/content/mpost_10472692.html'
EAST_DAY='https://m.thepaper.cn/newsDetail_forward_31700679'
REMAINDER='https://static.sse.com.cn/disclosure/bond/announcement/corporate/c/new/2026-05-29/139196_20260529_08YE.pdf'
EIA='https://gdee.gd.gov.cn/attachment/0/360/360962/2474598.pdf'
NAMES='赤沙 琶洲 员村 天河公园 华景路 华师 龙口西 广州东站 沙河 云台花园 大金钟路 中医药大学 梓元岗 流花 彩虹桥 中山八 如意坊 石围塘 芳村 大冲口 沙涌 鹤洞东 棣园 燕岗 江泰路 五凤 逸景路 上涌 大塘 龙潭'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    gz=data['cities']['guangzhou'];target=official['cities']['guangzhou']
    cutoff=next(c for c in gz['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='guangzhou-line11-11'))
    cities=read('data/cities.json');city=next(c for c in cities['cities'] if c['id']=='guangzhou')
    catalog={s['id']:s for s in city['stations']};by_name={catalog[s]['name']:s for s in template['stationIds']}
    def group(names,task):
        ids=[by_name[n] for n in names];g=deepcopy(template)
        g.update(taskId=task,coverageGroupId=task,stationIds=ids,stationNames=dict(zip(ids,names)),
            stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
            stationOrderSource=ORDER,loop=True,replaceExistingService=True,reconfirmLaterServices=True,
            servicePathRevision=4,precisionNote='依据运营方逐站手册及实际开放公告。环线必须补齐龙潭—赤沙闭合区间；广州火车站尚未开放，不能提前计入停站。')
        return g
    # Existing stable task becomes the later infill, instead of a late whole
    # modern line appearing for the first time in September 2025.
    later=next(c for c in gz['chapters'] if c['id']=='guangzhou-network-milestone-2025-09-29')
    later['lineGroups']=[g for g in later['lineGroups'] if g['historicalLineId']!='guangzhou-line11-11']+[group(NAMES,'route:guangzhou-r11')]
    later.update(title='11号线广州东站开放及13、14号线延伸',scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['lineGroups']=[g for g in cutoff['lineGroups'] if g['historicalLineId']!='guangzhou-line11-11']+[group(NAMES,'route:guangzhou-r11')]
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    cid='guangzhou-line11-ring-opening-2024'
    first=deepcopy(later)
    first.update(id=cid,date='2024-12-28',title='首条市区环线：29站连成一环',
        lineGroups=[group([n for n in NAMES if n!='广州东站'],'opening:gz11-ring-2024')],
        requiredTransfers=[],historicalEventIds=[cid+':opening'],routeTargetCount=1,eventOnly=False,
        source=FIRST,sourcePublicationDate='2025-04-29',sourceTitle='广州市交通发展年度报告：11号线首开29站，两座铁路枢纽站暂缓',
        chapterScope='dated_ring_opening',scopeCorrections=[],serviceTransitions=[])
    first['eventText']='2024年12月28日，11号线环线开放29座车站。广州东站及广州火车站暂缓开放，列车经过其所在区间而不停站。'
    first['story'].update(opening=first['eventText'],purpose='完成闭合环线，沿本期29个目标站区建设；两座暂缓站另行处理。',outcome='环线形成，广州东站于后续节点开放，广州火车站保留为建设篇工程。')
    gz['chapters']=sorted([c for c in gz['chapters'] if c['id']!=cid]+[first],key=lambda c:c['date'])
    # Add the two missing, explicitly named independent-body interchanges at
    # Guangzhou East; proximity of the old map's duplicate points is not enough.
    east_links=[]
    for line,body in [('guangzhou-line1','guangzhou-s177__line1'),('guangzhou-line3-3','guangzhou-s177__line3-3')]:
        east_links.append(dict(id='historic-transfer-gz11-east-'+line,name='广州东站',complexId='guangzhou-s177',
            stationInstanceIds=[body,'guangzhou-s342'],lineIds=[line,'guangzhou-line11-11'],precision='schematic',
            source=EAST_DAY,sourceNote='广州发布转述运营方2025-09-29开放；与既有1、3号线独立站体换乘。'))
    pool={t['id']:deepcopy(t) for c in gz['chapters'] for t in c.get('requiredTransfers',[]) if 'guangzhou-line11-11' in t.get('lineIds',[])}
    pool.update({t['id']:t for t in east_links})
    seen=set();available=set()
    for ch in gz['chapters']:
        ch['requiredTransfers']=[t for t in ch.get('requiredTransfers',[]) if t['id'] not in pool]
        for g in ch.get('lineGroups',[]):
            for s in g['stationIds']:available.add((g['historicalLineId'],g.get('stationInstances',{}).get(s,s)))
        for id_,t in pool.items():
            if id_ not in seen and all(pair in available for pair in zip(t['lineIds'],t['stationInstanceIds'])):
                ch['requiredTransfers'].append(deepcopy(t));seen.add(id_)
    answers=[]
    for ch,names,source,pub in [(first,[n for n in NAMES if n!='广州东站'],FIRST,'2025-04-29'),(later,NAMES,EAST,'2025-10-09')]:
        expected=dict(id='opening:gz11-ring-2024' if ch is first else 'route:guangzhou-r11',historicalLineId='guangzhou-line11-11',
            scopeType='stations',stationNames=names,loop=True,fullServiceOrder=True,allowReverse=True)
        old=next((m for m in target.get('historicalMilestones',[]) if m['chapterId']==ch['id']),{})
        answer=deepcopy(old) if old else dict(chapterId=ch['id'],date=ch['date'],source=source,sourcePublicationDate=pub)
        answer['groups']=[g for g in old.get('groups',[]) if g.get('historicalLineId',g['id'])!='guangzhou-line11-11']+[expected]
        answer.setdefault('additionalSources',[]).extend([ORDER,source])
        if ch is later:answer['transfers']=list(dict.fromkeys(answer.get('transfers',[])+[t['id'] for t in east_links]))
        answers.append(answer)
    ids={a['chapterId'] for a in answers}
    target['historicalMilestones']=[m for m in target.get('historicalMilestones',[]) if m['chapterId'] not in ids]+answers
    target['cutoffNetwork']['groups']=[g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])!='guangzhou-line11-11']+[deepcopy(answers[-1]['groups'][-1])]
    target['cutoffNetwork'].setdefault('temporalEvidence',[]).append(dict(source=EAST,effectiveDate='2025-09-29',scope='11号线广州东站开放，广州火车站不计入开放停站'))
    data['contentRevision']=REVISION
    data['contentRevisionNote']='广州11号线还原2024闭环29站及2025广州东站开放，建设篇补广州火车站；规划增站不改写当前环线停站。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)

    spec=dict(city='guangzhou',projectIds=['gz-line11-railway-station'],
        stations=[dict(id=id_,name=name,existing=True) for id_,name in [('guangzhou-s346','梓元岗'),('guangzhou-s136','广州火车站'),('guangzhou-s347','流花')]],
        lineGroups=[dict(key='infill',mapRouteId='guangzhou-future-line11-railway',coverageGroupId='guangzhou-line11-railway',
            name='11号线广州火车站剩余工程',historicalLineId='guangzhou-line11-11',color='#FAC525',
            stationIds=['guangzhou-s346','guangzhou-s136','guangzhou-s347'],
            stationInstances={'guangzhou-s346':'guangzhou-s346','guangzhou-s136':'guangzhou-s136__line11-11','guangzhou-s347':'guangzhou-s347'},
            constructionVariant=True,toleranceM=350,alignmentPrecision='station_areas_and_approximate_corridor',
            precisionNote='仅建设未开放站体及相邻两段，既有运营环线仍保留梓元岗—流花不停站路径；不虚构未来开通日期。',stationOrderSource=EIA)],
        transfers=[dict(id='future-transfer-gz11-railway-'+str(number),name='广州火车站',complexId='guangzhou-s136',
            stationInstanceIds=['guangzhou-s136__line'+str(number)+'-'+str(number),'guangzhou-s136__line11-11'],
            lineIds=['guangzhou-line'+str(number)+'-'+str(number),'guangzhou-line11-11'],
            sourceNote='环评明确2/5/14与11号线换乘；各线站体独立。14号线须先完成已批准剩余工程，均不提前开放。') for number in [2,5,14]],
        plan=dict(id='gz-line11-railway-build',title='环线补站：广州火车站剩余工程',date='2026-10-01',
            status='under_construction',projectType='under_construction',required=True,source=REMAINDER,sourceType='issuer_disclosure_and_approved_eia',
            sourceTitle='广州地铁2026跟踪评级及11号线环评已批准站序',sourcePublicationDate='2026-05-29',sourceCheckedAt='2026-10-24',
            description='完成11号线广州火车站独立站体及相邻区间，并确认2/5/14线路联系。建成状态与真实开放分开，现状列车不提前停靠。',
            contentRevisionNote='广州11号线首开29站环线、2025广州东增站及广州火车站剩余工程分开；未开放建设不改变既有列车停站。',
            contentRevision=REVISION,scopeRevision=REVISION,requiresScopeRecheck=True))
    path='tools/project_specs/gz-line11-railway.json';write(path,spec)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path),'--check'],check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],check=True)
    official=read('data/official_targets_2026-10-01.json');target=official['cities']['guangzhou']
    answer=dict(id='gz-line11-railway-station',reviewStatus='verified',constructionOnly=True,source=EIA,
        sourcePublicationDate='2014-12-31',additionalSources=[REMAINDER,EAST],
        groups=[dict(id='guangzhou-line11-railway',historicalLineId='guangzhou-line11-11',scopeType='stations',
            stationNames=['梓元岗','广州火车站','流花'],allowReverse=True,requiredServiceStatus='built')],
        existingScopes=[dict(id='guangzhou-line11-operating-bypass',historicalLineId='guangzhou-line11-11',
            stationNames=['梓元岗','流花'],allowReverse=True,requireServiceOpen=True)],
        transfers=[t['id'] for t in spec['transfers']])
    target['projects']=[p for p in target['projects'] if p['id']!=answer['id']]+[answer]
    write('data/official_targets_2026-10-01.json',official)
    print('Guangzhou11: real closed ring, dated East-station infill, construction-only Railway-station task')


if __name__=='__main__':main()
