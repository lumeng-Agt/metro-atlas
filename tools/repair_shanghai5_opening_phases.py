"""Restore the 2003 opening, 2018 shuttle and 2020 through-service change."""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write
from expand_historical_event_chapters import refresh_schedule

REV = '2026.10.27.1'
LINE = 'shanghai-line5-5'
FIRST = 'https://news.sina.cn/sa/2003-11-26/detail-ikkntiak8685403.d.html?vt=4'
CHANGE = 'https://jtw.sh.gov.cn/bmts/20201225/be0cf9f1e8fa4fdf8c81b624df3fda7d.html'
ORIGINAL = '莘庄 春申路 银都路 颛桥 北桥 剑川路 东川路 金平路 华宁路 文井路 闵行开发区'.split()
SOUTH = '莘庄 春申路 银都路 颛桥 北桥 剑川路 东川路 江川路 西渡 萧塘 奉浦大道 环城东路 望园路 金海湖 奉贤新城'.split()
SCOPES = [
    ('shanghai-line5-first-2003', '2003-11-25', '5号线首开：莘庄至闵行开发区', [ORIGINAL], FIRST, '2003-11-26'),
    ('shanghai-network-milestone-2018-12-30', '2018-12-30', '5号线南延伸：奉贤主线与东川支线', [SOUTH, ORIGINAL[6:]], CHANGE, '2020-12-25'),
    ('shanghai-network-milestone-2020-12-26', '2020-12-26', '5号线支线恢复直达与10号线延伸', [SOUTH, ORIGINAL], CHANGE, '2020-12-25'),
]


