"""Bind three published opening scopes to existing Shenzhen milestone tasks.

Literal stop orders are transcribed from operator/government information,
not reconstructed from the chapters being tested. No player saves are edited.
"""
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule

REVISION = '2026.10.25.13'
ORDER_SOURCE = 'https://www.mtrsz.com.cn/frontend/default/src/channel/line_introduce_13Line.html'
SOUTH_ORDER_SOURCE = 'https://ka.sz.gov.cn/gkmlpt/content/11/11673/mpost_11673022.html'
SOUTH_OPENING_SOURCE = 'https://www.szmc.net/home/xinwenzhongxin/gongsixinwen/202512/105561.html'
NORTH_OPENING_SOURCE = 'https://jtys.sz.gov.cn/zwgk/jtzx/cxtx/content/post_12576020.html'
EXTENSION_OPENING_SOURCE = 'https://www.sz.gov.cn/cn/xxgk/zfxxgj/bmdt/content/post_12880227.html'
SKIP_SOURCE = 'https://hmo.sz.gov.cn/zx/wqzc/content/post_1642610.html'
SOUTH = '深圳湾口岸 人才公园 后海 科苑 粤海门 深大 高新中'.split()
PHASE_ONE = SOUTH + '高新北 石鼓 留仙洞 百旺 应人石 罗租 石岩 上屋'.split()
FULL = PHASE_ONE + '红坳公园 光明城 德雅路 凤凰城 月亮路 将围 新庄 公明广场 上村 下村 李松蓢'.split()


