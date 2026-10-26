"""Add both approved northern Line 19 tasks without replacing today's service."""
import subprocess
import sys
import math
from repair_chengdu_historical_phases import ROOT,read,write
from validate_project_spec import distance_m

REV='2026.10.26.8'
APPROVAL='https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202503/t20250303_4023616.htm'
START='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202602/t20260224_4537012.html'
SCOPE='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202503/t20250304_4024106.html'
EIA='https://www.bii.com.cn/file/2025/03/03/1740974915275.pdf'
FORMER='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202308/t20230816_3223339.html'


def main():
    ids=['beijing-s178','beijing-s3','beijing-f19-shangqing-south','beijing-s250',
         'beijing-f19-xisanqi','beijing-open18-longzexi','beijing-f19-lifescience-south','beijing-f19-lifegu']
    names=['牡丹园','北沙滩','上清桥南','清河小营桥','西三旗','新龙泽','生命科学园南','生命谷']
    bodies={sid:sid+'__north19' for sid in ids}
    bodies[ids[0]]='beijing-s178__line19-19'
    qinghe='beijing-s96';bodies[qinghe]=qinghe+'__north19'
    stations=[dict(id=sid,name=name,existing=True) for sid,name in zip(ids,names) if sid not in
              ['beijing-f19-shangqing-south','beijing-f19-xisanqi','beijing-f19-lifescience-south','beijing-f19-lifegu']]
    stations.append(dict(id=qinghe,name='清河',existing=True))
    for sid,name,ll,note in [
        (ids[2],names[2],[40.01395,116.3536], '最终环评排水表指向银泉路，许可公开信息为银泉路与京藏高速路口；本地OSM银泉路way/161453474路口近似站区，不取桥名中心代替站址。'),
        (ids[4],names[4],[40.05375,116.32289], '西三旗京藏高速走廊及安宁庄路排水接口；OSM西三旗桥way/691456226定位路口站区，不是测绘站中心。'),
        (ids[6],names[6],[40.0835,116.2982], '京投公开答复的二拨子桥与二龙北路之间、京藏高速西侧站区；OSM二拨子桥way/1530337633、二龙北路way/1544797654核对范围。站位为近似，不将村庄或园区中心当车站。'),
        (ids[7],names[7],[40.1006,116.2685], '最终环评明确生命谷地面站、医疗园路在站北侧及与东北环线衔接。按本地OSM医疗园路way/202235308南侧铁路走廊定位，仅作近似站区。')]:
        stations.append(dict(id=sid,name=name,latlng=ll,coordinateSource='official_project_statement_and_local_road_geometry',
                             coordinateAccuracyM=600,coordinateNote=note,source=EIA))
    note='采用2025年可研批复和最终环评：北延7站、支线1站，复用牡丹园本线端点。站区为官方地点描述与许可地理数据的近似参考，隧道与埋深不宣称测绘精度；本期包含生命谷，不沿用旧版6站北延。'
    main_group=dict(key='north',mapRouteId='beijing-future-line19-north',coverageGroupId='beijing19-north-main',
        historicalLineId='beijing-line19-19',name='19号线北延主线',color='#D4AEDE',stationIds=ids,
        stationInstances={sid:bodies[sid] for sid in ids},toleranceM=650,officialLengthM=17100,
        alignmentPrecision='station_areas_and_approximate_corridor',precisionNote=note,stationOrderSource=SCOPE,
        constructionVariant=True,stationNamingSource=EIA)
    branch_group=dict(key='branch',mapRouteId='beijing-future-line19-qinghe',coverageGroupId='beijing19-north-branch',
        historicalLineId='beijing-line19-19',name='19号线清河支线',color='#D4AEDE',stationIds=[ids[2],qinghe],
        stationInstances={sid:bodies[sid] for sid in [ids[2],qinghe]},toleranceM=650,
        alignmentPrecision='corridor_only',precisionNote='官方北延支线7.1公里，仅新增清河1站；从上清桥南分出，经京藏高速、北五环、京新高速至清河。地图采用这些公开道路的近似弯曲走廊，不用两站直线代替，也不声称示意显示里程等于工程里程。',stationOrderSource=EIA,
        constructionVariant=True,stationNamingSource=EIA,requiredPlanningCorridorId='beijing19-qinghe-road-corridor',planningCorridorToleranceM=650)
    pairs=[]
    for key,sid,name,other,other_body in [
        ('beishatan-15',ids[1],names[1],'beijing-line15-15','beijing-s3'),
        ('xiaoying-changping',ids[3],names[3],'beijing-route-20','beijing-s250'),
        ('qinghe-13',qinghe,'清河','beijing-line13-13','beijing-s96__line13-13'),
        ('qinghe-changping',qinghe,'清河','beijing-route-20','beijing-s96__line20'),
        ('qinghe-capacity13A',qinghe,'清河','beijing-capacity13A','beijing-s96__line13-13'),
        ('newlongze-capacity13A',ids[5],'新龙泽／龙泽西','beijing-capacity13A','beijing-open18-longzexi'),
        ('newlongze-capacity13B',ids[5],'新龙泽／龙泽西','beijing-capacity13B','beijing-open18-longzexi__capacity13B'),
        ('newlongze-18',ids[5],'新龙泽／龙泽西','beijing-line18-18','beijing-open18-longzexi')]:
        pairs.append(dict(id='future-transfer-bj19-'+key,name=name,complexId=sid,lineIds=['beijing-line19-19',other],
            stationInstanceIds=[bodies[sid],other_body],source=SCOPE,
            sourceNote='最终环评明确的地铁衔接；19号线使用独立站体。工程名新龙泽与13扩能、18号线龙泽西站区关联，保留对侧正式站名，不误接旧龙泽或还建龙泽。规划联系不表示已开放。'))
    plan=dict(id='bj-line19-north-build',title='19号线北延主线与清河支线',date='2026-10-01',
        status='approved_and_under_construction',projectType='approved_and_under_construction',required=True,
        sourceType='municipal_approval_and_final_eia',source=START,sourceTitle='北京地铁19号线二期全面开工',
        sourcePublicationDate='2026-02-24',sourceCheckedAt='2026-10-26',exactAlignment='corridor_only',
        description='分别建设牡丹园—生命谷北延主线和上清桥南—清河支线，共8座本期站体；复用牡丹园。清河与清河小营桥的本线预留土建已有实施记录，游戏将其作为明确本线站体完成接轨，不拿其他线路站体代替。只记录规划建设完成，不虚构未来开通时间。',
        additionalSources=[APPROVAL,EIA,SCOPE,FORMER],contentRevision=REV,
        contentRevisionNote='补齐原清单遗漏的19号线北延及清河支线；保留既有一期开放范围。',
        stationProfiles={bodies[sid]:dict(id='bj19-final-eia-'+str(index),form=form,depthM=0.0 if form.startswith('地面') else -15.0,
            parameterStatus={'form':'public_reference','depthM':'game_estimate'},parameterSources={'form':EIA},
            note='最终环评表2-1-3：'+form+'。显示埋深、矩形尺寸和展示车型为游戏示意；清河与清河小营桥本线土建已预留，不与对侧线路共用轨道。')
            for index,(sid,form) in enumerate([(ids[1],'地下三层岛式'),(ids[2],'地下二层双岛四线'),(ids[3],'地下四层叠落岛式'),
                (ids[4],'地下二层岛式'),(ids[5],'地下三层岛式'),(ids[6],'地下二层双岛四线'),(ids[7],'地面一层双岛四线'),(qinghe,'地下二层岛式')])})
    spec=dict(city='beijing',projectIds=['bj-line19-north-phase2'],stations=stations,lineGroups=[main_group,branch_group],transfers=pairs,plan=plan)
    write('tools/project_specs/bj-line19-north.json',spec)
    baseline=read('data/network_baselines_2026-10-01.json');roster=baseline['cities']['beijing']['projectsAtCutoff']
    entry=dict(id='bj-line19-north-phase2',name='19号线二期（北延及北延支线）',projectType='approved_and_under_construction',
        status='2025年可研获批，2026年2月全面开工',source=APPROVAL,sourceTitle='京发改（审）〔2025〕109号',
        sourceCheckedAt='2026-10-26',statusAtCutoff='已批在建',note='北延7站及清河支线1站，含生命谷；主支线分别制作，不包括另行审查的南延。')
    roster[:]=[p for p in roster if p['id']!=entry['id']]+[entry]
    write('data/network_baselines_2026-10-01.json',baseline)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/'tools/project_specs/bj-line19-north.json')],cwd=ROOT,check=True)
    official=read('data/official_targets_2026-10-01.json');bj=official['cities']['beijing']
    target=dict(id=entry['id'],reviewStatus='verified',source=APPROVAL,sourcePublicationDate='2025-03-03',sourceCheckedAt='2026-10-26',
        additionalSources=[SCOPE,EIA,START],constructionOnly=True,
        groups=[dict(id='beijing19-north-main',historicalLineId='beijing-line19-19',scopeType='stations',
            stationNames=['牡丹园','北沙滩','上清桥南','清河小营桥','西三旗','新龙泽','生命科学园南','生命谷'],allowReverse=True,fullServiceOrder=True),
            dict(id='beijing19-north-branch',historicalLineId='beijing-line19-19',scopeType='stations',stationNames=['上清桥南','清河'],allowReverse=True,matchScope='contiguous_subsequence',requiredPlanningCorridorId='beijing19-qinghe-road-corridor',planningCorridorToleranceM=650)],
        transfers=['future-transfer-bj19-beishatan-15','future-transfer-bj19-xiaoying-changping','future-transfer-bj19-qinghe-13',
                   'future-transfer-bj19-qinghe-changping','future-transfer-bj19-qinghe-capacity13A',
                   'future-transfer-bj19-newlongze-capacity13A','future-transfer-bj19-newlongze-capacity13B','future-transfer-bj19-newlongze-18'],
        transferReviewStatus='pending',transferReviewNote='地铁侧联系已配置，工程名新龙泽与正式龙泽西的全量分层证据、预留铁路接口继续核对；不因8站建成而解除项目完整性门槛。')
    bj['projects']=[p for p in bj['projects'] if p['id']!=target['id']]+[target]
    if target['id'] not in bj['requiredProjectIds']:bj['requiredProjectIds'].append(target['id'])
    write('data/official_targets_2026-10-01.json',official)
    # Separate authored planning corridors: never disguise road samples as
    # measured OSM railway ways, and never replace the modern rail dataset.
    path=ROOT/'data/planning_corridors.json'
    corridors=read('data/planning_corridors.json') if path.exists() else dict(version=REV,coordinateSystem='EPSG:4326',alignments=[])
    points=[[40.01395,116.3536],[40.0160,116.3517],[40.0193,116.3495],[40.0215,116.3476],
            [40.0217,116.3445],[40.0210,116.3400],[40.0204,116.3330],[40.01927,116.32143],
            [40.0238,116.3188],[40.0300,116.3145],[40.0350,116.3110],[40.0397646,116.3086433]]
    dense=[]
    for a,b in zip(points,points[1:]):
        steps=max(1,math.ceil(distance_m(a,b)/80))
        dense.extend([[a[0]+(b[0]-a[0])*i/steps,a[1]+(b[1]-a[1])*i/steps] for i in range(steps)])
    points=dense+[points[-1]]
    corridor=dict(id='beijing19-qinghe-road-corridor',cityId='beijing',fromId=ids[2],toId=qinghe,points=points,
        historicalLineId='beijing-line19-19',coordinateSystem='EPSG:4326',precision='approximate_corridor',
        sourceKind='official_road_corridor',source=EIA,sourceAccuracyM=None,checkedAt='2026-10-26',amapReview='pending',
        sourceRoadWayIds=[161453474,994926043,994926040],license='ODbL-1.0',attribution='© OpenStreetMap contributors',
        sourceDate='2026-10-09',appliesTo='planned_construction',projectId=target['id'],
        note='最终环评第22页道路走向、PDF第5页示意图核对顺序；坐标只取许可道路和桥梁附近的近似游戏走廊，不从示意图变换工程坐标。未公开隧道弯曲和长度不伪造，实际显示里程与官方7.1公里分开。')
    corridors['alignments']=[c for c in corridors['alignments'] if c['id']!=corridor['id']]+[corridor];corridors['version']=REV
    write('data/planning_corridors.json',corridors)
    write('data/official_evidence/beijing19_north_review.json',dict(projectId=target['id'],source=APPROVAL,
        finalEia=EIA,finalEiaPdfPage=33,finalEiaPrintedPage=25,finalEiaTable='2-1-3',
        mainStationOrder=['北沙滩','上清桥南','清河小营桥','西三旗','新龙泽','生命科学园南','生命谷'],
        branchStationOrder=['上清桥南','清河'],mainLengthKm=17.1,branchLengthKm=7.1,
        surfaceStation='生命谷',existingCivilReservations=['清河','清河小营桥'],constructionStartSource=START,
        scopeNote='Only north extension and its branch; no fabricated opening year or southern phase. Planning-road geometry is approximate, not a surveyed tunnel.',
        transferReviewStatus='pending'))
    print('BJ19 NORTH: 7 main stops + 1 branch stop, existing Mudanyuan preserved; separate planned service variants')


if __name__=='__main__':main()
