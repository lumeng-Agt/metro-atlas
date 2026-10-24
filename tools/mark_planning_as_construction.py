"""Planning completion is physical construction, not a historical opening."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REVISION='2026.10.24.8'


def main():
    path=ROOT/'data/campaigns.json'
    data=json.loads(path.read_text(encoding='utf-8'))
    changed=[]
    for city_id,city in data['cities'].items():
        for plan in city.get('futurePlans',[]):
            if not plan.get('lineGroups') or (plan.get('requireOpen') is False and plan.get('serviceStatusSchema')==2):continue
            plan['requireOpen']=False
            plan['serviceStatusSchema']=2
            plan['requiresScopeRecheck']=True
            plan['scopeRevision']=REVISION
            changed.append(f'{city_id}/{plan["id"]}')
    if changed:
        revision_key=lambda value:tuple(int(part) for part in value.split('.'))
        if revision_key(REVISION)>=revision_key(data.get('contentRevision','0')):
            data['contentRevision']=REVISION
            data['contentRevisionNote']='规划篇只确认已建成的规划路径，不生成真实历史开放；既有区间开放状态按段保留。'
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'Planning-only scope corrections: {len(changed)}')
    for plan in changed:print(plan)


if __name__=='__main__':main()
