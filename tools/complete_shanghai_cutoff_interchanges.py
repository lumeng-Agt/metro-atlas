"""Complete cutoff transfer actions from separately captured operator claims."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from review_shanghai_operator_transfers import EVIDENCE

REVISION='2026.10.26.3'


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    evidence=read(EVIDENCE);city=data['cities']['shanghai'];target=official['cities']['shanghai']
    refs={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='shanghai' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    aliases=city.setdefault('stationComplexAliases',{})
    names={'新天地':'一大会址·新天地','黄陂南路':'一大会址·黄陂南路'}
    def canonical(sid):
        seen=set()
        while sid in aliases:
            if sid in seen:raise ValueError('complex alias cycle')
            seen.add(sid);sid=aliases[sid]
        return sid
    def body(line,name):
        matches=set()
        for group in cutoff['lineGroups']:
            if group['historicalLineId']!=line:continue
            for sid in group['stationIds']:
                actual=group.get('stationNames',{}).get(sid,refs[sid]['name'])
                if names.get(actual,actual)!=name:continue
                instance=city.get('stationInstanceAliases',{}).get(line+'|'+sid,group.get('stationInstances',{}).get(sid,sid))
                matches.add((sid,instance))
        if len(matches)!=1:raise ValueError(f'{line}/{name}: expected one cutoff body, got {matches}')
        return next(iter(matches))
    known=[t for node in city['chapters'] for t in node.get('requiredTransfers',[]) if t.get('status','active')=='active']
    pairs=[];new_count=0
    for item in evidence['pairs']:
        name=item['stationName'];a,b=item['lineIds'];sa,ia=body(a,name);sb,ib=body(b,name)
        if ia==ib:raise ValueError(f'{name}: existing shared body needs explicit structural review')
        ca=canonical(sa);cb=canonical(sb)
        if ca!=cb:
            aliases[cb]=ca
            city.setdefault('stationComplexAliasSources',{})[cb]=dict(source=evidence['source'],sourceCheckedAt='2026-10-26',note='运营方相互声明同名换乘；统一逻辑身份，不移动站体或合并轨道。')
        previous=next((t for t in known if set(t.get('lineIds',[]))=={a,b} and canonical(t.get('complexId',''))==canonical(sa)),None)
        if previous:
            pair=deepcopy(previous)
            if pair['stationInstanceIds'] not in ([ia,ib],[ib,ia]):raise ValueError(f'{name}: conflicting existing pairing')
        else:
            new_count+=1
            pair=dict(id='sh-cutoff-xfer-'+sa+'-'+a+'-'+b,name=name,complexId=canonical(sa),lineIds=[a,b],
                      stationInstanceIds=[ia,ib],precision='schematic',source=evidence['source'])
        pair.update(cutoffEvidence='res://data/official_evidence/shanghai_interchanges_retrieved2026-10-23.json',
                    sourceNote='运营方线路配对核对，包含共线或站外换乘信息；本游戏的联系不声称各站均有独立站厅或已复原精确通道。历史形成日期另核对。')
        pairs.append(pair)
    # The three southern bodies retain their stable instances after the 1997
    # joining. The temporary 1996 service identifier is not their permanent
    # line identity. Apply through the existing explicit task transaction.
    first_join=next(c for c in city['chapters'] if c['id']=='sh-line1-1997')
    for chapter in [first_join,cutoff]:
        group=next(g for g in chapter['lineGroups'] if g['historicalLineId']=='shanghai-line1')
        key=group.get('taskId','line:'+chapter['id']+':'+str(chapter['lineGroups'].index(group)))
        for sid in ['shanghai-s126','shanghai-s127','shanghai-s128']:
            correction=dict(taskId=key,bodyLineReclassification=dict(stationInstanceId=sid,oldLineId='shanghai-line1-south-extension',newLineId='shanghai-line1',newLineName='1号线'),
                            description=refs[sid]['name']+'：贯通后保留站体、朝向和轨道，将临时南延段归属更新为1号线。',source=first_join['source'])
            corrections=chapter.setdefault('scopeCorrections',[])
            corrections[:]=[c for c in corrections if c.get('bodyLineReclassification',{}).get('stationInstanceId')!=sid]+[correction]
    cutoff.update(requiredTransfers=pairs,scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['story']['purpose']='核对截至日各线连续站序及运营方列出的131组线路换乘配对；缺少的联系需明确预览确认。'
    target['cutoffNetwork'].update(transfers=[p['id'] for p in pairs],
        transferEvidence='res://data/official_evidence/shanghai_interchanges_retrieved2026-10-23.json')
    # Current claims do not waive the separately pending dated-cutoff review.
    for doc in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='上海运营方131组配对补成明确换乘操作，修正1号线南延贯通后的站体线路归属；逐时期全量核验继续。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('SHANGHAI cutoff transfer actions',len(pairs),'new identities',new_count)


if __name__=='__main__':main()