def main():
    data = read('data/campaigns.json'); cities = read('data/cities.json')
    official = read('data/official_targets_2026-10-01.json'); baseline = read('data/network_baselines_2026-10-01.json')
    campaign = data['cities']['shenzhen']; geography = next(c for c in cities['cities'] if c['id'] == 'shenzhen')
    target = official['cities']['shenzhen']; row = baseline['cities']['shenzhen']
    stages = [
        dict(chapterId='shenzhen-network-milestone-2024-12-28', date='2024-12-28', title='13号线南段：深圳湾口岸至高新中',
             taskId='dated:shenzhen-2024-12-28-five-openings:shenzhen-line13-14', stationNames=SOUTH,
             source=SOUTH_OPENING_SOURCE, sourcePublicationDate='2025-12-29',
             precisionNote='口岸办公室逐站南段范围与运营方已开通日期回顾相互核对：7站6区间；线路几何为近似地理参考。'),
        dict(chapterId='shenzhen-network-milestone-2025-12-28', date='2025-12-28', title='13号线一期贯通至上屋',
             taskId='dated:shenzhen-2025-12-28-lines5-8-11-13:shenzhen-line13-14:range-1', stationNames=PHASE_ONE,
             constructionStationNames=['高新中'] + PHASE_ONE[len(SOUTH):],
             source=NORTH_OPENING_SOURCE, sourcePublicationDate='2025-12-29',
             precisionNote='交通运输局开通公告和港铁逐站表核对；西丽高铁站因枢纽施工越站，不计开放停站。'),
        dict(chapterId='shenzhen-network-milestone-2026-06-28', date='2026-06-28', title='13号线二期北延至李松蓢',
             taskId='dated:shenzhen-2026-06-28-line13-north:shenzhen-line13-14:range-1', stationNames=FULL,
             constructionStationNames=['上屋'] + FULL[len(PHASE_ONE):],
             source=EXTENSION_OPENING_SOURCE, sourcePublicationDate='2026-07-06',
             precisionNote='市国资委开通回顾确认2026年6月28日、上屋不含至李松蓢11座新增站；站序由港铁逐站表独立核对。'),
    ]
    names={s['id']:s['name'] for s in geography['stations']}
    for stage in stages:
        chapter=next(c for c in campaign['chapters'] if c['id']==stage['chapterId'])
        group=next(g for g in chapter['lineGroups'] if g['historicalLineId']=='shenzhen-line13-14')
        wanted=stage.get('constructionStationNames',stage['stationNames'])
        assert [names[s] for s in group['stationIds']]==wanted, 'Existing task differs from independently reviewed subsection'
        group.update(stationOrderSource=stage['source'],precisionNote=stage['precisionNote'])
        chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        milestone = next((m for m in target['historicalMilestones'] if m['chapterId'] == stage['chapterId']),None)
        if milestone is None:
            milestone=dict(chapterId=chapter['id'],date=stage['date'],source=stage['source'],sourcePublicationDate=stage['sourcePublicationDate'],groups=[])
            target['historicalMilestones'].append(milestone)
        expected=dict(id=group['coverageGroupId'] if 'coverageGroupId' in group else group['taskId'],historicalLineId='shenzhen-line13-14',scopeType='stations',stationNames=stage['stationNames'],constructionStationNames=wanted,fullServiceOrder=True,allowReverse=True)
        milestone['groups']=[g for g in milestone['groups'] if g.get('historicalLineId',g['id'])!='shenzhen-line13-14']+[expected]
        milestone['additionalSources']=list(dict.fromkeys(milestone.get('additionalSources',[])+[ORDER_SOURCE,stage['source']]))
        if stage['date'] == '2024-12-28':
            milestone['additionalSources'] = list(dict.fromkeys(milestone.get('additionalSources', []) + [SOUTH_ORDER_SOURCE]))
        for expected in milestone['groups']:
            if expected.get('historicalLineId') == 'shenzhen-line13-14':
                expected['forbiddenStationNames'] = ['西丽高铁']
                expected['unopenedStationEvidence'] = SKIP_SOURCE
    # Existing correct multi-line events retain their stable IDs. Earlier
    # materialization used the single-line phase helper; restore that archived
    # event rather than making already completed saves confirm a renamed ID.
    prefix='reviewed-phases:shenzhen-r14:'
    row['documentedMilestones']=[e for e in row['documentedMilestones'] if not e['id'].startswith(prefix)]
    existing={e['id'] for e in row['documentedMilestones']}
    for archived in row.get('supersededDocumentedMilestones',[]):
        if archived['id']=='shenzhen-2026-06-28-line13-north' and archived['id'] not in existing:
            restored=dict(archived);restored.pop('supersededReason',None)
            row['documentedMilestones'].append(restored);existing.add(restored['id'])
    for chapter in campaign['chapters']:
        chapter['historicalEventIds']=[e for e in chapter.get('historicalEventIds',[]) if not e.startswith(prefix)]
        for event in row['documentedMilestones']:
            if event.get('date')==chapter['date'] and 'shenzhen-r14' in event.get('routeIds',[]) and event['id'] not in chapter['historicalEventIds']:
                chapter['historicalEventIds'].append(event['id'])
    row['documentedMilestoneCount']=len(row['documentedMilestones'])
    evidence = target['cutoffNetwork'].setdefault('temporalEvidence', [])
    for stage in stages:
        record = dict(source=stage['source'], effectiveDate=stage['date'], scope=stage['title'],
                      historicalLineId='shenzhen-line13-14', chapterId=stage['chapterId'])
        if record not in evidence: evidence.append(record)
    target['cutoffNetwork']['note'] = '17条路径站序另有独立清单；本次仅补核13号线三期开放证据，不宣称其余16条截止日时序已全部审核。'
    refresh_schedule('shenzhen', row, campaign, '2026-10-01')
    revision_key = lambda value: tuple(int(part) for part in value.split('.'))
    for doc in (data, baseline):
        if revision_key(REVISION) >= revision_key(doc.get('contentRevision', '0')): doc['contentRevision'] = REVISION
    data['contentRevisionNote'] = '深圳13号线三期开通独立核对：2024南段7站、2025贯通15站、2026北延26站；不开放西丽高铁站。'
    for path, value in [('data/cities.json', cities), ('data/campaigns.json', data),
                        ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('Shenzhen13 independent dated scopes: 7 / 15 / 26 open stops; Xili high-speed station excluded')


if __name__ == '__main__': main()
