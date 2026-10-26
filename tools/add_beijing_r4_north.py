"""Materialize the omitted, approved R4 northern first phase.

Station order is transcribed from the dated official opening-of-works notice,
independently of the campaign. Locations are explicitly geographic estimates,
not coordinates extracted from the distorted network illustration.
"""
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT, read, write

REVISION = '2026.10.26.7'
WORKS = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202606/t20260602_4681873.html'
APPROVAL = 'https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202501/t20250107_3982106.htm'
EIA = 'https://www.bii.com.cn/file/2024/08/27/1724750589512.pdf'
T3 = 'https://ggzyfw.beijing.gov.cn/jyxxgcjszbjh/20250317/5002992.html'
LINHE = 'https://ghzrzyw.beijing.gov.cn/zhengwuxinxi/ghcg/xxgh/sy/202401/P020240201380098381172.pdf'
GUAN = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251219_4350423.html'


def main():
    # Correct a reference location only. Saved station positions are never
    # modified by this authoring tool or by loading the revised reference.
    east = read('tools/project_specs/bj-line3-east.json')
    guan = next(s for s in east['stations'] if s['id'] == 'beijing-f3e-guanzhuanglu')
    guan.update(latlng=[39.9756, 116.5650], coordinateSource='official_project_statement_and_local_road_geometry',
        coordinateAccuracyM=250,
        coordinateNote='官方报道：楼梓庄路与东苇路交叉口南侧。对照离线OSM东苇路way/31557751与东坝大街way/31557749共用端点[39.975724,116.565027]，在路口南侧取近似站区；不是测绘站中心。旧版116.578位于该路口以东约1.1公里，予以更正参考点，旧存档不搬站。', source=GUAN)
    east['plan'].update(contentRevision=REVISION, requiresScopeRecheck=True,
        contentRevisionNote='纠正管庄路西口官方路口参考，补充R4一期北段五站建设；保留已建站体位置。')
    write('tools/project_specs/bj-line3-east.json', east)
    subprocess.run([sys.executable, str(ROOT/'tools/add_project_plan.py'), str(ROOT/'tools/project_specs/bj-line3-east.json')], cwd=ROOT, check=True)

    names = ['管庄路西口', '3号航站楼', '中德产业园', '临河', '燕京桥']
    ids = ['beijing-f3e-guanzhuanglu', 'beijing-s207', 'beijing-fr4-zhongde', 'beijing-fr4-linhe', 'beijing-fr4-yanjingqiao']
    bodies = {s: s+'__r4north' for s in ids}
    stations = [dict(guan, existing=True), dict(id=ids[1], name=names[1], existing=True),
        dict(id=ids[2], name=names[2], latlng=[40.057196,116.6353076], coordinateAccuracyM=700,
            coordinateSource='official_project_statement_and_local_road_geometry', source=EIA,
            coordinateNote='环评PDF第24页表1.8-4及第26页表1.8-6将头二营村及村委会列为中德站相关保护目标；用OSM村落节点6410843011定位头二营站区，仅作近似站区，不宣称村中心等于车站中心。'),
        dict(id=ids[3], name=names[3], latlng=[40.0896,116.6550], coordinateAccuracyM=600,
            coordinateSource='official_project_statement_and_local_road_geometry', source=LINHE,
            coordinateNote='仁和组团控规PDF第15页第33条及第36页空间结构图显示临河站在林河大街、通顺路周边。结合本地OSM林河大街way/1069137480和通顺路way/169683840取站区；图纸为规划示意，未作为精确施工坐标。'),
        dict(id=ids[4], name=names[4], latlng=[40.11618,116.65187], coordinateAccuracyM=400,
            coordinateSource='local_road_geometry', source='https://m.bjnews.com.cn/detail/1755152233129344.html',
            coordinateNote='站址报道为通顺路与顺平路交叉口，离线OSM通顺路way/1252702215、顺平路way/48064226附近，燕京桥way/552782914核对，仅为路口站区。')]
    group = dict(key='north', mapRouteId='beijing-future-r4-north', coverageGroupId='beijing-r4-north-phase1',
        name='R4线一期北段', historicalLineId='beijing-r4-north', color='#3867A0', stationIds=ids,
        stationInstances=bodies, toleranceM=700, alignmentPrecision='station_areas_and_approximate_corridor',
        officialLengthM=20780, maxSpacingM=10000, stationOrderSource=WORKS,
        precisionNote='五站站序及20.78公里取自2026年6月2日开工记录。早期批复与环评为21.3公里，分别保留来源版本。站区为许可地理数据和官方地点描述的近似定位，区间为走廊示意；管庄路西口至T3为长区间，不添加虚构中间站。')
    transfers = []
    for sid, name, other, other_body in [(ids[0], names[0], 'beijing-line3-3', ids[0]),
                                          (ids[1], names[1], 'beijing-route-23', ids[1])]:
        transfers.append(dict(id='future-transfer-r4-'+('guanzhuanglu-3' if sid==ids[0] else 't3-airport'),
            name=name, complexId=sid, lineIds=['beijing-r4-north',other], stationInstanceIds=[bodies[sid],other_body],
            source=WORKS, sourceNote='官方开工记录明确的两处换乘。两线独立站体与线路路径分别建设后由玩家明确确认；规划联系不算截止日已开放。'))
    spec = dict(city='beijing', projectIds=['bj-r4-north-phase1'], stations=stations, lineGroups=[group], transfers=transfers,
        plan=dict(id='bj-r4-north-build', title='北京R4线一期北段建设篇', date='2026-10-01',
            status='approved_and_under_construction', projectType='approved_and_under_construction', required=True,
            sourceType='municipal_construction_start', source=WORKS, sourceTitle='北京地铁快线+1！共设5站，将与3号线、首都机场线换乘',
            sourcePublicationDate='2026-06-02', sourceCheckedAt='2026-10-26', exactAlignment='corridor_only',
            additionalSources=[APPROVAL,EIA,T3,LINHE], contentRevision=REVISION,
            contentRevisionNote='补入原清单遗漏的R4一期北段，五站四区间及两处规划换乘；不虚构未来开放时间。',
            description='复现已于2026年6月开工的管庄路西口—燕京桥五站工程，并分别衔接3号线和首都机场线。临河为高架站，其余四站地下，结构来自公开环评；埋深未公开部分仍为游戏示意。成果为规划建设完成，不是历史开通。',
            stationProfiles={bodies[sid]:dict(id='r4-eia-'+str(index),form=form,depthM=8.0 if index==3 else -15.0,
                parameterStatus={'form':'public_reference','depthM':'game_estimate'},parameterSources={'form':EIA},
                note='公开环评表2.1-3：'+form+'。站体矩形、长度、宽度和'+('高架显示高度' if index==3 else '埋深')+'为游戏示意；未将估算写成工程测量，展示车型仍为简化替身。')
                for index,(sid,form) in enumerate(zip(ids,['地下双岛四线','地下岛侧五线','地下二层单岛四线','高架三层侧式','地下二层岛式']))}))
    write('tools/project_specs/bj-r4-north.json', spec)
    baseline=read('data/network_baselines_2026-10-01.json')
    projects=baseline['cities']['beijing']['projectsAtCutoff']
    entry=dict(id='bj-r4-north-phase1',name='R4线一期北段（管庄路西口—燕京桥）',
        projectType='approved_and_under_construction',status='2026年6月2日开工',source=WORKS,
        sourceTitle=spec['plan']['sourceTitle'],sourceCheckedAt='2026-10-26',statusAtCutoff='已批在建',
        note='五站完整站序；早期21.3公里与开工20.78公里分版本记录，不用未公开隧道精度免除建设任务。')
    projects[:]=[p for p in projects if p['id']!=entry['id']]+[entry]
    write('data/network_baselines_2026-10-01.json',baseline)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/'tools/project_specs/bj-r4-north.json')],cwd=ROOT,check=True)

    # Independently transcribed source answer, not a copy of materialized tasks.
    official=read('data/official_targets_2026-10-01.json');bj=official['cities']['beijing']
    if entry['id'] not in bj['requiredProjectIds']:bj['requiredProjectIds'].append(entry['id'])
    target=dict(id=entry['id'],reviewStatus='verified',source=WORKS,sourcePublicationDate='2026-06-02',sourceCheckedAt='2026-10-26',
        constructionOnly=True,groups=[dict(id='beijing-r4-north-phase1',historicalLineId='beijing-r4-north',scopeType='stations',
        stationNames=['管庄路西口','3号航站楼','中德产业园','临河','燕京桥'],fullServiceOrder=True,allowReverse=True)],
        transfers=['future-transfer-r4-guanzhuanglu-3','future-transfer-r4-t3-airport'],transferReviewStatus='verified',
        additionalSources=[APPROVAL,EIA,T3],
        note='截止日前已批在建的北段五站及官方明确的3号线、首都机场线联系。S6、北部联络及城际联络在此为远期接口资料，不伪造已建线路或开放换乘。')
    bj['projects']=[p for p in bj['projects'] if p['id']!=target['id']]+[target]
    write('data/official_targets_2026-10-01.json',official)
    write('data/official_evidence/beijing_r4_north_review.json',dict(projectId=target['id'],cutoff='2026-10-01',
        reviewedAt='2026-10-26',sourceRecords=[dict(url=APPROVAL,publicationDate='2025-01-07',approval='京发改（审）〔2024〕1067号',lengthKm=21.3),
        dict(url=WORKS,publicationDate='2026-06-02',event='construction_start',lengthKm=20.78,
             stationOrder=['管庄路西口','3号航站楼','中德产业园','临河','燕京桥'],interchanges={'管庄路西口':['3号线'],'3号航站楼':['首都机场线']}),
        dict(url=EIA,pdfPage=35,printedPage=25,table='2.1-3',stationCount=5,elevatedStation='临河')],
        coordinateReview='Official site descriptions + licensed road/village geography; station-area estimates, never a georeferenced schematic network map.',
        excludedFromOpening=['all R4 stations','planned S6/北部联络/城际铁路 interfaces'],
        broaderInventoryReview='Still pending: adding this omitted project does not establish a complete Beijing approved-project inventory.'))
    print('R4 NORTH: 5 stations, 4 intervals, 2 explicit planned interchanges; original saves are not relocated')


if __name__=='__main__':main()
