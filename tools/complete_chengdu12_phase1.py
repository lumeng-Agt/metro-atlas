"""Materialize the two Chengdu Line 12 phase-1 scopes that have published plans.

The 2026-08-26 EIA notice publishes only the extent of the project: 34.2 km,
28 stations, Pu'an to Shunhejiayuan, 13 interchanges. It carries no station
table. Two sections do have municipal detailed-planning announcements that fix
station positions:

  2026-08-12  Pu'an - Tonggang Road
  2026-08-14  Tiansheng Road - Guangming Village

Everything between and beyond those two sections is still unpublished, so this
tool builds the two published sections as separate tasks. It does not invent
the other 24 stations, and it does not connect the two sections with a made-up
corridor across the unpublished gap.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.27.3'
PLAN_PUAN = ('https://mpnr.chengdu.gov.cn/ghhzrzyj/kzxxgh/2026-08/12/'
             'content_41c22b9b0dfe480b9768ce96099c2f86.shtml')
PLAN_TIANSHENG = ('https://mpnr.chengdu.gov.cn/ghhzrzyj/kzxxgh/2026-08/14/'
                  'content_2af2add8e3224ef8a0b0772b8d5f05a8.shtml')
EIA = 'https://sina.cn/news/detail/5336287474091136.html'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    spec = {
        'city': 'chengdu', 'projectIds': ['cd-line12-phase1'],
        'stations': [
            {'id': 'chengdu-f12-puan', 'name': '普安',
             'latlng': [30.7865618, 103.8718141], 'coordinateAccuracyM': 150,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '2026-08-12详细规划公告：普安站位于西源大道与华港路北段交叉口附近。取西源大道（OSM way/849817405）与华港路（way/250862730）交点作站区近似，非站体中心测绘。',
             'source': PLAN_PUAN},
            {'id': 'chengdu-f12-tongganglu', 'name': '通港路',
             'latlng': [30.7800492, 103.8841247], 'coordinateAccuracyM': 150,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '同一详细规划公告：通港路站位于西源大道与正港路交叉口附近。取西源大道（way/849817405）与正港路（way/250862732）交点。',
             'source': PLAN_PUAN},
            {'id': 'chengdu-f12-tianshenglu', 'name': '天盛路',
             'latlng': [30.7678876, 103.900929], 'coordinateAccuracyM': 150,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '2026-08-14详细规划公告：天盛路站位于合信路与天盛路交叉口附近。取合信路（way/250861520）与天盛路（way/250861992）交点。',
             'source': PLAN_TIANSHENG},
            {'id': 'chengdu-f12-guangmingcun', 'name': '光明村',
             'latlng': [30.7599129, 103.9081635], 'coordinateAccuracyM': 150,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '同一详细规划公告：光明村站位于合信路与天彩路交叉口附近。取合信路（way/250861520）与天彩路（way/510945633）交点。',
             'source': PLAN_TIANSHENG}],
        'lineGroups': [
            {'key': 'puan', 'mapRouteId': 'chengdu-future-line12-phase1-puan',
             'coverageGroupId': 'chengdu-line12-phase1-puan',
             'name': '12号线一期：普安—通港路（已公示）',
             'historicalLineId': 'chengdu-line12', 'color': '#4B1F6F',
             'stationIds': ['chengdu-f12-puan', 'chengdu-f12-tongganglu'],
             'toleranceM': 250, 'alignmentPrecision': 'station_areas_and_approximate_corridor',
             'precisionNote': '两站位置来自2026-08-12详细规划公告的路口描述，站区约150米精度；区间线位未公布，按西源大道走廊示意，不冒充隧道中心线。',
             'stationOrderSource': PLAN_PUAN},
            {'key': 'tiansheng', 'mapRouteId': 'chengdu-future-line12-phase1-tiansheng',
             'coverageGroupId': 'chengdu-line12-phase1-tiansheng',
             'name': '12号线一期：天盛路—光明村（已公示）',
             'historicalLineId': 'chengdu-line12', 'color': '#4B1F6F',
             'stationIds': ['chengdu-f12-tianshenglu', 'chengdu-f12-guangmingcun'],
             'toleranceM': 250, 'alignmentPrecision': 'station_areas_and_approximate_corridor',
             'precisionNote': '两站位置来自2026-08-14详细规划公告的路口描述，站区约150米精度；区间线位未公布，按合信路走廊示意。',
             'stationOrderSource': PLAN_TIANSHENG}],
        'transfers': [],
        'plan': {'id': 'cd-line12-phase1-build',
                 'title': '12号线一期：已公示的西端两段',
                 'date': '2026-10-01', 'status': 'approved_preparatory',
                 'projectType': 'approved_preparatory',
                 'sourceType': 'municipal_planning_bureau_detail_plan_announcement',
                 'required': True, 'source': PLAN_PUAN,
                 'additionalSources': [PLAN_TIANSHENG, EIA],
                 'sourceTitle': '成都市规划和自然资源局2026-08-12：成都轨道交通12号线详细规划方案（普安站—通港路站）公告',
                 'sourcePublicationDate': '2026-08-12', 'sourceCheckedAt': '2026-10-27',
                 'description': '环评信息公开（2026-08-26）只公布全线34.2公里、28座车站、普安—舜和家园及13座换乘，没有站名表；仅普安—通港路、天盛路—光明村两段有详细规划公告确定站位。本任务只建设这两段共4座已公示车站，其余24座未公布车站不虚构、不连成假走廊；不把详细规划公示当作开工或运营许可。',
                 'contentRevision': REVISION, 'requiresScopeRecheck': True,
                 'contentRevisionNote': '补入成都12号线一期两段已公示详细规划，只建4座有官方路口的车站，未公布区段保留缺项。'}}
    write('tools/project_specs/cd-line12-phase1.json', spec)
    subprocess.run([sys.executable, str(ROOT / 'tools/add_project_plan.py'),
                    str(ROOT / 'tools/project_specs/cd-line12-phase1.json'), '--check'], check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/add_project_plan.py'),
                    str(ROOT / 'tools/project_specs/cd-line12-phase1.json')], check=True)

    baseline = read('data/network_baselines_2026-10-01.json')
    projects = baseline['cities']['chengdu']['projectsAtCutoff']
    row = {'id': 'cd-line12-phase1', 'name': '12号线一期（普安—舜和家园）',
           'projectType': 'approved_preparatory', 'status': '已立项，前期环评与设计',
           'statusAtCutoff': '已立项，前期环评与设计',
           'source': PLAN_PUAN, 'sourceTitle': spec['plan']['sourceTitle'],
           'sourceCheckedAt': '2026-10-27', 'playabilityStatus': 'playable_build_task',
           'note': '仅两段详细规划已公示，制作4座有官方路口的车站；其余24座车站与13座换乘未公布，保留缺项，不虚构站名与走廊。'}
    projects[:] = [p for p in projects if p['id'] != row['id']] + [row]
    write('data/network_baselines_2026-10-01.json', baseline)

    official = read('data/official_targets_2026-10-01.json')
    city = official['cities']['chengdu']
    # Only the two published sections are independently checked. The rest of
    # the 28-station line has no published order, so it stays a recorded gap
    # instead of being projected from the generated task.
    target = {'id': 'cd-line12-phase1', 'reviewStatus': 'verified',
              'constructionOnly': True, 'source': PLAN_PUAN,
              'sourcePublicationDate': '2026-08-12', 'sourceCheckedAt': '2026-10-27',
              'additionalSources': [PLAN_TIANSHENG, EIA],
              'scopeNote': '环评只公布34.2公里、28站、13换乘与端点，未发布站名表；只有普安—通港路、天盛路—光明村两段有详细规划公告。独立目标只核对这4站两段，其余24站与13座换乘登记为未公布，不得用第三方站表补成官方站序。',
              'groups': [
                  {'id': 'chengdu-line12-phase1-puan', 'historicalLineId': 'chengdu-line12',
                   'scopeType': 'stations', 'stationNames': ['普安', '通港路'], 'allowReverse': True},
                  {'id': 'chengdu-line12-phase1-tiansheng', 'historicalLineId': 'chengdu-line12',
                   'scopeType': 'stations', 'stationNames': ['天盛路', '光明村'], 'allowReverse': True}],
              'transfers': []}
    city['projects'] = [p for p in city['projects'] if p['id'] != target['id']] + [target]
    if target['id'] not in city['requiredProjectIds']:
        city['requiredProjectIds'].append(target['id'])
    write('data/official_targets_2026-10-01.json', official)
    print('12 phase 1: two published sections, four stations with official junctions')


if __name__ == '__main__':
    main()
