"""Repair missing stations in the 2025 opening, preserving existing bodies.

The bundled OSM route member filter had retained six stops while omitting five
station nodes. The operator's eleven-stop order is the independent answer;
local WGS84 OSM station nodes provide geographic reference only.
"""
from copy import deepcopy
from repair_chengdu_historical_phases import read,write

REVISION='2026.10.24.20'
OPEN='https://jtw.beijing.gov.cn/zmhd/jtdjt/202512/t20251224_4360655.html'
DAY='https://www.beijing.gov.cn/fuwu/bmfw/sy/jrts/202512/t20251228_4370895.html'
OPERATOR='https://www.bjsubway.com/station/xltcx/line18/2025-12-28/645.html'
NAMES='马连洼 上地软件园 东北旺 龙泽西 回龙观西大街 文华路 回龙观东大街 霍营东 天通苑 太平庄 天通苑东'.split()
NEW=[
    ('softwarepark','上地软件园',13410014896,[40.043537,116.2805664]),
    ('dongbeiwang','东北旺',13410014897,[40.051835,116.2887219]),
    ('longzexi','龙泽西',13354529561,[40.0714794,116.3040433]),
    ('huilongguanwest','回龙观西大街',13410014898,[40.0772781,116.3245924]),
    ('wenhualu','文华路',13410014899,[40.0788401,116.3356615])]


