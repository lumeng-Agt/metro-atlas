"""Correct the reviewed cutoff service, retaining every legacy physical body."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from build_network_baseline import build

REVISION = '2026.10.25.14'
ORDER_SOURCE = 'https://www.bjmoa.cn/metroLineList.html?sline=1'
RESTORE_SOURCE = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202605/t20260516_4653696.html'
FS_SOURCE = 'https://ggzyfw.beijing.gov.cn/jyxxgcjszbjh/20260929/5731562.html'
BATONG_SOURCE = 'https://www.bjmoa.cn/metroLineList.html?sline=17'
# Parentheses are a display disambiguator for the already stable Line 1 body,
# not a different station or a historical renaming of 木樨地.
ORDER = '苹果园 古城 八宝山 玉泉路 五棵松 万寿路 公主坟 军事博物馆 木樨地（1号线） 南礼士路 复兴门 西单 天安门西 天安门东 王府井 东单 建国门 永安里 国贸 大望路 四惠 四惠东 高碑店 传媒大学 双桥 管庄 八里桥 通州北苑 果园 九棵树 梨园 临河里 土桥 花庄 环球度假区'.split()


def main():
    data=read('data/campaigns.json');cities=read('data/cities.json')
    targets=read('data/official_targets_2026-10-01.json');baseline=read('data/network_baselines_2026-10-01.json')
    campaign=data['cities']['beijing'];target=targets['cities']['beijing']
    city=next(c for c in cities['cities'] if c['id']=='beijing')
    catalog={s['id']:s for s in city['stations']}
    route=next(r for r in city['lines'] if r['id']=='beijing-r1')
    lookup={catalog[s]['name']:s for s in route['stationIds']}
    assert set(ORDER).issubset(lookup),set(ORDER)-lookup.keys()
    ids=[lookup[n] for n in ORDER]
    cutoff=next(c for c in campaign['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    group=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-lineearly0')
    old_ids=group['stationIds'].copy()
    group.update(stationIds=ids,stationNames=dict(zip(ids,ORDER)),
        stationInstances={s:group.get('stationInstances',{}).get(s,s) for s in ids},
        replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=31,
        stationOrderSource=ORDER_SOURCE,precisionNote='运营方区间表与2026年5月恢复公告核对：福寿岭未开放，八角游乐园通过不停车；木樨地括号为地图同名站体区分。站轨几何为近似参考。')
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    transition=dict(id='bj1-cutoff-open-scope',historicalLineId='beijing-lineearly0',stationIds=ids,
                    displayStationNames=['苹果园','环球度假区'],status='open',source=RESTORE_SOURCE,
                    description='按截止日复核当前35站开放范围；不是在2026年10月1日新开通整条线路。')
    cutoff['serviceTransitions']=[t for t in cutoff.get('serviceTransitions',[]) if t.get('id')!=transition['id']]+[transition]
    answer=dict(id='beijing-lineearly0',historicalLineId='beijing-lineearly0',scopeType='stations',
        stationNames=ORDER,allowReverse=True,fullServiceOrder=True,
        forbiddenStationNames=['福寿岭','八角游乐园'],source=ORDER_SOURCE,additionalSources=[BATONG_SOURCE,RESTORE_SOURCE,FS_SOURCE],
        stationNamesNote='木樨地（1号线）括号只区分物理站体；对应官方木樨地。',
        lastServiceChangeDate='2026-05-16',lastServiceChangeSource=RESTORE_SOURCE)
    target['cutoffNetwork']['groups']=[g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id'])!='beijing-lineearly0']+[answer]
    temporal=target['cutoffNetwork'].setdefault('temporalEvidence',[])
    for evidence in [dict(source=RESTORE_SOURCE,effectiveDate='2026-05-16',scope='苹果园、古城、八宝山恢复；八角游乐园继续通过不停车。'),
                     dict(source=FS_SOURCE,effectiveDate='2026-09-29',scope='福寿岭增加安全出口改造仍处招标计划阶段，不列入开放停站。')]:
        if evidence not in temporal:temporal.append(evidence)
    physical_ids=ids.copy();physical_ids.insert(2,lookup.get('八角游乐园','beijing-s68'))
    if route['stationIds']!=physical_ids:
        route.setdefault('previousRouteMembership',[]).append(dict(stationIds=route['stationIds'].copy(),source='previous_bundled_map',supersededReason='福寿岭未开放、八角误排末尾；八角保留在实体线路正确位置，当前开放序列单独排除。'))
    route.update(stationIds=physical_ids,nonStoppingStationIds=['beijing-s68'],stationOrderSource=ORDER_SOURCE,stationOrderReviewedAt='2026-10-25')
    for index,direction in enumerate(route['directions']):direction['stationIds']=physical_ids.copy() if index==0 else list(reversed(physical_ids))
    # The generated catch-up task contained a fictitious 苹果园—福寿岭—八角
    # subsection. Retain its stable task ID, but repair the physical connection
    # instead of treating an unopened station as part of a modern service.
    # This is an explicitly labelled legacy-scope repair, not independent
    # certification of the still-unreviewed 2021 chronology.
    for chapter in campaign['chapters']:
        if chapter['id']!='beijing-network-milestone-2021-08-26':continue
        for g in chapter['lineGroups']:
            if g.get('mapRouteId')!='beijing-r1':continue
            g['sourceStationIds']=list(reversed(physical_ids)) if g.get('taskId')=='route:beijing-r1:range-1' else physical_ids.copy()
            if g.get('taskId')=='route:beijing-r1:range-2':
                g.update(stationIds=physical_ids[:4],stationInstances={s:group.get('stationInstances',{}).get(s,s) for s in physical_ids[:4]},
                         name='1号线 · 补齐既有西段连接',scopeBackfill=True,
                         constructionScopeNote='修复旧图漏画八角站体与错误连接，复用苹果园、古城、八宝山；不表示这些车站在2021年新建或全部开放。')
        chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    # A future branch is a separate construction preview. It must not replace
    # the actual open main-line route merely because both share line identity.
    spec=read('tools/project_specs/bj-line1-branch.json')
    spec['lineGroups'][0]['constructionVariant']=True
    spec['plan'].update(contentRevision=REVISION,requiresScopeRecheck=True)
    write('tools/project_specs/bj-line1-branch.json',spec)
    for plan in campaign['futurePlans']:
        if plan['id']!='bj-line1-branch-build':continue
        plan.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        for g in plan['lineGroups']:g['constructionVariant']=True
    generated=build(cities,data)['cities']['beijing']
    for key in ['routes','mapRouteEntryCount','mapRouteStopOccurrenceCount','mapUniqueStationCount']:baseline['cities']['beijing'][key]=generated[key]
    # Geographic source objects and all earlier history scopes remain intact.
    # Earlier construction/closure chronology is reviewed separately.
    for doc in (data,baseline):
        revision_key=lambda value:tuple(int(p) for p in value.split('.'))
        if revision_key(REVISION)>=revision_key(doc.get('contentRevision','0')):doc['contentRevision']=REVISION
    data['contentRevisionNote']='北京1号线截止日按35个开放停站核对，福寿岭不提前开放、八角越站；未来支线不覆盖当前主线。'
    for path,value in [('data/campaigns.json',data),('data/cities.json',cities),('data/network_baselines_2026-10-01.json',baseline),('data/official_targets_2026-10-01.json',targets)]:write(path,value)
    print('Beijing Line1 cutoff: 35 open stops, Fushouling/Bajiao excluded; all legacy bodies retained')


if __name__=='__main__':main()
