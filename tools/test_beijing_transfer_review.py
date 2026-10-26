from copy import deepcopy
import json
import unittest
from review_beijing_cutoff_interchanges import EVIDENCE,ORDERS,evidence_errors,documented_pairs,source_memberships,LINES,LINE14_NAMES


class BeijingTransferReview(unittest.TestCase):
    def setUp(self):
        self.evidence=json.loads(EVIDENCE.read_text(encoding='utf-8'))
        self.orders=json.loads(ORDERS.read_text(encoding='utf-8'))
    def test_all_reviewed_symbols_match_independent_source_membership(self):
        self.assertEqual(evidence_errors(self.evidence,self.orders),[])
        self.assertEqual(len(documented_pairs(self.evidence)),122)
    def test_missing_four_line_complex_pair_is_not_a_complete_roster(self):
        next(r for r in self.evidence['stations'] if r['stationName']=='草桥')['lineNumbers'].remove('19')
        self.assertTrue(evidence_errors(self.evidence,self.orders))
    def test_missing_different_spelling_qinghe_is_not_invisible(self):
        self.evidence['stations']=[r for r in self.evidence['stations'] if r['stationName']!='清河']
        self.assertTrue(evidence_errors(self.evidence,self.orders))
    def test_gray_symbol_is_outside_transfer_not_a_closed_station(self):
        for name in ['木樨地','大钟寺']:
            row=next(r for r in self.evidence['stations'] if r['stationName']==name)
            self.assertEqual(row['transferKind'],'out_of_station');row['transferKind']='interchange'
        self.assertTrue(evidence_errors(self.evidence,self.orders))
    def test_nearby_new_and_old_stations_do_not_become_fake_transfer(self):
        for name in ['龙泽西','霍营东']:
            self.evidence['stations'].append(dict(stationName=name,lineNumbers=['13','18'],transferKind='interchange'))
        self.assertTrue(evidence_errors(self.evidence,self.orders))
    def test_stale_planned_station_table_does_not_override_operator_stop_list(self):
        memberships=source_memberships(self.orders)
        self.assertEqual(len(LINE14_NAMES),33)
        self.assertTrue({'红庙','陶然桥','高家园','南八里庄'}.isdisjoint(memberships['14']))
        self.assertTrue({'东管头南','首经贸','花乡东桥','白盆窑'}.issubset(memberships['房山']))
    def test_mapping_drift_fails(self):
        self.evidence['lineIds']['14']='beijing-line15-15'
        self.assertTrue(evidence_errors(self.evidence,self.orders))
    def test_duplicate_station_symbol_fails(self):
        self.evidence['stations'].append(deepcopy(self.evidence['stations'][0]))
        self.assertTrue(evidence_errors(self.evidence,self.orders))


if __name__=='__main__':unittest.main()
