"""Attach independent transfer structures to reviewed future projects.

The interchange list of a project is an official claim: which stations exchange
with which lines. `transferDefinitions` adds the physical pairing the runtime
must actually hold, so a correct station name wired to the wrong platform body
cannot pass.

Division of evidence:
  * station + paired line  -> transcribed from an official https document,
                              quoted and located in the review file;
  * physical body pairing  -> the engine's own fact. A definition may not invent
                              a body that the project does not build.
The two are kept apart on purpose: the official document never says which game
body carries a platform.

A project is only marked reviewed when every required pair is documented and
every further interchange named by the same documents is either required or
excluded for a stated reason (the line has no body in this game, or another
project's chapter already requires that connection). Projects with unproven
pairs keep `pending` and receive a note naming them.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEWED_AT = '2026-10-28'

BJ13 = 'data/official_evidence/beijing13_capacity_and_m101_transfer_review_2026-10-28.json'
SHBJ = 'data/official_evidence/shanghai19_and_beijing22_28_transfer_review_2026-10-28.json'
BJ11 = 'data/official_evidence/beijing11_phase2_and_yizhuang_transfer_review_2026-10-28.json'

NOTES = {
    'bj-m101-phase1': (BJ13, 'verified',
        '按M101一期环评、2022-04-20线路图稿与2024-07-17首都之窗逐站换乘清单核对：城市副中心枢纽与6号线、'
        '22号线两对均有原文点名，站体按项目实际建设分别记录。同一批文件还列出通州西（M102、通密线）、'
        '龙旺庄（R1）、通胡大街（M103）、北京大剧院（M104）、张家湾（M102/M104）五处换乘，'
        '这些线路在本作没有线体，记录为范围外，不计入要求，也不冒充已建换乘。'),
    'bj-line28': (SHBJ, 'verified',
        '按2021-07-27北京市重大项目办“9座车站5座可换乘”逐站清单、2020-09-11发改委批复稿、'
        '2024-01-06首都之窗京广桥三线换乘与2025-08-01线路一体化规划公示核对：8对换乘全部有原文点名。'
        '同一批文件另列光华路（规划R4）、大望路（规划R1），这两条为区域快线、本作没有线体，记录为范围外；'
        '茂兴西路官方未写出对方线路，不臆造配对。'),
    'bj-line22': (SHBJ, 'verified',
        '按2026-08-25空载试运行稿、2026-09-24站名公布稿、2020-09-11发改委批复稿逐站核对：'
        '红庙14、管庄1号线（八通线）、运河6、北运河东6、东大桥6、东大桥17、金台夕照10共7对全部有原文点名。'
        '官方同稿写东大桥还可换乘28号线；该线体由28号线项目章节建立并要求东大桥—22号线这一对，'
        '故不在本项目重复要求，也不作为漏项。城市副中心与京唐城际的国铁联系属范围外背景。'),
    'bj-line13-capacity': (BJ13, 'pending',
        '已独立复核21对中的17对（环评逐站点名11对，另6对由官方网页补齐）。仍未取得点名的4对是'
        '知春路—10号线、霍营—8号线、立水桥—5号线、芍药居—10号线：环评把这些站当作既有站改造，'
        '没有重述换乘线路，不能凭常识补。另发现光熙门—12号线这一对官方已点名（2024-03-21首都之窗）'
        '但本项目清单未列。因此不标已核对，待补站级来源与光熙门一对后再评。'),
    'bj-line11-phase2': (BJ11, 'pending',
        '已独立复核7对中的6对：体育场南街—1号线支线、北京西站—7号线、北京西站—9号线、'
        '丽泽商务区—14/16/大兴机场线均有原文点名（环评第98页“与M7、M9线换乘”等）。'
        '莲花桥—10号线只有“换乘站”标注，没有点名10号线的官方句子，故不标已核对。'
        '另：官方把丽金线列为丽泽五线换乘之一，本作没有丽金线线体，记录为范围外。'),
    'sh-line19': (SHBJ, 'pending',
        '已独立复核13对中的6对：华泾西—15、东方体育中心—6/8/11、浦东南路—2、浦东南路—14、'
        '华泾路—23、江杨南路—18有官方点名。其余7对（凌兆新村8、后滩7、世博大道13、塘桥4、'
        '商城路9、提篮桥12、海伦路4/10）没有站级官方文件点名；原先当作主来源的czj文件实为债券'
        '信用评级报告，只写“18座换乘站”不逐站列线，19号线工可与初设批复未公开，故不标已核对。'),
    'bj-yizhuang-connector': (BJ11, 'pending',
        '本工程不新增客运车站（可研批复“不新增运营里程，无新增站点”，环评“无新建、改（扩）建场站”），'
        '但并非不改变换乘：批复要求“改造亦庄线宋家庄站，优化与10号线换乘条件”，环评第19页写明3.6万人次'
        '改为同台换乘（10号线西向东方向与亦五贯通线南向北方向）、6.5万人次由三线“T”形换乘改为两线“平行”换乘。'
        '复核运行世界后确认本项目不产生新的站体对：贯通线在宋家庄复用5号线站体（beijing-s119__line5-5），'
        '与10号线站体之间的active换乘已在2012里程碑章建立，因此“新增要求条数”确实为0，不是漏项。'
        '仍不能标已核对的原因只剩一项：官方要求的具体形式是“同台”，而现有transferKind只有站内换乘与出闸换乘两种，'
        '无法把站台布置写入数据；若另立一条同站体对换乘，既重复既有物理配对，也违反工程类章节'
        '“不得凭空新增active换乘”的独立规格规则。故保持pending，并把它记为建模能力缺口而不是转录缺口。'),
}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def resolve_source(review, locator):
    """Pick the cited document from the locator's publication date."""
    hits = [s for s in review.get('sources', [])
            if s.get('publicationDate') and s['publicationDate'] in str(locator) and str(s.get('url', '')).startswith('https://')]
    if len(hits) != 1:
        raise SystemExit(f'cannot resolve one https source for locator: {locator} ({len(hits)} hits)')
    return hits[0]['url']


