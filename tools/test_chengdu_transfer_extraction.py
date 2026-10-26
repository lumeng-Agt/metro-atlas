import unittest
from copy import deepcopy
from review_chengdu_operator_transfers import extract,LINES


def payload():
    return dict(code=0,data=[dict(lineNo=n,subLine=[dict(stationList=[dict(stationNo=n+'20',stationName='站点'+n,transferLines=n,stationCodes=[dict(lineNo=n,stationCode='01')])])]) for n in LINES])


def row(value,line):
    return next(l for l in value['data'] if l['lineNo']==line)['subLine'][0]['stationList'][0]


class ExtractionChecks(unittest.TestCase):
    def test_failed_response_rejected(self):
        with self.assertRaises(ValueError):extract(dict(code=1,data=[]))

    def test_missing_line_rejected(self):
        value=payload();value['data'].pop()
        with self.assertRaises(ValueError):extract(value)

    def test_station_name_does_not_create_interchange(self):
        value=payload();row(value,'01')['stationName']='同名';row(value,'02')['stationName']='同名'
        self.assertEqual(extract(value)['pairs'],[])

    def test_reference_must_resolve_real_peer_code(self):
        value=payload();row(value,'01').update(transferLines='01,02',stationCodes=[dict(lineNo='01',stationCode='01'),dict(lineNo='02',stationCode='missing')])
        with self.assertRaises(ValueError):extract(value)

    def test_shared_running_is_not_a_walking_interchange(self):
        value=payload()
        shared=deepcopy(row(value,'18'));shared['stationName']='三岔'
        next(l for l in value['data'] if l['lineNo']=='19')['subLine'][0]['stationList'].append(shared)
        result=extract(value)
        self.assertFalse(result['pairs']);self.assertEqual(len(result['sharedRunningStops']),1)
        self.assertEqual(result['sharedRunningStops'][0]['physicalLineId'],LINES['18'])

    def test_unreviewed_cross_line_ownership_rejected(self):
        value=payload();row(value,'02').update(stationNo='0120',transferLines='01',stationCodes=[dict(lineNo='01',stationCode='01')])
        with self.assertRaises(ValueError):extract(value)

    def test_out_of_gate_names_preserved_as_different_bodies(self):
        value=payload()
        row(value,'10').update(stationName='双流机场2航站楼（出闸换乘）',transferLines='10,19',stationCodes=[dict(lineNo='10',stationCode='01'),dict(lineNo='19',stationCode='01')])
        row(value,'19')['stationName']='双流机场2航站楼东'
        result=extract(value)
        self.assertEqual(len(result['pairs']),1);pair=result['pairs'][0]
        self.assertEqual(pair['kind'],'out_of_station');self.assertNotEqual(*pair['stationNamesByLine'].values())

    def test_duplicate_branches_do_not_duplicate_contacts_or_mutate_source(self):
        value=payload();codes=[dict(lineNo='01',stationCode='01'),dict(lineNo='02',stationCode='01')]
        for line in ['01','02']:row(value,line).update(stationName='换乘站',transferLines='01,02',stationCodes=deepcopy(codes))
        value['data'][0]['subLine'].append(deepcopy(value['data'][0]['subLine'][0]));before=deepcopy(value)
        self.assertEqual(len(extract(value)['pairs']),1);self.assertEqual(value,before)


if __name__=='__main__':unittest.main()
