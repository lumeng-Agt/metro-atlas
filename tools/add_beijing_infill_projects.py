"""Materialize three dated infill projects, using licensed existing rail corridors.

Source scopes are transcribed below, not inferred from today's route snapshots.
OSM geometry supplies a modern geographic reference only. In particular, a yard
track does not prove an approved new passenger-track design or a station centre.
"""
import hashlib
import heapq
import json
import math
import subprocess
import sys
from pathlib import Path

import osmium
from repair_chengdu_historical_phases import ROOT, read, write
from validate_project_spec import distance_m

REV = '2026.10.26.9'
TAIHU = 'https://ggzyfw.beijing.gov.cn/jyxxgcjszbjh/20251124/5341905.html'
TAIHU_WORKS = 'https://thzb.crsc.cn/news/tsi_2587_5978_96711.html'
TAIHU_FORM = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202508/t20250813_4171885.html'
GUOZHAN = 'https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202607/t20260721_4774285.htm'
GUOZHAN_EIA = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202609/t20260903_4849251.html'
WANGJING = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202604/t20260407_4575686.html'
WANGJING_EIA = 'https://www.bii.com.cn/file/2024/11/14/1731565997785.pdf'
WANGJING_SCOPE = 'https://zdzqgw.beijing.gov.cn/zqfw/bjsdgjjc/bjsdgjjcdt/202411/t20241119_3945372.html'
PBF = ROOT / '.tools/osm-source/beijing-latest.osm.pbf'


