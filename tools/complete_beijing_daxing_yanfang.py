"""Add two omitted operating scopes, using official orders and local siting.

The official task answer is authored below. OSM supplies WGS84 station points
and relation provenance, never the opening date or historical completion.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write
from build_network_baseline import build
from expand_historical_event_chapters import refresh_schedule

REVISION='2026.10.24.35'
DX_SOURCE='https://jtw.beijing.gov.cn/xxgk/dtxx/201012/t20101231_335839.html'
YF_SOURCE='https://jtw.beijing.gov.cn/xxgk/xwfbh/201912/t20191209_1007565.html'
MTR='https://www.mtr.bj.cn/service/line/timetable/line-4'
FOUR='安河桥北 北宫门 西苑 圆明园 北京大学东门 中关村 海淀黄庄 人民大学 魏公村 国家图书馆 动物园 西直门 新街口 平安里 西四 灵境胡同 西单 宣武门 菜市口 陶然亭 北京南站 马家堡 角门西 公益西桥'.split()
DAXING='新宫 西红门 高米店北 高米店南 枣园 清源路 黄村西大街 黄村火车站 义和庄 生物医药基地 天宫院'.split()
YANFANG='燕山 房山城关 饶乐府 马各庄 大石河东 星城 阎村 紫草坞 阎村东'.split()
# Reviewed railway=station/station=subway nodes, not same-name bus/rail stops.
DX_POINTS=[
 ('xingong',9706596471,[39.8110444,116.359749]),('xihongmen',7860703071,[39.7883939,116.322677]),
 ('gaomidianbei',7860703072,[39.7730301,116.3244805]),('gaomidiannan',5441536634,[39.7622885,116.325694]),
 ('zaoyuan',5444440441,[39.7518055,116.3260337]),('qingyuanlu',7860703073,[39.7417561,116.3263162]),
 ('huangcunwest',7860703074,[39.730422,116.3265186]),('huangcunrail',7860703075,[39.7215049,116.3266541]),
 ('yihezhuang',7860703076,[39.7111046,116.3130186]),('biomedicine',5441516142,[39.6851077,116.3156802]),
 ('tiangongyuan',5428310397,[39.6689886,116.3139055])]
YF_POINTS=[
 ('yanshan',5402957177,[39.7184583,115.9674631]),('fangshanchengguan',5402956432,[39.7046285,115.9835976]),
 ('raolefu',7796853448,[39.7002557,116.000048]),('magezhuang',7796839024,[39.7037753,116.0105495]),
 ('dashiheeast',9153343830,[39.7085836,116.0339981]),('xingcheng',9153343831,[39.7122214,116.0551386]),
 ('yancun',5402953665,[39.715288,116.0739687]),('zicaowu',9153343832,[39.723022,116.0804553])]


def main():
    data=read('data/campaigns.json');cities=read('data/cities.json');official=read('data/official_targets_2026-10-01.json')
    city=next(c for c in cities['cities'] if c['id']=='beijing');campaign=data['cities']['beijing'];target=official['cities']['beijing']
    chapters={c['id']:c for c in campaign['chapters']};cutoff=next(c for c in campaign['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    def add_points(prefix,names,points,source):
        result={}
        for name,(key,node,point) in zip(names,points):
            id_='beijing-'+prefix+'-'+key;result[name]=id_
            if not any(s['id']==id_ for s in city['stations']):
                city['stations'].append(dict(id=id_,name=name,latlng=point,osmIds=[node],coordinateSource='local_osm_station_node',
                    coordinateNote='本地OSM地铁站节点，仅作近似地理参考；官方公告独立证明站序和开通。来源未给测量误差，不用游戏容差替代。',source=source))
        return result
    dx=add_points('daxing',DAXING,DX_POINTS,DX_SOURCE)
    yf=add_points('yanfang',YANFANG[:-1],YF_POINTS,YF_SOURCE);yf['阎村东']='beijing-s206'
    campaign.setdefault('stationComplexAliases',{})[dx['新宫']]='beijing-s395'
    route=next(r for r in city['lines'] if r['id']=='beijing-r4')
    old_names={s['id']:s['name'] for s in city['stations']};base={old_names[s]:s for s in route['stationIds'] if old_names[s] in FOUR}
    assert set(base)==set(FOUR)
    four_ids=[base[n] for n in FOUR];dx_ids=[dx[n] for n in DAXING];full=four_ids+dx_ids
    route.update(name='4号线—大兴线',stationIds=full,stationOrderSource=MTR,stationOrderReviewedAt='2026-10-24')
    for i,d in enumerate(route['directions']):d['stationIds']=full.copy() if i==0 else list(reversed(full))
    # A separate map route for Yanfang; do not merge its service into Fangshan.
    yf_ids=[yf[n] for n in YANFANG]
    map_yf=dict(id='beijing-r25',ref='燕房线',name='燕房线',color='#D86018',stationIds=yf_ids,
        osmRelationIds=[12798054,8469053],stationOrderSource=YF_SOURCE,stationOrderReviewedAt='2026-10-24',
        directions=[dict(id='yanfang-out',name='燕山→阎村东',stationIds=yf_ids,osmRelationId=12798054),
                    dict(id='yanfang-in',name='阎村东→燕山',stationIds=list(reversed(yf_ids)),osmRelationId=8469053)])
    city['lines']=[r for r in city['lines'] if r['id']!='beijing-r25']+[map_yf]
    four_group=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-line4-4')
    four_instances={s:four_group.get('stationInstances',{}).get(s,s) for s in four_ids}
    four_instances.update({s:s+'__line4-4' for s in dx_ids})
    group=deepcopy(four_group);new_ids=[four_ids[-1]]+dx_ids;task='opening:beijing-daxing-2010'
    group.update(taskId=task,coverageGroupId=task,name='大兴线：公益西桥—天宫院贯通',stationIds=new_ids,
        stationNames=dict(zip(new_ids,['公益西桥']+DAXING)),stationInstances={s:four_instances[s] for s in new_ids},
        stationOrderSource=DX_SOURCE,source=DX_SOURCE,constructionScope='new_contiguous_range',sourceStationIds=new_ids.copy(),
        constructionScopeNote='复用4号线公益西桥接头，新增大兴线11站；不是与4号线形成换乘。',
        replaceExistingService=False,reconfirmLaterServices=True,servicePathRevision=4)
    dx_chapter=chapters['beijing-network-milestone-2010-12-30']
    dx_chapter['lineGroups']=[g for g in dx_chapter['lineGroups'] if g.get('taskId')!=task]+[group]
    dx_chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    four_group.update(name='4号线—大兴线',stationIds=full,stationNames=dict(zip(full,FOUR+DAXING)),stationInstances=four_instances,
        stationOrderSource=MTR,replaceExistingService=True,reconfirmLaterServices=True,servicePathRevision=4)
    cutoff.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    yf_group=dict(taskId='opening:beijing-yanfang-2017',coverageGroupId='opening:beijing-yanfang-2017',mapRouteId='beijing-r25',
        historicalLineId='beijing-lineyanfang',name='燕房线',color='#D86018',stationIds=yf_ids,
        stationNames=dict(zip(yf_ids,YANFANG)),stationInstances={s:s+'__yanfang' for s in yf_ids},
        toleranceM=220,stationOrderSource=YF_SOURCE,alignmentPrecision='station_areas_and_approximate_corridor',
        precisionNote='官方9站主线和同台换乘关系；独立线路站体不共轨，隧道及站内结构为示意。')
    yf_chapter=chapters['beijing-network-milestone-2017-12-30']
    yf_chapter['lineGroups']=[g for g in yf_chapter['lineGroups'] if g['historicalLineId']!='beijing-lineyanfang']+[deepcopy(yf_group)]
    yf_chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    cutoff['lineGroups']=[g for g in cutoff['lineGroups'] if g['historicalLineId']!='beijing-lineyanfang']+[dict(deepcopy(yf_group),replaceExistingService=True)]
    fangshan=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-route-22')
    transfer=dict(id='historic-transfer-beijing-yanfang-fangshan',name='阎村东',complexId='beijing-s206',
        lineIds=['beijing-route-22','beijing-lineyanfang'],
        stationInstanceIds=[fangshan.get('stationInstances',{}).get('beijing-s206','beijing-s206'),'beijing-s206__yanfang'],
        precision='schematic',source=YF_SOURCE,sourceNote='交通委明确同台换乘；两条线路各自有独立轨道与站体身份，不把换乘边当列车线路。')
    yf_chapter['requiredTransfers']=[t for t in yf_chapter.get('requiredTransfers',[]) if t['id']!=transfer['id']]+[transfer]
    # New Palace already has a 19-line physical body. Bind to that exact body.
    nineteen=next(g for g in cutoff['lineGroups'] if g['historicalLineId']=='beijing-line19-19')
    transfer4=dict(id='historic-transfer-beijing-xingong-4-19',name='新宫',complexId='beijing-s395',
        lineIds=['beijing-line4-4','beijing-line19-19'],stationInstanceIds=[four_instances[dx['新宫']],nineteen.get('stationInstances',{}).get('beijing-s395','beijing-s395')],
        source='https://www.mtr.bj.cn/service/line/line-4',precision='schematic',sourceNote='4—大兴线新宫与19号线换乘；分别引用线路站体，不合并轨道。')
    nineteen_chapter=next(c for c in campaign['chapters'] if any(g['historicalLineId']=='beijing-line19-19' for g in c.get('lineGroups',[])) and c['date']<'2026-10-01')
    nineteen_chapter['requiredTransfers']=[t for t in nineteen_chapter.get('requiredTransfers',[]) if t['id']!=transfer4['id']]+[transfer4]
    nineteen_chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
    for chapter,date,source,pub,expected,transfers in [
        (dx_chapter,'2010-12-30',DX_SOURCE,'2010-12-31',dict(id=task,historicalLineId='beijing-line4-4',scopeType='stations',
            stationNames=FOUR+DAXING,constructionStationNames=['公益西桥']+DAXING,fullServiceOrder=True,allowReverse=True),[]),
        (yf_chapter,'2017-12-30',YF_SOURCE,'2017-12-29',dict(id=yf_group['coverageGroupId'],historicalLineId='beijing-lineyanfang',
            scopeType='stations',stationNames=YANFANG,fullServiceOrder=True,allowReverse=True),[transfer['id']])]:
        milestone=next((m for m in target['historicalMilestones'] if m['chapterId']==chapter['id']),None)
        if milestone is None:
            milestone=dict(chapterId=chapter['id'],date=date,source=source,sourcePublicationDate=pub,groups=[]);target['historicalMilestones'].append(milestone)
        milestone['groups']=[g for g in milestone['groups'] if g.get('historicalLineId',g['id'])!=expected['historicalLineId']]+[expected]
        milestone['transfers']=list(dict.fromkeys(milestone.get('transfers',[])+transfers))
    target['cutoffNetwork']['groups']=[g for g in target['cutoffNetwork']['groups'] if g.get('historicalLineId',g['id']) not in ['beijing-line4-4','beijing-lineyanfang']]+[
        dict(id='beijing-line4-daxing-cutoff',historicalLineId='beijing-line4-4',scopeType='stations',stationNames=FOUR+DAXING,allowReverse=True,fullServiceOrder=True,lastPhysicalOpeningDate='2010-12-30',lastPhysicalOpeningSource=DX_SOURCE),
        dict(id='beijing-lineyanfang',historicalLineId='beijing-lineyanfang',scopeType='stations',stationNames=YANFANG,allowReverse=True,fullServiceOrder=True,lastPhysicalOpeningDate='2017-12-30',lastPhysicalOpeningSource=YF_SOURCE)]
    target['cutoffNetwork']['transfers']=list(dict.fromkeys(target['cutoffNetwork'].get('transfers',[])+[transfer['id'],transfer4['id']]))
    coverage=campaign['catalogCoverage']
    coverage['baselineRouteIds']=list(dict.fromkeys(coverage['baselineRouteIds']+['beijing-r25']))
    coverage['playableRouteTaskIds']=list(dict.fromkeys(coverage['playableRouteTaskIds']+[yf_group['taskId']]))
    coverage['playableRouteCount']=25
    baseline=read('data/network_baselines_2026-10-01.json');row=baseline['cities']['beijing'];generated=build(cities,data)['cities']['beijing']
    for key in ['routes','mapRouteEntryCount','mapRouteStopOccurrenceCount','mapUniqueStationCount']:row[key]=deepcopy(generated[key])
    for chapter,task,route_id,source,pub in [(dx_chapter,'opening:beijing-daxing-2010','beijing-r4',DX_SOURCE,'2010-12-31'),
            (yf_chapter,'opening:beijing-yanfang-2017','beijing-r25',YF_SOURCE,'2017-12-29')]:
        event='reviewed:'+task;chapter['historicalEventIds']=list(dict.fromkeys(chapter.get('historicalEventIds',[])+[event]))
        row['documentedMilestones']=[e for e in row['documentedMilestones'] if e['id']!=event]+[
            dict(id=event,date=chapter['date'],title=group['name'] if route_id=='beijing-r4' else '燕房线9站主线开通',status='operated',
                chapterId=chapter['id'],routeIds=[route_id],source=source,sourcePublicationDate=pub,
                targetLineGroups=[deepcopy(g) for g in chapter['lineGroups'] if g['taskId']==task])]
    row['documentedMilestones'].sort(key=lambda e:(e['date'],e['id']));row['documentedMilestoneCount']=len(row['documentedMilestones'])
    refresh_schedule('beijing',row,campaign,'2026-10-01')
    data.update(contentRevision=REVISION,contentRevisionNote='补入北京遗漏的大兴线11站与燕房线9站主线，4—大兴贯通、阎村东独立换乘及新宫4/19联系可实际建设。')
    for path,value in [('data/cities.json',cities),('data/campaigns.json',data),('data/official_targets_2026-10-01.json',official),('data/network_baselines_2026-10-01.json',baseline)]:write(path,value)
    print('Beijing: Daxing11 + Yanfang9 actual construction; 4/Daxing through service and two explicit interchanges')


if __name__=='__main__':main()
