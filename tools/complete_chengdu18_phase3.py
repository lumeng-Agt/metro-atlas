"""Add the sourced Linjiang/Guanyan scope to the existing phase-3 task.

Guanyan is the reserved station on the Linjiang section, not an extra passenger
station called Linjiang plus a second station called Guanyan. Three already
operating station additions are checked as reused construction, not rebuilt.
"""
from copy import deepcopy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVISION = '2026.10.24.6'
RESPONSE = 'https://m.thepaper.cn/newsDetail_forward_17773463'
FUNDING = 'https://www.cdb.com.cn/xwzx/xxgg/fzgg/202604/P020260430518506727486.pdf'


def read(path):
    return json.loads((ROOT/path).read_text(encoding='utf-8'))


def write(path,value):
    (ROOT/path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    campaigns=read('data/campaigns.json');cities=read('data/cities.json');official=read('data/official_targets_2026-10-01.json')
    city=next(c for c in cities['cities'] if c['id']=='chengdu')
    identity='chengdu-f18p3-guanyan'
    if not any(s['id']==identity for s in city['stations']):
        city['stations'].append({'id':identity,'name':'官堰','latlng':[30.3514322,104.4799671],
                                 'coordinateSource':'existing_station','osmNodeId':8849555979,
                                 'source':RESPONSE,
                                 'coordinateNote':'OSM地铁预留站节点8849555979，近临江停车场。用于站区近似；不得把附近国铁简阳南站或村名直接作为本站。',
                                 'constructionStatus':'civil_reserved'})
    plan=next(p for p in campaigns['cities']['chengdu']['futurePlans'] if p['id']=='cd-line18-phase3-build')
    north=deepcopy(plan['lineGroups'][0])
    east={'key':'linjiang','taskId':'project:cd-line18-phase3-build:linjiang',
          'mapRouteId':'chengdu-future-line18-phase3-linjiang','coverageGroupId':'chengdu-line18-phase3-linjiang',
          'name':'18号线三期临江段：官堰土建预留','historicalLineId':'chengdu-line18-13','color':'#00A4A9',
          'stationIds':['chengdu-s313',identity],
          'stationNames':{'chengdu-s313':'天府机场北',identity:'官堰'},
          'stationInstances':{'chengdu-s313':'chengdu-s313__line18-13',identity:identity+'__line18-13'},
          'toleranceM':250,'alignmentPrecision':'station_areas_and_approximate_corridor',
          'stationOrderSource':RESPONSE,'servicePathRevision':1,
          'precisionNote':'天府机场北以东的临江段，官堰为土建预留；现代站区及区间走廊近似，不编造开放日期。',
          'reservedStationIds':[identity]}
    plan['lineGroups']=[north,east]
    plan.update(title='18号线三期：北延与临江预留段',scopeRevision=REVISION,requiresScopeRecheck=True,
                description='北延分别建设火车北、骡马市、省体育馆、倪家桥站体；临江段接出天府机场北至官堰土建预留站。已经运营的三站一区间复用并核对，不重复建造，不把预留站写成历史开放。')
    plan.setdefault('additionalSources',[])
    for url in [RESPONSE,FUNDING]:
        if url not in plan['additionalSources']:plan['additionalSources'].append(url)
    target=next(p for p in official['cities']['chengdu']['projects'] if p['id']=='cd-line18-phase3')
    target['groups']=[g for g in target['groups'] if g['id']!='chengdu-line18-phase3-linjiang']+[
        {'id':'chengdu-line18-phase3-linjiang','historicalLineId':'chengdu-line18-13','scopeType':'stations',
         'stationNames':['天府机场北','官堰'],'allowReverse':True,'civilReservedStationNames':['官堰']}]
    target['existingScopes']=[{'id':'chengdu-line18-existing-three-stations-and-section',
        'historicalLineId':'chengdu-line18-13','scopeType':'stations','allowReverse':True,'requireServiceOpen':True,
        'stationNames':'火车南站 孵化园 锦城广场东 世纪城 海昌路 西博城 兴隆 天府站 三岔 福田 天府机场1号2号航站楼 天府机场北'.split(),
        'source':'https://www.chengdurail.com/op/station-time',
        'note':'孵化园、福田、天府机场北及相关已投用区间复用；不因同属三期再次建设。'}]
    target.update(reviewStatus='verified',constructionOnly=True,
                  scopeNote='4座北延新站加1座临江土建预留站均有任务；三站一区间以正式既有路径核对。资料精度与历史开放日期仍单独验收。')
    target.pop('requiredScopeGaps',None)
    target.setdefault('additionalSources',[])
    for url in [RESPONSE,FUNDING]:
        if url not in target['additionalSources']:target['additionalSources'].append(url)
    revision_key=lambda value:tuple(int(part) for part in value.split('.'))
    if revision_key(REVISION)>=revision_key(campaigns.get('contentRevision','0')):
        campaigns['contentRevision']=REVISION
        campaigns['contentRevisionNote']='18号线三期补齐临江段官堰土建预留，北延与东段分任务，不把已投用三站一区间重复建设。'
    write('data/campaigns.json',campaigns);write('data/cities.json',cities);write('data/official_targets_2026-10-01.json',official)
    print('18 phase 3: north + Linjiang tasks, operating construction separately reused')


if __name__=='__main__':main()
