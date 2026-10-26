import unittest
from copy import deepcopy
from audit_operator_transfers import audit,audit_pairs
from review_shenzhen_cutoff_interchanges import documented_pairs,evidence_errors,EVIDENCE,ROOT
import json


def evidence():
    return dict(retrievedAt='2026-10-25',source='https://example.invalid/operator',lines=[
        dict(operatorLineId=1,interchanges=[dict(stationName='示例站',operatorLineIds=[2,3,15])]),
        dict(operatorLineId=2,interchanges=[dict(stationName='示例站',operatorLineIds=[1])])])


def world():
    return dict(cityId='guangzhou',stations=[
        dict(id='a',stationInstanceId='a',name='示例站',stationLineId='guangzhou-line1'),
        dict(id='b',stationInstanceId='b',name='示例站',stationLineId='guangzhou-line2-2')],
        routes=[dict(open=True,historicalLineId='guangzhou-line1',directions=[dict(stationIds=['a'])]),
                dict(open=True,historicalLineId='guangzhou-line2-2',directions=[dict(stationIds=['b'])])],
        transferConnections=[dict(id='link',lineIds=['guangzhou-line1','guangzhou-line2-2'],stationInstanceIds=['a','b'])])


class OperatorTransferAudit(unittest.TestCase):
    def test_duplicate_direction_claim_is_one_pair(self):
        report=audit(world(),evidence())
        self.assertEqual(report['expectedPairs'],2)  # 1/2 and 1/3; outside-scope 15 excluded.
        self.assertEqual(report['matchedPairs'],1)
        self.assertFalse(report['completeDeliveryCertified'])

    def test_same_name_does_not_establish_a_transfer(self):
        value=world();value['transferConnections']=[]
        self.assertEqual(audit(value,evidence())['matchedPairs'],0)

    def test_same_body_cannot_replace_two_platforms(self):
        value=world();value['transferConnections'][0]['stationInstanceIds']=['a','a']
        report=audit(value,evidence())
        self.assertEqual(report['matchedPairs'],0);self.assertTrue(report['invalidConnections'])

    def test_retired_line_does_not_serve_the_body(self):
        value=world();value['routes'][1]['retired']=True
        report=audit(value,evidence())
        self.assertEqual(report['matchedPairs'],0);self.assertTrue(report['nonOpenConnections']);self.assertFalse(report['invalidConnections'])

    def test_body_line_ownership_is_checked(self):
        value=world();value['stations'][1]['stationLineId']='guangzhou-line1'
        self.assertEqual(audit(value,evidence())['matchedPairs'],0)

    def test_no_mutation_of_source_or_saved_world(self):
        value=world();source=evidence();before=deepcopy((value,source))
        audit(value,source)
        self.assertEqual((value,source),before)

    def test_reserved_contact_cannot_replace_open_interchange(self):
        value=world();value['transferConnections'][0]['status']='reserved'
        self.assertEqual(audit(value,evidence())['matchedPairs'],0)

    def test_alias_only_changes_station_spelling_not_line_identity(self):
        value=world();value['stations'][0]['name']='旧显示名'
        report=audit_pairs(value,[('示例站','guangzhou-line1','guangzhou-line2-2')],evidence(),{'旧显示名':'示例站'})
        self.assertEqual(report['matchedPairs'],1)
        value['stations'][1]['stationLineId']='wrong-line'
        self.assertEqual(audit_pairs(value,[('示例站','guangzhou-line1','guangzhou-line2-2')],evidence(),{'旧显示名':'示例站'})['matchedPairs'],0)

    def test_duplicated_external_station_roster_rejected(self):
        row=dict(stationName='测试',lineNumbers=['1','2'])
        with self.assertRaises(ValueError):documented_pairs(dict(stations=[row,row],lineIds={'1':'a','2':'b'}))

    def test_repeated_external_line_does_not_create_self_transfer(self):
        with self.assertRaises(ValueError):documented_pairs(dict(stations=[dict(stationName='测试',lineNumbers=['1','1'])],lineIds={'1':'a'}))

    def test_external_map_omission_is_detected_without_campaign_data(self):
        source=json.loads(EVIDENCE.read_text(encoding='utf-8'))
        orders=json.loads((ROOT/'data/official_evidence/shenzhen_2026-06-28_station_orders.json').read_text(encoding='utf-8'))
        self.assertFalse(evidence_errors(source,orders))
        source['stations']=[s for s in source['stations'] if s['stationName']!='光明城']
        self.assertTrue(evidence_errors(source,orders))

    def test_two_of_four_lines_cannot_certify_a_whole_interchange(self):
        source=json.loads(EVIDENCE.read_text(encoding='utf-8'))
        orders=json.loads((ROOT/'data/official_evidence/shenzhen_2026-06-28_station_orders.json').read_text(encoding='utf-8'))
        next(s for s in source['stations'] if s['stationName']=='岗厦北')['lineNumbers']=['2','10']
        self.assertTrue(evidence_errors(source,orders))


if __name__=='__main__':unittest.main()
