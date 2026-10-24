"""Build the published one-station/two-section remainder without opening it.

The existing line-3 branch stays with line 3. A construction-scope completion
does not invent a date or an implementation scheme for the later service split.
"""
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT, read, write

REVISION='2026.10.24.16'
SOURCE='https://www.by.gov.cn/gzjg/qtdkfzx/jcss/content/post_10790614.html'
TRANSFER='https://gzw.gz.gov.cn/qy/qydt/content/post_9188848.html'
BOND='https://static.cninfo.com.cn/finalpage/2025-07-15/1224176165.PDF'
SITE='https://pc.nfnews.com/38/1512702.html'


def main():
    spec={'city':'guangzhou','projectIds':['gz-line10-remainder'],
        'stations':[{'id':'guangzhou-s362','name':'杨箕东','existing':True},
            {'id':'guangzhou-f10-tianhelu','name':'天河路','latlng':[23.1359124,113.3201819],
             'coordinateAccuracyM':450,'coordinateSource':'official_project_statement_and_local_road_geometry',
             'coordinateNote':'工程报道定位于BRT体育中心站下方，地理参考取该BRT站OSM node4577368333。该坐标为地面公交站的走廊参考，不是地铁站体测绘；换乘通道另据广州地铁公开资料。'},
            {'id':'guangzhou-s5','name':'石牌桥','existing':True},
            {'id':'guangzhou-s6','name':'体育西路','existing':True}],
        'lineGroups':[{'key':'remainder','mapRouteId':'guangzhou-future-line10-remainder',
            'coverageGroupId':'guangzhou-line10-remainder','name':'10号线后通建设段',
            'historicalLineId':'guangzhou-line10-10','color':'#7D9CCB',
            'stationIds':['guangzhou-s362','guangzhou-f10-tianhelu','guangzhou-s5'],
            'stationInstances':{'guangzhou-s362':'guangzhou-s362',
                'guangzhou-f10-tianhelu':'guangzhou-f10-tianhelu__line10-10',
                'guangzhou-s5':'guangzhou-s5__line3-3'},
            'toleranceM':450,'alignmentPrecision':'station_areas_and_approximate_corridor',
            'stationOrderSource':SOURCE,
            'precisionNote':'官方2026-04明确一座新站、两个区间；石牌桥复用既有支线接头。建设完成不调整3号线实际归属，不把尚未确定的拆分实施日期写成历史。'}],
        'transfers':[{'id':'future-transfer-gz10-tianhe-1','name':'天河路／体育西路','complexId':'guangzhou-s6',
             'stationInstanceIds':['guangzhou-s6__line1','guangzhou-f10-tianhelu__line10-10'],
             'lineIds':['guangzhou-line1','guangzhou-line10-10'],
             'sourceNote':'广州地铁2023年公开资料明确远期接入1号线体育西路站的通道；独立10号线站体，不共用站厅或轨道。'},
            {'id':'future-transfer-gz10-tianhe-3','name':'天河路／体育西路','complexId':'guangzhou-s6',
             'stationInstanceIds':['guangzhou-s6__line3-3','guangzhou-f10-tianhelu__line10-10'],
             'lineIds':['guangzhou-line3-3','guangzhou-line10-10'],
             'sourceNote':'通过天河路与体育西路既有1/3换乘站区建立线路联系；通道形制示意，不声称两线共轨或提前完成3号线拆分。'}],
        'plan':{'id':'gz-line10-remainder-build','title':'10号线后通段：天河路与石牌桥接头',
            'date':'2026-10-01','status':'under_construction','projectType':'under_construction','required':True,
            'source':SOURCE,'sourceTitle':'白云区2026-04官方工程进度：十号线后通一站两区间',
            'sourceType':'municipal_construction_progress','sourcePublicationDate':'2026-04-28','sourceCheckedAt':'2026-10-24',
            'description':'复现杨箕东—天河路—石牌桥的已公布后通建设范围，保留3号线既有天河客运站支线。未来拆分实施方案和日期未确定，不借本任务提前改写现状或宣称开通。',
            'contentRevision':REVISION,'requiresScopeRecheck':True}}
    path='tools/project_specs/gz-line10-remainder.json';write(path,spec)
    # Explicit shared-complex identity represents the planned pedestrian
    # interchange only. All existing physical bodies and coordinates stay put.
    data=read('data/campaigns.json');gz=data['cities']['guangzhou']
    gz.setdefault('stationComplexAliases',{})['guangzhou-f10-tianhelu']='guangzhou-s6'
    write('data/campaigns.json',data)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path),'--check'],check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],check=True)
    baseline=read('data/network_baselines_2026-10-01.json'); rows=baseline['cities']['guangzhou']['projectsAtCutoff']
    rows[:]=[r for r in rows if r['id']!='gz-line10-remainder']+[{'id':'gz-line10-remainder',
        'name':'10号线后通段（杨箕东—天河路—石牌桥）','projectType':'under_construction','statusAtCutoff':'在建，未开放',
        'source':SOURCE,'sourceTitle':spec['plan']['sourceTitle'],'playabilityStatus':'playable_build_task',
        'note':'新增一站两区间；既有3号线支线只复用接头，拆分实施时间不作虚构。'}]
    write('data/network_baselines_2026-10-01.json',baseline)
    official=read('data/official_targets_2026-10-01.json'); city=official['cities']['guangzhou']
    target={'id':'gz-line10-remainder','reviewStatus':'verified','constructionOnly':True,'source':SOURCE,
        'sourcePublicationDate':'2026-04-28','additionalSources':[TRANSFER,BOND,SITE],
        'scopeNote':'新建一站两区间；保留既有三号线五站范围，不把规划建设成果当作运营重组。',
        'groups':[{'id':'guangzhou-line10-remainder','historicalLineId':'guangzhou-line10-10',
            'scopeType':'stations','stationNames':['杨箕东','天河路','石牌桥'],'allowReverse':True,
            'sharedBodyLines':{'石牌桥':['guangzhou-line3-3']},'sharedBodyEvidence':BOND}],
        'existingScopes':[{'id':'guangzhou-line3-existing-north','historicalLineId':'guangzhou-line3-3',
            'stationNames':['石牌桥','岗顶','华师','五山','天河客运站'],'allowReverse':True,'requireServiceOpen':True}],
        'transfers':['future-transfer-gz10-tianhe-1','future-transfer-gz10-tianhe-3']}
    city['projects']=[p for p in city['projects'] if p['id']!=target['id']]+[target]
    if target['id'] not in city['requiredProjectIds']:city['requiredProjectIds'].append(target['id'])
    write('data/official_targets_2026-10-01.json',official)
    print('Guangzhou10: one new body, two new sections; original line3 branch retained')


if __name__=='__main__':main()
