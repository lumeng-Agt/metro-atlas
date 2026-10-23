"""Separate actual Guangzhou services instead of concatenating OSM relations.

Reviewed scopes: 3 main/branch, 12 two disconnected operating sections, and
14 main/Knowledge City branch. This is deliberately not a full-city historical
certificate. Airport South's dated closure is kept separate from physical stock.
"""
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.24.4'
SCOPE_SOURCES = {
    '3': 'https://news.dayoo.com/guangzhou/202605/03/139995_54955522.htm',
    '12': 'https://news.dayoo.com/gzrbrmt/202506/13/170628_54835315.htm',
    '14': 'https://mzj.gz.gov.cn/gk/dmgg/content/post_10446306.html',
}
ORDERS = {
    '3': [
        '机场北 高增 人和 龙归 嘉禾望岗 白云大道北 永泰 同和 京溪南方医院 梅花园 燕塘 广州东站 林和西 体育西路 珠江新城 广州塔 客村 大塘 沥滘 厦滘 大石 汉溪长隆 市桥 番禺广场 傍江 石碁南 海涌路 海傍',
        '天河客运站 五山 华师 岗顶 石牌桥 体育西路',
    ],
    '12': [
        '浔峰岗 浔峰岗北 西洲 聚龙 广州白云站 棠涌 新市墟 白云文化广场 广州体育馆',
        '二沙岛 赤岗塔 赤岗 赤沙北 赤沙 北山 官洲 大学城北 大学城南',
    ],
    '14': [
        '乐嘉路 云霄路 新市墟 马务 鹤边 鹤龙 彭边 嘉禾望岗 白云东平 夏良 太和 竹料 钟落潭 马沥 新和 太平 神岗 赤草 从化客运站 东风',
        '新和 红卫 新南 枫下 知识城 何棠下 旺村 汤村 镇龙北 镇龙',
    ],
}


