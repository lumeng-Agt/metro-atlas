"""Author explicit missing cutoff transfer actions from a separate map review.

The current official map does not prove each historical opening date. Existing
dated actions remain where they are; the cutoff check explicitly repairs any
remaining relationship without changing physical stations or inventing dates.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from review_shenzhen_cutoff_interchanges import EVIDENCE,documented_pairs

REVISION='2026.10.26.2'


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    evidence=read(EVIDENCE);city=data['cities']['shenzhen'];target=official['cities']['shenzhen']
    refs={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='shenzhen' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    aliases=city.setdefault('stationComplexAliases',{})
    def canonical(sid):
        seen=set()
        while sid in aliases:
            if sid in seen:raise ValueError('complex alias cycle')
            seen.add(sid);sid=aliases[sid]
        return sid
    def body(line,name):
        matches=[]
        for group in cutoff['lineGroups']:
            if group['historicalLineId']!=line:continue
            for sid in group['stationIds']:
                actual=group.get('stationNames',{}).get(sid,refs[sid]['name'])
                if actual=='深圳北':actual='深圳北站'
                if actual!=name:continue
                instance=city.get('stationInstanceAliases',{}).get(line+'|'+sid,group.get('stationInstances',{}).get(sid,sid))
                matches.append((sid,instance))
        if len(matches)!=1:raise ValueError(f'{line}/{name}: expected one cutoff body, got {matches}')
        return matches[0]
    known=[t for node in city['chapters'] for t in node.get('requiredTransfers',[]) if t.get('status','active')=='active']
    pairs=[];new_count=0
    for name,a,b in documented_pairs(evidence):
        sa,ia=body(a,name);sb,ib=body(b,name)
        if ia==ib:raise ValueError(f'{name}: shared physical body cannot establish transfer')
        ca=canonical(sa);cb=canonical(sb)
        if ca!=cb:
            aliases[cb]=ca
            city.setdefault('stationComplexAliasSources',{})[cb]=dict(source=evidence['source'],sourceCheckedAt='2026-10-26',note='官方运营图明确同一换乘站区；各线路独立实体及位置不变。')
        previous=next((t for t in known if set(t.get('lineIds',[]))=={a,b} and canonical(t.get('complexId',''))==canonical(sa)),None)
        if previous:
            pair=deepcopy(previous)
            # Preserve historical identity/order and any actual dated evidence.
            if pair['stationInstanceIds']!=[ia,ib] and pair['stationInstanceIds']!=[ib,ia]:
                raise ValueError(f'{name}: conflicting existing physical pairing {pair}')
        else:
            new_count+=1
            pair=dict(id='sz-cutoff-xfer-'+sa+'-'+a+'-'+b,name=name,complexId=canonical(sa),
                      lineIds=[a,b],stationInstanceIds=[ia,ib],precision='schematic',source=evidence['source'])
        pair.update(cutoffEvidence='res://data/official_evidence/shenzhen_interchanges_reviewed2026-10-26.json',
                    sourceNote='截止日全网换乘核对；官方图确认线路配对，原有有日期的历史联系保留。通道形式和深度为示意。')
        pairs.append(pair)
    cutoff.update(requiredTransfers=pairs,scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['story']['purpose']='核对全网本期站序及68处换乘站区的96组线路配对。缺少联系时，直接预览并建立对应两侧独立站体的换乘。'
    target['cutoffNetwork'].update(transfers=[p['id'] for p in pairs],transferReviewStatus='verified',
        transferEvidence='res://data/official_evidence/shenzhen_interchanges_reviewed2026-10-26.json')
    target['cutoffNetwork']['note']='17条路径站序有独立票价表；68处站区、96组换乘由官方网络图逐符号核对。全网历史形成时间及其他截止日开放证据仍逐项审核，不能由现代图倒推。'
    for doc in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='深圳截止日换乘逐组对照官方图，补齐96组线路配对的明确操作；未把现代图当作历史日期证明。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('SHENZHEN cutoff transfer actions',len(pairs),'new explicit identities',new_count)


if __name__=='__main__':main()
