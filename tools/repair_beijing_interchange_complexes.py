"""Unify documented interchange complexes, never their physical line bodies."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE='https://www.bii.com.cn/Portals/0/AttachUpload/pdf/2021102114294985.pdf'

def main():
    path=ROOT/'data/campaigns.json'
    data=json.loads(path.read_text(encoding='utf-8'))
    city=next(c for c in json.loads((ROOT/'data/cities.json').read_text(encoding='utf-8'))['cities'] if c['id']=='beijing')
    names={s['id']:s['name'] for s in city['stations']}
    config=data['cities']['beijing'];aliases=config.setdefault('stationComplexAliases',{})
    evidence=config.setdefault('stationComplexAliasSources',{})
    for old,new,name,reason in [('beijing-s8','beijing-s89','望京西','13B沿用13号线东段，与15、17号线在望京西换乘。'),
                                ('beijing-s85','beijing-s74','东直门','13B沿用13号线东段，在东直门与2号线、首都机场线换乘。')]:
        if names.get(old)!=name or names.get(new)!=name:raise ValueError('Reviewed interchange geography changed')
        if old in aliases and aliases[old]!=new:raise ValueError('Conflicting reviewed interchange identity')
        aliases[old]=new;evidence[old]=dict(source=SOURCE,sourceCheckedAt='2026-10-25',note=reason+'仅统一站区，不移动或合并各线路物理站体。')
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('REPAIRED_COMPLEX_IDENTITY Wangjingxi/Dongzhimen; independent line bodies retained')
if __name__=='__main__':main()
