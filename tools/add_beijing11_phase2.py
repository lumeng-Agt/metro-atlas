"""Published 14-station second phase, not the superseded Yangqiao proposal.

The official order/approval is independent of the geographical estimates.
Road-area points are explicitly approximate and are never a tunnel survey.
"""
from copy import deepcopy
import hashlib
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT, read, write

REV = '2026.10.27.2'
PID = 'bj-line11-phase2'
LINE = 'beijing-line11-11'
SCOPE = 'https://www.beijing.gov.cn/ywdt/gzdt/202505/t20250503_4080250.html'
APPROVAL = 'https://zdb.beijing.gov.cn/zfxxgk/zfxxgkzl/fdzdgknr/ghxx/202601/t20260114_4429896.html'
EIA = 'https://www.bii.com.cn/file/2025/07/28/1753687412210.pdf'
HUB = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202603/t20260313_4556163.html'
NAMES = '新首钢 型材 锅炉厂南路 衙门口西 体育场南街 衙门口东 鲁谷大街 吴家村 小瓦窑 青塔 万丰路 莲花桥 北京西站 马连道 丽泽商务区'.split()
# Approximate station areas along the roads named in the official scheme.
# No diagram pixel coordinates are transformed into geographic positions.
NEW = [
    ('xingcai', '型材', [39.8987,116.1699], '规划二型材南路西段／北辛安路走廊；现状路网尚未完整实施。'),
    ('guoluchang', '锅炉厂南路', [39.8962,116.1810], '人民渠路西部弯曲段与锅炉厂南路走廊。'),
    ('yamenkouxi', '衙门口西', [39.8951,116.1908], '人民渠路／古城南街一带，非把同名公交站当作地铁中心。'),
    ('yamenkoudong', '衙门口东', [39.8946,116.2144], '市郊铁路衙门口东站附近的独立地铁站区；不复用铁路站台。'),
    ('lugu', '鲁谷大街', [39.8928,116.2246], '鲁谷大街南部、莲石东路与吴家村路衔接走廊。'),
    ('wujiacun', '吴家村', [39.8884,116.2361], '吴家村路沿线站区。'),
    ('xiaowayao', '小瓦窑', [39.8884,116.2470], '吴家村路向大成路衔接的站区。'),
    ('qingta', '青塔', [39.8884,116.2586], '大成路与青塔西路附近站区。'),
    ('wanfeng', '万丰路', [39.8915,116.2891], '万丰路北部、向莲花池西路衔接走廊。'),
    ('maliandao', '马连道', [39.8805,116.3204], '马连道路南部站区；与铁路及公交同名对象分开。'),
]


