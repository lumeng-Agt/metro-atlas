"""Construct the 14-line side of the planned Hongmiao interchange explicitly.

It was wrongly present in the old current network. Correcting that network
must not leave Line 22's real interchange target without a buildable 14 side.
The construction variant keeps the current 33-stop service unchanged.
"""
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT,read,write

REVISION='2026.10.26.6'
WORKS='https://ggzyfw.beijing.gov.cn/jyxxgcjszbjh/20240412/4485547.html'
NAMES='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202609/t20260924_4879057.html'


def main():
    spec=read('tools/project_specs/bj-line22.json');data=read('data/campaigns.json')
    city=data['cities']['beijing'];cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-line14-14')
    for station in spec['stations']:
        if station['id']=='beijing-s325':station['name']='通州北关'
        if station['id']=='beijing-s322':station['name']='城市副中心'
    for sid,name in [('beijing-s276','金台路'),('beijing-s278','大望路')]:
        if not any(s['id']==sid for s in spec['stations']):spec['stations'].append(dict(id=sid,name=name,existing=True))
    ids=['beijing-s276','beijing-s277','beijing-s278']
    group=dict(key='hongmiao14',mapRouteId='beijing-future-hongmiao14-infill',coverageGroupId='beijing-line14-hongmiao-planned',
        historicalLineId='beijing-line14-14',name='14号线红庙预留站及换乘工程',color='#D8B9B3',stationIds=ids,
        stationInstances={s:template.get('stationInstances',{}).get(s,s) for s in ids},
        constructionVariant=True,toleranceM=100,alignmentPrecision='station_areas_and_approximate_corridor',
        stationOrderSource=WORKS,servicePathRevision=41,
        precisionNote='2024年官方工程范围：14号线红庙及22号线换乘。保留截止日33站开放主线，另行预览未开放的补站方案，不伪造未来开放日期。')
    spec['lineGroups']=[g for g in spec['lineGroups'] if g.get('key')!='hongmiao14']+[group]
    for relation in spec['transfers']:
        if relation['id']=='future-transfer-bj22-hongmiao-14':
            relation['source']=WORKS;relation['sourceNote']='分别建设14、22号线独立站体和本项目接轨，再明确确认规划换乘；不把未来方案计入截止日开放。'
        if relation['complexId']=='beijing-s325':relation['name']='通州北关'
        if relation['complexId']=='beijing-s322':relation['name']='城市副中心'
    spec['plan'].update(contentRevision=REVISION,scopeRevision=REVISION,requiresScopeRecheck=True,
        contentRevisionNote='北京22号线配套14号线红庙补站作为独立未开放建设方案，当前33站主线保留；应用截止日前最终站名。',
        description='首开20站、西段两站及14号线红庙配套工程分别建设。通州北关、城市副中心采用截止日前公布名称；规划成果不表示已开放。')
    spec['plan']['additionalSources']=list(dict.fromkeys(spec['plan'].get('additionalSources',[])+[WORKS,NAMES]))
    write('tools/project_specs/bj-line22.json',spec)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/'tools/project_specs/bj-line22.json')],check=True,cwd=ROOT)
    official=read('data/official_targets_2026-10-01.json');target=next(t for t in official['cities']['beijing']['projects'] if t['id']=='bj-line22')
    for expected in target['groups']:
        if expected['historicalLineId']=='beijing-line22-22':
            expected['stationNames']=[{'运河商务区':'通州北关','北运河东':'城市副中心'}.get(n,n) for n in expected['stationNames']]
    expected=dict(id='beijing-line14-hongmiao-planned',historicalLineId='beijing-line14-14',scopeType='stations',
        stationNames=['金台路','红庙','大望路'],allowReverse=True,requiredStationInstances=group['stationInstances'])
    # requiredStationInstances is keyed by public name, not geographic ID.
    expected['requiredStationInstances']={name:group['stationInstances'][sid] for name,sid in zip(expected['stationNames'],ids)}
    target['groups']=[g for g in target['groups'] if g['id']!=expected['id']]+[expected]
    target['additionalSources']=list(dict.fromkeys(target.get('additionalSources',[])+[WORKS,NAMES]))
    target['scopeNote']='22站全工程及14号线红庙配套补站分别建造。截止日14号线红庙不开放，采用独立建设方案保留既有33站主线；未建远期R4不伪造开放换乘。其他规划联系分期审核仍单独保留。'
    write('data/official_targets_2026-10-01.json',official)
    print('BJ22: explicit 14-side Hongmiao construction variant; final pre-cutoff station labels applied')


if __name__=='__main__':main()
