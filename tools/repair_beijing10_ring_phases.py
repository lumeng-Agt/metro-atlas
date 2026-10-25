"""Restore the 22-stop first line, 42-stop C and genuine 45-stop closure."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from author_reviewed_route_phases import apply_phases, reschedule_transfers
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.25.5'
LINE = 'beijing-line10-10'
FIRST_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/ndzdgz/201912/t20191210_1017724.html'
C_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/dtxx/201211/t20121122_337170.html'
RING_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/dtxx/201306/t20130624_333103.html'
SCOPE_SOURCE = 'https://ggzyfw.beijing.gov.cn/jyxxgcjszbjh/20240117/4298740.html'
FIRST = '巴沟 苏州街 海淀黄庄 知春里 知春路 西土城 牡丹园 健德门 北土城 安贞门 惠新西街南口 芍药居 太阳宫 三元桥 亮马桥 农业展览馆 团结湖 呼家楼 金台夕照 国贸 双井 劲松'.split()
WEST = '西局 六里桥 莲花桥 公主坟 西钓鱼台 慈寿寺 车道沟 长春桥 火器营'.split()
SOUTH = '潘家园 十里河 分钟寺 成寿寺 宋家庄 石榴庄 大红门 角门西 草桥 纪家庙 首经贸'.split()
C_ORDER = WEST + FIRST + SOUTH
FULL = '巴沟 苏州街 海淀黄庄 知春里 知春路 西土城 牡丹园 健德门 北土城 安贞门 惠新西街南口 芍药居 太阳宫 三元桥 亮马桥 农业展览馆 团结湖 呼家楼 金台夕照 国贸 双井 劲松 潘家园 十里河 分钟寺 成寿寺 宋家庄 石榴庄 大红门 角门东 角门西 草桥 纪家庙 首经贸 丰台站 泥洼 西局 六里桥 莲花桥 公主坟 西钓鱼台 慈寿寺 车道沟 长春桥 火器营'.split()


def main():
    assert len(FIRST) == 22 and len(C_ORDER) == 42 and len(FULL) == len(set(FULL)) == 45
    data = read('data/campaigns.json'); cities = read('data/cities.json')
    official = read('data/official_targets_2026-10-01.json'); baseline = read('data/network_baselines_2026-10-01.json')
    campaign = data['cities']['beijing']; geography = next(c for c in cities['cities'] if c['id'] == 'beijing')
    target = official['cities']['beijing']; row = baseline['cities']['beijing']
    # The old relation appended a second Guomao and Dahongmen after Liuliqiao.
    # Keep the line-10 Guomao body and the already bound Dahongmen complex
    # target; the latter remains a labelled station-area approximation.
    campaign.setdefault('stationComplexAliases', {}).update({'beijing-s168':'beijing-s48', 'beijing-s191':'beijing-s127'})
    cutoff = next(c for c in campaign['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE)
    old_instances = template.get('stationInstances', {})
    replacements = {'beijing-s48__line10-10': old_instances.get('beijing-s168', 'beijing-s168')}
    correction_pairs = []
    for chapter in campaign['chapters'] + campaign.get('futurePlans', []):
        for transfer in chapter.get('requiredTransfers', []):
            if LINE not in transfer['lineIds']: continue
            before = deepcopy(transfer); index = transfer['lineIds'].index(LINE)
            old = transfer['stationInstanceIds'][index]
            if old in replacements and old != replacements[old]:
                transfer['stationInstanceIds'][index] = replacements[old]
                correction_pairs.append(dict(taskId='opening:bj10-first', transferId=transfer['id'], oldLineIds=before['lineIds'],
                    oldStationInstanceIds=before['stationInstanceIds'], newStationInstanceIds=transfer['stationInstanceIds'].copy(),
                    description='10号线关系含重复站区成员；保留全部实体建设，将既有换乘明确指向本线正确站体。', source=SCOPE_SOURCE))
    stages = [dict(chapterId='beijing-line10-first-2008', date='2008-07-19', title='10号线一期：巴沟至劲松',
        taskId='opening:bj10-first', stationNames=FIRST, source=FIRST_SOURCE, sourcePublicationDate='2008-07-28'),
        dict(chapterId='beijing-network-milestone-2012-12-30', date='2012-12-30', title='10号线二期先行段：大C形运行',
            taskId='opening:bj10-c', stationNames=C_ORDER, source=C_SOURCE, sourcePublicationDate='2012-11-22',
            purpose='复用一期，沿南部和西部扩展至首经贸与西局；丰台、泥洼仍未开通，不能提前闭环。'),
        dict(chapterId='beijing-network-milestone-2013-05-05', date='2013-05-05', title='10号线45站成环',
            taskId='route:beijing-r10', stationNames=FULL, loop=True, source=RING_SOURCE, sourcePublicationDate='2013-06-24')]
    for stage in stages: stage['stationIdOverrides'] = {'国贸':'beijing-s168', '大红门':'beijing-s127'}
    apply_phases(campaign, geography, target, row, line_id=LINE, route_id='beijing-r10', stages=stages,
        revision=REVISION, cutoff_order=FULL, order_source='https://www.bjmoa.cn/metroLineList.html?sline=9', loop=True)
    first = next(c for c in campaign['chapters'] if c['id'] == 'beijing-line10-first-2008')
    first['scopeCorrections'] += correction_pairs
    reschedule_transfers(campaign, target, [LINE])
    for milestone in target['historicalMilestones']:
        if milestone['chapterId'] in [s['chapterId'] for s in stages]:
            milestone['additionalSources'] = list(dict.fromkeys(milestone.get('additionalSources', []) + [SCOPE_SOURCE]))
    generated = build(cities, data)['cities']['beijing']
    for key in ['routes', 'mapRouteEntryCount', 'mapRouteStopOccurrenceCount', 'mapUniqueStationCount']: row[key] = generated[key]
    refresh_schedule('beijing', row, campaign, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='10号线恢复22站首开、42站大C、45站真正闭环，剔除线路关系中重复国贸／大红门并保留玩家原实体。')
    for path, value in [('data/cities.json', cities), ('data/campaigns.json', data),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('Beijing10: 22 / 42 / 45, final 45th interval must physically close the circuit')


if __name__ == '__main__': main()
