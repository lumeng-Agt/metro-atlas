"""Approved but unopened railway-station remainder, separate from 2025 opening."""
import subprocess
import sys
from repair_chengdu_historical_phases import ROOT, read, write

REVISION='2026.10.24.15'
SOURCE='https://ghzyj.gz.gov.cn/ywpd/cxgh/ghxkgsgb/gzyjfk/content/post_10815588.html'
NAMES='https://www.gz.gov.cn/hdjlpt/yjzj/api/attachments/view/f87a5b4c39b6325d1cb34982f031d616'
BOND='https://static.cninfo.com.cn/finalpage/2025-07-15/1224176165.PDF'


def main():
    spec={'city':'guangzhou','projectIds':['gz-line14-remainder'],
        'stations':[{'id':'guangzhou-s136','name':'广州火车站','existing':True},
                    {'id':'guangzhou-s231','name':'乐嘉路','existing':True}],
        'lineGroups':[{'key':'remainder','mapRouteId':'guangzhou-future-line14-remainder',
            'coverageGroupId':'guangzhou-line14-remainder','name':'14号线二期广州火车站段',
            'historicalLineId':'guangzhou-line14-14','color':'#81312F',
            'stationIds':['guangzhou-s136','guangzhou-s231'],
            'stationInstances':{'guangzhou-s136':'guangzhou-s136__line14-14','guangzhou-s231':'guangzhou-s231'},
            'toleranceM':350,'alignmentPrecision':'station_areas_and_approximate_corridor',
            'precisionNote':'已批准的一站一区间剩余范围，复用乐嘉路接头；铁路枢纽地铁站体为近似位置，不冒充已经开通或施工测绘。',
            'stationOrderSource':BOND}],
        'transfers':[{'id':'future-transfer-gz14-railway-2','name':'广州火车站','complexId':'guangzhou-s136',
            'stationInstanceIds':['guangzhou-s136__line2-2','guangzhou-s136__line14-14'],
            'lineIds':['guangzhou-line2-2','guangzhou-line14-14'],'sourceNote':'交通运输局车站命名资料明确与既有2号线换乘；使用独立14号线站体。'},
            {'id':'future-transfer-gz14-railway-5','name':'广州火车站','complexId':'guangzhou-s136',
            'stationInstanceIds':['guangzhou-s136__line5-5','guangzhou-s136__line14-14'],
            'lineIds':['guangzhou-line5-5','guangzhou-line14-14'],'sourceNote':'交通运输局车站命名资料明确与既有5号线换乘；11号线该站未开放，不能当作现成换乘。'}],
        'plan':{'id':'gz-line14-remainder-build','title':'14号线二期：接入广州火车站',
            'date':'2026-10-01','status':'approved_unbuilt','projectType':'approved_project',
            'sourceType':'municipal_planning_reply_and_approved_project_scope','required':True,
            'source':SOURCE,'sourceTitle':'广州市规划和自然资源局2026-05-18：乐嘉路—广州火车站暂未建设',
            'sourcePublicationDate':'2026-05-19','sourceCheckedAt':'2026-10-24',
            'description':'2025年二期开通仅到乐嘉路。按批准工程补建广州火车站一站及接头区间，明确建立2/5/14换乘。市规划部门2026年5月说明受国铁改造影响暂未建设，本任务只记规划建设完成，不编造未来开通日期。',
            'contentRevision':REVISION,'requiresScopeRecheck':True}}
    path='tools/project_specs/gz-line14-remainder.json'
    write(path,spec)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path),'--check'],check=True)
    subprocess.run([sys.executable,str(ROOT/'tools/add_project_plan.py'),str(ROOT/path)],check=True)
    baseline=read('data/network_baselines_2026-10-01.json')
    rows=baseline['cities']['guangzhou']['projectsAtCutoff']
    rows[:]=[r for r in rows if r['id']!='gz-line14-remainder']+[{'id':'gz-line14-remainder',
        'name':'14号线二期乐嘉路—广州火车站','projectType':'approved_project','statusAtCutoff':'已批未建，受国铁改造影响',
        'source':SOURCE,'sourceTitle':spec['plan']['sourceTitle'],'sourceCheckedAt':'2026-10-24',
        'playabilityStatus':'playable_build_task','note':'独立于已开通七站；一座新站、一个区间与2/5换乘，不漏出项目目录。'}]
    write('data/network_baselines_2026-10-01.json',baseline)
    official=read('data/official_targets_2026-10-01.json'); city=official['cities']['guangzhou']
    target={'id':'gz-line14-remainder','reviewStatus':'verified','constructionOnly':True,
        'source':SOURCE,'sourcePublicationDate':'2026-05-19','additionalSources':[NAMES,BOND],
        'groups':[{'id':'guangzhou-line14-remainder','historicalLineId':'guangzhou-line14-14',
            'scopeType':'stations','stationNames':['广州火车站','乐嘉路'],'allowReverse':True}],
        'transfers':['future-transfer-gz14-railway-2','future-transfer-gz14-railway-5']}
    city['projects']=[p for p in city['projects'] if p['id']!=target['id']]+[target]
    if target['id'] not in city['requiredProjectIds']:city['requiredProjectIds'].append(target['id'])
    write('data/official_targets_2026-10-01.json',official)
    print('Guangzhou14: approved unbuilt one-station remainder and independent 2/5 transfers')


if __name__=='__main__':main()
