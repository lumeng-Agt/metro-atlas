"""Dated first-build, service split and extension; never clone a modern full line.

Expected opening orders are authored below independently of the campaign.
The current operator inventory is only the geographic/body lookup. The split
is a chapter ending at the November opening, not a claim it happened that day.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read, write, normalize

REVISION = '2026.10.24.14'
FIRST = 'https://www.chinametro.net/index.php?aid=51326&id=539&m=newscon'
SPLIT = 'https://news.chengdu.cn/2023/0904/2371119.shtml'
SHARED = 'https://www.thepaper.cn/newsDetail_forward_24520657'
OPEN19 = 'https://www.chengdurail.com/info/1151/51732.htm'
OPEN17 = 'https://news.chengdu.cn/2025/0916/68c914750c3a9c5be1c4be5c.shtml'
LINE17 = 'chengdu-line17-12'
LINE19 = 'chengdu-line19-14'
LINE18 = 'chengdu-line18-13'


def main():
    campaigns = read('data/campaigns.json')
    official = read('data/official_targets_2026-10-01.json')
    cd = campaigns['cities']['chengdu']
    chapters = {c['id']: c for c in cd['chapters']}
    catalog = {s['id']: s for c in read('data/cities.json')['cities'] if c['id'] == 'chengdu' for s in c['stations']}
    cutoff = next(c for c in cd['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    templates = {g['historicalLineId']: deepcopy(g) for g in cutoff['lineGroups']}
    lookup = {normalize(s['name']): sid for sid, s in catalog.items()}
    # The source inventories contain separate line-body reference points at
    # Fengxi. A shared complex identity does not move or merge those bodies.
    cd.setdefault('stationComplexAliases', {})['chengdu-s352']='chengdu-s58'
    shared_ids = ['chengdu-s309', 'chengdu-s310', 'chengdu-s312', 'chengdu-s313']
    # Publicly documented through running: reuse real track/body instances;
    # these are not four pedestrian transfer links between duplicate platforms.
    for sid in shared_ids:
        cd.setdefault('stationInstanceAliases', {})[f'{LINE19}|{sid}'] = templates[LINE18]['stationInstances'][sid]
    for g in cutoff['lineGroups']:
        if g['historicalLineId'] == LINE19:
            for sid in shared_ids:
                g['stationInstances'][sid] = templates[LINE18]['stationInstances'][sid]
            g['sharedTrackEvidence'] = SHARED
    cutoff['scopeRevision'] = REVISION

    first_names = '金星 黄石 市五医院 凤溪河 温泉大道 明光 九江北 白佛桥 机投桥'.split()
    short_names = '九江北 白佛桥 机投桥'.split()
    nineteen_first = '金星 黄石 市五医院 凤溪河 温泉大道 明光 九江北'.split()
    nineteen_second = '九江北 龙桥路 双流机场2航站楼东 龙港 温家山 牧华路 怡心湖 正兴湾 红莲 天府商务区 蓝家店 天府站 三岔 福田 天府机场1号2号航站楼 天府机场北'.split()
    seventeen_second = '机投桥 阳公桥 龙爪堰 清水河大桥 浣花里 省骨科医院 小南街 人民公园 西大街 城隍庙 红星桥 建设北路 踏水桥 二仙桥 机车厂 人民塘 航天路 威灵 高洪'.split()

    def group(line, names, key, source, replace=False):
        template = deepcopy(templates[line])
        # Resolve only within the line's geographic inventory. Two different
        # complexes with the same name may not be selected by array order.
        ids_by_name = {normalize(catalog[s]['name']): s for s in template['stationIds']}
        if line == LINE17:
            ids_by_name.update({n: lookup[n] for n in first_names[:6]})
        ids = [ids_by_name[normalize(n)] for n in names]
        instances = {}
        for sid, name in zip(ids, names):
            instances[sid] = template.get('stationInstances', {}).get(sid, sid)
            if line == LINE17 and name in first_names[:6]:
                instances[sid] = templates[LINE19]['stationInstances'][sid]
            if line == LINE19 and sid in shared_ids:
                instances[sid] = templates[LINE18]['stationInstances'][sid]
        template.update(stationIds=ids, stationInstances=instances, stationNames=dict(zip(ids, names)),
                        taskId=key, coverageGroupId=key, replaceExistingService=replace,
                        reconfirmLaterServices=replace, stationOrderSource=source,
                        servicePathRevision=5, loop=False,
                        precisionNote='本期范围和线路关系按开通、拆分公告核对；复用既有物理站体。地下线位与站台结构仍为地理示意。')
        return template

    first = chapters['chengdu-network-milestone-2020-12-18']
    original_transfers = {t['id']: deepcopy(t) for c in cd['chapters'] for t in c.get('requiredTransfers', [])}
    first['lineGroups'] = [g for g in first['lineGroups'] if g['historicalLineId'] != LINE17]
    first['lineGroups'].append(group(LINE17, first_names, 'opening:cd17-first-2020', FIRST, True))
    first.pop('unreviewedHistoricalScopes', None)
    first['scopeRevision'] = REVISION

    split_id = 'chengdu-reorganization-17-19-2023'
    split = deepcopy(chapters['chengdu-opening-line18-terminal-2021'])
    split.update(id=split_id, date='2023-11-27', title='17／19号线拆分：保留轨道，整理线路归属',
                 requiresLineReorganization=True, operationType='reorganization', eventOnly=False,
                 lineGroups=[group(LINE17, short_names, 'reorganization:cd17-short', SPLIT, True),
                             group(LINE19, nineteen_first, 'reorganization:cd19-first', SPLIT, True)],
                 historicalEventIds=['cd-17-19-service-split-2023'], requiredTransfers=[],
                 source=SPLIT, sourceTitle='成都轨道集团对17／19号线拆分运营的公开答复',
                 sourcePublicationDate='2023-09-04', sourceCheckedAt='2026-10-24',
                 chapterScope='dated_service_reorganization', requiresScopeRecheck=True,
                 scopeRevision=REVISION, routeTargetCount=2)
    split['eventText']='19号线二期开通前，既有金星—机投桥线路在九江北拆分：西段归入19号线，17号线保留九江北—机投桥。整理线路关系，不拆除既有轨道。'
    split['periodEndDateNote']='本章以二期开通前一日为范围终点，不将该日冒充拆分实际生效日；公开答复已说明拆分范围与同台换乘。'
    split['story'].update(opening=split['eventText'], purpose='亲手将既有轨道分成两条线路，在九江北确认换乘联系。',
                          outcome='原有实体轨道保留；九江北成为两条线路的换乘节点。')
    split['scopeCorrections'] = []
    for name in first_names[:6]:
        sid = lookup[name]
        split['scopeCorrections'].append({'id': 'cd17-to19-'+sid, 'taskId':'', 'source':SPLIT,
            'description': f'{name}既有站体归入19号线，位置、朝向和轨道保持。',
            'bodyLineReclassification': {'stationInstanceId': templates[LINE19]['stationInstances'][sid],
                'oldLineId': LINE17, 'newLineId': LINE19, 'newLineName':'19号线'}})
    chapters[split_id] = split

    second19 = chapters['chengdu-network-milestone-2023-11-28']
    second19.update(lineGroups=[group(LINE19, nineteen_second, 'opening:cd19-second-2023', OPEN19)],
                    requiresLineReorganization=False, requiresScopeRecheck=True, scopeRevision=REVISION,
                    source=OPEN19, sourceTitle='成都地铁19号线二期11月28日开通初期运营',
                    sourcePublicationDate='2023-11-27', routeTargetCount=1,
                    chapterScope='dated_opening_ranges', title='双机场联系：19号线二期与18号线共线')
    second19['story'].update(opening='复用19号线一期端点，向东连接天府站，并按公开运营方案在天府站以东接入18号线既有轨道。',
                             purpose='建设二期新段，并让19号线列车沿18号线既有三岔—机场北区间展示；共线不等于新建四座换乘站。')
    second19['scopeCorrections'] = []
    # Old duplicate bodies and track remain editable. Only the specifically
    # known old pedestrian transfer records cease to represent through running.
    shared_transfers = {k:t for k,t in original_transfers.items()
                        if t['complexId'] in shared_ids and set(t['lineIds']) == {LINE18, LINE19}}
    for tid, t in shared_transfers.items():
        second19['scopeCorrections'].append({'id':'archive-shared-'+tid, 'taskId':'', 'transferId':tid,
            'oldStationInstanceIds':t['stationInstanceIds'], 'oldLineIds':t['lineIds'], 'source':SHARED,
            'description':t['name']+'按18／19共线方案复用既有轨道，不再把旧重复站体间步行联系当作必要换乘。'})
        original_transfers.pop(tid)
    cutoff.setdefault('scopeCorrections', [])[:] = [x for x in cutoff.get('scopeCorrections', []) if not str(x.get('id','')).startswith('archive-shared-')]
    cutoff['scopeCorrections'].extend(deepcopy(second19['scopeCorrections']))

    second17 = chapters['chengdu-opening-line10-phase3-first-2025']
    second17['lineGroups'] = [g for g in second17['lineGroups'] if g['historicalLineId'] != LINE17]
    second17['lineGroups'].append(group(LINE17, seventeen_second, 'opening:cd17-second-2025', OPEN17))
    second17.update(title='17号线二期与10号线三期先开段', scopeRevision=REVISION, requiresScopeRecheck=True,
                    routeTargetCount=len(second17['lineGroups']))

    # First physical arrival of the existing verified interchange pairs, plus
    # the missing Fengxi transfer. Rename the line membership at the split.
    fengxi = lookup['凤溪河']
    four_id=next(s for s in templates['chengdu-line4-4']['stationIds'] if catalog[s]['name']=='凤溪河')
    four = templates['chengdu-line4-4']['stationInstances'][four_id]
    western_body = templates[LINE19]['stationInstances'][fengxi]
    old_fengxi = {'id':'historic-transfer-cd-fengxi-4-17', 'name':'凤溪河', 'complexId':four_id,
        'stationInstanceIds':[four,western_body], 'lineIds':['chengdu-line4-4',LINE17],
        'source':FIRST, 'precision':'schematic', 'sourceNote':'首开时凤溪河与4号线的独立线路站体换乘。'}
    new_fengxi = dict(deepcopy(old_fengxi), id='historic-transfer-cd-fengxi-4-19',
        lineIds=['chengdu-line4-4',LINE19], source=SPLIT,
        sourceNote='拆分后西段归19号线，复用原凤溪河站体；换乘需明确确认新线路配对。')
    original_transfers[old_fengxi['id']] = old_fengxi
    original_transfers[new_fengxi['id']] = new_fengxi
    split['scopeCorrections'].append({'id':'archive-fengxi-4-17', 'taskId':'', 'transferId':old_fengxi['id'],
        'oldStationInstanceIds':old_fengxi['stationInstanceIds'], 'oldLineIds':old_fengxi['lineIds'],
        'source':SPLIT, 'description':'凤溪河西段改归19号线，确认4／19号线换乘；原4／17历史记录归档。'})
    # Old 2020 snapshots incorrectly included second-phase interchanges. Only
    # exact known old pairings may be archived before the corrected first scope.
    first['scopeCorrections'] = [x for x in first.get('scopeCorrections',[]) if not str(x.get('id','')).startswith('defer-17phase2-')]
    for t in original_transfers.values():
        if LINE17 in t['lineIds'] and t['complexId'] in [lookup[n] for n in seventeen_second[1:]]:
            first['scopeCorrections'].append({'id':'defer-17phase2-'+t['id'], 'taskId':'', 'transferId':t['id'],
                'oldStationInstanceIds':t['stationInstanceIds'], 'oldLineIds':t['lineIds'], 'source':OPEN17,
                'description':t['name']+'属于2025年17号线二期，保留建设，稍后按实际日期确认线路及换乘。'})

    ordered = sorted(chapters.values(), key=lambda c:c['date'])
    available = {}; aliases=cd.get('stationComplexAliases',{})
    canonical = lambda s: aliases.get(s,s)
    for c in ordered:
        c['requiredTransfers'] = []
        for g in c.get('lineGroups',[]):
            for sid in g['stationIds']:
                available.setdefault((g['historicalLineId'],canonical(sid)), c)
    for t in original_transfers.values():
        if t['id'] == new_fengxi['id'] or t['id'].endswith('s287-line17-12-line19-14'):
            destination = split
        elif t['id'] == old_fengxi['id']:destination = first
        else:
            keys=[(line,canonical(t['complexId'])) for line in t['lineIds']]
            if not all(k in available for k in keys):raise ValueError(('missing transfer bodies',t))
            destination=max((available[k] for k in keys),key=lambda c:c['date'])
        destination['requiredTransfers'].append(t)
    cd['chapters'] = ordered

    target = official['cities']['chengdu']
    def expected(g, names, **extra):
        return dict(id=g['coverageGroupId'], historicalLineId=g['historicalLineId'], scopeType='stations',
                    stationNames=names, allowReverse=True, **extra)
    first_answer = next(m for m in target['historicalMilestones'] if m['chapterId']==first['id'])
    first_answer['groups'] = [g for g in first_answer['groups'] if g['historicalLineId']!=LINE17]
    first_answer['groups'].append(expected(first['lineGroups'][-1],first_names,
        bodyLineAliases=[LINE19],bodyLineAliasEvidence=SPLIT))
    target['historicalMilestones'] = [m for m in target['historicalMilestones'] if m['chapterId'] not in [split_id,second19['id']]]
    target['historicalMilestones'].extend([
        {'chapterId':split_id, 'date':split['date'], 'source':SPLIT, 'sourcePublicationDate':'2023-09-04',
         'periodEndDateNote':split['periodEndDateNote'], 'groups':[
             expected(split['lineGroups'][0],short_names,fullServiceOrder=True), expected(split['lineGroups'][1],nineteen_first,fullServiceOrder=True)],
         'transfers':[new_fengxi['id'],'historic-transfer-chengdu-s287-line17-12-line19-14']},
        {'chapterId':second19['id'], 'date':second19['date'], 'source':OPEN19, 'sourcePublicationDate':'2023-11-27',
         'groups':[expected(second19['lineGroups'][0],nineteen_second,
             bodyLineAliases=[LINE18],bodyLineAliasEvidence=SHARED)]}])
    seventeen_answer = next(m for m in target['historicalMilestones'] if m['chapterId']==second17['id'])
    seventeen_answer['groups']=[g for g in seventeen_answer['groups'] if g['historicalLineId']!=LINE17]
    seventeen_answer['groups'].append(expected(second17['lineGroups'][-1],seventeen_second))
    for g in target['cutoffNetwork']['groups']:
        if g['historicalLineId']==LINE19:g.update(bodyLineAliases=[LINE18],bodyLineAliasEvidence=SHARED)
    if tuple(map(int,campaigns.get('contentRevision','0').split('.')))<tuple(map(int,REVISION.split('.'))):
        campaigns['contentRevision']=REVISION
    campaigns['contentRevisionNote']='成都17号线首期九站、17／19拆分和2025二期分别建设；18／19有公开依据的共线区间复用既有轨道，旧站轨保留。'
    write('data/campaigns.json',campaigns);write('data/official_targets_2026-10-01.json',official)
    print('Chengdu 17/19: first 9, split 3+7, extension 16, second 17-phase 19 incl joint; shared track reused')


if __name__=='__main__':main()
