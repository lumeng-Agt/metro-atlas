"""11-line first three stops and the separately dated Modekou extension."""
from repair_chengdu_historical_phases import read, write
from author_reviewed_route_phases import apply_phases, reschedule_transfers
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.25.6'
FIRST_SOURCE = 'https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202201/t20220101_2581335.html'
EXT_SOURCE = 'https://jtw.beijing.gov.cn/xxgk/xwfbh/202312/t20231229_3520885.html'


def main():
    data = read('data/campaigns.json'); cities = read('data/cities.json')
    official = read('data/official_targets_2026-10-01.json'); baseline = read('data/network_baselines_2026-10-01.json')
    campaign = data['cities']['beijing']; geography = next(c for c in cities['cities'] if c['id'] == 'beijing')
    target = official['cities']['beijing']; row = baseline['cities']['beijing']
    first = ['金安桥', '北辛安', '新首钢']; full = ['模式口'] + first
    stages = [dict(chapterId='beijing-network-milestone-2021-12-31', date='2021-12-31', title='11号线西段首开三站',
        taskId='route:beijing-r11', stationNames=first, source=FIRST_SOURCE, sourcePublicationDate='2022-01-01'),
        dict(chapterId='beijing-network-milestone-2023-12-30', date='2023-12-30', title='11号线模式口站开放',
            taskId='opening:bj11-modekou', constructionStationNames=['模式口', '金安桥'], stationNames=full,
            source=EXT_SOURCE, sourcePublicationDate='2023-12-29')]
    apply_phases(campaign, geography, target, row, line_id='beijing-line11-11', route_id='beijing-r11', stages=stages,
        revision=REVISION, cutoff_order=full, order_source='https://www.bjmoa.cn/metroLineList.html?sline=10')
    reschedule_transfers(campaign, target, ['beijing-line11-11'])
    generated = build(cities, data)['cities']['beijing']
    for key in ['routes', 'mapRouteEntryCount', 'mapRouteStopOccurrenceCount', 'mapUniqueStationCount']: row[key] = generated[key]
    refresh_schedule('beijing', row, campaign, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='11号线按2021年三站首开、2023年模式口延伸建设；同步保留13、10、19号线及昌平线已核对分期。')
    for path, value in [('data/cities.json', cities), ('data/campaigns.json', data),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('Beijing11: 3 stops in 2021; Modekou extends the same line to 4 stops in 2023')


if __name__ == '__main__': main()
