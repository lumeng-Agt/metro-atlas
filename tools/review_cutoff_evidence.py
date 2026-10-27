"""Record independent cutoff-network review outcomes for the five cities.

Three separate questions are answered here, each with its own verdict:

  * opening chronology  -> dated official rows, every effectiveDate at or before
                           the cutoff; a city is only `verified` when the rows
                           reach the cutoff and no undated gap is left;
  * interchange roster  -> the set of multi-line stations at the cutoff, compared
                           station by station with the game's requirement list;
  * shared running      -> whether an official document supports the modelled
                           common section, not just that trains share a corridor.

A city keeps its previous status when the review found a gap. The note always
names what is missing, so a reader can tell "not looked at" from "looked at and
found short". Nothing here relaxes a check.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEWED_AT = '2026-10-28'

SH = 'data/official_evidence/shanghai_cutoff_review_2026-10-28.json'
BJSZ = 'data/official_evidence/beijing_shenzhen_cutoff_review_2026-10-28.json'
GZCD = 'data/official_evidence/guangzhou_chengdu_cutoff_review_2026-10-28.json'

TEMPORAL = {
    'shanghai': SH, 'beijing': BJSZ, 'shenzhen': BJSZ, 'guangzhou': GZCD, 'chengdu': GZCD,
}
INTERCHANGES = {
    'shanghai': SH, 'beijing': BJSZ, 'shenzhen': BJSZ, 'guangzhou': GZCD, 'chengdu': GZCD,
}

# City -> note written next to the opening-chronology verdict.
TEMPORAL_NOTES = {
    'beijing': '按官方通稿与年度运营通告逐次核对截止日前开通：补入2024-12-15三线、2025-12-27'
               '十七号线中段与六号线南延、2026-02-03否定证据等8条带日期行；红庙、陶然桥、广渠门外、'
               '福寿岭、八角游乐园等暂缓开通车站均未计入截止网，未发现把未开通站当已开通。',
    'shenzhen': '按官方通稿逐次核对截止日前开通：补入2025-09-28两段与2025-12-28三段（大剧院、湖贝、'
                '红岭南由此成立），共7条带日期行；西丽高铁站等未开通站未计入截止网。',
    'guangzhou': '按官方通稿与佛山线网通告核对到2026-06-18佛山三号线贯通（敦厚站启用，不新增换乘站）；'
                 '广州本市最近一次为2025-12-29二十二号线后通段。十一号线广州火车站自2024-12-28起'
                 '通过不停车、至截止日仍未开通，游戏截止网确实没有该站；未发现把未开通站当已开通。',
    'chengdu': '原temporalEvidence为空，本轮补入14条带日期行，逐线落到最后一次开通日（1/3/4/5/7/10/13/'
               '17/18/19/27/30号线分别记录，6/8/9号线并入2020-12-18与2024-12-19两条）。截止日前最近'
               '一次开通为2025-12-16十三号线一期与三十号线一期；三十号线玉虹路、分水与十号线文翁石室、'
               '人民公园按官方“暂未开通”处理，游戏站序同样不含。',
    'shanghai': '补入7条官方带日期行（2024-06-22宜山路通道、2025-11-01二号线蟠祥路、2025-12-27'
                '十八号线二期、2026-02-22宝山路站台恢复、2026-07-03南京西路仅获规划许可等），'
                '最近一次开通为2025-12-27。仍判未核对：没有官方文件逐线确认2026年内未再开通任何车站；'
                '运营方站序本轮无法重抓（service.shmetro.com 全站301后只返回占位页），不能用最新站序反证。',
}

# City -> note written next to the interchange verdict.
INTERCHANGE_NOTES = {
    'beijing': '按官方线网图换乘符号与运营方站序普查得104座多线换乘站，与游戏122条编号（去重104站）'
               '逐站比对，漏项0、虚项0。巴沟（10号线/西郊线）、苹果园与金安桥的S1、四惠—四惠东—公益西桥'
               '贯通段按“有轨、磁浮、贯通不计换乘”排除并单独写明。',
    'chengdu': '按运营方首末班车时刻接口实抓（与2026-10-23抓取逐字节一致）聚合得83座多线站，剔除18/19号线'
               '共线运营的三岔、福田、天府机场1号2号航站楼、天府机场北4座（同一实体站台，不构成步行换乘）'
               '后79座；游戏截止网为78个站区、92条编号，差的那一座是双流机场：官方把双流机场2航站楼'
               '（10/19）与双流机场2航站楼东（19/30）算作两座，游戏按官方“出闸换乘”把它们并入同一站区，'
               '因此78站对79站不是漏项。另官方写“中医大省医院”，游戏站名带间隔号写作“中医大·省医院”，'
               '同一座站。按此口径逐站比对漏项0、虚项0；蓉2有轨与S3资阳线不计。'
               '复核时专门查了双流机场2航站楼—三十号线这一对：三十号线西端是双流机场2航站楼东，'
               '不经双流机场2航站楼，但官方站名后标注“出闸换乘”，两座站名不同的实体站之间确实存在出闸步行联系，'
               '故这一对按出闸换乘保留，不删；十号线—十九号线、十九号线—三十号线两对为付费区内换乘，分别保留。',
    'guangzhou': '按运营方线网接口实抓得75座多线换乘站（广州市内70、佛山5，不含APM，计APM为77）。'
                 '上一版把这75座与`cutoffNetwork.transfers`里的24个站区相比得出“缺51站”，但那份清单只是'
                 '2026核对章重列的25条编号，不是游戏截止网的全部换乘。改按全部历史章节的换乘要求重算：'
                 '历史章节共97条编号，其中赤沙一对同站体有两个编号（旧的`-s337-line12-12-line11-11`与'
                 '复核后的`-s337-11-12`），旧编号在存档里被标为`superseded`、只有复核后那条是active，'
                 '故清单取复核后的那一条，得96条编号、75个站区。逐名双向比对（官方有而游戏无、游戏有而官方无均为空），'
                 '每站线路数也逐站相同（75站全部相等，差异0）。漏项0、虚项0。'
                 '本次结论到站级与线路数级，站内通道形式与同台／出闸的逐对分类仍以各城专项证据为准。',
    'shanghai': '按运营方车站码换乘位掩码解码并与18条线路站序逐站交叉核对得86座换乘站、131个线路对，'
                '游戏84站/123对：官方有而游戏缺中潭路、延安西路两站（仅3/4号线服务），虚项0；'
                '共轨段另有8个3↔4号线换乘对未列，而宝山路、宜山路反而列了，口径不一致。'
                '这两座正是共轨段的站，游戏按同一物理站体建模、不另设换乘，与成都剔除共线站的口径相同；'
                '但共轨段端点本身与官方不一致（官方“宝山路至虹桥路”，游戏止于上海火车站），'
                '在该条转绿之前本项不单独放行。'
                '本轮service.shmetro.com全站301后仅返回占位页，无法重抓掩码，只能核对既有官方抓取件，'
                '不算独立复现。未标已核对。',
    'shenzhen': '按官方线网图换乘符号与2026-06-28运营站序普查得68座多线换乘站，与游戏96条编号'
                '（去重68站）逐站逐对比对，漏项0、虚项0；同台换乘与通道换乘都计入，'
                '有轨、磁浮与贯通运营段不计。',
}

SHARED_NOTE = ('区间端点已按官方原文声明为「宝山路—虹桥路」并纳入强制校验：'
               'section 的 intervalEndpoints 必须与 official 写法一致，端点里不在 stationNames 中的那个'
               '必须恰好是方向性站台要求覆盖的车站，且 stationNames 全部要落在两端之间（按3号线实际站序）。'
               '改前只写到上海火车站，端点少一站；现在写的是官方东端宝山路。'
               '宝山路站台分工（4号线外圈独用1号站台、3号线往江杨北路与4号线内圈共用3号站台、'
               '3号线往上海南站用2号站台）与官方2026-02-25通稿逐条一致，专项按运行世界验证'
               '「上海火车站—宝山路」这一段由3号线与4号线内圈共用同一站体与同一实体轨道、'
               '4号线外圈走自己的站台且不停共用站台。虹桥路—上海火车站8站两线共用同一站体与实体轨道。'
               '中潭路、延安西路在截止网里各是一座站体、两线都停靠，与运营方把它列为换乘站的口径一致。'
               '宜山路3/4/9号线以全地下三段通道换乘、站体分离，不纳入共轨。'
               '“同一站体”是游戏对官方“共用区间／共用站台”的表示方式，不是额外的测绘结论；'
               '官方没有给出中心线与站台尺寸，游戏也没有据此声明精度。')

# No requirement is dropped here. The airport contact between the two separately
# named stations (双流机场2航站楼 / 双流机场2航站楼东) was re-checked and kept: the
# official guide labels it 出闸换乘, which is exactly an out-of-gate contact
# between two differently named physical stations, not a claim that line 30
# calls at the line 10 platform.
DROP_TRANSFERS = {}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def merge_evidence(existing, additions):
    """Append dated rows that are not already recorded, and drop exact duplicates."""
    merged = []
    seen = set()
    for row in list(existing) + list(additions):
        key = (str(row.get('source', '')), str(row.get('effectiveDate', '')), str(row.get('scope', '')))
        if key in seen:
            continue
        seen.add(key)
        merged.append(row)
    return merged


def game_interchange_census(campaigns, city_doc, city_id, cutoff_date, reconciliation_id=''):
    """Every interchange the historical chapters require, keyed by station complex.

    `cutoffNetwork.transfers` is a re-check list for the reconciliation chapter,
    not the full cutoff inventory. A station-level census has to read the
    requirements of every chapter up to the cutoff, otherwise a complete network
    looks half empty.

    One physical pair can carry two connection ids when a later review renamed
    it (Guangzhou's 赤沙 has both `...-s337-line12-12-line11-11` and the reviewed
    `...-s337-11-12`). The engine keeps a single active connection per pair, so
    the cutoff list must name the survivor, never both: a superseded id in the
    list would make the audit demand a connection that cannot exist.
    """
    geography = next(c for c in city_doc['cities'] if c['id'] == city_id)['stations']
    names = {s['id']: s['name'] for s in geography}
    transfer_ids = []
    complexes = {}
    pairs = {}
    for plan in campaigns['cities'][city_id].get('chapters', []):
        if str(plan.get('date', '')) > cutoff_date:
            continue
        chapter_id = str(plan.get('id', ''))
        for row in plan.get('requiredTransfers', []):
            complex_id = str(row.get('complexId', ''))
            transfer_id = str(row.get('id', ''))
            if transfer_id and transfer_id not in transfer_ids:
                transfer_ids.append(transfer_id)
            complexes.setdefault(complex_id, {'name': names.get(complex_id) or str(row.get('name', complex_id)),
                                              'lines': set()})
            complexes[complex_id]['lines'].update(str(x) for x in row.get('lineIds', []))
            pair_key = (complex_id, tuple(sorted(str(x) for x in row.get('stationInstanceIds', []))))
            pairs.setdefault(pair_key, []).append((str(plan.get('date', '')), chapter_id, transfer_id))
    survivors = {}
    for pair_key, rows in pairs.items():
        ids = {row[2] for row in rows}
        if len(ids) == 1:
            survivors[pair_key] = rows[0][2]
            continue
        reviewed = {row[2] for row in rows if row[1] == reconciliation_id}
        survivors[pair_key] = reviewed.pop() if len(reviewed) == 1 else max(rows)[2]
    keep = set(survivors.values())
    return [x for x in transfer_ids if x in keep], complexes


def drop_requirement(city_id, campaign_city, transfer_id):
    dropped = 0
    for plan in campaign_city.get('chapters', []) + campaign_city.get('futurePlans', []):
        rows = plan.get('requiredTransfers', [])
        kept = [row for row in rows if row.get('id') != transfer_id]
        if len(kept) != len(rows):
            plan['requiredTransfers'] = kept
            dropped += len(rows) - len(kept)
    return dropped


def main():
    targets = read('data/official_targets_2026-10-01.json')
    campaigns = read('data/campaigns.json')
    city_doc = read('data/cities.json')
    changed = False
    for city_id, city in targets.get('cities', {}).items():
        network = city.get('cutoffNetwork', {})
        if not network:
            continue
        before = json.dumps(network, ensure_ascii=False, sort_keys=True)

        if city_id in DROP_TRANSFERS:
            transfer_id, reason = DROP_TRANSFERS[city_id]
            if transfer_id in network.get('transfers', []):
                network['transfers'] = [x for x in network['transfers'] if x != transfer_id]
                print(f'DROPPED {city_id} {transfer_id}')
            dropped = drop_requirement(city_id, campaigns['cities'][city_id], transfer_id)
            if dropped:
                print(f'DROPPED_REQUIREMENT_ROWS {city_id} {dropped}')

        review = read(TEMPORAL[city_id])
        block = review.get('cities', {}).get(city_id, review if review.get('city') == city_id else {})
        temporal = block.get('temporal', {})
        if temporal.get('evidence'):
            network['temporalEvidence'] = merge_evidence(network.get('temporalEvidence', []), temporal['evidence'])
        if temporal.get('verdict') == 'complete':
            network['temporalReviewStatus'] = 'verified'
        elif network.get('temporalReviewStatus') != 'verified':
            network['temporalReviewStatus'] = network.get('temporalReviewStatus', 'pending')
        network['temporalReviewNote'] = TEMPORAL_NOTES[city_id]

        interchange = block.get('interchanges', {})
        if interchange.get('verdict') == 'complete':
            network['transferReviewStatus'] = 'verified'
        elif network.get('transferReviewStatus') != 'verified':
            network['transferReviewStatus'] = network.get('transferReviewStatus', 'pending')
        network['transferReviewNote'] = INTERCHANGE_NOTES[city_id]

        if city_id == 'shanghai':
            # The interval endpoint now matches the published wording and is
            # enforced on both sides (Python coverage + Godot definition/order),
            # and the actual track sharing was replayed, so the geometry is
            # reviewed. What stays unproven is centreline/size precision, which
            # the game never claims.
            network['sharedRunningReviewStatus'] = 'verified'
            network['sharedRunningReviewNote'] = SHARED_NOTE

        if city_id == 'guangzhou':
            # Re-run the station census against the requirements of every
            # chapter up to the cutoff, and make the target list enumerate them
            # all. This widens what the audit checks (25 -> 152 ids); it does not
            # remove or weaken a requirement.
            transfer_ids, complexes = game_interchange_census(
                campaigns, city_doc, city_id, targets.get('cutoffDate', '2026-10-01'),
                str(network.get('chapterId', '')))
            roster = read(GZCD)['cities']['guangzhou']['interchanges']['roster']
            official = {row['station']: len(set(row['lines'])) for row in roster}
            game = {value['name']: len(value['lines']) for value in complexes.values()}
            missing = sorted(set(official) - set(game))
            extra = sorted(set(game) - set(official))
            wrong_lines = sorted(name for name in official if name in game and official[name] != game[name])
            if missing or extra or wrong_lines:
                raise SystemExit(f'guangzhou census still differs: missing={missing} extra={extra} '
                                 f'lineCount={wrong_lines}')
            network['transfers'] = transfer_ids
            network['transferReviewStatus'] = 'verified'

        if json.dumps(network, ensure_ascii=False, sort_keys=True) != before:
            changed = True
            print(f'{city_id}: temporal={network.get("temporalReviewStatus")} '
                  f'transfer={network.get("transferReviewStatus")} '
                  f'shared={network.get("sharedRunningReviewStatus", "-")} '
                  f'evidence={len(network.get("temporalEvidence", []))}')

    if not changed:
        print('ALREADY_RECORDED no cutoff review outcome changed')
        return
    write('data/official_targets_2026-10-01.json', targets)
    write('data/campaigns.json', campaigns)


if __name__ == '__main__':
    main()
