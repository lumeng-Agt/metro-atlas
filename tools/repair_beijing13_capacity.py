"""Author the full 13A/13B works from the archived primary EIA, not a map snapshot.

Station orders below were transcribed from the 2021 report. The 2025 naming
decision supplies aliases. Existing platform identities come from the current
geographic catalogue only; they do not generate the independent answer.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EIA = 'https://www.bii.com.cn/Portals/0/AttachUpload/pdf/2021102114294985.pdf'
ARCHIVE = 'https://web.archive.org/web/20211023062003id_/https://www.bii.com.cn/Portals/0/AttachUpload/pdf/2021102114294985.pdf'
NAMING = 'https://www.beijing.gov.cn/ywdt/gzdt/202508/t20250821_4179115.html'
RENAMING = 'https://yewu.ghzrzyw.beijing.gov.cn/zkdncms/cxghphgsdmgg/esSearchDetail/31f464cd7a73878d2e5efed190a8559e'
APPROVAL = 'https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202105/t20210528_2401129.htm'
A_ORDER = ['车公庄','西直门','四道口','大钟寺','知春路','保福寺','五道口','清华东路西口','上地','清河','西二旗','龙泽西','回龙观西大街','文华路','回龙观东大街','霍营东','天通苑','太平庄','天通苑东']
B_ORDER = ['马连洼','上地软件园','东北旺','龙泽西','龙泽','回龙观','霍营','东小口','立水桥','北苑','望京西','芍药居','光熙门','柳芳','东直门']


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    catalog = read(ROOT / 'data/campaigns.json')['cities']['beijing']
    city = next(c for c in read(ROOT / 'data/cities.json')['cities'] if c['id'] == 'beijing')
    geography = {s['id']: s for s in city['stations']}
    cutoff = next(c for c in catalog['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    groups = cutoff['lineGroups']

    def stop(line, name):
        for g in groups:
            if g['historicalLineId'] != line:
                continue
            for id_ in g['stationIds']:
                label = g.get('stationNames', {}).get(id_, geography[id_]['name'])
                if label == name or (name == '清河' and label == '清河站'):
                    return id_, g.get('stationInstances', {}).get(id_, id_)
        raise ValueError((line, name))

    line13, line18 = 'beijing-line13-13', 'beijing-line18-18'
    declared = {}

    def existing(line, old_name, scheme_name=None):
        id_, body = stop(line, old_name)
        declared[id_] = dict(id=id_, name=scheme_name or old_name, existing=True)
        return id_, body

    a, b = {}, {}
    for name in ['大钟寺','知春路','五道口','上地','清河','西二旗']:
        a[name] = existing(line13, name)
    for name in ['回龙观西大街','文华路','回龙观东大街','霍营东','天通苑','太平庄','天通苑东']:
        a[name] = existing(line18, name)
    for name in ['马连洼','上地软件园','东北旺']:
        b[name] = existing(line18, name)
    # Current first-opening labels remain intact. The ultimate construction
    # scheme carries its own sourced name instead of renaming the open body.
    a['龙泽西'] = existing(line18, '龙泽西', '龙泽西')
    b['龙泽西'] = (a['龙泽西'][0], a['龙泽西'][0] + '__capacity13B')
    for name in ['回龙观','霍营','立水桥','北苑','望京西','芍药居','光熙门','柳芳','东直门']:
        b[name] = existing(line13, name)
    for name, host_line in [('车公庄','beijing-lineearly1'),('西直门','beijing-lineearly1'),('清华东路西口','beijing-line15-15')]:
        id_, _ = existing(host_line, name)
        a[name] = (id_, id_ + '__capacity13A')
    # These are licensed geographic references checked against the official
    # street descriptions, not map-marker coordinates labelled as a survey.
    for name, id_, point, note in [
        ('四道口','beijing-cap13-sidaokou',[39.9567418,116.3418538], '学院南路与四道口片区，参考本地OSM旧道口节点1748306003及2025公示道路关系；站体中心近似。'),
        ('保福寺','beijing-cap13-baofusi',[39.9847699,116.3321537], '北四环南侧既有13号线高架走廊，本地OSM节点3060379046／way122090412；不是公示地图标签中心或工程测绘。'),
        ('东小口','beijing-cap13-dongxiaokou',[40.0619197,116.38003], '建材城东路北侧既有13号线走廊，本地OSM节点1090671700／way1485871543；位置近似，不采用同名村落或公交站中心。')]:
        declared[id_] = dict(id=id_, name=name, latlng=point, coordinateSource='official_project_statement_and_local_road_geometry', coordinateNote=note, source=NAMING)
        (b if name == '东小口' else a)[name] = (id_, id_ + ('__capacity13B' if name == '东小口' else '__capacity13A'))
    old_longze, _ = existing(line13, '龙泽')
    # The 2025 decision explicitly locates the rebuilt station ~110m east of
    # the old one. Preserve the old station and give the new body its own site.
    latitude, longitude = geography[old_longze]['latlng']
    import math
    rebuilt_point = [latitude, longitude + 110 / (111320 * math.cos(math.radians(latitude)))]
    rebuilt_id = 'beijing-cap13-longze-rebuild-reference'
    declared[rebuilt_id] = dict(id=rebuilt_id, name='龙泽重建站参考点', latlng=rebuilt_point, coordinateSource='official_site_description', coordinateNote='依据2025定名说明的旧站东侧约110米构造近似站区参考点；不是工程坐标，不移动旧龙泽站。', source=NAMING)
    b['龙泽'] = (old_longze, old_longze + '__capacity13B-rebuilt')
    scheme_groups = []
    note = '2021环评19站13A及15站13B完整范围，2025定名并采用12月龙泽西更名公告；复用已有站轨，南部与重建站体单独建设。高程、站体尺寸与站外连接为游戏示意；不宣称施工线位精度。规划名称另存，当前开放站名和服务保留。'
    for key, order, bindings, color, length in [('A', A_ORDER, a, '#F6D547', 31200), ('B', B_ORDER, b, '#DFB133', 32200)]:
        scheme_groups.append(dict(key=key, mapRouteId=f'beijing-future-capacity13{key}', name=f'13{key}线扩能最终建设关系', historicalLineId=f'beijing-capacity13{key}', color=color,
                                  stationIds=[bindings[n][0] for n in order], stationInstances={bindings[n][0]:bindings[n][1] for n in order}, toleranceM=250, alignmentPrecision='corridor_only', precisionNote=note,
                                  stationOrderSource=EIA, stationNamingSource=NAMING, stationNamingSources=[NAMING,RENAMING], constructionVariant=True, officialLengthM=length))
    scheme_groups[1]['stationReferenceIds'] = {old_longze: rebuilt_id}
    # Interchange inventory is a distinct review. These are explicit physical
    # pairings, never track connections or a claim that the planned lines run.
    transfers = []
    def transfer(key, name, other_line, other_name=None):
        bindings = a if key == 'A' else b
        id_, project_body = bindings[name]
        _, other_body = stop(other_line, other_name or name)
        transfers.append(dict(id=f'future-transfer-bj13{key}-{name}-{other_line}', name=name, complexId=id_, stationInstanceIds=[project_body,other_body], lineIds=[f'beijing-capacity13{key}',other_line], source=EIA,
                              sourceNote='环评逐站换乘关系与现有线路身份对照；规划线路未开放，站体独立，换乘联系不进入轨道图。'))
    for name, other_line in [('车公庄','beijing-lineearly1'),('车公庄','beijing-line6-6'),('西直门','beijing-lineearly1'),('西直门','beijing-line4-4'),('大钟寺','beijing-line12-12'),('知春路','beijing-line10-10'),('清华东路西口','beijing-line15-15'),('清河','beijing-route-20'),('西二旗','beijing-route-20'),('回龙观东大街','beijing-line8-8'),('天通苑','beijing-line5-5'),('天通苑东','beijing-line17-17')]:
        transfer('A',name,other_line,'清河' if name=='清河' else None)
    for name, other_line in [('马连洼','beijing-line16-16'),('霍营','beijing-line8-8'),('立水桥','beijing-line5-5'),('望京西','beijing-line15-15'),('望京西','beijing-line17-17'),('芍药居','beijing-line10-10'),('东直门','beijing-lineearly1'),('东直门','beijing-route-23')]:
        transfer('B',name,other_line)
    transfers.append(dict(id='future-transfer-bj13capacity-newlongze',name='龙泽西（环评新龙泽）',complexId=a['龙泽西'][0],stationInstanceIds=[a['龙泽西'][1],b['龙泽西'][1]],lineIds=['beijing-capacity13A','beijing-capacity13B'],source=EIA,sourceNote='环评76、80—81页双岛四线结构，两线各绑定站体；同台换乘不等于共轨。'))
    spec = dict(city='beijing', projectIds=['bj-line13-capacity'], stations=list(declared.values()), lineGroups=scheme_groups, transfers=transfers,
                plan=dict(id='bj-line13-capacity-build',title='13号线扩能提升 · 两条L形线路',date='2026-10-01',status='under_construction',projectType='under_construction',sourceType='operator_environmental_impact_report',source=EIA,sourceArchive=ARCHIVE,
                          sourceTitle='北京轨道交通13号线扩能提升工程环境影响报告书（2021全文）及2025定名',sourcePublicationDate='2021-10-21',sourceCheckedAt='2026-10-25',description=note,
                          contentRevision='2026.10.25.12',requiresScopeRecheck=True,requiresLineReorganization=True,operationType='reorganization',operationGuide='复用既有站轨，补齐新增段和独立站体，再在「线路整理」核对两条L形路径；当前运营范围保留，成果为规划建设完成。',additionalSources=[APPROVAL,NAMING,RENAMING],required=True))
    write(ROOT / 'tools/project_specs/bj-line13-capacity.json', spec)
    print('AUTHORED_REVIEW_SPEC bj-line13-capacity: 19 + 15 station targets; no world or completion state changed')


if __name__ == '__main__':
    main()