def main():
    cities = read('data/cities.json'); city = next(c for c in cities['cities'] if c['id']=='beijing')
    existing = {s['name']:s for s in city['stations']}
    stations = [dict(id=sid,name=name,existing=True) for name,sid in [
        ('新首钢','beijing-s374'),('体育场南街','beijing-f1b-tiyuchangnanjie'),
        ('莲花桥','beijing-s189'),('北京西站','beijing-s215'),('丽泽商务区','beijing-s287')]]
    by_name = {s['name']:s['id'] for s in stations}
    for suffix,name,point,note in NEW:
        sid='beijing-f11p2-'+suffix;by_name[name]=sid
        stations.append(dict(id=sid,name=name,latlng=point,
            coordinateSource='official_project_statement_and_local_road_geometry',coordinateAccuracyM=600,
            coordinateNote=note+' 按官方线路所经道路及许可OSM地理参照作约600米精度站区估计；不是已核验站体中心。',source=SCOPE))
    # Give the new line an explicit, separately qualified reference. Do not
    # move the old Line-1 branch body or imply its old estimate is surveyed.
    ref='beijing-f11p2-tiyu-reference'
    stations.append(dict(id=ref,name='体育场南街',latlng=[39.89512,116.19979],
        coordinateSource='official_project_statement_and_local_road_geometry',coordinateAccuracyM=650,
        coordinateNote='人民渠路现状way/948716213东段附近的近似站区。旧1号线支线站址也是走廊估计，本任务不移动旧站，不把两处参考差异解释成真实650米通道。',source=SCOPE))
    ids=[by_name[n] for n in NAMES]
    instances={s:s+'__line11-phase2' for s in ids};instances['beijing-s374']='beijing-s374'
    transfers=[]
    pairs=[('体育场南街','beijing-lineearly0','beijing-f1b-tiyuchangnanjie'),
           ('莲花桥','beijing-line10-10','beijing-s189'),
           ('北京西站','beijing-line7-7','beijing-s215__line7-7'),
           ('北京西站','beijing-line9-9','beijing-s215__line9-9'),
           ('丽泽商务区','beijing-line14-14','beijing-s287__line14-14'),
           ('丽泽商务区','beijing-line16-16','beijing-s287__line16-16'),
           ('丽泽商务区','beijing-route-21','beijing-s287__line21')]
    for name,other,other_body in pairs:
        sid=by_name[name]
        transfers.append(dict(id='future-transfer-bj11phase2-'+sid+'-'+other,name=name,complexId=sid,
            lineIds=[LINE,other],stationInstanceIds=[instances[sid],other_body],source=HUB if name=='丽泽商务区' else EIA,
            precision='schematic',sourceNote='已公布的线路换乘关系，各线采用独立站体；没有隧道或通道测绘，不把近似中心差当作真实通道长度。'))
    profiles={}
    forms={'型材':'地下二层岛式','锅炉厂南路':'地下二层岛式','衙门口西':'地下二层岛式',
           '体育场南街':'地下二层岛式（1号线支线代建预留）','衙门口东':'地下三层岛式',
           '鲁谷大街':'地下岛式，层次待按最终工程资料确认','吴家村':'地下二层岛式',
           '小瓦窑':'地下三层岛式','青塔':'两端地下三层、中部单层岛式','万丰路':'地下二层岛式',
           '莲花桥':'地下三层岛式','北京西站':'地下三层岛式','马连道':'地下二层岛式',
           '丽泽商务区':'地下岛式（枢纽整体地下五层口径）'}
    for name in NAMES[1:]:
        body=instances[by_name[name]]
        profiles[body]=dict(id=PID+'-'+name,form=forms[name],depthM=-25,
            parameterStatus={'form':'public_reference' if name!='鲁谷大街' else 'schematic','depthM':'game_estimate'},
            parameterSources={'form':HUB if name=='丽泽商务区' else EIA},
            note='地面位置、矩形、朝向和显示深度为游戏示意；不以未公开工程尺寸设置通关门槛。')
    profiles[instances[by_name['鲁谷大街']]]['note']+=' 环评总述为全地下线，但表2-2-2该行写地面三层，保留资料差异，不据此生成高架站。'
    group=dict(key='main',coverageGroupId='beijing11-phase2',mapRouteId='beijing-future-line11-phase2',
        historicalLineId=LINE,name='11号线二期：新首钢—丽泽商务区',color='#ED796B',
        stationIds=ids,stationInstances=instances,stationReferenceIds={by_name['体育场南街']:ref},
        toleranceM=650,constructionVariant=True,stationNamingSource=SCOPE,
        alignmentPrecision='station_areas_and_approximate_corridor',stationOrderSource=SCOPE,
        precisionNote='官方14座新站及既有新首钢接头；位置为所经道路的近似站区，非正式站体中心，隧道为近似走廊。体育场南街旧支线位置不自动变更。',officialLengthM=18400)
    plan=dict(id='bj-line11-phase2-build',title='11号线二期：连接北京西站与丽泽',date='2026-10-01',
        status='approved',projectType='approved_project',required=True,sourceType='official_integrated_scheme_approved',
        source=APPROVAL,sourceTitle='市重大办2025年四季度：11号线二期线路一体化方案获批',
        sourcePublicationDate='2026-01-14',sourceCheckedAt='2026-10-27',additionalSources=[SCOPE,EIA,HUB],
        contentRevision=REV,requiresScopeRecheck=True,stationProfiles=profiles,
        description='复用一期新首钢接头，建设公开的14座新站及连续区间，建立1支线、10、7、9、14、16及机场线换乘。按已获批的一体化范围制作规划建设，不把招标计划当作开工或未来开通公告。衙门口东铁路接驳单列背景；丽金线整体另行核验，不伪造已运营线路。')
    spec=dict(city='beijing',projectIds=[PID],stations=stations,lineGroups=[group],transfers=transfers,plan=plan)
    path='tools/project_specs/'+PID+'.json';write(path,spec)
    # Register first so the materializer updates the same stable project row.
    baseline=read('data/network_baselines_2026-10-01.json');rows=baseline['cities']['beijing']['projectsAtCutoff']
    rows[:]=[r for r in rows if r['id']!=PID]+[dict(id=PID,name=plan['title'],projectType='approved_project',status='一体化方案已获批',
        statusAtCutoff='已批准规划范围；不推断整线开工',source=APPROVAL,sourceTitle=plan['sourceTitle'],sourceCheckedAt='2026-10-27',note=plan['description'])]
    write('data/network_baselines_2026-10-01.json',baseline)
    subprocess.run([sys.executable,str(ROOT/'tools/validate_project_spec.py'),str(ROOT/path)],cwd=ROOT,check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],cwd=ROOT,check=True)
    official=read('data/official_targets_2026-10-01.json');bj=official['cities']['beijing']
    target=dict(id=PID,reviewStatus='verified',transferReviewStatus='pending',source=APPROVAL,sourcePublicationDate='2026-01-14',
        additionalSources=[SCOPE,EIA,HUB],constructionOnly=True,
        groups=[dict(id='beijing11-phase2',historicalLineId=LINE,stationNames=NAMES,allowReverse=True,scopeType='stations',stationNamingSource=SCOPE)],
        transfers=[t['id'] for t in transfers],transferDefinitions=deepcopy(transfers),
        note='完整14新站范围有官方独立站序；丽金线预留及整体枢纽站体资料口径仍需单独核对，不将其标为全部换乘已审核。')
    bj['projects']=[p for p in bj['projects'] if p['id']!=PID]+[target]
    if PID not in bj['requiredProjectIds']:bj['requiredProjectIds'].append(PID)
    roster=bj.setdefault('sourceProjectInventory',[])
    roster[:]=[r for r in roster if r['projectId']!=PID]+[dict(projectId=PID,officialName='11号线二期',required=True,source=APPROVAL,sourcePublicationDate='2026-01-14')]
    write('data/official_targets_2026-10-01.json',official)
    data=read('data/campaigns.json');data.update(contentRevision=REV,contentRevisionNote='补北京11号线二期14座新站、既有接头与独立线路站体换乘；不采用旧洋桥方案，不改变现状开放范围。');write('data/campaigns.json',data)
    write('data/official_evidence/beijing11_phase2_review.json',dict(cutoff='2026-10-01',reviewedAt='2026-10-27',
        stationOrderSource=SCOPE,approvalSource=APPROVAL,eiaSource=EIA,eiaPdfPages=[35,36,37],
        eiaSha256=hashlib.sha256((ROOT/'.tmp-remediation-sources/beijing11-phase2-eia202507.pdf').read_bytes()).hexdigest(),
        stationNames=NAMES[1:],existingConnectionStation='新首钢',constructionScope='14 new station facilities, including 2 civil reservations built by other projects',
        geographyPrecision='road_area_estimates_600m_not_station_survey',metroTransfers=deepcopy(transfers),
        excludedBackgroundInterfaces=[dict(station='衙门口东',interface='市郊铁路城市副中心线',reason='主线范围为地铁，铁路不加入列车轨道图')],
        unresolvedInterfaces=[dict(station='丽泽商务区',interface='丽金线',reason='枢纽预留已公开；完整项目和换乘目标尚未纳入独立审核，保留缺项')],
        sourceConflicts=[dict(station='鲁谷大街',issue='EIA table says ground three floors but whole line underground'),
                         dict(station='丽泽商务区',issue='EIA standalone four-floor and later overall hub five-floor datums differ; no fabricated absolute depth')]))
    print('BJ11 PHASE2: 14 new stops + reused terminal; 7 explicit metro contacts; current service remains unchanged')


if __name__=='__main__':main()
