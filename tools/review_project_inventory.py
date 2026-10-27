"""Transcribe independently published project rosters for the five cities.

`sourceProjectInventory` answers a different question than a project's own
`source`: it is the roster of projects a city published, so a project cannot
disappear from the requirements simply because its task or ID was dropped.

A roster is only marked `verified` when every project this game requires is
either named in a published document or explicitly explained as outside that
document's scope. A city whose public list aggregates metro lines into one row
cannot support a project-level roster, and keeps `pending` with that reason.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEWED_AT = '2026-10-28'

SHGZ = 'data/official_evidence/shanghai_guangzhou_inventory_review_2026-10-28.json'
SZCDBJ = 'data/official_evidence/shenzhen_chengdu_beijing_inventory_review_2026-10-28.json'
GAP = 'data/official_evidence/shenzhen_chengdu_inventory_gap_review2_2026-10-28.json'

# Projects the annual key-project list omits but another dated official document
# names directly. They are added as roster rows from that document.
GAP_ROWS = {
    'shenzhen': ('sz-line10-east-shenzhen', 'sz-line11-north-shenzhen'),
    'chengdu': ('cd-line12-phase1',),
}

BJ_ROSTER_SOURCE = 'https://fgw.beijing.gov.cn/fgwzwgk/2024zcwj/ghjhwb/qt/202602/W020260203349484131373.pdf'
BJ_ROSTER_DATE = '2026-02-03'

# Rows that the Beijing key-project PDF does not itself name. Each is re-pointed
# at the document that does name it instead of being dropped from the roster.
BJ_ROW_SOURCES = {
    'bj-r4-north-phase1': (
        'https://fgw.beijing.gov.cn/fgwzwgk/ysqzzdgk/202501/t20250107_3982106.htm', '2025-01-07',
        '北京轨道交通R4线一期北段工程（京发改（审）〔2024〕1067号）'),
    'bj-line11-phase2': (
        'https://zdb.beijing.gov.cn/zfxxgk/zfxxgkzl/fdzdgknr/ghxx/202601/t20260114_4429896.html', '2026-01-14',
        '北京地铁11号线二期（型材—丽泽商务区）一体化规划方案批复'),
}

NOTES = {
    'shanghai': ('verified',
        '按《2026年上海市重大工程项目清单》（市发改委2026-02-12发布，正式项目184项）城市基础设施—'
        '轨道交通15项（序号132—146）逐条原文转录。11个必做项目中9个在清单内；'
        '18号线预留站（长江西路、江杨南路、爱辉路）与南京西路三线换乘通道不属年度重大工程列项对象，'
        '清单内无对应条目，其自身证据另存。清单另列市域线机场联络线、嘉闵线、示范区线、南汇支线等'
        '市域铁路，按干线口径报批，不属本作城市轨道交通范围，未列为必做。'),
    'guangzhou': ('verified',
        '按《广州市2026年重点建设项目计划》（市发改委2026-02-14，附件1印刷页2）5.城市轨道交通8项'
        '逐条原文转录。9个必做项目中8个在清单内；11号线广州火车站站为既有线未开通车站，'
        '清单正文与预备项目册均无该条目，其自身证据另存。清单另列城际铁路与车辆段更新改造，'
        '按干线铁路/非线路工程报批，不属本作范围。附件原始链接为 http，同域 https 返回200，故按 https 记录。'),
    'beijing': ('verified',
        '按《北京市2026年重点工程计划》（市发改委2026-02-03）第9—10页“（二）轨道交通（13项）”'
        '逐条原文转录13行；R4线一期北段与11号线二期在该册中分别属前期项目与规划批复事项，'
        '改引其各自的市发改委批复文件，不塞进轨道章。该册是年度重点工程计划，不等于全部已批建设项目，'
        '本标记只声明“已发布的年度清单已逐条转录”，不声明北京市全部项目清点完成。'),
    'shenzhen': ('verified',
        '按《深圳市2026年重大项目计划清单》（2026-02-28，832项）第46页地铁11条逐条转录，'
        '10号线东延（深圳段）与11号线北延（深圳段）不在该册，改引深圳市发改委2024-01-08公开件'
        '（批复方案共11条线路，含这两段，总长185.6公里），两段均落到原文点名。'
        '12个必做项目全部有带日期的官方记录。该册另列13号线二期（北延）等本作未建模项目与枢纽、'
        '城际、动车基地，按非本作范围处理。'),
    'chengdu': ('pending',
        '《成都市2026年市级政府投资项目计划》（成办发〔2026〕4号，2026-03-05）与《2026年成都市'
        '重点项目计划》（2026-01-30）对地铁均采用聚合口径，全表只有“成都市城市轨道交通续建项目”'
        '一行，无法形成项目级清单。6个必做项目中18号线三期、10号线三期对上聚合行；12号线一期有'
        '2026-08-26成都轨道集团首次环评信息公开可点名（起于普安站、止于舜和家园站、34.2km、28站）；'
        '18号线四期、27号线二期、10号线四期只找到招标公告引述省发改委先行开展勘察设计招标的函，'
        '可研、节能审查与环评原件均未取得（相关站点412反爬、正文页不可达）。故不标已核对。'),
}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def rows_from_review(city_id):
    for name in (SHGZ, SZCDBJ):
        review = read(name)
        block = review.get('cities', {}).get(city_id)
        if block and block.get('rows'):
            rows = []
            for row in block['rows']:
                if not row.get('source', '').startswith('https://'):
                    continue
                rows.append({k: row[k] for k in ('projectId', 'officialName', 'source',
                                                 'sourcePublicationDate', 'required', 'locator', 'quote')
                             if k in row})
            return rows
    return []


def main():
    targets = read('data/official_targets_2026-10-01.json')
    gap = read(GAP).get('projects', {})
    changed = 0
    for city_id, city in targets.get('cities', {}).items():
        if city_id not in NOTES:
            continue
        status, note = NOTES[city_id]
        if city_id == 'beijing':
            rows = city.get('sourceProjectInventory', [])
            for row in rows:
                fix = BJ_ROW_SOURCES.get(str(row.get('projectId', '')))
                if fix:
                    row['source'], row['sourcePublicationDate'], row['officialName'] = fix
                else:
                    row['source'], row['sourcePublicationDate'] = BJ_ROSTER_SOURCE, BJ_ROSTER_DATE
        else:
            rows = rows_from_review(city_id)
            if city_id in GAP_ROWS:
                gap_rows = read(GAP).get('projects', {})
                for project_id in GAP_ROWS[city_id]:
                    entry = gap_rows.get(project_id, {})
                    if entry.get('status') != 'found' or not str(entry.get('source', '')).startswith('https://'):
                        continue
                    rows.append({'projectId': project_id, 'officialName': entry.get('officialName', ''),
                                 'source': entry['source'],
                                 'sourcePublicationDate': entry.get('sourcePublicationDate', ''),
                                 'required': True, 'locator': entry.get('locator', ''),
                                 'quote': entry.get('quote', '')})
        already = (city.get('inventoryReviewStatus') == status
                   and city.get('inventoryReviewNote') == note
                   and city.get('sourceProjectInventory', []) == rows)
        if already:
            continue
        city['sourceProjectInventory'] = rows
        city['inventoryReviewStatus'] = status
        city['inventoryReviewNote'] = note
        changed += 1
        print(f'{"VERIFIED" if status == "verified" else "STILL_PENDING"} {city_id} rows={len(rows)}')

    if not changed:
        print('ALREADY_RECORDED no project inventory changed')
        return
    write('data/official_targets_2026-10-01.json', targets)


if __name__ == '__main__':
    main()
