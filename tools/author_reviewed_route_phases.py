"""Author-time helper for independently transcribed dated route scopes.

Callers provide literal station orders and dated sources. This helper cannot
infer opening dates, certify a whole inventory, or mark player tasks complete.
"""
from copy import deepcopy


def apply_phases(campaign, geography, target, baseline, *, line_id, route_id, stages, revision,
                 cutoff_order, order_source, loop=False):
    chapters = {c['id']: c for c in campaign['chapters']}
    cutoff = next(c for c in campaign['chapters'] if c.get('chapterScope') == 'cutoff_reconciliation')
    template = deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == line_id))
    geographic_names = {s['id']: s['name'] for s in geography['stations']}
    # A duplicated same-name map member must not change the physical identity
    # already used by the task. Require the caller to choose its canonical ID.
    lookup = {}
    for sid in template['stationIds']: lookup.setdefault(geographic_names[sid], sid)
    for stage in stages:
        lookup.update(stage.get('stationIdOverrides', {}))
    assert set(cutoff_order).issubset(lookup), set(cutoff_order) - lookup.keys()
    original = [c for c in chapters.values() if any(g['historicalLineId'] == line_id for g in c.get('lineGroups', []))]
    for chapter in original:
        if chapter is not cutoff:
            chapter['lineGroups'] = [g for g in chapter['lineGroups'] if g['historicalLineId'] != line_id]
    for stage in stages:
        cid = stage['chapterId']; order = stage['stationNames']; construction = stage.get('constructionStationNames', order)
        source = stage['source']; date = stage['date']; task = stage['taskId']; title = stage['title']
        chapter = chapters.get(cid)
        if chapter is None:
            sample = next((c for c in campaign['chapters'] if c.get('chapterScope') == 'dated_opening_ranges'), original[0])
            chapter = deepcopy(sample)
            chapter.update(id=cid, date=date, title=title, lineGroups=[], requiredTransfers=[], scopeCorrections=[],
                serviceTransitions=[], historicalEventIds=[], eventOnly=False, operationType=stage.get('operationType', 'extension'),
                chapterScope='dated_opening_ranges', routeTargetCount=1, requireOpen=True, source=source,
                sourcePublicationDate=stage['sourcePublicationDate'], sourceType=stage.get('sourceType', 'government_dated_opening_notice'),
                sourceTitle=title, sourceCheckedAt='2026-10-25', status='trial_operation', eventText=title,
                alignmentNote='站序与分期开通有公开来源；现代地理参考及隧道走向为近似，不是工程测绘。')
            chapter['story'] = dict(opening=stage.get('opening', title+'。'), purpose=stage.get('purpose', '复用既有站轨，完成本期新增范围。'),
                outcome=stage.get('outcome', '核对本期线路与换乘，不提前开放后期范围。'), eventKind='network_expansion',
                steps=deepcopy(sample['story']['steps']), beats=[], planVersions=[])
            chapters[cid] = chapter
        else:
            chapter['date'] = date
            if stage.get('replaceChapterStory', False):
                chapter.update(title=title, source=source, sourcePublicationDate=stage['sourcePublicationDate'], eventText=title)
                chapter['story'].update(opening=title+'。', purpose=stage.get('purpose', '复用既有建设，确认本期范围。'),
                    outcome=stage.get('outcome', '本期线路建设完成。'))
        if not str(chapter.get('operationGuide','')).strip():
            chapter['operationGuide']=stage.get('operationGuide', f'复用既有站轨，按蓝图完成{construction[0]}至{construction[-1]}的本期范围，检查连续路径，再确认本期历史节点。')
        ids = [lookup[n] for n in construction]; group = deepcopy(template)
        # Original generated snapshot metadata cannot masquerade as the newly
        # reviewed contiguous range. Do not inherit stale sourceStationIds.
        for key in ['constructionScope', 'constructionScopeNote', 'sourceStationIds', 'sourceStationInstances', 'loop']:
            group.pop(key, None)
        group.update(taskId=task, coverageGroupId=task, name=title, stationIds=ids,
            stationNames=dict(zip(ids, construction)),
            stationInstances={s: template.get('stationInstances', {}).get(s, s) for s in ids},
            stationOrderSource=source, source=source, replaceExistingService=construction == order,
            reconfirmLaterServices=True, servicePathRevision=stage.get('pathRevision', 30), defaultServiceStatus='trial',
            precisionNote=stage.get('precisionNote', '官方分期开通站序；近似地理参考，不以现代全线快照代替历史范围。'))
        if stage.get('loop', False): group['loop'] = True
        chapter['lineGroups'].append(group)
        chapter.update(scopeRevision=revision, requiresScopeRecheck=True)
        milestone = next((m for m in target['historicalMilestones'] if m['chapterId'] == cid), None)
        if milestone is None:
            milestone = dict(chapterId=cid, date=date, source=source, sourcePublicationDate=stage['sourcePublicationDate'], groups=[])
            target['historicalMilestones'].append(milestone)
        milestone['date'] = date
        expected = dict(id=task, historicalLineId=line_id, scopeType='stations', stationNames=order,
            constructionStationNames=construction, allowReverse=True, fullServiceOrder=True, requiredServiceStatus='trial')
        if stage.get('loop', False): expected['loop'] = True
        milestone['groups'] = [g for g in milestone['groups'] if g.get('historicalLineId', g['id']) != line_id] + [expected]
        milestone['additionalSources'] = list(dict.fromkeys(milestone.get('additionalSources', []) + [source, order_source]))
    # An obsolete generated-only node can remain a dated information event;
    # its historical metadata is archived below. Never fabricate construction.
    for chapter in original:
        if chapter is cutoff or chapter['lineGroups']: continue
        chapter.update(eventOnly=True, routeTargetCount=0, requiresLineReorganization=False, serviceTransitions=[])
        chapter['story']['purpose'] = '原整线快照已拆回真实建设日期；本条保留旧节点身份，不重复要求铺轨。'
    full_ids = [lookup[n] for n in cutoff_order]
    cutoff_group = next(g for g in cutoff['lineGroups'] if g['historicalLineId'] == line_id)
    cutoff_group.update(stationIds=full_ids, stationNames=dict(zip(full_ids, cutoff_order)),
        stationInstances={s: template.get('stationInstances', {}).get(s, s) for s in full_ids},
        replaceExistingService=True, reconfirmLaterServices=True, servicePathRevision=30)
    if loop: cutoff_group['loop'] = True
    else: cutoff_group.pop('loop', None)
    cutoff.update(scopeRevision=revision, requiresScopeRecheck=True)
    route = next(r for r in geography['lines'] if r['id'] == route_id)
    if route['stationIds'] != full_ids:
        route.setdefault('previousRouteMembership', []).append(dict(stationIds=route['stationIds'].copy(),
            source='previous_bundled_map', supersededReason='按独立站序剔除重复关系成员，保留原地理点及玩家对象。'))
    route.update(stationIds=full_ids, stationOrderSource=order_source, stationOrderReviewedAt='2026-10-25')
    if loop: route['loop'] = True
    for i, direction in enumerate(route['directions']):
        direction['stationIds'] = full_ids.copy() if i == 0 else list(reversed(full_ids))
        if loop: direction['stationIds'].append(direction['stationIds'][0])
    last = stages[-1]
    expected = dict(id=line_id, historicalLineId=line_id, scopeType='stations', stationNames=cutoff_order,
        allowReverse=True, fullServiceOrder=True, lastPhysicalOpeningDate=last['date'], lastPhysicalOpeningSource=last['source'])
    if loop: expected['loop'] = True
    target['cutoffNetwork']['groups'] = [g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId', g['id']) != line_id] + [expected]
    old = [e for e in baseline['documentedMilestones'] if e.get('routeIds') == [route_id]]
    for event in old:
        if not any(e['id'] == event['id'] for e in baseline.setdefault('supersededDocumentedMilestones', [])):
            baseline['supersededDocumentedMilestones'].append(dict(event, supersededReason='整线现代快照改为经来源核对的逐期开通范围。'))
    old_ids = {e['id'] for e in old}; prefix = 'reviewed-phases:'+route_id+':'
    baseline['documentedMilestones'] = [e for e in baseline['documentedMilestones'] if e not in old and not e['id'].startswith(prefix)]
    for chapter in chapters.values():
        chapter['historicalEventIds'] = [e for e in chapter.get('historicalEventIds', []) if e not in old_ids and not e.startswith(prefix)]
    for stage in stages:
        event = prefix+stage['taskId']; chapter = chapters[stage['chapterId']]; chapter['historicalEventIds'].append(event)
        baseline['documentedMilestones'].append(dict(id=event, date=stage['date'], title=stage['title'], status='trial_operation',
            chapterId=chapter['id'], routeIds=[route_id], source=stage['source'], sourcePublicationDate=stage['sourcePublicationDate'],
            targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['taskId'] == stage['taskId']]))
    campaign['chapters'] = sorted(chapters.values(), key=lambda c: c['date'])
    baseline['documentedMilestones'].sort(key=lambda e: (e['date'], e['id']))
    baseline['documentedMilestoneCount'] = len(baseline['documentedMilestones'])


