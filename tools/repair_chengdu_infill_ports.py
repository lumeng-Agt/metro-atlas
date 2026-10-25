"""Recheck accepted infill paths affected by the former terminal-end bug.

Changes task revision only; no existing station or track is edited on load.
The normal preview proposes the correctly facing replacement connection.
"""
from repair_chengdu_historical_phases import read,write
REVISION='2026.10.25.17'
def main():
    data=read('data/campaigns.json');baseline=read('data/network_baselines_2026-10-01.json')
    for chapter in data['cities']['chengdu']['chapters']:
        if chapter['id'] not in ['chengdu-line1-ocean-2013','chengdu-line1-jincheng-rename-2013']:continue
        chapter.update(scopeRevision=REVISION,requiresScopeRecheck=True)
        for group in chapter['lineGroups']:
            group.update(servicePathRevision=7,reconfirmLaterServices=True)
    for doc in [data,baseline]:
        if tuple(map(int,REVISION.split('.')))>=tuple(map(int,doc.get('contentRevision','0').split('.'))):doc['contentRevision']=REVISION
    data['contentRevisionNote']='修复既有区间增站误用终端空闲端，2013增站及更名任务按正常预览重核，保留站轨；不放宽方向或连续性检查。'
    write('data/campaigns.json',data);write('data/network_baselines_2026-10-01.json',baseline)
    print('Chengdu 2013 infill paths scheduled for formal-command reconfirmation')
if __name__=='__main__':main()
