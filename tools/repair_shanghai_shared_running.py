"""Correct shared rail identities and the sourced 2026 Baoshan platform split.

Existing duplicate construction is kept in old saves. Only explicit service
reorganisation and guarded transfer corrections change the active network.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

REV='2026.10.26.13'
SOURCE='https://www.shanghai.gov.cn/nw17239/20260226/73ef09216b6a4558bdbbbacca9a7e887.html'
OLD='https://www.shanghai.gov.cn/cmsres/58/58e17817bef943b3bbb2c757b6b8162e/55e70032e0daa9d630ec35a01252cf5d.pdf'
L3='shanghai-line3-3';L4='shanghai-line4-4'
NAMES=['虹桥路','延安西路','中山公园','金沙江路','曹杨路','镇坪路','中潭路','上海火车站','宝山路']
IDS=['shanghai-s'+str(i) for i in range(53,44,-1)]
SHARED={sid:sid+'__line3-3' for sid in IDS}

def bump(entry):
    """Never downgrade a revision written by a later authoring step."""
    if str(entry.get('scopeRevision',''))<REV:entry.update(scopeRevision=REV,requiresScopeRecheck=True)
    return entry

def main():
    data=read('data/campaigns.json');sh=data['cities']['shanghai']
    cutoff=next(c for c in sh['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    base4=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==L4)
    cutoff['lineGroups']=[g for g in cutoff['lineGroups'] if g.get('historicalLineId')!=L4 or g is base4]
    old_outer_body='shanghai-s45__line4-4'
    # Change all relevant historic snapshots: the pre-2026 common section
    # really used the same station and track, not nine separate walkways.
    for chapter in sh['chapters']:
        groups=[g for g in chapter.get('lineGroups',[]) if g.get('historicalLineId')==L4]
        if not groups:continue
        for group in groups:
            for sid in IDS:
                if sid in group['stationIds']:group.setdefault('stationInstances',{})[sid]=SHARED[sid]
            group['physicalSharingSource']=OLD
        bump(chapter)
    inner=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==L4)
    inner.update(servicePatternId='sh4-inner-2026',name='4号线内圈',replaceExistingService=True)
    inner['coverageGroupId']='shanghai-line4-inner-2026';inner['taskId']='route:shanghai-r4:inner'
    outer=deepcopy(inner)
    outer.update(servicePatternId='sh4-outer-2026',name='4号线外圈',replaceExistingService=False,
        coverageGroupId='shanghai-line4-outer-2026',taskId='route:shanghai-r4:outer')
    outer['stationIds']=[inner['stationIds'][0]]+list(reversed(inner['stationIds'][1:]))
    outer['stationInstances']['shanghai-s45']=old_outer_body
    outer['physicalSharingSource']=SOURCE
    # The outer loop keeps the separate Baoshan platform, so its task has to be
    # built before the inner pattern replaces the pre-2026 ring service. Built
    # the other way round, the surviving walking contact at Baoshan would point
    # at a platform that no stored pattern serves yet.
    at=cutoff['lineGroups'].index(inner);cutoff['lineGroups'].insert(at,outer)
    # The outer-loop platform is part of the same Baoshan complex, not an
    # invented second station hall. Its exact footprint is not publicly fixed.
    cutoff.setdefault('stationProfiles',{})[old_outer_body]=dict(id='sh-baoshan-outer-platform-2026',
        form='宝山路1号站台：4号线外圈独用轨道',depthM=10,
        parameterStatus={'form':'public_reference','depthM':'game_estimate'},parameterSources={'form':SOURCE},
        note='2026-02-22启用；共用站区内新增方向性站台，非另一座独立站厅。高度、矩形和中心位置为游戏示意，旧站不自动搬动。')
    # Guard each old walking contact. The historical transaction archives it
    # only if the old line/body pair still matches; user-edited pairs fail.
    for chapter in sh['chapters']:
        has4=next((g for g in chapter.get('lineGroups',[]) if g.get('historicalLineId')==L4),None)
        retire=set(IDS[:-1] if chapter is cutoff else IDS)
        required=[]
        for pair in chapter.get('requiredTransfers',[]):
            sides=pair.get('lineIds',[]);bodies=pair.get('stationInstanceIds',[])
            shared_sid=next((sid for sid in IDS if sid+'__line4-4' in bodies or (L4 in sides and bodies[sides.index(L4)]==SHARED[sid])),None)
            same34=set(sides)=={L3,L4}
            if same34 and shared_sid in retire:
                if has4:
                    correction=dict(taskId=has4['taskId'],transferId=pair['id'],oldLineIds=sides[:],oldStationInstanceIds=bodies[:],
                        description=pair['name']+'：复用3/4号线真实共用站体及轨道，归档旧版误建的独立步行换乘；原站轨保留。',source=OLD)
                    corrections=chapter.setdefault('scopeCorrections',[])
                    corrections[:]=[c for c in corrections if c.get('transferId')!=pair['id']]
                    corrections.append(correction)
                continue
            if L4 in sides and shared_sid in IDS[:-1] and not same34:
                i=sides.index(L4);old=shared_sid+'__line4-4';new=SHARED[shared_sid]
                correcting_group=has4 or next((g for g in chapter.get('lineGroups',[]) if g.get('historicalLineId') in sides),None)
                if correcting_group:
                    bump(chapter)
                    corrections=chapter.setdefault('scopeCorrections',[])
                    corrections[:]=[c for c in corrections if not (c.get('transferId')==pair['id'] and c.get('bodyRebindings'))]
                    corrections.append(dict(taskId=correcting_group['taskId'],transferId=pair['id'],oldLineIds=sides[:],
                        bodyRebindings=[dict(index=i,oldStationInstanceId=old,newStationInstanceId=new)],source=OLD,
                        description=pair['name']+'：4号线实际停靠3/4共用站体，保留另一线路独立站体及原换乘性质。'))
                pair['stationInstanceIds'][i]=new;pair['physicalSharingSource']=OLD
            required.append(pair)
        chapter['requiredTransfers']=required
    # Planning-side contacts at the common section must refer to the same
    # physical bodies; none is changed into a new open connection here.
    for plan in sh.get('futurePlans',[]):
        for pair in plan.get('requiredTransfers',[]):
            if L4 not in pair.get('lineIds',[]):continue
            i=pair['lineIds'].index(L4);old=pair['stationInstanceIds'][i]
            for sid in IDS[:-1]:
                if old==sid+'__line4-4':pair['stationInstanceIds'][i]=SHARED[sid];pair['physicalSharingSource']=OLD;bump(plan)
    targets=read('data/official_targets_2026-10-01.json');network=targets['cities']['shanghai']['cutoffNetwork']
    wanted=next(g for g in network['groups'] if g.get('historicalLineId')==L4)
    inner_target=deepcopy(wanted);inner_target.update(id=inner['coverageGroupId'],allowReverse=False,
        requiredStationInstances={inner['stationNames'][sid]:inner['stationInstances'][sid] for sid in inner['stationIds']},
        bodyLineAliases=[L3],bodyLineAliasEvidence=OLD,servicePatternId=inner['servicePatternId'])
    # Independent operator order gives the reverse circuit; the published
    # 2026 platform rule, not the chapter, fixes the different Baoshan body.
    outer_target=deepcopy(inner_target);outer_target.update(id=outer['coverageGroupId'],servicePatternId=outer['servicePatternId'])
    outer_target['stationNames']=[wanted['stationNames'][0]]+list(reversed(wanted['stationNames'][1:]))
    outer_target['requiredStationInstances']['宝山路']=old_outer_body
    network['groups']=[g for g in network['groups'] if g.get('historicalLineId')!=L4]+[inner_target,outer_target]
    remaining={p['id'] for p in cutoff['requiredTransfers']}
    network['transfers']=[p for p in network.get('transfers',[]) if p in remaining]
    for definition in network.get('transferDefinitions',[]):
        if L4 in definition['lineIds']:
            i=definition['lineIds'].index(L4)
            for sid in IDS[:-1]:
                if definition['stationInstanceIds'][i]==sid+'__line4-4':definition['stationInstanceIds'][i]=SHARED[sid]
    rule=dict(id='shanghai34-common-2026',physicalLineId=L3,serviceLineId=L4,intervalEndpoints=['宝山路','虹桥路'],
        stationNames=NAMES[:-1],source=OLD,
        directionalStationRules=[dict(stationName='宝山路',precedingStationName='上海火车站',
            sharedPatternId='sh4-inner-2026',independentPatternId='sh4-outer-2026',
            sharedStationInstanceId=SHARED['shanghai-s45'],independentStationInstanceId=old_outer_body,
            source=SOURCE,effectiveDate='2026-02-22')])
    network.update(sharedRunningSections=[rule],sharedRunningEvidence=[dict(stationName=n,physicalLineId=L3,serviceLineId=L4,source=OLD) for n in NAMES[:-1]],
        sharedRunningReviewStatus='pending',sharedRunningReviewNote='已制作真实共轨与宝山路方向性站台；实际轨道、旧档及负例检查完成后再记录核验结果，不以数据配置替代验证。')
    network['sharedRunningEvidence'].append(dict(stationName='宝山路',physicalLineId=L3,serviceLineId=L4,sharing='directional',sharedPatternId='sh4-inner-2026',independentPatternId='sh4-outer-2026',source=SOURCE))
    # Future independent contacts referencing these bodies need the same
    # explicit identities as the revised planning task.
    for project in targets['cities']['shanghai']['projects']:
        for pair in project.get('transferDefinitions',[])+project.get('reservedTransfers',[]):
            if L4 not in pair.get('lineIds',[]):continue
            i=pair['lineIds'].index(L4)
            for sid in IDS[:-1]:
                if pair['stationInstanceIds'][i]==sid+'__line4-4':pair['stationInstanceIds'][i]=SHARED[sid]
    if str(data.get('contentRevision',''))<=REV:data.update(contentRevision=REV,contentRevisionNote='3/4号线共用真实站体与轨道，宝山路2026年外圈独立站台按方向建模，旧重复站轨保留。')
    for path,value in [('data/campaigns.json',data),('data/official_targets_2026-10-01.json',targets)]:write(path,value)
    write('data/official_evidence/shanghai34_shared_running_review.json',dict(cutoff='2026-10-01',reviewedAt='2026-10-26',
        commonSectionSource=OLD,platformChangeSource=SOURCE,effectiveDate='2026-02-22',
        fullSharedStationNames=NAMES[:-1],partialSharedStationName='宝山路',
        sourcePlatforms=[dict(platform=1,services=['4号线外圈'],sharing='independent_track'),
            dict(platform=2,services=['3号线往上海南站']),dict(platform=3,services=['3号线往江杨北路','4号线内圈'])],
        physicalRequirement=rule,reviewStatus='awaiting_actual_replay',
        note='宜山路3/4站体分离，不纳入共轨。原旧版重复站体和轨道不擅自删除；来源只证明真实拓扑，不宣称中心线/新增站台尺寸已测绘。'))
    print('SH3/4: eight fully shared stations; Baoshan direction-specific platform patterns; explicit legacy walk corrections')

if __name__=='__main__':main()