def read(name):
    return json.loads((ROOT / name).read_text(encoding='utf-8'))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    data = read('data/campaigns.json')
    targets = read('data/official_targets_2026-10-01.json')
    campaign = data['cities']['guangzhou']
    city = next(c for c in read('data/cities.json')['cities'] if c['id'] == 'guangzhou')
    catalog = {s['id']: s for s in city['stations']}
    chapter = next(c for c in campaign['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    old_groups = chapter['lineGroups']
    replaced = {f'guangzhou-line{n}-{n}' for n in ORDERS}
    # Canonical route IDs and existing platform identities remain unchanged.
    groups = [g for g in old_groups if g['historicalLineId'] not in replaced]
    expected = []
    for number, paths in ORDERS.items():
        line_id = f'guangzhou-line{number}-{number}'
        template = next(g for g in old_groups if g['historicalLineId'] == line_id)
        lookup = {}
        instances = {}
        for old in old_groups:
            if old['historicalLineId'] != line_id:
                continue
            lookup.update({catalog[s]['name']:s for s in old['stationIds']})
            instances.update(old.get('stationInstances', {}))
        for index, path in enumerate(paths):
            names = path.split()
            ids = [lookup[name] for name in names]
            group = deepcopy(template)
            group.update(stationIds=ids, stationNames=dict(zip(ids,names)),
                         stationInstances={s:instances.get(s,s) for s in ids},
                         taskId=f'route:{template["mapRouteId"]}:service-{index+1}',
                         coverageGroupId=f'{line_id}:service-{index+1}',
                         replaceExistingService=index == 0, servicePathRevision=3,
                         stationOrderSource=SCOPE_SOURCES[number],
                         precisionNote='独立线路路径：支线与分段不串成一条跨城跳跃的折线；3号线机场南按2026-05-07暂停服务公告不列为截止日停站，原站体保留。')
            groups.append(group)
            expected.append({'id':group['coverageGroupId'],'historicalLineId':line_id,
                             'stationNames':names,'scopeType':'stations','allowReverse':True})
    chapter['lineGroups'] = groups
    chapter['requiresScopeRecheck'] = True
    chapter['scopeRevision'] = REVISION
    # Correcting 12's cutoff service temporarily removes its already-built
    # future middle service. Archive only the explicitly documented links;
    # the middle task restores them after reconfirming its new full path.
    middle = next(p for p in campaign['futurePlans'] if p['id'] == 'gz-line12-mid-build')
    corrections = chapter.setdefault('scopeCorrections', [])
    # Replacing the first path must not leave a live interchange pointing to
    # a temporarily absent second path. Reconfirm it after that branch task;
    # chapter-wide confirmation must then leave the restored link active.
    all_historical_transfers = {t['id']:t for p in campaign['chapters'] for t in p.get('requiredTransfers', [])}
    all_future_transfers = {t['id']:t for p in campaign['futurePlans'] for t in p.get('requiredTransfers', [])}
    canonical = lambda identity: campaign.get('stationComplexAliases', {}).get(identity,identity)
    for number in ORDERS:
        line_id = f'guangzhou-line{number}-{number}'
        first, second = [g for g in groups if g.get('coverageGroupId','').startswith(line_id+':service-')]
        first_complexes = {canonical(s) for s in first['stationIds']}
        second_complexes = {canonical(s) for s in second['stationIds']}
        for transfer in all_historical_transfers.values():
            complex_id = canonical(transfer['complexId'])
            if line_id not in transfer['lineIds'] or complex_id not in second_complexes-first_complexes:
                continue
            correction = {'taskId':first['taskId'],'restoreAfterTaskId':second['taskId'],
                          'transferId':transfer['id'],'oldLineIds':transfer['lineIds'],
                          'oldStationInstanceIds':transfer['stationInstanceIds'],
                          'description':'分开确认两条路径：先保留站体，第二条路径确认后明确恢复此换乘联系。',
                          'source':SCOPE_SOURCES[number]}
            if correction not in corrections:corrections.append(correction)
            if not any(t['id']==transfer['id'] for t in chapter.get('requiredTransfers', [])):
                chapter.setdefault('requiredTransfers', []).append(deepcopy(transfer))
        for transfer in all_future_transfers.values():
            if line_id not in transfer['lineIds'] or canonical(transfer['complexId']) in first_complexes|second_complexes:
                continue
            correction = {'taskId':first['taskId'],'transferId':transfer['id'],
                          'oldLineIds':transfer['lineIds'],'oldStationInstanceIds':transfer['stationInstanceIds'],
                          'description':'更正历史分段时保留后续建设，重新确认依赖此线的规划换乘。',
                          'source':SCOPE_SOURCES[number]}
            if correction not in corrections:corrections.append(correction)
    task_id = next(g['taskId'] for g in groups if g.get('coverageGroupId') == 'guangzhou-line12-12:service-1')
    for transfer in middle.get('requiredTransfers', []):
        correction = {'taskId':task_id,'transferId':transfer['id'],
                      'oldLineIds':transfer['lineIds'],
                      'oldStationInstanceIds':transfer['stationInstanceIds'],
                      'description':'12号线截止日东西段分开保存；已建中段站轨保留，中段线路及换乘随后重新确认。',
                      'source':SCOPE_SOURCES['12']}
        if correction not in corrections:corrections.append(correction)
    target = targets['cities']['guangzhou']
    target['cutoffNetwork'] = {
        'chapterId':chapter['id'],'date':'2026-10-01',
        'source':'https://www.huadu.gov.cn/gzhdjt/gkmlpt/content/10/10586/mpost_10586818.html',
        'sourcePublicationDate':'2025-12-10','temporalReviewStatus':'pending',
        'inventoryReviewStatus':'partial',
        'note':'这里只独立列明3/12/14号线的6条路径，其余线路及全量换乘仍需补齐，不能据此宣布广州完整交付。机场南实体另归历史台账，不计暂停服务期间的停站。',
        'additionalSources':[{'url':url} for url in SCOPE_SOURCES.values()],
        'groups':expected,
        'futureTopologyChanges':[{'projectId':'gz-line12-mid','historicalLineId':'guangzhou-line12-12',
                                  'kind':'merge_cutoff_branches','cutoffBranchCount':2,'resultBranchCount':1,
                                  'source':'https://www.by.gov.cn/gzjg/qtdkfzx/jcss/content/post_10790614.html'}],
    }
    if tuple(map(int,REVISION.split('.'))) >= tuple(map(int,data.get('contentRevision','0').split('.'))):
        data['contentRevision'] = REVISION
        data['contentRevisionNote'] = '广州3/14主支线、12东西分段分别保存，修正把不同运营路径串接为同一条线的错误。'
    write('data/campaigns.json',data)
    write('data/official_targets_2026-10-01.json',targets)
    print('Guangzhou: six reviewed branch/section paths; full inventory remains incomplete')


if __name__ == '__main__':
    main()
