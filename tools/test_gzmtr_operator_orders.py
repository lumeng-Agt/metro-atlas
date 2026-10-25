"""Reject misleading operator extraction inputs before they reach targets."""
from copy import deepcopy
import unittest
from unittest.mock import patch
import import_gzmtr_station_orders as parser


def payload():
    return dict(success=True,businessObject=[dict(lineId=1,lineShowCode='1',lineName='一号线',stations=[
        dict(stationId=101,stationName='西塱',orderNum=1,isHuanCheng=False),
        dict(stationId=102,stationName='坑口',orderNum=2,isHuanCheng=False)])])


class OperatorOrders(unittest.TestCase):
    def test_transport_failure_is_not_an_empty_complete_inventory(self):
        value=payload();value['success']=False
        with self.assertRaises(ValueError):parser.extract(value)

    def test_missing_required_line_fails(self):
        with patch.object(parser,'LINE_IDS',{1,2}):
            with self.assertRaises(ValueError):parser.extract(payload())

    def test_duplicate_stop_order_fails(self):
        value=payload();value['businessObject'][0]['stations'][1]['orderNum']=1
        with patch.object(parser,'LINE_IDS',{1}):
            with self.assertRaises(ValueError):parser.extract(value)

    def test_duplicate_station_id_fails(self):
        value=payload();value['businessObject'][0]['stations'][1]['stationId']=101
        with patch.object(parser,'LINE_IDS',{1}):
            with self.assertRaises(ValueError):parser.extract(value)

    def test_duplicate_line_fails(self):
        value=payload();value['businessObject'].append(deepcopy(value['businessObject'][0]))
        with patch.object(parser,'LINE_IDS',{1}):
            with self.assertRaises(ValueError):parser.extract(value)

    def test_nonmetro_does_not_enter_whitelisted_scope(self):
        value=payload();extra=deepcopy(value['businessObject'][0]);extra.update(lineId=15,lineName='海珠有轨');value['businessObject'].append(extra)
        with patch.object(parser,'LINE_IDS',{1}):
            rows=parser.extract(value)
        self.assertEqual(len(rows),1);self.assertEqual(rows[0]['stationNames'],['西塱','坑口'])

    def test_source_spellings_remain_available_after_normalization(self):
        value=payload();value['businessObject'][0]['stations'][0]['stationName']='虫雷 岗'
        with patch.object(parser,'LINE_IDS',{1}):rows=parser.extract(value)
        self.assertEqual(rows[0]['rawStationNames'][0],'虫雷 岗');self.assertEqual(rows[0]['stationNames'][0],'𧒽岗')


if __name__=='__main__':unittest.main()
