"""Extract redistributable station-pair corridors from local OSM rail geometry.

No AMap data is downloaded. Historical applicability and independent map review
remain explicitly unverified. Run after refreshing the Geofabrik extracts.
"""
from __future__ import annotations
import hashlib, heapq, json, math, re
from pathlib import Path
import osmium

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {"shanghai":"shanghai", "beijing":"beijing", "guangzhou":"guangdong", "shenzhen":"guangdong", "chengdu":"sichuan"}
HISTORICAL_EXCLUSIONS={"shanghai-s422":{'reason':'新龙华站2004年由地面改地下；现代轨道不能代表1993—1997原线位，原站精确位置待核验。','source':'https://www.xuhui.gov.cn/xhda/xhda/xhbl/xhqz/2017/03/24/d_105505.html'}}
def apply_historical_exclusions(output):
    for sid,record in HISTORICAL_EXCLUSIONS.items():
        output['stationReferences'].pop(sid,None)
        for item in list(output['alignments']):
            if sid not in [item['fromId'],item['toId']]:continue
            output['alignments'].remove(item)
            output['gaps'].append(dict(cityId=item['cityId'],fromId=item['fromId'],toId=item['toId'],**record))
def distance(a, b):
    return math.hypot((a[1]-b[1])*111320*math.cos(math.radians(a[0])), (a[0]-b[0])*111132)

class Relations(osmium.SimpleHandler):
    def __init__(self, wanted):
        super().__init__(); self.wanted=wanted; self.ways={};self.stops={}
    def relation(self, r):
        if r.id in self.wanted:
            self.ways[r.id]=[m.ref for m in r.members if m.type=='w']
            self.stops[r.id]=[m.ref for m in r.members if m.type=='n' and m.role.startswith('stop')]

class Ways(osmium.SimpleHandler):
    def __init__(self, wanted, stops):
        super().__init__(); self.wanted=wanted; self.ways={};self.stop_ids=stops;self.nodes={}
    def node(self,n):
        if n.id in self.stop_ids:self.nodes[n.id]={'name':n.tags.get('name',''),'latlng':[n.location.lat,n.location.lon]}
    def way(self, w):
        if w.id in self.wanted and w.tags.get('railway') in ('subway','light_rail','rail'):
            try: self.ways[w.id]=[(n.ref,[round(n.lat,7),round(n.lon,7)]) for n in w.nodes]
            except osmium.InvalidLocationError: pass

def graph_for(ways, ids):
    graph={}; coords={}
    for wid in ids:
        ns=ways.get(wid,[])
        for n,ll in ns: coords[n]=ll
        for (a,la),(b,lb) in zip(ns,ns[1:]):
            d=distance(la,lb)
            graph.setdefault(a,[]).append((b,d,wid)); graph.setdefault(b,[]).append((a,d,wid))
    return graph,coords

def find_path(graph, coords, a, b):
    # OSM stop positions and platforms are distinct. Project to the nearest
    # graph vertex, then retain its measured offset instead of moving stations.
    if not coords: return [],[],[]
    # Snap to segments, not just existing vertices: a straight mapped way may
    # have no vertex near the centre of a station platform.
    graph=graph.copy();coords=coords.copy();virtual=-1
    sets=[]
    for target in [a,b]:
        candidates=[];kx=111320*math.cos(math.radians(target[0]));ky=111132
        for n,neighbors in list(graph.items()):
            if n<0:continue
            for other,length,wid in neighbors:
                if n>=other or other<0:continue
                x=(coords[n][1]-target[1])*kx;y=(coords[n][0]-target[0])*ky
                dx=(coords[other][1]-coords[n][1])*kx;dy=(coords[other][0]-coords[n][0])*ky
                t=max(0,min(1,-(x*dx+y*dy)/max(dx*dx+dy*dy,1e-9)))
                gap=math.hypot(x+t*dx,y+t*dy)
                if gap<=150:candidates.append((gap,n,other,t,length,wid))
        selected=[]
        for gap,n,other,t,length,wid in sorted(candidates)[:8]:
            q=virtual;virtual-=1;selected.append(q)
            coords[q]=[coords[n][i]+(coords[other][i]-coords[n][i])*t for i in range(2)]
            graph[q]=[(n,length*t,wid),(other,length*(1-t),wid)]
            graph[n]=graph[n]+[(q,length*t,wid)];graph[other]=graph[other]+[(q,length*(1-t),wid)]
        sets.append(selected)
    starts=sets[0]+sorted((n for n in coords if n>=0),key=lambda n:distance(coords[n],a))[:12]
    ends=set(sets[1]+sorted((n for n in coords if n>=0),key=lambda n:distance(coords[n],b))[:12])
    starts=[n for n in starts if distance(coords[n],a)<=150]
    ends={n for n in ends if distance(coords[n],b)<=150}
    if not starts or not ends:return [],[],[]
    queue=[(distance(coords[n],a)*4,n) for n in starts];heapq.heapify(queue)
    cost=dict((n,d) for d,n in queue); previous={};end=None;best=float('inf')
    while queue:
        d,n=heapq.heappop(queue)
        if d!=cost[n]:continue
        if d>best:break
        if n in ends and d+distance(coords[n],b)*4<best:end=n;best=d+distance(coords[n],b)*4
        for other,weight,wid in graph.get(n,[]):
            nd=d+weight
            if nd<cost.get(other,float('inf')):
                cost[other]=nd;previous[other]=(n,wid);heapq.heappush(queue,(nd,other))
    if end is None:return [],[],[]
    nodes=[end]; used=[]
    while nodes[-1] in previous:
        n,w=previous[nodes[-1]];nodes.append(n);used.append(w)
    offsets=[distance(coords[nodes[-1]],a),distance(coords[end],b)]
    return [coords[n] for n in reversed(nodes)],sorted(set(used)),offsets

