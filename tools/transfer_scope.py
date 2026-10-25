"""Definition checks for sourced pedestrian-transfer construction chapters."""


def is_transfer_task(chapter,city_id):
    if chapter.get('lineGroups') or chapter.get('eventOnly') or chapter.get('operationType')!='transfer_connection':return False
    transfers=chapter.get('requiredTransfers',[])
    if not transfers or not str(chapter.get('source','')).startswith('https://'):return False
    seen=set()
    for transfer in transfers:
        lines=transfer.get('lineIds',[]);bodies=transfer.get('stationInstanceIds',[])
        identity=transfer.get('id')
        if not identity or identity in seen or len(lines)<2 or len(lines)!=len(bodies):return False
        if len(set(lines))!=len(lines) or len(set(bodies))!=len(bodies):return False
        if not all(isinstance(v,str) and v.startswith(city_id+'-') for v in lines+bodies):return False
        if not str(transfer.get('source','')).startswith('https://'):return False
        seen.add(identity)
    return True
