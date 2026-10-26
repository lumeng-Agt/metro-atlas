"""Separate existing exit transfers from the approved, unopened civil passage."""
from copy import deepcopy
from itertools import combinations
from repair_chengdu_historical_phases import read,write

REV='2026.10.26.10'
APPROVAL='https://www.shanghai.gov.cn/nw15343/20260703/34ae6a8618fa447082256b5f2d1873ab.html'
MAP='https://www.shanghai.gov.cn/shanghai/newshanghai/shgl2025.pdf'
RAILWAY='https://www.shanghai.gov.cn/xbhygq/20231206/646ef8c98d8b4b0995177dd8c71d595c.html'
PID='sh-nanjingwest-paid-passage'


def main():
    data=read('data/campaigns.json');city=data['cities']['shanghai']
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    facts=[]
    for chapter in city['chapters']:
        touched=False
        for pair in chapter.get('requiredTransfers',[]):
            lines=set(pair.get('lineIds',[]));name=pair.get('name')
            is_nanjing=name=='南京西路' and lines.issubset({'shanghai-line2-2','shanghai-line12-12','shanghai-line13-13'})
            is_railway=name=='上海火车站' and 'shanghai-line1' in lines and bool(lines & {'shanghai-line3-3','shanghai-line4-4'})
            if not (is_nanjing or is_railway):continue
            pair.update(transferKind='out_of_station',source=MAP if is_nanjing else RAILWAY,
                sourceNote='官方网络图的出站换乘标记；既有独立站体保留。新通道尚未开放，不能提前改成站内换乘。' if is_nanjing else '上海城市出行码官方说明明确1号线与3/4号线需要出站换乘；铁路直联免安检不是地铁付费区贯通。')
            touched=True
            if chapter is cutoff:facts.append(deepcopy(pair))
        if touched:chapter.update(scopeRevision=REV,requiresScopeRecheck=True)
    existing=[p for p in cutoff['requiredTransfers'] if p['name']=='南京西路']
    bodies={line:body for p in existing for line,body in zip(p['lineIds'],p['stationInstanceIds'])}
    if len(bodies)!=3:raise ValueError('Expected three separately built current line bodies')
    reserved=[]
    for a,b in combinations(['shanghai-line2-2','shanghai-line12-12','shanghai-line13-13'],2):
        reserved.append(dict(id='planned-nanjingwest-passage-'+a+'-'+b,name='南京西路三线通道',complexId=existing[0]['complexId'],lineIds=[a,b],
            stationInstanceIds=[bodies[a],bodies[b]],status='reserved',reservationKind='pedestrian_passage',transferKind='interchange',
            source=APPROVAL,reservationEvidence=APPROVAL,precision='schematic',
            sourceNote='2026年7月正式规划许可涉及2、12、13号线，玩家确认规划通道；不把尚未开放的工程写成截止日站内换乘，不新建或共用列车轨道。'))
    plan=dict(id='sh-nanjingwest-passage-build',cityId='shanghai',projectIds=[PID],phase='future',date='2026-10-01',title='南京西路：三线换乘通道建设篇',
        source=APPROVAL,sourceTitle='静安区完成全市首个轨道交通类“两证合一”审批',sourcePublicationDate='2026-07-03',sourceCheckedAt='2026-10-26',sourceType='municipal_planning_approval',
        status='approved',projectType='approved_project',required=True,requireOpen=False,dataStatus='blueprint_ready',exactAlignment='station_areas',
        lineGroups=[],requiredTransfers=reserved,operationType='transfer_connection',eventOnly=False,scopeRevision=REV,requiresScopeRecheck=True,
        geometryStatus='existing_station_bodies_planned_pedestrian_links',precision='schematic',
        description='比较南京西路既有三线出站换乘与已批准的站内通道工程；分别查看三个线路站体，预览并确认规划通道。工程确认只表示方案建设完成，不改变截止日开放状态。',
        operationGuide='逐一预览并确认规划通道；三座站体复用，不新增车站、共用站厅或连接列车轨道。',
        story=dict(opening='南京西路的三条线路已形成出站换乘，新的站内通道工程在2026年获得规划许可。',purpose='复用三线既有独立站体，明确建立三组规划通道关系；保留当前出站换乘。',outcome='规划通道连接关系已记录；实际开放时间没有在本章虚构。',eventKind='planned_pedestrian_passage',planVersions=[],steps=[dict(id='inspect',action='read_context'),dict(id='passage',action='establish_transfer'),dict(id='check',action='validate_official_scope')],beats=[]))
    city['futurePlans']=[p for p in city['futurePlans'] if p['id']!=plan['id']]+[plan]
    data['contentRevision']=REV;data['contentRevisionNote']='区分上海既有出站换乘与南京西路已批未开放通道；不将规划通道当作列车轨道或现状站内联系。'
    baseline=read('data/network_baselines_2026-10-01.json');projects=baseline['cities']['shanghai']['projectsAtCutoff']
    entry=dict(id=PID,name='南京西路站三线换乘通道',projectType='approved_project',status='2026年取得规划许可',source=APPROVAL,sourceTitle=plan['sourceTitle'],sourceCheckedAt='2026-10-26',statusAtCutoff='已批准，未记作已开放',playabilityStatus='playable_build_task',playablePlanId=plan['id'],playabilityNote='三组明确的规划通道操作，复用独立站体，不生成假铺轨。',note=plan['description'])
    projects[:]=[p for p in projects if p['id']!=PID]+[entry];baseline['contentRevision']=REV
    targets=read('data/official_targets_2026-10-01.json');sh=targets['cities']['shanghai']
    if PID not in sh['requiredProjectIds']:sh['requiredProjectIds'].append(PID)
    answer=dict(id=PID,reviewStatus='verified',source=APPROVAL,sourcePublicationDate='2026-07-03',sourceCheckedAt='2026-10-26',
        constructionOnly=True,operationType='transfer_connection',groups=[],transfers=[],transferReviewStatus='verified',reservedTransfers=deepcopy(reserved),
        note='独立转录规划许可的三线衔接范围，未公开通道施工中心线不虚构。三线独立站体保留，规划联系不代替现状出站换乘。')
    sh['projects']=[p for p in sh['projects'] if p['id']!=PID]+[answer]
    for fact in facts:
        pair=next(p for p in sh['cutoffNetwork']['transfers'] if p['id']==fact['id']) if sh['cutoffNetwork'].get('transfers') and isinstance(sh['cutoffNetwork']['transfers'][0],dict) else None
        if pair:pair.update(transferKind='out_of_station')
    # The old cutoff answer stores IDs. Add independently sourced explicit
    # structure requirements rather than pretending a bitmask proves the type.
    sh['cutoffNetwork']['transferDefinitions']=[p for p in sh['cutoffNetwork'].get('transferDefinitions',[]) if p['id'] not in {f['id'] for f in facts}]+facts
    for rel,doc in [('data/campaigns.json',data),('data/network_baselines_2026-10-01.json',baseline),('data/official_targets_2026-10-01.json',targets)]:write(rel,doc)
    write('data/official_evidence/shanghai_exit_and_planned_passage_review.json',dict(cutoff='2026-10-01',checkedAt='2026-10-26',existingExitTransfers=facts,
        mapSource=MAP,mapPdfPage=29,mapVersion='D202501',railwayExitSource=RAILWAY,plannedPassageSource=APPROVAL,plannedDefinitions=reserved,
        sharedTrackReview='Separate: the 3/4 common section and the 2026 Baoshan directional-platform change are not settled by this exit-transfer review.'))
    print('SH: five exit-transfer structures corrected; three independently defined, unopened passage contacts made playable')


if __name__=='__main__':main()