def main():
    cities=json.loads((ROOT/'data/cities.json').read_text(encoding='utf-8'))['cities']
    catalog=json.loads((ROOT/'data/campaigns.json').read_text(encoding='utf-8'))
    manifest=json.loads((ROOT/'data/basemap/manifest.json').read_text(encoding='utf-8'))
    output={'version':'osm-corridors-2026-10-17-v1','coordinateSystem':'EPSG:4326','license':'ODbL-1.0','attribution':'© OpenStreetMap contributors / Geofabrik','stationReferences':{},'alignments':[],'gaps':[]}
    for city in cities:
        cid=city['id']; stations={s['id']:s for s in city['stations']}; pairs=set();preferred={}
        for chapter in catalog['cities'][cid]['chapters']:
            # Only built final scopes may reuse modern geometry. Earlier plan
            # versions intentionally remain schematic unless independently sourced.
            for group in chapter.get('lineGroups',[]):
                ids=group['stationIds'];pairs.update(tuple(sorted(p)) for p in zip(ids,ids[1:]))
                ref=re.search(r'\d+号线',group.get('name',''))
                line=next((ln for ln in city['lines'] if ref and ln.get('ref')==ref[0]),None)
                if line:
                    for sid in ids:preferred.setdefault(sid,line['id'])
            for c in chapter.get('requiredConnections',[]):pairs.add(tuple(sorted([c['fromId'],c['toId']])))
        wanted={int(d['osmRelationId']) for line in city['lines'] for d in line.get('directions',[]) if d.get('osmRelationId')}
        source=ROOT/'.tools/osm-source'/f'{SOURCES[cid]}-latest.osm.pbf'
        source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
        rh=Relations(wanted);rh.apply_file(str(source))
        wh=Ways({w for ws in rh.ways.values() for w in ws},{n for ns in rh.stops.values() for n in ns});wh.apply_file(str(source),locations=True)
        # Existing city references can point to a different platform in a large
        # interchange. Use route-specific stop positions, preserving the raw point.
        used=set()
        for line in city['lines']:
            nodes={n for rid in line.get('osmRelationIds',[]) for n in rh.stops.get(rid,[]) if n in wh.nodes}
            candidates=set(line['stationIds'])|{sid for sid,lid in preferred.items() if lid==line['id']}
            for sid in candidates:
                if sid in used:continue
                if sid in preferred and preferred[sid]!=line['id']:continue
                raw=stations[sid];name=raw['name'].replace('西塱','西朗')
                matches=[n for n in nodes if wh.nodes[n]['name'].replace('西塱','西朗')==name and distance(raw['latlng'],wh.nodes[n]['latlng'])<800]
                if not matches:continue
                n=min(matches,key=lambda x:distance(raw['latlng'],wh.nodes[x]['latlng']))
                ll=wh.nodes[n]['latlng'];used.add(sid)
                output['stationReferences'][sid]={'latlng':ll,'rawLatlng':raw['latlng'],'sourceNodeId':n,'lineId':line['id'],'coordinateSystem':'EPSG:4326','checkedAt':'2026-10-17','amapReview':'pending'}
                stations[sid]=dict(raw,latlng=ll)
        graphs=[]
        for line in city['lines']:
            ids={w for rid in line.get('osmRelationIds',[]) for w in rh.ways.get(rid,[])}
            graphs.append((set(line['stationIds'])|{sid for sid,lid in preferred.items() if lid==line['id']},*graph_for(wh.ways,ids)))
        # Some early route identities now span multiple modern services (Beijing).
        graphs.append((set(stations),*graph_for(wh.ways,set(wh.ways))))
        for a,b in sorted(pairs):
            selected=None
            for ids,g,coords in graphs:
                if a not in ids or b not in ids:continue
                points,ways,offsets=find_path(g,coords,stations[a]['latlng'],stations[b]['latlng'])
                if len(points)<2 or max(offsets)>150:continue
                length=sum(distance(x,y) for x,y in zip(points,points[1:]))
                if length>distance(stations[a]['latlng'],stations[b]['latlng'])*2.5:continue
                selected=(points,ways,offsets,length);break
            if selected is None:
                output['gaps'].append({'cityId':cid,'fromId':a,'toId':b,'reason':'No continuous local OSM rail path within 150m of both station references.'});continue
            points,ways,offsets,length=selected
            dense=[points[0]]
            for x,y in zip(points,points[1:]):
                count=max(1,math.ceil(distance(x,y)/20))
                dense.extend([[round(x[k]+(y[k]-x[k])*i/count,7) for k in range(2)] for i in range(1,count+1)])
            points=dense
            output['alignments'].append({'id':a+'__'+b,'cityId':cid,'fromId':a,'toId':b,'points':points,'coordinateSystem':'EPSG:4326','precision':'approximate_corridor','sourceAccuracyM':None,'stationOffsetsM':[round(x,2) for x in offsets],'lengthM':round(length,2),'sourceWayIds':ways,'source':'https://download.geofabrik.de/asia/china.html','sourceFile':source.name,'sourceSha256':source_hash,'sourceDate':manifest['cities'][cid].get('sourceModified','unknown'),'checkedAt':'2026-10-17','amapReview':'pending','historicalReview':'modern_reference_only','note':'连续OSM轨道走廊；高德对照及历史适用性待核验，不是历史测绘线位。'})
        print(cid,len([a for a in output['alignments'] if a['cityId']==cid]),'corridors',flush=True)
    apply_historical_exclusions(output)
    (ROOT/'data/reference_alignments.json').write_text(json.dumps(output,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    print('Total',len(output['alignments']),'gaps',len(output['gaps']))
if __name__=='__main__':main()
