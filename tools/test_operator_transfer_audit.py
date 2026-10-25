import unittest
from copy import deepcopy
from audit_operator_transfers import audit


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


if __name__=='__main__':unittest.main()
