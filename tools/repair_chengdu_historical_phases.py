"""Materialize reviewed opening scopes, without moving existing player objects.

The station-name sequences below are an independently authored historical
checklist, not extracted from the old chapters. Operator current orders provide
the geographic lookup only; opening boundaries/dates use the dated evidence.
This covers the reviewed 2010--2019 lines, not the later remaining history.
"""
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.24.2'
BOND = 'https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf'
ANNIVERSARY = 'https://m.thepaper.cn/newsDetail_forward_9369431'
SOURCES = {
    'bond': (BOND, '2026-06-18'),
    'line2': ('https://www.crsc.cn/news/tsi_1079_3797_1878.html', '2013-06-13'),
    'line3': ('https://www.crecg.com/crcdi/cpyfw/gdjt97/2026032511084063483/index.html', '2026-03-25'),
    'line3extensions': ('https://www.crecg.com/crcdi/cpyfw/gdjt97/2026032511073480334/index.html', '2026-03-25'),
    'line10': ('https://www.tunnelling.cn/PNews/NewsDetail.aspx?newsId=24763', '2017-09-08'),
    'anniversary': (ANNIVERSARY, '2020-09-28'),
}
# Each list includes the existing connection station, where applicable.
SCOPES = [
    ('cd-line1-2010', '2010-09-27', '1号线一期：南北主轴', '1', 'bond', [
        '升仙湖 火车北站 人民北路 文殊院 骡马市 天府广场 锦江宾馆 华西坝 省体育馆 倪家桥 桐梓林 火车南站 高新 金融城 孵化园 锦城广场 世纪城']),
    ('chengdu-opening-line2-first-2012', '2012-09-16', '十字成网：2号线一期', '2', 'line2', [
        '茶店子客运站 羊犀立交 一品天下 蜀汉路东 白果林 中医大省医院 通惠门 人民公园 天府广场 春熙路 东门大桥 牛王庙 牛市口 东大路 塔子山公园 成都东客站 成渝立交 惠王陵 洪河 成都行政学院']),
    ('chengdu-opening-line2-west-2013', '2013-06-08', '2号线西延：接入犀浦', '2', 'bond', [
        '犀浦 天河路 百草路 金周路 金科北路 迎宾大道 茶店子客运站']),
    ('chengdu-network-milestone-2014-10-26', '2014-10-26', '2号线东延：通达龙泉驿', '2', 'bond', [
        '成都行政学院 大面铺 连山坡 界牌 书房 龙平路 龙泉驿']),
    ('cd-line1-2015', '2015-07-25', '1号线南延至广都', '1', 'bond', [
        '世纪城 天府三街 天府五街 华府大道 四河 广都']),
    ('chengdu-opening-line4-first-2015', '2015-12-26', '4号线一期：非遗博览园至万年场', '4', 'anniversary', [
        '非遗博览园 蔡桥 中坝 成都西站 清江西路 文化宫 西南财大 草堂北路 中医大省医院 宽窄巷子 骡马市 太升南路 市二医院 玉双路 双桥路 万年场']),
    ('chengdu-opening-line3-first-2016', '2016-07-31', '米字骨架：3号线一期', '3', 'line3', [
        '军区总医院 熊猫大道 动物园 昭觉寺南路 驷马桥 李家沱 前锋路 红星桥 市二医院 春熙路 新南门 磨子桥 省体育馆 衣冠庙 高升桥 红牌楼 太平园']),
    ('chengdu-network-milestone-2017-12-26', '2017-06-02', '4号线两端延伸：温江与龙泉', '4', 'bond', [
        '万盛 杨柳河 凤溪河 南熏大道 光华公园 涌泉 凤凰大街 马厂坝 非遗博览园',
        '万年场 槐树店 来龙 十陵 成都大学 明蜀王陵 西河']),
    ('chengdu-opening-line10-first-2017', '2017-09-06', '机场专线：10号线一期', '10', 'line10', [
        '太平园 簇锦 华兴 金花 双流机场1航站楼 双流机场2航站楼']),
    ('chengdu-network-milestone-2017-12-06', '2017-12-06', '首条环线：7号线闭合', '7', 'bond', [
        '火车北站 驷马桥 府青路 八里庄 二仙桥 理工大学 崔家店 双店路 槐树店 迎晖路 成都东客站 大观 狮子山 四川师大 琉璃场 三瓦窑 火车南站 神仙树 高朋大道 太平园 武侯大道 龙爪堰 东坡路 文化宫 金沙博物馆 一品天下 茶店子 花照壁 西南交大 九里堤 北站西二路']),
    ('chengdu-historical-milestone-2018-03-18', '2018-03-18', '1号线三期：北延与南段两支', '1', 'bond', [
        '韦家碾 升仙湖',
        '四河 华阳 海昌路 广福 红石公园 麓湖 武汉路 天府公园 西博城 广州路 兴隆湖 科学城',
        '广都 五根松']),
    ('chengdu-network-milestone-2018-12-26', '2018-12-26', '3号线南北延伸：新都与双流', '3', 'line3extensions', [
        '成都医学院 石油大学 钟楼 马超西路 团结新区 锦水河 三河场 金华寺东路 植物园 军区总医院',
        '太平园 川藏立交 武侯立交 武青南路 双凤桥 龙桥路 航都大街 迎春桥 东升 双流广场 三里坝 双流西站']),
    ('chengdu-network-milestone-2019-06-02', '2019-12-27', '5号线一、二期：第二条南北主轴', '5', 'bond', [
        '华桂路 柏水场 廖家湾 北部商贸城 幸福桥 九道堰 杜家碾 大丰 石犀公园 皇花园 陆家桥 泉水路 洞子口 福宁路 五块石 赛云台 北站西二路 西北桥 花牌坊 抚琴 中医大省医院 青羊宫 省骨科医院 高升桥 科园 九兴大道 神仙树 石羊立交 市一医院 交子大道 锦城大道 锦城湖 大源 民乐 骑龙 警官学院 二江寺 南湖立交 怡心湖 龙马路 回龙']),
    ('chengdu-network-milestone-2019-12-27', '2019-12-27', '10号线二期：向新津延伸', '10', 'bond', [
        '双流机场2航站楼 双流西站 应天寺 黄水 花源 新津站 花桥 五津 儒林路 刘家碾 新平']),
]


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def normalize(name):
    return name.replace('·', '').removesuffix('站')


