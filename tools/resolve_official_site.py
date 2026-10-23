"""Read-only suggestions: locate an official road junction in offline OSM data.

Results are modern geographic references, not surveyed station centers.
An author must review the official siting description before using a result.
"""
import argparse
import gzip
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def roads(city):
    result = {}
    seen = set()
    for path in (ROOT / 'data/basemap' / city).glob('*.gz'):
        for feature in json.load(gzip.open(path, 'rt', encoding='utf-8')).get('features', []):
            if feature['id'] in seen or not feature.get('kind', '').startswith('road_'):
                continue
            seen.add(feature['id'])
            if feature.get('name'):
                result.setdefault(feature['name'], []).append(feature)
    return result


def closest(a, b, p):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(0, min(1, ((p[0]-a[0])*dx + (p[1]-a[1])*dy)/(dx*dx+dy*dy))) if dx or dy else 0
    return a[0]+t*dx, a[1]+t*dy


def junction(index, first, second, latitude):
    scale = (111132, 111320*math.cos(math.radians(latitude)))
    best = None
    for f in index.get(first, []):
        for g in index.get(second, []):
            for a0, b0 in zip(f['points'], f['points'][1:]):
                for c0, d0 in zip(g['points'], g['points'][1:]):
                    a,b,c,d = [tuple(v[i]*scale[i] for i in (0,1)) for v in (a0,b0,c0,d0)]
                    u,v,w = (b[0]-a[0],b[1]-a[1]),(d[0]-c[0],d[1]-c[1]),(c[0]-a[0],c[1]-a[1])
                    cross = lambda x,y:x[0]*y[1]-x[1]*y[0]
                    den = cross(u,v)
                    if den and 0 <= cross(w,v)/den <= 1 and 0 <= cross(w,u)/den <= 1:
                        t = cross(w,v)/den
                        point = (a[0]+u[0]*t,a[1]+u[1]*t)
                        return {'latlng':[round(point[i]/scale[i],7) for i in (0,1)],'distanceM':0,'roads':[first,second],'osmIds':[f['id'],g['id']]}
                    pairs = [(p,closest(x,y,p)) for p,x,y in ((a,c,d),(b,c,d),(c,a,b),(d,a,b))]
                    for p,q in pairs:
                        distance = math.dist(p,q)
                        if best is None or distance < best['distanceM']:
                            best = {'latlng':[round((p[i]+q[i])/2/scale[i],7) for i in (0,1)],'distanceM':round(distance,1),'roads':[first,second],'osmIds':[f['id'],g['id']]}
    return best or {'error':'road missing','roads':[first,second]}


def main():
    import sys
    sys.stdout.reconfigure(encoding='utf-8')
    p=argparse.ArgumentParser();p.add_argument('city');p.add_argument('sites',nargs='+');args=p.parse_args()
    index=roads(args.city)
    for site in args.sites:
        first,second=site.split('|')
        print(json.dumps(junction(index,first,second,22.6 if args.city=='shenzhen' else 40),ensure_ascii=False))

if __name__=='__main__':main()
