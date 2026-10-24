"""Repair three stale source-directory dates without changing stable IDs.

These chapter scopes were already reviewed. The old generated directory still
carried unrelated modern-snapshot dates, creating unreachable empty intervals.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.24.29'
BOND = 'https://static.sse.com.cn/bond/bridge2/disclosure/announcement/c/202606/9dbefc_20260618_SLKT.pdf'
SCOPES = [
    ('guangzhou', 'guangzhou-network-milestone-2022-09-28', '2021-09-28',
     'https://www.cnr.cn/gd/guangdongyaowen/20210928/t20210928_525617567.shtml', '2021-09-28',
     '广州地铁十八号线首通段今日开通运营：记者向运营方核实'),
    ('chengdu', 'chengdu-network-milestone-2017-12-26', '2017-06-02', BOND, '2026-06-18',
     '成都轨道交通2026年债券募集说明书：4号线二期通车日期表'),
    ('chengdu', 'chengdu-network-milestone-2019-06-02', '2019-12-27', BOND, '2026-06-18',
     '成都轨道交通2026年债券募集说明书：5号线一二期通车日期表'),
]


def main():
    data = read('data/campaigns.json'); baseline = read('data/network_baselines_2026-10-01.json')
    official = read('data/official_targets_2026-10-01.json')
    for city_id, chapter_id, date, source, publication, title in SCOPES:
        city = data['cities'][city_id]; row = baseline['cities'][city_id]
        chapter = next(c for c in city['chapters'] if c['id'] == chapter_id)
        assert chapter['date'] == date, (chapter_id, chapter['date'], date)
        chapter.update(source=source, sourcePublicationDate=publication, sourceTitle=title)
        for group in chapter.get('lineGroups', []):
            group.update(stationOrderSource=source, source=source)
        for milestone in official['cities'][city_id]['historicalMilestones']:
            if milestone['chapterId'] == chapter_id:
                milestone.update(source=source, sourcePublicationDate=publication)
        for event in row['documentedMilestones']:
            if event.get('chapterId') != chapter_id: continue
            if event['date'] != date:
                archived = row.setdefault('supersededDocumentedMilestones', [])
                if not any(e['id'] == event['id'] for e in archived):
                    archived.append(dict(deepcopy(event), supersededReason='旧生成目录沿用错误快照日期；按运营方正式通车记录修正。'))
            event.update(date=date, source=source, sourcePublicationDate=publication, title=chapter['title'],
                         targetLineGroups=deepcopy(chapter.get('lineGroups', [])))
        row['documentedMilestones'].sort(key=lambda e: (e['date'], e['id']))
        refresh_schedule(city_id, row, city, '2026-10-01')
    data.update(contentRevision=REVISION, contentRevisionNote='同步广州18号线、成都4号线二期和5号线的真实开放日期到来源目录，保留存档稳定章节身份。')
    for path, value in [('data/campaigns.json', data), ('data/network_baselines_2026-10-01.json', baseline),
                        ('data/official_targets_2026-10-01.json', official)]: write(path, value)
    print('Three reviewed event-directory dates now match their playable chapters; stable IDs retained')


if __name__ == '__main__': main()