def main():
    campaigns = read('data/campaigns.json')
    official = read('data/official_targets_2026-10-01.json')
    city = next(c for c in read('data/cities.json')['cities'] if c['id'] == 'chengdu')
    catalog = {s['id']: s for s in city['stations']}
    cd = campaigns['cities']['chengdu']
    chapters = {c['id']: c for c in cd['chapters']}
    cutoff = next(c for c in cd['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    templates = {}
    for group in cutoff['lineGroups']:
        templates.setdefault(group['historicalLineId'], group)
    sample = deepcopy(chapters['chengdu-network-milestone-2014-10-26'])
    reviewed = []
    for chapter_id, date, title, number, source_key, paths in SCOPES:
        line_id = 'chengdu-line1' if number == '1' else next(k for k in templates if k.startswith(f'chengdu-line{number}-'))
        template = templates[line_id]
        ids_by_name = {}
        # For line 1 both branches are needed; other lines have one main path.
        for group in cutoff['lineGroups']:
            if group['historicalLineId'] == line_id:
                ids_by_name.update({normalize(catalog[s]['name']): s for s in group['stationIds']})
        chapter = chapters.get(chapter_id, deepcopy(sample))
        is_new = chapter_id not in chapters
        old_task = chapter.get('lineGroups', [{}])[0].get('taskId') if not is_new else None
        groups, expected = [], []
        source, publication = SOURCES[source_key]
        for index, path in enumerate(paths):
            names = path.split()
            ids = [ids_by_name[normalize(name)] for name in names]
            group = deepcopy(template)
            # Stable physical instances come from the reviewed line-specific
            # lookup, never from whichever same-name station appears first.
            instances = {}
            for canonical in cutoff['lineGroups']:
                if canonical['historicalLineId'] == line_id:
                    instances.update(canonical.get('stationInstances', {}))
            group.update(stationIds=ids, stationNames=dict(zip(ids, names)),
                         stationInstances={s: instances.get(s, s) for s in ids},
                         taskId=old_task if len(paths) == 1 and old_task else f'opening:{chapter_id}:{index+1}',
                         coverageGroupId=f'{line_id}:{chapter_id}:{index+1}',
                         name=title + (f' · 第{index+1}段' if len(paths) > 1 else ''),
                         loop=number == '7', replaceExistingService=False, stationOrderSource=source,
                         precisionNote='开通日期与本期端点据列明资料核对，站序用运营方逐站资料交叉检查；现代地理站区和隧道走廊为近似参考。',
                         servicePathRevision=3)
            groups.append(group)
            expected.append({'id': group['coverageGroupId'], 'historicalLineId':line_id,
                             'scopeType':'stations', 'stationNames':names, 'allowReverse':True,
                             'loop':number == '7'})
        chapter.update(id=chapter_id, date=date, title=title, lineGroups=groups,
                       requireOpen=True, status='operated',
                       source=source, sourcePublicationDate=publication,
                       sourceCheckedAt='2026-10-24', sourceTitle='有日期的开通范围资料与运营方逐站时刻表交叉核对',
                       chapterScope='dated_opening_ranges', requiresScopeRecheck=True,
                       scopeRevision=REVISION, routeTargetCount=len(groups), eventOnly=False)
        if is_new:
            chapter['historicalEventIds'] = [chapter_id + ':opening']
            chapter['requiredTransfers'] = []
        chapter['eventText'] = f'{date}，{title}。本期仅增加所列站段，既有端站复用，后期开通范围不提前加入。'
        chapter['alignmentNote'] = '本期站序来自独立开通范围清单；地理几何只作近似参考，不把现状整线放入早期章节。'
        chapter['story']['opening'] = chapter['eventText']
        chapter['story']['purpose'] = '接续既有路网，建设本期新增范围；每个接头复用所属线路站体。'
        chapter['story']['outcome'] = '新增站段与既有线路相接，本历史节点已记录；后续建设另列任务。'
        for field in ['sourceStatus', 'publicationDateNote']:
            chapter.pop(field, None)
        chapters[chapter_id] = chapter
        reviewed.append({'chapterId':chapter_id, 'date':date, 'source':source,
                         'sourcePublicationDate':publication,
                         'additionalSources':[{'url':BOND, 'title':'运营方2026年募集说明书历史运营工程表'},
                                              {'url':ANNIVERSARY,'title':'微成都2020周年开通节点回顾'}],
                         'groups':expected})
    # Remove the line-1 ranges incorrectly left until 2020; they are now built
    # at their actual 2018 event. Keep this chapter ID and its 18-line task.
    late = chapters['chengdu-network-milestone-2020-09-27']
    late['lineGroups'] = [g for g in late['lineGroups'] if g['historicalLineId'] != 'chengdu-line1']
    late['title'] = '18号线首开段'
    late['requiresScopeRecheck'] = True
    late['scopeRevision'] = REVISION
    # Rehome the EXISTING documented transfer requirements to the first event
    # with both line-specific platforms. No geometric crossing creates a link.
    ordered = sorted(chapters.values(), key=lambda c:c['date'])
    transfer_specs = {}
    for chapter in ordered:
        for transfer in chapter.get('requiredTransfers', []):
            transfer_specs.setdefault(transfer['id'], deepcopy(transfer))
    aliases = cd.get('stationComplexAliases', {})
    def canonical(identity):
        return aliases.get(identity, identity)
    bodies = {}
    for group in cutoff['lineGroups']:
        for station in group['stationIds']:
            line_id = group['historicalLineId']
            bodies[(line_id, canonical(station))] = cd.get('stationInstanceAliases', {}).get(
                f'{line_id}|{station}', group.get('stationInstances', {}).get(station, station))
    first = {}
    for chapter in ordered:
        for group in chapter.get('lineGroups', []):
            for station in group['stationIds']:
                first.setdefault((group['historicalLineId'], canonical(station)), chapter)
        chapter['requiredTransfers'] = []
    for transfer in transfer_specs.values():
        complex_id = canonical(transfer['complexId'])
        keys = [(line, complex_id) for line in transfer['lineIds']]
        if not all(key in first and key in bodies for key in keys):
            raise ValueError(f"Cannot assign historical transfer {transfer['id']}: {keys}")
        destination = max((first[key] for key in keys), key=lambda c:c['date'])
        transfer['stationInstanceIds'] = [bodies[key] for key in keys]
        destination['requiredTransfers'].append(transfer)
    cd['chapters'] = ordered
    target = official['cities']['chengdu']
    ids = {m['chapterId'] for m in reviewed}
    target['historicalMilestones'] = [m for m in target.get('historicalMilestones', []) if m['chapterId'] not in ids] + reviewed
    # Explicitly leave the unreviewed late history and inventory gate closed.
    target['historyReviewStatus'] = 'pending'
    if tuple(map(int,REVISION.split('.'))) >= tuple(map(int,campaigns.get('contentRevision','0').split('.'))):
        campaigns['contentRevision'] = REVISION
        campaigns['contentRevisionNote'] = '纠正成都2010—2019分期范围，补回2/3/4/10首期及延伸，5号线日期改回2019-12-27；不宣称晚期历史核对完成。'
    write('data/campaigns.json', campaigns)
    write('data/official_targets_2026-10-01.json', official)
    print(f'Reviewed opening chapters {len(reviewed)}; current total {len(ordered)}')


if __name__ == '__main__':
    main()
