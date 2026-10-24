"""Separate public project facts from OSM-derived approximate siting points."""
from repair_chengdu_historical_phases import read, write


def main():
    spec=read('tools/project_specs/sh-line19.json');cities=read('data/cities.json');data=read('data/campaigns.json')
    city=next(c for c in cities['cities'] if c['id']=='shanghai');lookup={s['id']:s for s in city['stations']}
    changed=[]
    for point in spec['stations']:
        if point.get('existing') or 'OSM' not in point.get('coordinateNote',''):continue
        point['coordinateSource']='local_osm_station_node'
        point.pop('coordinateAccuracyM',None)
        point['coordinateAccuracyNote']='来源未给出可核实的测量误差；不把游戏容差作为资料精度。'
        point['coordinateNote']=point['coordinateNote'].split(' 坐标来源说明：')[0]+' 坐标来源说明：离线OSM地理点作近似站区参考；官方项目资料证明站名和建设范围，不证明本坐标为测绘中心。'
        station=lookup[point['id']]
        station.pop('coordinateAccuracyM',None)
        for key in ['coordinateSource','coordinateAccuracyNote','coordinateNote']:station[key]=point[key]
        changed.append(point['id'])
    assert changed,'No OSM-derived station points found'
    data.update(contentRevision='2026.10.24.34',contentRevisionNote='上海19号线明确区分官方项目范围与离线OSM近似站址，保留所有坐标和玩家几何。')
    for path,value in [('tools/project_specs/sh-line19.json',spec),('data/cities.json',cities),('data/campaigns.json',data)]:write(path,value)
    print(f'Corrected coordinate provenance for {len(changed)} siting references; coordinates unchanged')


if __name__=='__main__':main()
