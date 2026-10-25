"""Restore the west/east openings and Qinghe infill, using literal source orders."""
from repair_chengdu_historical_phases import read, write
from author_reviewed_route_phases import apply_phases, reschedule_transfers
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.25.4'
WEST_SOURCE = 'https://news.sohu.com/35/91/news203429135.shtml'
EAST_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/xwfbh/201912/t20191209_1007437.html'
QINGHE_SOURCE = 'https://zdzqgw.beijing.gov.cn/zqfw/qhzdq/qhzzqjs/202008/t20200821_1988566.html'
WEST = '西直门 大钟寺 知春路 五道口 上地 西二旗 龙泽 回龙观 霍营'.split()
EAST = '立水桥 北苑 望京西 芍药居 光熙门 柳芳 东直门'.split()
FULL = '西直门 大钟寺 知春路 五道口 上地 清河站 西二旗 龙泽 回龙观 霍营 立水桥 北苑 望京西 芍药居 光熙门 柳芳 东直门'.split()


def main():
    data = read('data/campaigns.json'); cities = read('data/cities.json')
    official = read('data/official_targets_2026-10-01.json'); baseline = read('data/network_baselines_2026-10-01.json')
    campaign = data['cities']['beijing']; geography = next(c for c in cities['cities'] if c['id'] == 'beijing')
    target = official['cities']['beijing']; row = baseline['cities']['beijing']
    stages = [dict(chapterId='beijing-line13-west-2002', date='2002-09-28', title='城市铁路西段：西直门至霍营',
        taskId='opening:bj13-west', stationNames=WEST, source=WEST_SOURCE, sourcePublicationDate='2002-09-28',
        sourceType='contemporary_news_agency_report',
        opening='2002年9月28日，西直门至霍营西段试运营，北京地铁路网开始向北部地面与高架走廊拓展。',
        precisionNote='新华社现场报道及运营方纪念票记录证明西段9站开放；现代近似站位不代表当年工程测绘。'),
        dict(chapterId='beijing-line13-east-2003', date='2003-01-28', title='城市铁路东西贯通', taskId='opening:bj13-east',
             constructionStationNames=['霍营']+EAST, stationNames=WEST+EAST, source=EAST_SOURCE, sourcePublicationDate='2016-09-08'),
        dict(chapterId='beijing-network-milestone-2019-07-26', date='2019-12-30', title='13号线清河站投入使用',
             taskId='route:beijing-r13', stationNames=FULL, source=QINGHE_SOURCE, sourcePublicationDate='2025-08-20',
             replaceChapterStory=True, purpose='在上地与西二旗之间补建清河站，保留其余16座既有车站和线路。')]
    apply_phases(campaign, geography, target, row, line_id='beijing-line13-13', route_id='beijing-r13', stages=stages,
                 revision=REVISION, cutoff_order=FULL, order_source='https://www.bjmoa.cn/metroLineList.html?sline=11')
    reschedule_transfers(campaign, target, ['beijing-line13-13', 'beijing-route-20'])
    generated = build(cities, data)['cities']['beijing']
    for key in ['routes', 'mapRouteEntryCount', 'mapRouteStopOccurrenceCount', 'mapUniqueStationCount']: row[key] = generated[key]
    refresh_schedule('beijing', row, campaign, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='13号线恢复2002西段9站、2003东段贯通16站、2019清河增站17站，不在2019一次建设现代全线。')
    for path, value in [('data/cities.json', cities), ('data/campaigns.json', data),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('Beijing13: west9 / east-through16 / Qinghe17; original task identity preserved')


if __name__ == '__main__': main()
