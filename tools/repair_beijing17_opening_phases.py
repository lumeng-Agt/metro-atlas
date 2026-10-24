"""Split the 2026 whole-line snapshot into actual southern/northern openings."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

REVISION='2026.10.24.21'
OPERATOR='https://www.mtr.bj.cn/service/line/line-17.html'
SOUTH='https://www.mtr.bj.cn/article/61ce5857b0972c463ee519fb.html'
NORTH='https://jtw.beijing.gov.cn/xxgk/xwfbh/202312/t20231229_3520885.html'
MIDDLE='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251228_4370895.html'
WANGJING='https://www.mtr.bj.cn/article/697b49106a97b45630c3c3ef.html'
SOUTH_NAMES='十里河 周家庄 十八里店 北神树 次渠北 次渠 嘉会湖'.split()
NORTH_NAMES='未来科学城北 未来科学城 天通苑东 清河营 红军营 太阳宫 西坝河 左家庄 工人体育场'.split()
FULL_NAMES='未来科学城北 未来科学城 天通苑东 清河营 红军营 望京西 太阳宫 西坝河 左家庄 工人体育场 东大桥 永安里 潘家园西 十里河 周家庄 十八里店 北神树 次渠北 次渠 嘉会湖'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    bj=data['cities']['beijing'];target=official['cities']['beijing']
    chapters={c['id']:c for c in bj['chapters']}
    cutoff=next(c for c in bj['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    template=deepcopy(next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-line17-17'))
    names={s['id']:s['name'] for c in read('data/cities.json')['cities'] if c['id']=='beijing' for s in c['stations']}
    lookup={names[s]:s for s in template['stationIds']}
    changes=[
        ('beijing-network-milestone-2021-12-31','2021-12-31',SOUTH_NAMES,SOUTH,'2021-12-31',True,'south'),
        ('beijing-network-milestone-2023-12-30','2023-12-30',NORTH_NAMES,NORTH,'2023-12-29',False,'north'),
        ('beijing-network-milestone-2025-12-27','2025-12-27',[n for n in FULL_NAMES if n!='望京西'],MIDDLE,'2025-12-28',True,'through'),
        ('beijing-network-milestone-2026-01-31','2026-01-31',FULL_NAMES,WANGJING,'2026-01-29',True,'wangjingxi')]
    answers=[]
    for cid,date,order,source,pub,replace,key in changes:
        ch=chapters[cid]
        group=deepcopy(template)
        group.update(taskId='route:beijing-r17' if key=='wangjingxi' else 'opening:bj17-'+key,
            coverageGroupId='beijing-line17-'+key,stationIds=[lookup[n] for n in order],
            stationNames={lookup[n]:n for n in order},stationOrderSource=source,
            replaceExistingService=replace,reconfirmLaterServices=True,servicePathRevision=4,
            precisionNote='按运营方分期开放范围建设；北段望京西2026-01-31才开放，广渠门外截至截止日仍未开放。隧道为近似走廊。')
        group['stationInstances']={s:template.get('stationInstances',{}).get(s,s) for s in group['stationIds']}
        ch['lineGroups']=[g for g in ch['lineGroups'] if g['historicalLineId']!='beijing-line17-17']+[group]
        ch.update(requiresScopeRecheck=True,scopeRevision=REVISION)
        expected=dict(id=group['coverageGroupId'],historicalLineId='beijing-line17-17',scopeType='stations',
                      stationNames=order,allowReverse=True,fullServiceOrder=replace)
        old=next((m for m in target.get('historicalMilestones',[]) if m['chapterId']==cid),{})
        answer=deepcopy(old) if old else dict(chapterId=cid,date=date,source=source,sourcePublicationDate=pub)
        answer['groups']=[g for g in old.get('groups',[]) if g.get('historicalLineId',g['id'])!='beijing-line17-17']+[expected]
        if old:answer.setdefault('additionalSources',[]).append(source)
        answers.append(answer)
    # Move each real transfer to the first chapter in which both physical
    # bodies actually exist. New 3/17 and 12/17 contacts therefore wait for 2024.
    pool={t['id']:deepcopy(t) for c in bj['chapters'] for t in c.get('requiredTransfers',[])
          if 'beijing-line17-17' in t.get('lineIds',[])}
    ordered=sorted(bj['chapters'],key=lambda c:c['date'])
    for ch in ordered:
        ch['requiredTransfers']=[t for t in ch.get('requiredTransfers',[]) if t['id'] not in pool]
    available=set()
    for ch in ordered:
        for g in ch.get('lineGroups',[]):
            for s in g['stationIds']:available.add((g['historicalLineId'],g.get('stationInstances',{}).get(s,s)))
        for id_,transfer in pool.items():
            if any(t['id']==id_ for earlier in ordered[:ordered.index(ch)] for t in earlier.get('requiredTransfers',[])):continue
            if all(pair in available for pair in zip(transfer['lineIds'],transfer['stationInstanceIds'])):
                transfer.update(source=OPERATOR,sourceNote='根据实际分期开站及两侧线路站体可用时期安排，换乘联系不进入列车轨道图。')
                ch['requiredTransfers'].append(deepcopy(transfer))
    # A known old completed whole-line snapshot may contain future transfers.
    # Accepting this correction archives only these exact recorded pairings.
    first=chapters[changes[0][0]]
    allowed={lookup[n] for n in SOUTH_NAMES}
    first['scopeCorrections']=[x for x in first.get('scopeCorrections',[]) if not str(x.get('id','')).startswith('defer-bj17-')]
    for transfer in pool.values():
        pairs=list(zip(transfer['lineIds'],transfer['stationInstanceIds']))
        line_body=next((b for l,b in pairs if l=='beijing-line17-17'),'')
        if line_body in {template.get('stationInstances',{}).get(s,s) for s in allowed}:continue
        first['scopeCorrections'].append(dict(id='defer-bj17-'+transfer['id'],taskId='opening:bj17-south',
            transferId=transfer['id'],oldStationInstanceIds=transfer['stationInstanceIds'],oldLineIds=transfer['lineIds'],
            source=SOUTH,description='此换乘不属于2021南段首开；保留物理站轨，在实际所属后续任务重新确认。'))
    ids={m['chapterId'] for m in answers}
    target['historicalMilestones']=[m for m in target.get('historicalMilestones',[]) if m['chapterId'] not in ids]+answers
    cutoff_target=target['cutoffNetwork']
    expected=deepcopy(answers[-1]['groups'][-1]);expected['id']='beijing-line17-cutoff'
    cutoff_target['groups']=[g for g in cutoff_target['groups'] if g.get('historicalLineId',g['id'])!='beijing-line17-17']+[expected]
    if not any(e.get('source')==WANGJING for e in cutoff_target.get('temporalEvidence',[])):
        cutoff_target.setdefault('temporalEvidence',[]).append(dict(source=WANGJING,effectiveDate='2026-01-31',scope='17号线望京西开放；广渠门外仍未开放'))
    data['contentRevision']=REVISION
    data['contentRevisionNote']='北京17号线还原2021南段、2023北段、2025贯通及2026望京西开站；不再2026一次倒灌整条线。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)
    print('Beijing17: 7-stop south, 9-stop north, 19-stop through, 20-stop Wangjingxi infill; transfer dates follow bodies')


if __name__=='__main__':main()
