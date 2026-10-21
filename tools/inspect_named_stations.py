"""List bundled station-area candidates for known project termini."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
cities = {str(row["id"]): row for row in json.loads((root / "data/cities.json").read_text(encoding="utf-8"))["cities"]}
queries = {
    "shanghai": ["闵行开发区", "上海体育场", "虹建路", "宝山站", "北新园路", "张杨北路", "东川路", "紫竹高新区", "上海南站", "莘庄", "江川东路", "龙漕路"],
    "beijing": ["商务园", "张家湾东", "管庄路西口", "曹各庄北", "东坝北", "东坝北街", "草桥", "丽泽商务区", "亦庄火车站", "宋家庄", "通州"],
    "guangzhou": ["江府", "纪念堂", "滘心", "广州北", "广州火车站", "嘉禾望岗", "鱼珠", "天河公园", "新塘", "南岗"],
    "shenzhen": ["罗湖西", "上李朗", "白石洲", "机场东", "机场北", "红树湾南", "兴东", "石龙", "吉华医院", "上沙", "黎光", "松和", "岗头西"],
    "chengdu": ["火车北站", "骡马市", "省体育馆", "倪家桥", "火车南站", "西河", "成都西", "天府机场", "黄田坝"],
}
for city in cities:
    rows = cities[city].get("stations", [])
    print(f"[{city}]")
    for query in queries.get(city, []):
        found = [
            {"id": str(row.get("id", "")), "name": str(row.get("name", "")), "latlng": row.get("latlng")}
            for row in rows
            if query in str(row.get("name", "")) or str(row.get("name", "")) in query
        ]
        if found:
            print(json.dumps({"query": query, "matches": found[:8]}, ensure_ascii=False))