class RailWays(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.rows = {'taihu': [], 'guozhan': [], 'airport': []}

    def way(self, way):
        if way.tags.get('railway') != 'subway':
            return
        name = way.tags.get('name', '')
        area = 'airport' if name == '首都机场线' else 'guozhan' if '15号线' in name else ''
        try:
            points = [(round(n.lat, 7), round(n.lon, 7)) for n in way.nodes]
        except osmium.InvalidLocationError:
            return
        if not area and way.tags.get('service') == 'yard' and any(39.811 <= p[0] <= 39.829 and 116.595 <= p[1] <= 116.603 for p in points):
            area = 'taihu'
        if area:
            self.rows[area].append((way.id, points))


def rail_path(rows, start, finish):
    """Snap onto segments, then follow connected OSM ways; no schematic fitting."""
    graph = {}
    segments = []
    def link(a, b, way):
        length = distance_m(a, b)
        graph.setdefault(a, []).append((b, length, way))
        graph.setdefault(b, []).append((a, length, way))
    for way, points in rows:
        for a, b in zip(points, points[1:]):
            link(a, b, way)
            segments.append((a, b, way))
    snapped = []
    factor = math.cos(math.radians(start[0]))
    for point in (start, finish):
        candidates = []
        for a, b, way in segments:
            dx = (b[1]-a[1])*factor; dy = b[0]-a[0]
            t = max(0, min(1, (((point[1]-a[1])*factor)*dx+(point[0]-a[0])*dy)/(dx*dx+dy*dy))) if dx*dx+dy*dy else 0
            p = (a[0]+t*(b[0]-a[0]), a[1]+t*(b[1]-a[1]))
            d = distance_m(point, p)
            candidates.append((d, p, a, b, way))
        candidates.sort()
        if not candidates or candidates[0][0] > 250:
            raise ValueError(f'No appropriate rail reference near {point}')
        # A station-area point may sit a few metres closer to the opposite
        # parallel track. Consider nearby tracks instead of routing around the
        # entire airport loop just to change sides. This is a geographic
        # corridor lookup, not proof of a train crossover or directed service.
        endpoint=tuple(point);graph.setdefault(endpoint,[]);snapped.append(endpoint)
        for d,p,a,b,way in candidates:
            if d > candidates[0][0]+25:break
            link(endpoint,p,way);link(p,a,way);link(p,b,way)
    queue = [(0, snapped[0])]; distances = {snapped[0]: 0}; previous = {}
    while queue:
        d, a = heapq.heappop(queue)
        if d != distances[a]: continue
        if a == snapped[1]: break
        for b, length, way in graph[a]:
            if d+length < distances.get(b, math.inf):
                distances[b] = d+length; previous[b] = (a, way); heapq.heappush(queue, (d+length, b))
    if snapped[1] not in distances: raise ValueError('Disconnected OSM reference; do not substitute a straight line')
    points = [snapped[1]]; ways = set()
    while points[-1] != snapped[0]:
        parent, way = previous[points[-1]]; ways.add(way); points.append(parent)
    points.reverse()
    dense = []
    for a,b in zip(points,points[1:]):
        steps = max(1, math.ceil(distance_m(a,b)/70))
        dense.extend([[round(a[0]+(b[0]-a[0])*i/steps,7),round(a[1]+(b[1]-a[1])*i/steps,7)] for i in range(steps)])
    return dense+[list(finish)], sorted(ways)


def main():
    city = next(c for c in read('data/cities.json')['cities'] if c['id']=='beijing')
    coords = {s['id']:s['latlng'] for s in city['stations']}
    # Station-area estimates, not a claim that a footprint centre is a platform.
    # Taihu is on the eastern test-track strip, not at the town/depot centroid.
    coords['beijing-future-taihu'] = [39.8245,116.60149]
    coords['beijing-future-guozhan2'] = [40.0754,116.5509]
    coords['beijing-airport-wangjingnan'] = [39.9828,116.47635]
    physical = 'beijing-s271__airport-infill'
    cases = [
        dict(project='bj-yizhuang-taihu-infill',plan='bj-yizhuang-taihu-build',line='beijing-route-24',color='#D6007B',
            title='亦庄线台湖车辆段加站',source=TAIHU,date='2025-11-24',extra=[TAIHU_WORKS,TAIHU_FORM],
            names=['亦庄火车站','台湖'],ids=['beijing-s266','beijing-future-taihu'],area='taihu',form='地面单侧站',height=0,
            precision='台湖站区取现状车辆段东侧试车线附近；OSM车辆段way/255022305与试车线way/1205979698核对地理范围。站位为约400米精度游戏参考，不以车辆段中心代替测绘站位。',
            description='从亦庄火车站沿既有入段走廊到试车线新增台湖站。公开工程运营里程约1.7公里，其中新建地面单线约0.3公里；游戏只复现公开连接及地面站，不恢复车辆段门槛，不把示意双向轨道说成实际双线。',
            coverage='beijing-yizhuang-taihu-infill'),
        dict(project='bj-line15-guozhan-infill',plan='bj-line15-guozhan-build',line='beijing-line15-15',color='#653279',
            title='15号线新国展二期加站',source=GUOZHAN,date='2026-07-21',extra=[GUOZHAN_EIA],
            names=['国展','新国展二期','花梨坎'],ids=['beijing-s14','beijing-future-guozhan2','beijing-s15'],area='guozhan',form='高架两层侧式站',height=8,
            precision='新站取首都国际会展中心东登录厅正对面的既有15号线高架走廊；会展中心OSM way/478555869、relation/18747310与既有轨道way/92598997核对，站名仍为工程称呼、站中心为约250米精度近似。',
            description='在国展—花梨坎现有高架区间增设一站；站体形式采用批复和2026年9月环评公开描述，保留两座展馆连廊说明。连廊通往场馆，不是另一条地铁，不生成假换乘。站名“新国展二期”为工程称呼，成果为规划建设完成。',
            coverage='beijing15-guozhan-infill'),
        dict(project='bj-airport-wangjingnan-infill',plan='bj-airport-wangjingnan-build',line='beijing-route-23',color='#9B91B1',
            title='首都机场线望京南加站与天桥换乘',source=WANGJING,date='2026-04-07',extra=[WANGJING_EIA,WANGJING_SCOPE],
            names=['三元桥','望京南','3号航站楼'],ids=['beijing-s174','beijing-s271','beijing-s207'],area='airport',form='高架三层侧式站',height=12,
            precision='机场线站体位于京密路与广顺南大街／万红西街交口南侧既有高架轨道上，单独的机场线站区参考[39.9828,116.47635]。14号线地下站位置保持原样；跨路天桥为换乘联系，不是列车轨道。',
            description='沿既有机场线高架增设独立望京南站，分别核对去T3和由T2返回的共用干线，再明确建立与14号线的天桥联系。站厅、换乘层及站台层来自公开环评；高度为游戏示意。只完成建设方案，不提前开放该站。',
            coverage='beijing-airport-wangjingnan-outbound'),
    ]
    references=read('data/reference_alignments.json'); handler=RailWays();handler.apply_file(str(PBF),locations=True)
    sha=hashlib.sha256(PBF.read_bytes()).hexdigest(); evidence=[]
    for case in cases:
        pid=case['project']; ids=case['ids'];line=case['line'];new_id=ids[-1] if case['area']=='taihu' else ids[1]
        instances = {sid:sid for sid in ids}
        if case['area']=='airport':instances.update({'beijing-s174':'beijing-s174__line23','beijing-s271':physical})
        stations=[]
        for sid,name in zip(ids,case['names']):
            if sid in ['beijing-future-taihu','beijing-future-guozhan2']:
                stations.append(dict(id=sid,name=name,latlng=coords[sid],coordinateSource='official_project_statement_and_local_road_geometry',coordinateAccuracyM=400 if case['area']=='taihu' else 250,coordinateNote=case['precision'],source=case['source']))
            else:stations.append(dict(id=sid,name=name,existing=True))
        group=dict(key='outbound' if case['area']=='airport' else 'main',mapRouteId='beijing-future-'+pid,
            coverageGroupId=case['coverage'],historicalLineId=line,name=case['title'],color=case['color'],stationIds=ids,
            stationInstances=instances,toleranceM=450,alignmentPrecision='station_areas_and_approximate_corridor',precisionNote=case['precision'],stationOrderSource=case['source'],constructionVariant=True,stationNamingSource=case['source'])
        if case['area']=='airport':group['maxSpacingM']=18000  # Real airport gap; never invent intermediate stations.
        if case['area']!='taihu':group['connectionMode']='infill'
        groups=[group];transfers=[]
        if case['area']=='airport':
            # Preserve independent geographic reference for the new physical body.
            # The logical station identity remains shared with Line 14.
            stations.append(dict(id='beijing-s208',name='2号航站楼',existing=True))
            stations.append(dict(id='beijing-airport-wangjingnan',name='望京南',latlng=coords['beijing-airport-wangjingnan'],coordinateSource='official_project_statement_and_local_road_geometry',coordinateAccuracyM=250,coordinateNote=case['precision'],source=WANGJING))
            group['stationReferenceIds']={'beijing-s271':'beijing-airport-wangjingnan'}
            return_group=dict(group,key='return',mapRouteId='beijing-future-airport-return',coverageGroupId='beijing-airport-wangjingnan-return',stationIds=['beijing-s208','beijing-s271','beijing-s174'],stationInstances={'beijing-s208':'beijing-s208','beijing-s271':physical,'beijing-s174':'beijing-s174__line23'},name='机场线望京南：T2返回干线')
            groups.append(return_group)
            transfers=[dict(id='future-transfer-airport-wangjingnan-14',name='望京南天桥换乘',complexId='beijing-s271',lineIds=[line,'beijing-line14-14'],stationInstanceIds=[physical,'beijing-s271'],source=WANGJING_EIA,sourceNote='公开环评PDF第16页：独立三层高架站，通过天桥接14号线C口；不共用地下站体，不将天桥放入列车轨道图。')]
        body=instances[new_id]
        plan=dict(id=case['plan'],title=case['title'],date='2026-10-01',status='approved_and_under_construction' if case['area']!='guozhan' else 'approved',projectType='approved_and_under_construction' if case['area']!='guozhan' else 'approved_project',required=True,sourceType='official_infill_project',source=case['source'],sourceTitle=case['title'],sourcePublicationDate=case['date'],sourceCheckedAt='2026-10-26',exactAlignment='station_areas',description=case['description'],additionalSources=case['extra'],contentRevision=REV,contentRevisionNote='补齐三项截止日前已公开的加站工程；不覆盖现状服务，不编造未来开放日期。',stationProfiles={body:dict(id=pid+'-profile',form=case['form'],depthM=case['height'],parameterStatus={'form':'public_reference','depthM':'game_estimate'},parameterSources={'form':case['extra'][-1] if case['area']=='taihu' else case['source']},note=case['description']+' 显示高度与站体矩形为游戏示意。')})
        spec=dict(city='beijing',projectIds=[pid],stations=stations,lineGroups=groups,transfers=transfers,plan=plan)
        write('tools/project_specs/'+pid+'.json',spec)
        baseline=read('data/network_baselines_2026-10-01.json');roster=baseline['cities']['beijing']['projectsAtCutoff']
        roster[:]=[p for p in roster if p['id']!=pid]+[dict(id=pid,name=case['title'],projectType=plan['projectType'],status='截止日前已公开实施范围',source=case['source'],sourceTitle=case['title'],sourceCheckedAt='2026-10-26',statusAtCutoff='已批在建' if case['area']!='guozhan' else '已批准',note=case['description'])]
        write('data/network_baselines_2026-10-01.json',baseline)
        subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/'tools/project_specs'/(pid+'.json'))],cwd=ROOT,check=True)
        target=dict(id=pid,reviewStatus='verified',source=case['source'],sourcePublicationDate=case['date'],sourceCheckedAt='2026-10-26',additionalSources=case['extra'],constructionOnly=True,groups=[],transfers=[t['id'] for t in transfers],transferReviewStatus='verified',note=case['description'])
        # Independent scope answer: explicitly transcribed project orders.
        orders={'taihu':[['亦庄火车站','台湖']], 'guozhan':[['国展','新国展二期','花梨坎']], 'airport':[['三元桥','望京南','3号航站楼'],['2号航站楼','望京南','三元桥']]}[case['area']]
        for g,names in zip(groups,orders):target['groups'].append(dict(id=g['coverageGroupId'],historicalLineId=line,scopeType='stations',stationNames=names,allowReverse=True,matchScope='contiguous_subsequence',stationNamingSource=case['source']))
        official=read('data/official_targets_2026-10-01.json');bj=official['cities']['beijing'];bj['projects']=[p for p in bj['projects'] if p['id']!=pid]+[target]
        if pid not in bj['requiredProjectIds']:bj['requiredProjectIds'].append(pid)
        write('data/official_targets_2026-10-01.json',official)
        geo_pairs=[]
        for g in groups:
            for a,b in zip(g['stationIds'],g['stationIds'][1:]):
                a_ll=coords['beijing-airport-wangjingnan'] if a=='beijing-s271' and case['area']=='airport' else coords[a]
                b_ll=coords['beijing-airport-wangjingnan'] if b=='beijing-s271' and case['area']=='airport' else coords[b]
                points,ways=rail_path(handler.rows[case['area']],a_ll,b_ll)
                refa=g.get('stationReferenceIds',{}).get(a,a);refb=g.get('stationReferenceIds',{}).get(b,b)
                rid=refa+'__'+refb
                old=[x for x in references['alignments'] if x.get('fromId')==refa and x.get('toId')==refb]
                if any(x.get('projectSource')!=case['source'] for x in old):raise ValueError('Do not overwrite an older reference pair '+rid)
                references['alignments']=[x for x in references['alignments'] if not (x.get('projectSource')==case['source'] and x.get('fromId') in [a,refa] and x.get('toId') in [b,refb])]
                references['alignments'].append(dict(id=rid,cityId='beijing',fromId=refa,toId=refb,historicalLineId=line,points=points,coordinateSystem='EPSG:4326',precision='approximate_corridor',sourceAccuracyM=None,sourceWayIds=ways,source='https://download.geofabrik.de/asia/china.html',sourceFile=PBF.name,sourceSha256=sha,sourceDate='2026-10-09',checkedAt='2026-10-26',amapReview='pending',historicalReview='planned_reuse_of_existing_rail_corridor',projectSource=case['source'],note='现有许可轨道走廊仅作加站地理参考；不等于未来施工中心线。'+case['precision']))
                geo_pairs.append(dict(fromId=refa,toId=refb,sourceWayIds=ways,pointCount=len(points),lengthM=round(sum(distance_m(x,y) for x,y in zip(points,points[1:])))))
        evidence.append(dict(projectId=pid,source=case['source'],publicationDate=case['date'],stationOrders=orders,additionalSources=case['extra'],existingRailReferencePairs=geo_pairs,coordinatePrecision=case['precision']))
    # Keep the existing compact representation; do not reformat the entire
    # older geometry resource or change its source version.
    (ROOT/'data/reference_alignments.json').write_text(json.dumps(references,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf8')
    write('data/official_evidence/beijing_infill_projects_review.json',dict(cutoff='2026-10-01',checkedAt='2026-10-26',projects=evidence,airportEiaPdfPage=16,airportEiaSha256='43e448ae030d8c6acd36444b1f71818df852bff1ab12b65c3146fe571d8fe5df',note='Station forms from approvals/EIA; footprint/rail geometry is geographic corroboration, not a surveyed station centre. Exhibition footbridges are not metro transfer edges.'))
    print('THREE INFILL PROJECTS: explicit station orders, independent airport body and transfer; existing service retained')


if __name__=='__main__':main()
