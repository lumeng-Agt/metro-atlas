"""Author actual transfer contacts; never turn shared running into walk links."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from review_chengdu_operator_transfers import EVIDENCE

REVISION='2026.10.26.4'


def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    evidence=read(EVIDENCE);city=data['cities']['chengdu'];target=official['cities']['chengdu']
    refs={s['id']:s for c in read('data/cities.json')['cities'] if c['id']=='chengdu' for s in c['stations']}
    cutoff=next(c for c in city['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    aliases=city.setdefault('stationComplexAliases',{})
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
                if group.get('stationNames',{}).get(sid,refs[sid]['name'])!=name:continue
                instance=city.get('stationInstanceAliases',{}).get(line+'|'+sid,group.get('stationInstances',{}).get(sid,sid))
                matches.add((sid,instance))
        if len(matches)!=1:raise ValueError(f'{line}/{name}: expected one physical target, got {matches}')
        return next(iter(matches))
    known=[t for node in city['chapters'] for t in node.get('requiredTransfers',[]) if t.get('status','active')=='active']
    pairs=[];new_count=0
    for item in evidence['pairs']:
        name=item['stationName'];a,b=item['lineIds'];sa,ia=body(a,item['stationNamesByLine'][a]);sb,ib=body(b,item['stationNamesByLine'][b])
        if ia==ib:raise ValueError('Shared running is not an independent-body interchange')
        ca=canonical(sa);cb=canonical(sb)
        if ca!=cb:
            aliases[cb]=ca
            city.setdefault('stationComplexAliasSources',{})[cb]=dict(source=item.get('source',evidence['source']),sourceCheckedAt='2026-10-26',note='逻辑换乘站区包含各自有名称的位置；不合并实体、站厅或轨道。')
        previous=next((t for t in known if set(t.get('lineIds',[]))=={a,b} and canonical(t.get('complexId',''))==canonical(sa)),None)
        if previous:
            pair=deepcopy(previous)
            if pair['stationInstanceIds'] not in ([ia,ib],[ib,ia]):raise ValueError(f'{name}: conflicting existing physical pair')
        else:
            new_count+=1
            pair=dict(id='cd-cutoff-xfer-'+sa+'-'+a+'-'+b,name=name,complexId=canonical(sa),lineIds=[a,b],
                      stationInstanceIds=[ia,ib],precision='schematic',source=item.get('source',evidence['source']))
        pair.update(transferKind='out_of_station' if item['kind']=='out_of_station' else 'interchange',
                    cutoffEvidence='res://data/official_evidence/chengdu_interchanges_retrieved2026-10-23.json',
                    sourceNote='按运营方实际站码确认联系；出闸换乘保留两侧不同站名。18／19号线共线四站另列，不生成步行联系。')
        pairs.append(pair)
    cutoff.update(requiredTransfers=pairs,scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['story']['purpose']='核对当前目标中的连续站序和92组线路联系；双流机场T2出闸换乘保持不同站名及实体。共线运行另按实际轨道关系处理。'
    target['cutoffNetwork'].update(transfers=[p['id'] for p in pairs],
        transferEvidence='res://data/official_evidence/chengdu_interchanges_retrieved2026-10-23.json',
        sharedRunningReviewStatus='verified',sharedRunningEvidence=evidence['sharedRunningStops'],
        sharedRunningSections=[dict(id='cd18-19-airport-shared',physicalLineId='chengdu-line18-13',serviceLineId='chengdu-line19-14',
                                    stationNames=['三岔','福田','天府机场1号2号航站楼','天府机场北'],
                                    source='https://www.chengdurail.com/info/1331/52042.htm',
                                    evidenceFile='res://data/official_evidence/chengdu_interchanges_retrieved2026-10-23.json',
                                    note='19号线过轨后使用18号线既有站体及同一实体区间；不是四组新的步行换乘。具体过轨工程位置不作测绘精度声明。')])
    for doc in (data,baseline):
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    if data['contentRevision']==REVISION:data['contentRevisionNote']='成都补齐实际换乘联系，区分双流机场出闸换乘与18／19共线站；共线实体及逐时期全量审核继续，成都12一期不伪装完成。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('CHENGDU cutoff transfer actions',len(pairs),'new identities',new_count,'shared-running physical rule authored; runtime validates actual paths')


if __name__=='__main__':main()
