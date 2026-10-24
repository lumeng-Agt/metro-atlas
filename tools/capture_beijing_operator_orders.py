"""Capture the operator's public distance tables as independent source data.

This writes evidence only. It never changes a campaign, station or completion
flag. Open/closed status and cutoff dates still require dated notices.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
import re

import requests

INDEX='https://www.bjmoa.cn/metroLineList.html?sline=16'


class Tables(HTMLParser):
    def __init__(self):
        super().__init__();self.links={};self.href=None;self.label=[];self.tables=[];self.table=None;self.row=None;self.cell=None
    def handle_starttag(self,tag,attrs):
        values=dict(attrs)
        if tag=='a' and 'metroLineList.html?sline=' in values.get('href',''):self.href=values['href'];self.label=[]
        if tag=='table':self.table=[]
        elif tag=='tr' and self.table is not None:self.row=[]
        elif tag in ['td','th'] and self.row is not None:self.cell=[]
    def handle_data(self,text):
        if self.href is not None:self.label.append(text)
        if self.cell is not None:self.cell.append(text)
    def handle_endtag(self,tag):
        if tag=='a' and self.href is not None:
            self.links[self.href]=''.join(self.label).strip();self.href=None
        elif tag in ['td','th'] and self.cell is not None:
            self.row.append(''.join(self.cell).strip());self.cell=None
        elif tag=='tr' and self.row is not None:
            self.table.append(self.row);self.row=None
        elif tag=='table' and self.table is not None:
            self.tables.append(self.table);self.table=None


def fetch(url):
    r=requests.get(url,timeout=30,headers={'User-Agent':'Mozilla/5.0'});r.raise_for_status()
    r.encoding='utf-8';page=Tables();page.feed(r.text)
    return r.content,page


def chain(rows):
    pairs=[row[:3] for row in rows if len(row)>=3 and re.fullmatch(r'\d+(?:\.\d+)?',row[2].strip())]
    if not pairs:return dict(stationNames=[],issues=['no numeric station-distance rows'],segments=[])
    order=[pairs[0][0]];issues=[]
    for start,end,_distance in pairs:
        if start!=order[-1]:issues.append('non-contiguous source table: '+order[-1]+' / '+start)
        order.append(end)
    loop=len(order)>2 and order[0]==order[-1]
    return dict(stationNames=order[:-1] if loop else order,loop=loop,issues=issues,segments=pairs)


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();args.output.mkdir(parents=True,exist_ok=False)
    raw,index=fetch(INDEX);(args.output/'index.html').write_bytes(raw)
    def capture(item):
        url,name=item;raw,page=fetch(url);id_=url.rsplit('=',1)[-1]
        (args.output/(id_+'.html')).write_bytes(raw)
        return dict(line=name,source=url,sha256=sha256(raw).hexdigest(),directions=[chain(table) for table in page.tables])
    with ThreadPoolExecutor(max_workers=3) as executor:results=list(executor.map(capture,index.links.items()))
    report=dict(retrievedAt='2026-10-25',source=INDEX,
        scopeNote='Independent public operator station-distance tables; dated opening/closure notices must be applied before claiming 2026-10-01 status.',lines=results)
    (args.output/'station-orders.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for result in results:print(result['line'],[(len(d['stationNames']),d['issues'][:2]) for d in result['directions']])


if __name__=='__main__':main()
