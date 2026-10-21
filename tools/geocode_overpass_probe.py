import json
import requests

names = ["墨江路", "吴泾北", "龙吴路", "景联路", "徐浦大桥", "龙瑞路"]
bbox = "30.50,120.70,31.70,122.20"
for name in names:
    query = f'''[out:json][timeout:20];(node["name"="{name}"]({bbox});way["name"="{name}"]({bbox});relation["name"="{name}"]({bbox}););out center tags;'''
    for url in ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]:
        try:
            r = requests.post(url, data={"data": query}, timeout=30, headers={"User-Agent":"MetroAtlas research contact metro-atlas@example.com"})
            if r.status_code == 200:
                payload = r.json()
                rows=[]
                for e in payload.get("elements", []):
                    lat=e.get("lat", e.get("center",{}).get("lat")); lon=e.get("lon", e.get("center",{}).get("lon"))
                    rows.append({"lat":lat,"lon":lon,"tags":e.get("tags",{})})
                print(json.dumps({"name":name,"url":url,"rows":rows},ensure_ascii=False))
                break
            print(name, url, r.status_code, r.text[:100])
        except Exception as exc:
            print(name, url, repr(exc))
