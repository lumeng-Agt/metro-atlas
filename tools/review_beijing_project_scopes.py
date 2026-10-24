"""Restore the approved west end of line 22 and review dated project scopes.

Expected orders below are transcribed from the cited public documents, never
derived from campaign groups. Construction completeness and the completeness
of the city's historical inventory remain separate checks.
"""
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT, read, write

REVISION = '2026.10.24.19'
WEST = 'https://www.beijing.gov.cn/ywdt/gqrd/202504/t20250403_4055758.html'
FULL = 'https://www.beijing.gov.cn/ywdt/yaowen/202607/t20260729_4797722.html'
FIRST = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202609/t20260924_4879057.html'
BUILD = 'https://www.beijing.gov.cn/ywdt/gzdt/202602/t20260203_4486799.html'
EAST3 = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251219_4350423.html'
INTERCHANGE28 = 'https://www.beijing.gov.cn/ywdt/gzdt/202401/t20240106_3527804.html'


def transfer(id_, name, complex_, bodies, lines, source, note):
    return dict(id=id_, name=name, complexId=complex_, stationInstanceIds=bodies,
                lineIds=lines, source=source, sourceNote=note, precision='schematic')


def main():
    path = 'tools/project_specs/bj-line22.json'
    spec = read(path)
    # Keep the already-published eastern task's stable identity. The two missing
    # stations are a second task, not a replacement that erases old completion.
    first = spec['lineGroups'][0]
    first.setdefault('stationInstances',spec.get('stationInstances',{}).copy())
    first.update(taskId='project:bj-line22-build',coverageGroupId='beijing-line22-first-opening', name='22号线首开建设段（红庙—平谷）',
                 precisionNote='官方20站首开范围，不能代替东大桥—平谷22站全工程。站址及隧道采用近似走廊；建设成果不代表截止日已开放。')
    for id_, name in [('beijing-s333', '东大桥'), ('beijing-s169', '金台夕照')]:
        if not any(s['id'] == id_ for s in spec['stations']):
            spec['stations'].append(dict(id=id_, name=name, existing=True))
    west = dict(key='west', mapRouteId='beijing-future-line22-west',
        coverageGroupId='beijing-line22-west', name='22号线西段（东大桥—红庙）',
        historicalLineId='beijing-line22-22', color='#B35C44',
        stationIds=['beijing-s333', 'beijing-s169', 'beijing-s277'],
        stationInstances={s:s+'__line22-22' for s in ['beijing-s333','beijing-s169','beijing-s277']},
        toleranceM=450, alignmentPrecision='station_areas_and_approximate_corridor',
        precisionNote='官方全工程22站与20站首开范围分开：本任务补两座新站及两个区间；站位复用既有换乘站区，独立建设22号线站体，不共轨。',
        stationOrderSource=WEST)
    spec['lineGroups'] = [first, west]
    additions = [
        transfer('future-transfer-bj22-dongdaqiao-6','东大桥','beijing-s333',
            ['beijing-s333__line6-6','beijing-s333__line22-22'],['beijing-line6-6','beijing-line22-22'],WEST,
            '东大桥6/22独立站体换乘；与17、28号线组成的枢纽关系分开确认。'),
        transfer('future-transfer-bj22-dongdaqiao-17','东大桥','beijing-s333',
            ['beijing-s333__line17-17','beijing-s333__line22-22'],['beijing-line17-17','beijing-line22-22'],INTERCHANGE28,
            '东大桥既有17号线与22号线各用本线站体，通道为示意。'),
        transfer('future-transfer-bj22-jintaixizhao-10','金台夕照','beijing-s169',
            ['beijing-s169','beijing-s169__line22-22'],['beijing-line10-10','beijing-line22-22'],INTERCHANGE28,
            '京广桥工程站区与金台夕照10号线衔接，不将两条线合成同一物理站体。')]
    ids={t['id'] for t in additions}
    spec['transfers']=[t for t in spec['transfers'] if t['id'] not in ids]+additions
    spec['plan'].update(title='22号线全工程：首开段与西段接续', source=FULL,
        sourceTitle='北京市政府：东大桥—平谷全工程22站，红庙—平谷首开20站',
        sourcePublicationDate='2026-07-29', sourceCheckedAt='2026-10-24',
        description='分别建设红庙—平谷20站首开段和东大桥—红庙西段，合计22座独立站体。截止日尚未开放；不把年底开通计划写成已发生事实。',
        contentRevision=REVISION, scopeRevision=REVISION, requiresScopeRecheck=True)
    write(path,spec)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path),'--check'],check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],check=True)

    data=read('data/campaigns.json'); city=data['cities']['beijing']
    # The map stores the two Dawanglu physical bodies separately. Alias only
    # their station-complex identity; no position, orientation or track changes.
    city.setdefault('stationComplexAliases',{})['beijing-s278']='beijing-s47'
    p=next(p for p in city['futurePlans'] if p['id']=='bj-line28-build')
    extra=[
        transfer('future-transfer-bj28-dongdaqiao-22','东大桥','beijing-s333',
            ['beijing-s333__line22-22','beijing-s333__line28-28'],['beijing-line22-22','beijing-line28-28'],INTERCHANGE28,
            '已公布东大桥22/28枢纽联系，各线轨道保持独立。'),
        transfer('future-transfer-bj28-jingguangqiao-22','京广桥／金台夕照','beijing-s169',
            ['beijing-s169__line22-22','beijing-s169__line28-28'],['beijing-line22-22','beijing-line28-28'],INTERCHANGE28,
            '官方施工报道明确10/22/28三线换乘；本关系补22/28独立站体。'),
        transfer('future-transfer-bj28-dawanglu-14','大望路','beijing-s47',
            ['beijing-s278','beijing-s47__line28-28'],['beijing-line14-14','beijing-line28-28'],INTERCHANGE28,
            '大望路既有1/14换乘站区；保留14号线独立坐标与站体，仅统一站区身份。')]
    ids={t['id'] for t in extra}
    p['requiredTransfers']=[t for t in p.get('requiredTransfers',[]) if t['id'] not in ids]+extra
    for t in p['requiredTransfers']:
        if t['id']=='future-transfer-bj28-dawanglu':
            t['sourceNote']='大望路1/28独立站体换乘；14/28另建联系，不能以已有1号线关系代替。'
    p.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    # Retain approved engineering identifiers until formal naming takes effect.
    # The 2025 public drawing uses 景辉街/茂兴西路; these are evidence aliases,
    # not a reason to silently rename the player's physical stations.
    p['stationNamingNote']='使用工程站名；2025一体化公示图的景辉街、茂兴西路分别对应核心区、北京东站，不当作已生效正式命名。'
    data['contentRevision']=REVISION
    data['contentRevisionNote']='补22号线西段两站和28号线三项缺失换乘，新增北京已核对项目独立范围；全城历史与工程类项目仍需完整验收。'
    write('data/campaigns.json',data)
    # Keep the materialized plan and editable source spec consistent.
    spec28=read('tools/project_specs/bj-line28.json')
    spec28['transfers']=[{k:v for k,v in t.items() if k!='precision'} for t in p['requiredTransfers']]
    spec28['plan'].update(scopeRevision=REVISION,requiresScopeRecheck=True,stationNamingNote=p['stationNamingNote'])
    write('tools/project_specs/bj-line28.json',spec28)

    targets=read('data/official_targets_2026-10-01.json'); bj=targets['cities']['beijing']
    reviewed=[dict(id='bj-line22',reviewStatus='verified',constructionOnly=True,
        transferReviewStatus='pending',source=FULL,sourcePublicationDate='2026-07-29',
        additionalSources=[WEST,FIRST,INTERCHANGE28],
        scopeNote='22站全部已公布范围；已实现与已收录线路的7项换乘，官方12项包含其他规划线路，完整换乘分期核查仍独立失败。',
        groups=[dict(id='beijing-line22-first-opening',historicalLineId='beijing-line22-22',scopeType='stations',
            stationNames='红庙 慈云寺 甘露园 定福庄 管庄 永顺 运河商务区 芙蓉西路 北运河东 潞源 潞源东 燕郊 神威大街 潮白大街 高楼 齐心庄 马坊物流港 马昌营 国农港 平谷'.split(),allowReverse=True),
            dict(id='beijing-line22-west',historicalLineId='beijing-line22-22',scopeType='stations',
                 stationNames='东大桥 金台夕照 红庙'.split(),allowReverse=True)],
        transfers=['future-transfer-bj22-hongmiao-14','future-transfer-bj22-guanzhuang-batong',
                   'future-transfer-bj22-yunhe-6','future-transfer-bj22-beiyunhedong-6']+[t['id'] for t in additions]),
        dict(id='bj-line3-phase1',reviewStatus='verified',constructionOnly=True,source=EAST3,
            sourcePublicationDate='2025-12-19',groups=[dict(id='beijing-line3-3',scopeType='stations',
                stationNames='东坝北 管庄路西口 楼梓庄桥西 楼梓庄 高辛庄 曹各庄北'.split())],transfers=[],
            scopeNote='既有东坝北加5座续建目标，曹各庄北远期预留。R4与M101远期衔接不冒充既有换乘。'),
        dict(id='bj-line12',reviewStatus='verified',constructionOnly=True,source=BUILD,
            sourcePublicationDate='2026-02-03',groups=[dict(id='beijing-line12-12',scopeType='stations',
                stationNames=['东坝北','东坝北街'])],transfers=[]),
        dict(id='bj-new-airport',reviewStatus='verified',constructionOnly=True,source=BUILD,
            sourcePublicationDate='2026-02-03',groups=[dict(id='beijing-route-21',scopeType='stations',
                stationNames=['草桥','丽泽商务区'])],transfers=['future-transfer-bj-lize-14','future-transfer-bj-lize-16'])]
    ids={t['id'] for t in reviewed}
    bj['projects']=[t for t in bj['projects'] if t['id'] not in ids]+reviewed
    write('data/official_targets_2026-10-01.json',targets)
    print('Beijing: 22 approved stops in two stable tasks; 28-line interchange gaps restored; 4 independent project scopes')


if __name__=='__main__':main()
