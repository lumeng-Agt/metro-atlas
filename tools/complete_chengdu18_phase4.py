"""Materialize the two separate, publicly named phase-4 construction scopes.

The official station order is authored below, independently of the existing
campaign. Road/facility coordinates are approximate site references only.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.24.9'
SOURCE = 'https://k.sina.cn/article_1905843503_7198dd2f02001fwk6.html'
RESPONSE = 'https://m.thepaper.cn/newsDetail_forward_17773463'
S11 = 'https://sthjt.sc.gov.cn/sthjt/c103939/2023/9/19/e7deb5b4a13c419591fffdedc2356a71/files/公示本.pdf'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def write(path, value):
    (ROOT / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    spec = {
        'city': 'chengdu', 'projectIds': ['cd-line18-phase4'],
        'stations': [
            {'id': 'chengdu-s22', 'name': '火车北站', 'existing': True},
            {'id': 'chengdu-s340', 'name': '双水碾', 'existing': True},
            {'id': 'chengdu-f18p4-fenghuangshan', 'name': '凤凰山',
             'latlng': [30.7332904, 104.0728334], 'coordinateAccuracyM': 500,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '站名、顺序据四川发布；以北星大道/熊猫大道西段交点（OSM ways517830656/974076328）及成德线环评中的共址走廊作近似参考，非18号线定点或隧道测绘。'},
            {'id': 'chengdu-f18p4-liminlu', 'name': '利民路',
             'latlng': [30.7550326, 104.0805032], 'coordinateAccuracyM': 650,
             'coordinateSource': 'local_road_geometry',
             'coordinateNote': '站名与顺序据四川发布；以停车场北侧利民路片区（OSM ways353999817/179764931）作近似站区，不能将该路口称作官方站位。出入线可兼正线，未公开各站间精确长度。'},
            {'id': 'chengdu-f18p3-guanyan', 'name': '官堰', 'existing': True},
            {'id': 'chengdu-f18p4-jianyangsouth', 'name': '简阳南',
             'latlng': [30.3563573, 104.515732], 'coordinateAccuracyM': 700,
             'coordinateSource': 'official_project_statement_and_local_road_geometry',
             'coordinateNote': '成都轨道集团公开答复指出官堰延伸至高铁简阳南站。以国铁枢纽OSM node3500462638附近作地铁独立站区参考，不把国铁站房中心当作地铁站体精确坐标。'}],
        'lineGroups': [
            {'key': 'north', 'mapRouteId': 'chengdu-future-line18-phase4-north',
             'coverageGroupId': 'chengdu-line18-phase4-north',
             'name': '18号线四期北段', 'historicalLineId': 'chengdu-line18-13',
             'color': '#00A4A9',
             'stationIds': ['chengdu-s22', 'chengdu-s340', 'chengdu-f18p4-fenghuangshan', 'chengdu-f18p4-liminlu'],
             'stationInstances': {'chengdu-s22': 'chengdu-s22__line18-13', 'chengdu-s340': 'chengdu-s340__line18-13'},
             'toleranceM': 700, 'alignmentPrecision': 'station_areas_and_approximate_corridor',
             'precisionNote': '公布北段3座新站全部进入任务，复用三期火车北站接头；道路参考站区及区间为近似，凤凰山与利民路不作精确线位评价。',
             'stationOrderSource': SOURCE},
            {'key': 'east', 'mapRouteId': 'chengdu-future-line18-phase4-east',
             'coverageGroupId': 'chengdu-line18-phase4-east',
             'name': '18号线四期东段', 'historicalLineId': 'chengdu-line18-13',
             'color': '#00A4A9',
             'stationIds': ['chengdu-f18p3-guanyan', 'chengdu-f18p4-jianyangsouth'],
             'stationInstances': {'chengdu-f18p3-guanyan': 'chengdu-f18p3-guanyan__line18-13'},
             'toleranceM': 700, 'alignmentPrecision': 'station_areas_and_approximate_corridor',
             'precisionNote': '东段接出三期官堰至简阳南地铁站区，独立于北段；不将两段间虚构为本期新增线路，不编造未来开通日期。',
             'stationOrderSource': SOURCE}],
        'transfers': [
            {'id': 'future-transfer-cd18-shuangshuinian-27', 'name': '双水碾',
             'complexId': 'chengdu-s340',
             'stationInstanceIds': ['chengdu-s340', 'chengdu-s340__line18-13'],
             'lineIds': ['chengdu-line27-15', 'chengdu-line18-13'],
             'sourceNote': '按四期工程概况及既有27号线站序，建立独立线路站体的换乘联系。凤凰山成德线、简阳南国铁接驳另属背景，不冒充已建地铁换乘。'}],
        'plan': {'id': 'cd-line18-phase4-build', 'title': '18号线四期：北段与简阳南东段',
                 'date': '2026-10-01', 'status': 'approved_preparatory', 'projectType': 'approved_preparatory',
                 'sourceType': 'provincial_government_information_office_project_scope',
                 'required': True, 'source': SOURCE,
                 'sourceTitle': '四川省政府新闻办四川发布2025-11-06：18号线四期工程概况',
                 'sourcePublicationDate': '2025-11-06', 'sourceCheckedAt': '2026-10-24',
                 'description': '分别建设北段双水碾、凤凰山、利民路及东段简阳南4座新站，复用三期两端。公布正线7.335千米、出入线约1.886千米可兼正线；不把节能审查当作开工或运营许可，站位仍为公开地理参考。',
                 'contentRevision': REVISION, 'requiresScopeRecheck': True,
                 'contentRevisionNote': '补齐18号线四期公开4座新站，北、东两段分别建设，保留既有与规划开放状态。'}}
    write('tools/project_specs/cd-line18-phase4.json', spec)
    subprocess.run([sys.executable, str(ROOT / 'tools/add_project_plan.py'),
                    str(ROOT / 'tools/project_specs/cd-line18-phase4.json'), '--check'], check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/add_project_plan.py'),
                    str(ROOT / 'tools/project_specs/cd-line18-phase4.json')], check=True)

    baseline = read('data/network_baselines_2026-10-01.json')
    projects = baseline['cities']['chengdu']['projectsAtCutoff']
    row = {'id': 'cd-line18-phase4', 'name': '18号线四期（北段及简阳南东段）',
           'projectType': 'approved_preparatory', 'statusAtCutoff': '第五期项目，前期工作',
           'source': SOURCE, 'sourceTitle': spec['plan']['sourceTitle'],
           'sourceCheckedAt': '2026-10-24', 'playabilityStatus': 'playable_build_task',
           'note': '4座公布新站全部制作；两段独立复用三期接头。不得将节能审查记为开放，国铁和市域接驳不计作已建地铁换乘。'}
    projects[:] = [p for p in projects if p['id'] != row['id']] + [row]
    write('data/network_baselines_2026-10-01.json', baseline)

    official = read('data/official_targets_2026-10-01.json')
    city = official['cities']['chengdu']
    # Expected orders are the published list above, not a projection of the
    # generated task station IDs. Both scopes must exist in the built world.
    target = {'id': 'cd-line18-phase4', 'reviewStatus': 'verified',
              'constructionOnly': True, 'source': SOURCE,
              'sourcePublicationDate': '2025-11-06', 'sourceCheckedAt': '2026-10-24',
              'additionalSources': [RESPONSE, S11],
              'scopeNote': '北段3新站、东段1新站；火车北与官堰为前期接头，不重复计入4座新站。位置为近似，不虚构地铁测绘。',
              'groups': [
                  {'id': 'chengdu-line18-phase4-north', 'historicalLineId': 'chengdu-line18-13',
                   'scopeType': 'stations', 'stationNames': ['火车北站', '双水碾', '凤凰山', '利民路'], 'allowReverse': True},
                  {'id': 'chengdu-line18-phase4-east', 'historicalLineId': 'chengdu-line18-13',
                   'scopeType': 'stations', 'stationNames': ['官堰', '简阳南'], 'allowReverse': True}],
              'transfers': ['future-transfer-cd18-shuangshuinian-27']}
    city['projects'] = [p for p in city['projects'] if p['id'] != target['id']] + [target]
    if target['id'] not in city['requiredProjectIds']:
        city['requiredProjectIds'].append(target['id'])
    write('data/official_targets_2026-10-01.json', official)
    print('18 phase 4: two independently checked scopes, four new stations')


if __name__ == '__main__':
    main()