def main():
    cities=read('data/cities.json');city=next(c for c in cities['cities'] if c['id']=='beijing')
    by_name={'马连洼':'beijing-s411','回龙观东大街':'beijing-s149','霍营东':'beijing-s412',
             '天通苑':'beijing-s413','太平庄':'beijing-s414','天通苑东':'beijing-s377'}
    for key,name,osm,point in NEW:
        id_='beijing-open18-'+key;by_name[name]=id_
        if not any(s['id']==id_ for s in city['stations']):
            city['stations'].append(dict(id=id_,name=name,latlng=point,osmIds=[osm],
                coordinateSource='local_osm_station_node',coordinateAccuracyM=120,
                source=OPEN,coordinateNote='WGS84车站节点，仅作地理参考；开通事实与站序由交通委公告及运营方资料独立核对。'))
    order=[by_name[n] for n in NAMES]
    route=next(l for l in city['lines'] if l['id']=='beijing-r18')
    route['stationIds']=order
    for i,direction in enumerate(route['directions']):direction['stationIds']=order if i==0 else list(reversed(order))
    route.update(stationOrderSource=OPERATOR,stationOrderReviewedAt='2026-10-24')
    write('data/cities.json',cities)

    data=read('data/campaigns.json');bj=data['cities']['beijing']
    bj.setdefault('stationComplexAliases',{}).update({'beijing-s411':'beijing-s352','beijing-s413':'beijing-s103'})
    opening=next(c for c in bj['chapters'] if c['id']=='beijing-network-milestone-2025-12-27')
    cutoff=next(c for c in bj['chapters'] if c.get('chapterScope')=='cutoff_reconciliation')
    for chapter in [opening,cutoff]:
        group=next(g for g in chapter['lineGroups'] if g['historicalLineId']=='beijing-line18-18')
        group.update(stationIds=order,stationNames=dict(zip(order,NAMES)),
            stationOrderSource=OPERATOR,replaceExistingService=True,reconfirmLaterServices=True,
            precisionNote='2025-12-27首开11站。车站位置为公开地理节点，隧道为近似走廊；保留原6站体，不把缺失站点当作精度问题省略。',
            coverageGroupId='beijing-line18-open-2025',servicePathRevision=3)
        group['stationInstances']={s:group.get('stationInstances',{}).get(s,s) for s in order}
        chapter.update(requiresScopeRecheck=True,scopeRevision=REVISION)
    additions=[
        dict(id='historic-transfer-bj18-malianwa-16',name='马连洼',complexId='beijing-s352',
             stationInstanceIds=['beijing-s352','beijing-s411'],lineIds=['beijing-line16-16','beijing-line18-18']),
        dict(id='historic-transfer-bj18-tiantongyuan-5',name='天通苑',complexId='beijing-s103',
             stationInstanceIds=['beijing-s103','beijing-s413'],lineIds=['beijing-line5-5','beijing-line18-18']),
        dict(id='historic-transfer-bj18-tiantongyuandong-17',name='天通苑东',complexId='beijing-s377',
             stationInstanceIds=['beijing-s377__line17-17','beijing-s377__line18-18'],lineIds=['beijing-line17-17','beijing-line18-18'])]
    for item in additions:item.update(precision='schematic',source=OPEN,sourceNote='交通委明确列出的首开换乘，独立站体、通道示意；不新增龙泽西与既有13号线的假换乘。')
    ids={t['id'] for t in additions}
    for chapter in [opening,cutoff]:
        chapter['requiredTransfers']=[t for t in chapter.get('requiredTransfers',[]) if t['id'] not in ids]+deepcopy(additions)
        for t in chapter['requiredTransfers']:
            if t['id']=='historic-transfer-beijing-s149-line8-8-line18-18':t.update(source=OPEN,sourceNote='2025-12-27回龙观东大街8/18换乘形成，各用本线物理站体。')
    data['contentRevision']=REVISION
    data['contentRevisionNote']='补齐北京18号线首开漏失的5站及3项换乘，首开与截止日目标均为11站；13号线拆分工程不冒充已实现。'
    write('data/campaigns.json',data)

    baselines=read('data/network_baselines_2026-10-01.json')
    baseline=next(r for r in baselines['cities']['beijing']['routes'] if r['mapRouteId']=='beijing-r18')
    baseline.setdefault('mapStationIds',baseline['cutoffStationIds'].copy())
    baseline.update(cutoffStationIds=order,cutoffStationCount=11,stationOrderSource=OPERATOR,
                    cutoffTemporalReviewStatus='verified',openingEvidence=OPEN)
    write('data/network_baselines_2026-10-01.json',baselines)
    official=read('data/official_targets_2026-10-01.json');target=official['cities']['beijing']
    expected=dict(id='beijing-line18-open-2025',historicalLineId='beijing-line18-18',
                  scopeType='stations',stationNames=NAMES,allowReverse=True,fullServiceOrder=True)
    answer=dict(chapterId=opening['id'],date='2025-12-27',source=OPEN,sourcePublicationDate='2025-12-24',
        additionalSources=[DAY,OPERATOR],groups=[expected],
        transfers=['historic-transfer-beijing-s149-line8-8-line18-18']+[t['id'] for t in additions])
    # Preserve independently reviewed other scopes if this same era is expanded.
    old=next((m for m in target.get('historicalMilestones',[]) if m['chapterId']==opening['id']),None)
    if old:
        answer['groups']=[g for g in old.get('groups',[]) if g.get('historicalLineId',g['id'])!='beijing-line18-18']+[expected]
        answer['transfers']=list(dict.fromkeys(old.get('transfers',[])+answer['transfers']))
    target['historicalMilestones']=[m for m in target.get('historicalMilestones',[]) if m['chapterId']!=opening['id']]+[answer]
    # This is one reviewed line, not a declaration that all Beijing lines have
    # been reconciled at the cutoff.
    cutoff_target=target.setdefault('cutoffNetwork',dict(date='2026-10-01',temporalReviewStatus='pending',groups=[],temporalEvidence=[]))
    cutoff_target['groups']=[g for g in cutoff_target['groups'] if g.get('historicalLineId',g['id'])!='beijing-line18-18']+[expected]
    cutoff_target.setdefault('temporalEvidence',[])
    if not any(e.get('source')==OPEN for e in cutoff_target['temporalEvidence']):
        cutoff_target['temporalEvidence'].append(dict(source=OPEN,effectiveDate='2025-12-27',scope='18号线11站，其他线路开放状态另行核对'))
    cutoff_target['transfers']=answer['transfers']
    write('data/official_targets_2026-10-01.json',official)
    print('Beijing18: all 11 opening stops; four source-backed physical-body interchanges')


if __name__=='__main__':main()
