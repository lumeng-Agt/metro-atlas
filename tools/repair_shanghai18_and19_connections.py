"""Restore 18's early openings and construct its unopened 19 interchange.

An open ring/line may coexist with an unopened infill variant. Do not replace
the operating bypass or invent an opening date for Jiangyang South Road.
"""
from copy import deepcopy
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT,read,write

REVISION='2026.10.24.23'
SOUTH='https://jtw.sh.gov.cn/bmts/20201225/be0cf9f1e8fa4fdf8c81b624df3fda7d.html'
NORTH='https://jtw.sh.gov.cn/xydt/20231218/def064da710d426a946e31760f3042e5.html'
ORDER='https://m.shmetro.com/interface/metromap/metromap.aspx?func=fltime&line=18'
RESERVED='https://jtw.sh.gov.cn/xwfb2/20251222/18dc74805200495eb362499c6c1f98d7.html'
PHASE2='https://www.shanghai.gov.cn/nw4411/20251227/b69b7008d2e647f7a3cab7e160ffe225.html'
HUAJING='https://www.shanghai.gov.cn/gwk/search/content/2d9b25a3bed24964a3739c117926ed58'
PUDONG='https://ghzyj.sh.gov.cn/gzcy/lxxd/20241104/60149eef6724456eb4dbebc1af1e9eec.html'
FIRST='航头 下沙 鹤涛路 沈梅路 繁荣路 周浦 康桥 御桥'.split()
NEXT='御桥 莲溪路 北中路 芳芯路 龙阳路 迎春路 杨高中路 民生路 昌邑路 丹阳路 平凉路 江浦公园 江浦路 抚顺路 国权路 复旦大学 上海财经大学 殷高路 长江南路'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    sh=data['cities']['shanghai'];target=official['cities']['shanghai']
    chapters={c['id']:c for c in sh['chapters']}
    cutoff=next(c for c in sh['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='shanghai-line18-18'))
    catalog={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='shanghai' for s in c['stations']}
    lookup={catalog[s]['name']:s for s in template['stationIds']}
    answers=[]
    for cid,date,names,source,pub,key,replace in [
        ('shanghai-network-milestone-2020-12-26','2020-12-26',FIRST,SOUTH,'2020-12-25','south',True),
        ('shanghai-network-milestone-2021-12-30','2021-12-30',NEXT,NORTH,'2023-12-14','north',False)]:
        ch=chapters[cid];g=deepcopy(template);ids=[lookup[n] for n in names]
        g.update(taskId='opening:sh18-'+key,coverageGroupId='opening:sh18-'+key,stationIds=ids,
            stationNames=dict(zip(ids,names)),stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
            replaceExistingService=replace,reconfirmLaterServices=True,stationOrderSource=source,
            precisionNote='按当期开放边界复现，逐站地理参考由运营方当前站序交叉核对；隧道为近似走廊。',servicePathRevision=5)
        ch['lineGroups']=[old for old in ch['lineGroups'] if old['historicalLineId']!='shanghai-line18-18']+[g]
        ch.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        previous=next((m for m in target.get('historicalMilestones',[]) if m['chapterId']==cid),{})
        answer=deepcopy(previous) if previous else dict(chapterId=cid,date=date,source=source,sourcePublicationDate=pub)
        answer['groups']=[old for old in previous.get('groups',[]) if old.get('historicalLineId',old['id'])!='shanghai-line18-18']+[
            dict(id=g['coverageGroupId'],historicalLineId='shanghai-line18-18',scopeType='stations',stationNames=names,allowReverse=True,fullServiceOrder=replace)]
        answer.setdefault('additionalSources',[]).append(ORDER);answers.append(answer)
    # Rehome existing recorded interchanges to the actual availability of both
    # bodies. This does not generate new interchange facts from proximity.
    pool={t['id']:deepcopy(t) for c in sh['chapters'] for t in c.get('requiredTransfers',[])
          if 'shanghai-line18-18' in t.get('lineIds',[])}
    available=set();seen=set()
    for ch in sorted(sh['chapters'],key=lambda c:c['date']):
        ch['requiredTransfers']=[t for t in ch.get('requiredTransfers',[]) if t['id'] not in pool]
        for g in ch.get('lineGroups',[]):
            for s in g['stationIds']:available.add((g['historicalLineId'],g.get('stationInstances',{}).get(s,s)))
        for id_,t in pool.items():
            if id_ not in seen and all(pair in available for pair in zip(t['lineIds'],t['stationInstanceIds'])):
                ch['requiredTransfers'].append(deepcopy(t));seen.add(id_)
    ids={a['chapterId'] for a in answers}
    target['historicalMilestones']=[m for m in target.get('historicalMilestones',[]) if m['chapterId'] not in ids]+answers
    old_first=chapters['shanghai-network-milestone-2020-12-26']
    first_bodies={template.get('stationInstances',{}).get(lookup[n],lookup[n]) for n in FIRST}
    old_first['scopeCorrections']=[x for x in old_first.get('scopeCorrections',[]) if not str(x.get('id','')).startswith('defer-sh18-')]
    for t in pool.values():
        body=next(b for l,b in zip(t['lineIds'],t['stationInstanceIds']) if l=='shanghai-line18-18')
        if body not in first_bodies:
            old_first['scopeCorrections'].append(dict(id='defer-sh18-'+t['id'],taskId='opening:sh18-south',transferId=t['id'],
                oldStationInstanceIds=t['stationInstanceIds'],oldLineIds=t['lineIds'],source=SOUTH,
                description='不在2020首开范围，保留实体建设，在后续实际开通节点重新确认。'))
    aliases=sh.setdefault('stationComplexAliases',{})
    aliases['shanghai-f19-huajinglu']='shanghai-f23-huajing'
    aliases['shanghai-s394']='shanghai-s301'
    aliases['shanghai-reserved18-jiangyangnanlu']='shanghai-f19-jiangyangnanlu'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)

    spec=dict(city='shanghai',projectIds=['sh-line18-jiangyang-reserved'],
        stations=[dict(id='shanghai-s382',name='长江西路',existing=True),
            dict(id='shanghai-reserved18-jiangyangnanlu',name='江杨南路',latlng=[31.352043,121.461732],
                 coordinateSource='local_osm_station_node',coordinateAccuracyM=80,
                 coordinateNote='取本地OSM18号线停靠点12543176082/12543176083中心。与19号线物理站体分别建造，既有位置不移动；公开公告证明已建暂缓开放，不把地理节点当开通证据。'),
            dict(id='shanghai-s383',name='爱辉路',existing=True)],
        lineGroups=[dict(key='infill',mapRouteId='shanghai-future-line18-reserved',coverageGroupId='shanghai-line18-reserved',
            name='18号线江杨南路已建未开放站',historicalLineId='shanghai-line18-18',color='#D6A461',
            stationIds=['shanghai-s382','shanghai-reserved18-jiangyangnanlu','shanghai-s383'],
            stationInstances={'shanghai-s382':'shanghai-s382','shanghai-reserved18-jiangyangnanlu':'shanghai-reserved18-jiangyangnanlu__line18-18','shanghai-s383':'shanghai-s383'},
            constructionVariant=True,toleranceM=250,alignmentPrecision='station_areas_and_approximate_corridor',
            precisionNote='官方已建暂缓站。完成实体站轨，不改变现有长江西路—爱辉路不停站服务；不开通、不虚构日期。',stationOrderSource=RESERVED)],
        transfers=[],plan=dict(id='sh-line18-jiangyang-reserved-build',title='18号线江杨南路：复现已建预留站',date='2026-10-01',
            status='built_unopened',projectType='approved_project',sourceType='municipal_opening_status_notice',required=True,
            source=RESERVED,sourceTitle='上海交通：江杨南路站已建且通过安全评估，因周边配套暂不开放',
            sourcePublicationDate='2025-12-22',sourceCheckedAt='2026-10-24',
            description='复现18号线已建但暂未开放的江杨南路站。当前列车仍不停站；随后19号线建设篇明确建立两线换乘。',
            contentRevision=REVISION,scopeRevision=REVISION,requiresScopeRecheck=True))
    path='tools/project_specs/sh-line18-jiangyang-reserved.json';write(path,spec)
    baseline=read('data/network_baselines_2026-10-01.json');rows=baseline['cities']['shanghai']['projectsAtCutoff']
    if not any(p['id']=='sh-line18-jiangyang-reserved' for p in rows):
        rows.append(dict(id='sh-line18-jiangyang-reserved',name='18号线江杨南路已建暂缓站',projectType='approved_project',
            statusAtCutoff='已建但暂未开放',source=RESERVED,sourceTitle=spec['plan']['sourceTitle'],
            sourceCheckedAt='2026-10-24',playabilityStatus='registered_geometry_and_playable_task_pending'))
    write('data/network_baselines_2026-10-01.json',baseline)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path),'--check'],check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],check=True)
    data=read('data/campaigns.json');sh=data['cities']['shanghai'];plans=sh['futurePlans']
    reserved=next(p for p in plans if p['id']==spec['plan']['id']);plans.remove(reserved)
    plans.insert(next(i for i,p in enumerate(plans) if p['id']=='sh-line19-build'),reserved)
    nineteen=next(p for p in plans if p['id']=='sh-line19-build')
    new_links=[
        dict(id='future-transfer-sh19-huajing-23',name='华泾路',complexId='shanghai-f23-huajing',
             stationInstanceIds=['shanghai-f23-huajing__line23-23','shanghai-f19-huajinglu'],lineIds=['shanghai-line23-23','shanghai-line19-19'],source=HUAJING),
        dict(id='future-transfer-sh19-pudongnan-14',name='浦东南路',complexId='shanghai-s301',
             stationInstanceIds=['shanghai-s394','shanghai-s301__line19-19'],lineIds=['shanghai-line14-14','shanghai-line19-19'],source=PUDONG),
        dict(id='future-transfer-sh19-jiangyang-18',name='江杨南路',complexId='shanghai-f19-jiangyangnanlu',
             stationInstanceIds=['shanghai-reserved18-jiangyangnanlu__line18-18','shanghai-f19-jiangyangnanlu'],lineIds=['shanghai-line18-18','shanghai-line19-19'],source=RESERVED)]
    for t in new_links:t.update(precision='schematic',sourceNote='依据明确公布的两线换乘关系；独立物理站体，通道及层次示意。规划完成不提前开放。')
    added={t['id'] for t in new_links}
    nineteen['requiredTransfers']=[t for t in nineteen['requiredTransfers'] if t['id'] not in added]+new_links
    nineteen.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    data['contentRevisionNote']='上海18号线补2020/2021一期分期，预留江杨南路与19号线联系；补华泾路23/19、浦东南路14/19独立换乘。'
    write('data/campaigns.json',data)
    official=read('data/official_targets_2026-10-01.json');target=official['cities']['shanghai']
    expected=dict(id='sh-line18-jiangyang-reserved',reviewStatus='verified',constructionOnly=True,source=RESERVED,sourcePublicationDate='2025-12-22',
        groups=[dict(id='shanghai-line18-reserved',historicalLineId='shanghai-line18-18',scopeType='stations',stationNames=['长江西路','江杨南路','爱辉路'],requiredServiceStatus='built',allowReverse=True)],
        existingScopes=[dict(id='shanghai-line18-operating-bypass',historicalLineId='shanghai-line18-18',stationNames=['长江西路','爱辉路'],requireServiceOpen=True,allowReverse=True)],transfers=[])
    target['projects']=[p for p in target['projects'] if p['id']!=expected['id']]+[expected]
    if expected['id'] not in target['requiredProjectIds']:target['requiredProjectIds'].append(expected['id'])
    nineteen_expected=next(p for p in target['projects'] if p['id']=='sh-line19')
    nineteen_expected['transfers']=list(dict.fromkeys(nineteen_expected['transfers']+[t['id'] for t in new_links]))
    nineteen_expected['additionalSources']=[HUAJING,PUDONG,RESERVED]
    nineteen_expected['scopeNote']='34站站序已核对，已补华泾路23/19、浦东南路14/19及江杨南路18/19。凉城路19/20在后续20号线任务明确确认；完整18处换乘及背景/远景分类仍需独立核查，不凭13条联系放行。'
    write('data/official_targets_2026-10-01.json',official)
    print('Shanghai18 early openings restored; unopened station variant; three missing19 interchanges are actual tasks')


if __name__=='__main__':main()
