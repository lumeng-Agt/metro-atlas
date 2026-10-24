"""Explicitly trim the exact obsolete Futian extension in old saves.

Physical construction remains untouched; the old service is archived. The
known operating phase-1 prefix must remain available for the new extension.
"""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
REVISION='2026.10.24.10'


def main():
    path=ROOT/'data/campaigns.json'
    data=json.loads(path.read_text(encoding='utf-8'))
    plan=next(p for p in data['cities']['shenzhen']['futurePlans'] if p['id']=='sz-line20-phase2-build')
    preserved=['shenzhen-s306','shenzhen-s307__line20-17','shenzhen-s308__line20-17',
               'shenzhen-s309','shenzhen-s194__line20-17']
    correction={'id':'sz20-obsolete-futian-suffix','taskId':'project:sz-line20-phase2-build',
                'source':plan['source'],
                'description':'归档旧版错误的机场北—福田会展远景线路关系，保留会展城至机场北已建站轨与既有线路；本期按环评向白石洲延伸。',
                'obsoleteService':{'historicalLineId':'shenzhen-line20-17',
                                   'stationInstanceIds':preserved+['shenzhen-f20-futianhuizhan'],
                                   'preservedStationInstanceIds':preserved}}
    plan['scopeCorrections']=[c for c in plan.get('scopeCorrections',[]) if c.get('id')!=correction['id']]+[correction]
    plan['scopeRevision']=REVISION
    plan['requiresScopeRecheck']=True
    data['contentRevision']=REVISION
    data['contentRevisionNote']='规划区间按段保留状态；旧版20号线错误福田延伸经预览归档，保留一期已建路网。'
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