def main():
    data = read('data/campaigns.json'); official = read('data/official_targets_2026-10-01.json')
    city = data['cities']['shanghai']; target = official['cities']['shanghai']
    chapters = {c['id']: c for c in city['chapters']}
    cutoff = next(c for c in city['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    templates = [g for g in cutoff['lineGroups'] if g['historicalLineId'] == LINE]
    lookup = {name: sid for g in templates for sid, name in g['stationNames'].items()}
    instances = {s: g.get('stationInstances', {}).get(s, s) for g in templates for s in g['stationIds']}
    sample = deepcopy(chapters['shanghai-line11-changji-2011'])
    reviewed = []
    for cid, date, title, orders, source, published in SCOPES:
        if cid not in chapters:
            chapter = deepcopy(sample)
            chapter.update(id=cid, date=date, lineGroups=[], requiredTransfers=[], scopeCorrections=[],
                           historicalEventIds=[], serviceTransitions=[], eventOnly=False)
            chapters[cid] = chapter
        chapter = chapters[cid]
        chapter['lineGroups'] = [g for g in chapter.get('lineGroups', []) if g['historicalLineId'] != LINE]
        new_groups = []; expected = []
        for index, order in enumerate(orders):
            ids = [lookup[n] for n in order]
            group = deepcopy(templates[0])
            group.update(taskId=f'opening:sh5:{date}:pattern-{index+1}',
                         coverageGroupId=f'sh5:{date}:pattern-{index+1}', name='5号线 · ' + order[0] + '—' + order[-1],
                         stationIds=ids, stationNames=dict(zip(ids, order)), stationInstances={s: instances[s] for s in ids},
                         stationOrderSource=source, constructionScope='dated_service_patterns', sourceStationIds=ids[:],
                         constructionScopeNote='有来源的完整时期交路，复用已建站轨；不模拟发车。',
                         replaceExistingService=index == 0, reconfirmLaterServices=True,
                         retainDocumentedFutureService=False, servicePathRevision=REV, loop=False,
                         precisionNote='开通及交路变更按同期报道和交通委公告核对；近似地理走廊不代表测绘。2018支线在东川路折返，2020才恢复莘庄直达。')
            new_groups.append(group)
            expected.append(dict(id=group['coverageGroupId'], historicalLineId=LINE,
                                 stationNames=order, allowReverse=True, fullServiceOrder=True))
        chapter['lineGroups'] += new_groups
        chapter.update(title=title, date=date, requiresScopeRecheck=True, scopeRevision=REV,
                       routeTargetCount=len(chapter['lineGroups']), source=source, sourcePublicationDate=published,
                       sourceTitle='5号线同期首开报道及上海市交通委2020年交路变更公告', sourceCheckedAt='2026-10-27')
        if len(chapter['lineGroups']) == len(new_groups):
            chapter['chapterScope'] = 'dated_opening_ranges'
        message = f'{date}，{title}。先复用既有站体，再核对本期两端及支线关系；不能把两个分支串成经过莘庄折返的单一路径。'
        chapter['eventText'] = message; chapter['story']['opening'] = message
        chapter['story']['purpose'] = '按实际时期的连接关系建设；2018年支线独立折返，2020年线路关系调整后才直达莘庄。'
        chapter['story']['outcome'] = '本期站体、区间及线路关系已确认；后续历史另列任务。'
        chapter['operationType'] = 'reorganization' if date == '2020-12-26' else 'extension'
        reviewed.append(dict(chapterId=cid, date=date, source=source, sourcePublicationDate=published,
                             groups=expected, note='2020交通委原文同时明确调整前、后两种交路；非由游戏章节推导的验收站序。'))
    # Explicitly preserve the geometry of completed later work while reopening
    # only the sourced, affected services and their out-of-period contacts.
    first = chapters[SCOPES[0][0]]; allowed = {instances[lookup[n]] for n in ORIGINAL}
    first['scopeCorrections'] = [c for c in first.get('scopeCorrections', []) if not c.get('id', '').startswith('defer-sh5:')]
    for plan in city.get('futurePlans', []):
        for transfer in plan.get('requiredTransfers', []):
            if LINE not in transfer['lineIds']: continue
            body = transfer['stationInstanceIds'][transfer['lineIds'].index(LINE)]
            if body not in allowed:
                first['scopeCorrections'].append(dict(id='defer-sh5:' + transfer['id'], taskId=first['lineGroups'][0]['taskId'],
                    transferId=transfer['id'], oldLineIds=transfer['lineIds'], oldStationInstanceIds=transfer['stationInstanceIds'],
                    source=FIRST, description='该5号线站体不在2003首开范围；保留建设及旧联系记录，待后续规划任务明确重新确认。'))
    city['chapters'] = sorted(chapters.values(), key=lambda c: c['date'])
    for group in target['cutoffNetwork']['groups']:
        if group.get('historicalLineId') != LINE: continue
        original = group.get('stationNames') in [ORIGINAL, list(reversed(ORIGINAL))]
        group.update(lastPhysicalOpeningDate='2003-11-25' if original else '2018-12-30',
                     lastPhysicalOpeningSource=FIRST if original else CHANGE,
                     physicalOpeningNote='物理站区日期与2020年直达交路恢复分开核对；不把交路调整当作重建旧站。')
    ids = {c[0] for c in SCOPES}
    for row in target.get('historicalMilestones', []):
        if row['chapterId'] in ids:
            row['groups'] = [g for g in row.get('groups', []) if g.get('historicalLineId') != LINE]
    for row in reviewed:
        existing = next((m for m in target.get('historicalMilestones', []) if m['chapterId'] == row['chapterId']), None)
        if existing is None: target.setdefault('historicalMilestones', []).append(row)
        else: existing['groups'] += row['groups']
    baseline = read('data/network_baselines_2026-10-01.json'); ledger = baseline['cities']['shanghai']
    obsolete = [e for e in ledger['documentedMilestones'] if e.get('routeIds') == ['shanghai-r5'] and not e['id'].startswith('reviewed-sh5:')]
    archive = ledger.setdefault('supersededDocumentedMilestones', [])
    for event in obsolete:
        if not any(e['id'] == event['id'] for e in archive): archive.append(dict(event, supersededReason='5号线按2003首开、2018南延及2020直达分别记录。'))
    removed = {e['id'] for e in obsolete}
    ledger['documentedMilestones'] = [e for e in ledger['documentedMilestones'] if e['id'] not in removed and not e['id'].startswith('reviewed-sh5:')]
    for chapter in city['chapters']:
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds', []) if e not in removed and not e.startswith('reviewed-sh5:')]
    for cid, date, title, _orders, source, published in SCOPES:
        event_id = 'reviewed-sh5:' + date
        chapter = chapters[cid]
        chapter['historicalEventIds'] = list(dict.fromkeys(chapter.get('historicalEventIds', []) + [event_id]))
        ledger['documentedMilestones'].append(dict(id=event_id, date=date, title=title, chapterId=cid,
            status='operated', source=source, sourcePublicationDate=published, routeIds=['shanghai-r5'],
            targetLineGroups=deepcopy([g for g in chapter['lineGroups'] if g['historicalLineId'] == LINE])))
    ledger['documentedMilestones'].sort(key=lambda e: (e['date'], e['id']))
    ledger['documentedMilestoneCount'] = len(ledger['documentedMilestones'])
    refresh_schedule('shanghai', ledger, city, '2026-10-01')
    if str(data.get('contentRevision', '')) <= REV:
        data.update(contentRevision=REV, contentRevisionNote='5号线补回2003首开、2018主线与东川折返支线、2020支线直达，修复现代全线拼接造成的假折返。')
    for path, value in [('data/campaigns.json', data), ('data/official_targets_2026-10-01.json', official), ('data/network_baselines_2026-10-01.json', baseline)]: write(path, value)
    print('SH5: sourced 2003 opening, 2018 main/shuttle, 2020 through-service; physical construction preserved')


if __name__ == '__main__': main()