def build_definitions(city, project_id, review, plans):
    wanted = set(project_id_transfers(city, project_id))
    by_id = {}
    for plan in plans:
        for pair in plan.get('requiredTransfers', []):
            if pair.get('id') in wanted:
                by_id[pair['id']] = pair
    if set(by_id) != wanted:
        raise SystemExit(f'{project_id}: {len(wanted - set(by_id))} required transfer(s) have no chapter entry')
    evidence = {row['id']: row for row in review.get('pairs', [])}
    definitions = []
    for transfer_id in project_id_transfers(city, project_id):
        pair = by_id[transfer_id]
        row = evidence.get(transfer_id)
        if not row or not row.get('documented'):
            raise SystemExit(f'{project_id}: {transfer_id} is not documented, refusing to define it')
        definition = {
            'id': transfer_id,
            'name': pair.get('name', ''),
            'complexId': pair.get('complexId', ''),
            'lineIds': pair.get('lineIds', []),
            'stationInstanceIds': pair.get('stationInstanceIds', []),
            'precision': pair.get('precision', 'schematic'),
            'source': resolve_source(review, row.get('locator', '')),
            'reviewLocator': row.get('locator', ''),
            'reviewQuote': row.get('quote', ''),
        }
        if 'transferKind' in pair:
            definition['transferKind'] = pair['transferKind']
        definitions.append(definition)
    return definitions


def project_id_transfers(city, project_id):
    for project in city.get('projects', []):
        if project.get('id') == project_id:
            return project.get('transfers', [])
    raise SystemExit(f'{project_id}: not in the independent project roster')


def sync_engineering_spec(project):
    """An engineering spec keeps a byte-identical copy of its official target."""
    path = ROOT / 'tools/engineering_specs' / f'{project["id"]}.json'
    if not path.exists():
        return False
    spec = json.loads(path.read_text(encoding='utf-8'))
    if str(spec.get('officialTarget', {}).get('id', '')) != project['id']:
        return False
    if spec['officialTarget'] == project:
        return False
    spec['officialTarget'] = json.loads(json.dumps(project))
    path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return True


def main():
    targets = read('data/official_targets_2026-10-01.json')
    campaigns = read('data/campaigns.json')
    changed = 0
    for city_id, city in targets.get('cities', {}).items():
        plans = campaigns['cities'][city_id].get('futurePlans', [])
        for project in city.get('projects', []):
            project_id = project.get('id', '')
            if project_id not in NOTES:
                continue
            path, status, note = NOTES[project_id]
            review = read(path)['projects'][project_id]
            definitions = build_definitions(city, project_id, review, plans) if status == 'verified' else []
            already = (project.get('transferReviewStatus') == status
                       and project.get('transferReviewNote') == note
                       and (status != 'verified' or project.get('transferDefinitions', []) == definitions))
            if already:
                if sync_engineering_spec(project):
                    changed += 1
                    print(f'SYNCED_ENGINEERING_SPEC {project_id}')
                continue
            project['transferReviewNote'] = note
            if status == 'verified':
                project['transferDefinitions'] = definitions
                project['transferReviewStatus'] = 'verified'
            else:
                project['transferReviewStatus'] = 'pending'
            sync_engineering_spec(project)
            changed += 1
            print(f'{"VERIFIED" if status == "verified" else "STILL_PENDING"} {project_id} '
                  f'definitions={len(project.get("transferDefinitions", []))}')
    if not changed:
        print('ALREADY_REVIEWED no project transfer review changed')
        return
    write('data/official_targets_2026-10-01.json', targets)
    print('PROJECTS_UPDATED', changed)


if __name__ == '__main__':
    main()