def reschedule_transfers(campaign, target, line_ids):
    """Retain sourced pairs, but never activate a body before its line exists."""
    pool = {t['id']: deepcopy(t) for c in campaign['chapters'] for t in c.get('requiredTransfers', [])
            if any(line in line_ids for line in t['lineIds'])}
    available = set(); placed = set()
    for chapter in campaign['chapters']:
        chapter['requiredTransfers'] = [t for t in chapter.get('requiredTransfers', []) if t['id'] not in pool]
        for group in chapter.get('lineGroups', []):
            available.update((group['historicalLineId'], group.get('stationInstances', {}).get(s, s)) for s in group['stationIds'])
        for tid, transfer in pool.items():
            if tid not in placed and all(pair in available for pair in zip(transfer['lineIds'], transfer['stationInstanceIds'])):
                chapter['requiredTransfers'].append(deepcopy(transfer)); placed.add(tid)
    assert placed == set(pool), 'Sourced transfer never becomes available: '+str(set(pool)-placed)
    for milestone in target['historicalMilestones']:
        milestone['transfers'] = [t for t in milestone.get('transfers', []) if t not in pool]
        chapter = next((c for c in campaign['chapters'] if c['id'] == milestone['chapterId']), {})
        milestone['transfers'] += [t['id'] for t in chapter.get('requiredTransfers', []) if t['id'] in pool]
