"""Do not confuse 17 constructed stations with 16 opened stations in 2010."""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

REVISION='2026.10.24.18'
APPROVAL='https://www.ndrc.gov.cn/fggz/zcssfz/zdgc/201209/t20120905_1145873.html'
OPEN='https://news.sina.com.cn/c/2013-06-08/154027353748.shtml?from=wap'
RENAME='https://news.sina.com.cn/c/2013-07-05/174027588924.shtml'
INITIAL='升仙湖 火车北站 人民北路 文殊院 骡马市 天府广场 锦江宾馆 华西坝 省体育馆 倪家桥 桐梓林 火车南站 高新 金融城 孵化园 世纪城'.split()


def main():
    data=read('data/campaigns.json');official=read('data/official_targets_2026-10-01.json')
    cd=data['cities']['chengdu'];target=official['cities']['chengdu']
    first=next(c for c in cd['chapters'] if c['id']=='cd-line1-2010')
    line_id=first['lineGroups'][0]['historicalLineId']
    cutoff=next(c for c in cd['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    modern=next(g for g in cutoff['lineGroups'] if g['historicalLineId']==line_id)
    cities=read('data/cities.json');catalog={s['id']:s for c in cities['cities'] if c['id']=='chengdu' for s in c['stations']}
    by_name={catalog[s]['name']:s for s in modern['stationIds']}
    def make_group(names,key,source):
        ids=[by_name['锦城广场' if n=='海洋公园' else n] for n in names]
        g=deepcopy(modern);g.update(stationIds=ids,stationNames=dict(zip(ids,names)),
            stationInstances={s:modern.get('stationInstances',{}).get(s,s) for s in ids},
            taskId=key,coverageGroupId=key,replaceExistingService=True,reconfirmLaterServices=True,
            stationOrderSource=source,loop=False,servicePathRevision=6)
        return g
    first['lineGroups']=[make_group(INITIAL,'opening:cd1-first-2010',APPROVAL)]
    first.update(requiresScopeRecheck=True,scopeRevision=REVISION)
    first['eventText']='2010年9月27日，1号线升仙湖至世纪城开放16座车站。海洋公园站后来单独增设并于2013年开放，不提前加入首开停站。'
    first['story'].update(opening=first['eventText'],purpose='复现首开16站南北主轴；后来的增站与名称变化分别处理。')
    additions=[];answers=[]
    for cid,date,label,source,pub,new_name,operation in [
        ('chengdu-line1-ocean-2013','2013-06-08','海洋公园站开放：既有区间增站',OPEN,'2013-06-08','海洋公园','infill_station'),
        ('chengdu-line1-jincheng-rename-2013','2013-07-08','海洋公园更名为锦城广场',RENAME,'2013-07-05','锦城广场','rename')]:
        names=INITIAL[:-1]+[new_name,INITIAL[-1]]
        g=make_group(names,cid+':line1',source)
        chapter=deepcopy(first)
        chapter.update(id=cid,date=date,title=label,lineGroups=[g],routeTargetCount=1,requireOpen=True,
            eventOnly=False,requiredTransfers=[],scopeCorrections=[],serviceTransitions=[],
            source=source,sourceTitle='同期记者从运营方取得的开放／命名公告',sourcePublicationDate=pub,
            sourceCheckedAt='2026-10-24',chapterScope='dated_infill_or_rename',operationType=operation,
            historicalEventIds=[cid+':event'])
        text=('2013年6月8日，海洋公园站随2号线西延线同日开放。复用1号线既有两侧站点，在孵化园与世纪城之间加入该站。'
              if operation=='infill_station' else '经市政府批准，2013年7月8日起海洋公园站更名为锦城广场。保持站体身份、位置和轨道，不重复建设。')
        chapter['eventText']=text
        chapter['story'].update(opening=text,purpose='复用已有建设，完成这次实际增站。' if operation=='infill_station' else '在车站详情确认新名称；保留物理车站及轨道。',outcome=text)
        additions.append(chapter)
        answers.append({'chapterId':cid,'date':date,'source':source,'sourcePublicationDate':pub,'groups':[
            {'id':g['coverageGroupId'],'historicalLineId':line_id,'scopeType':'stations','stationNames':names,
             'allowReverse':True,'fullServiceOrder':True}]})
    # A known old modern snapshot may already have later interchange links.
    # Archive exact pairs when their line-1 stop is outside the first opening;
    # later sourced tasks explicitly restore them from the retained geometry.
    permitted=set(first['lineGroups'][0]['stationIds'])
    all_transfers={t['id']:t for c in cd['chapters']+cd.get('futurePlans',[]) for t in c.get('requiredTransfers',[])}
    first['scopeCorrections']=[x for x in first.get('scopeCorrections',[]) if not str(x.get('id','')).startswith('defer-later-line1-')]
    canonical=lambda s:cd.get('stationComplexAliases',{}).get(s,s)
    for t in all_transfers.values():
        if line_id not in t['lineIds'] or canonical(t['complexId']) in {canonical(s) for s in permitted}:continue
        first['scopeCorrections'].append({'id':'defer-later-line1-'+t['id'],'taskId':'','transferId':t['id'],
            'oldStationInstanceIds':t['stationInstanceIds'],'oldLineIds':t['lineIds'],'source':APPROVAL,
            'description':t['name']+'不在2010首开1号线范围；保留站轨，在其所属后续任务中重新确认线路与换乘。'})
    changed={c['id'] for c in additions}
    cd['chapters']=sorted([c for c in cd['chapters'] if c['id'] not in changed]+additions,key=lambda c:c['date'])
    first_answer=next(m for m in target['historicalMilestones'] if m['chapterId']=='cd-line1-2010')
    first_answer['groups']=[{'id':first['lineGroups'][0]['coverageGroupId'],'historicalLineId':line_id,
        'scopeType':'stations','stationNames':INITIAL,'allowReverse':True,'fullServiceOrder':True}]
    first_answer['additionalSources']=first_answer.get('additionalSources',[])+[
        {'url':APPROVAL,'title':'2012年可研批复明确海洋公园为增设站，不能用工程17站数证明2010全开放'},
        {'url':OPEN,'title':'2013年6月8日实际开放报道'}]
    target['historicalMilestones']=[m for m in target['historicalMilestones'] if m['chapterId'] not in changed]+answers
    data['contentRevision']=REVISION
    data['contentRevisionNote']='更正2010成都1号线首开16站；2013海洋公园增站与锦城广场更名单列，工程17站不冒充首开全部开放。'
    write('data/campaigns.json',data);write('data/official_targets_2026-10-01.json',official)
    print('Corrected 2010 opening: 16 stations; infill June2013 and rename July2013 retain the same physical station')


if __name__=='__main__':main()
