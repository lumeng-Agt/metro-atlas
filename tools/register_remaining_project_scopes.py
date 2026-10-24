"""Keep known required projects visible until their actual commands exist.

This does not turn a source link or policy/engineering classification into a
playable task. Independent coverage must fail on these explicit missing scopes.
"""
from repair_chengdu_historical_phases import read,write

ROWS={
    'chengdu':[
        {'id':'cd-line12-phase1','name':'12号线一期（普安—舜和家园）',
         'projectType':'approved_preparatory','statusAtCutoff':'已立项，前期环评与设计',
         'source':'https://www.chengdurail.com/info/1171/134904.htm',
         'sourceTitle':'成都轨道集团2026-08-26首次环评：34.2千米、28座车站',
         'note':'独立登记必做项目。完整站名表尚未在此次公告中公布，不能拿已制作的其他三项第五期工程代替本线；须制作有依据的站区和走廊任务。'}],
    'guangzhou':[
        {'id':'gz-line11-railway-station','name':'11号线广州火车站未开放工程',
         'projectType':'under_construction','statusAtCutoff':'主体及附属工程继续建设，未开放',
         'source':'https://static.cninfo.com.cn/finalpage/2025-07-15/1224176165.PDF',
         'sourceTitle':'广州地铁发行人资料：广州火车站与广州东站原暂缓开放工程',
         'note':'广州东站已于2025-09-29开放，广州火车站剩余工程不可遗漏；下一步核对截止日状态并制作独立站体、环线路径及换乘任务。'}],
    'shenzhen':[
        {'id':'sz-line10-east-shenzhen','name':'10号线东延深圳段',
         'projectType':'approved_project','statusAtCutoff':'第五期批准的深圳段',
         'source':'https://www.szmc.net/SMARTC/upload/file/20240619/1718790831457082212.pdf',
         'sourceTitle':'深圳地铁10号线东延深圳段环境影响评价项目范围',
         'note':'深圳段工程不得被东莞段审批情况替代；需制作公开站点及跨界接头，不虚构境外开通。'},
        {'id':'sz-line11-north-shenzhen','name':'11号线北延深圳段',
         'projectType':'approved_project','statusAtCutoff':'第五期批准的深圳段',
         'source':'https://www.szmc.net/SMARTC/upload/file/20240202/1706841517912063272.pdf',
         'sourceTitle':'深圳地铁11号线北延深圳段环评项目范围',
         'note':'纯区间边界接头仍是实际工程，不能因深圳境内无新增车站就用工程分类免除可玩任务。'}]}


def main():
    baseline=read('data/network_baselines_2026-10-01.json');official=read('data/official_targets_2026-10-01.json')
    for cid,rows in ROWS.items():
        actual=baseline['cities'][cid]['projectsAtCutoff']
        required=official['cities'][cid]['requiredProjectIds']
        for row in rows:
            if not any(p['id']==row['id'] for p in actual):
                actual.append(dict(row,sourceCheckedAt='2026-10-24',playabilityStatus='registered_geometry_and_playable_task_pending'))
            if row['id'] not in required:required.append(row['id'])
    old=next(p for p in baseline['cities']['chengdu']['projectsAtCutoff'] if p['id']=='cd-fifth-phase-consultation')
    old['statusAtCutoff']='原始征求意见版本，非后续批准项目范围'
    old['status']='保留原征求意见版本作资料；实际第五期项目分别登记'
    old['playabilityNote']='此条仅是旧征求意见方案，不代表10四、12一、18四、27二等后续工程尚未立项或已被制作。'
    write('data/network_baselines_2026-10-01.json',baseline);write('data/official_targets_2026-10-01.json',official)
    print('Four known required scopes remain explicit failures until playable tasks and independent targets exist')


if __name__=='__main__':main()
