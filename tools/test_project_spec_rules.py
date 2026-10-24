"""Regression cases for authored order and multi-line project interchanges."""
from copy import deepcopy
import unittest
from validate_project_spec import validate


class ProjectSpecRules(unittest.TestCase):
    def setUp(self):
        self.city = dict(id='test', center=[30, 104], stations=[])
        self.spec = dict(city='test', plan=dict(id='test-plan', title='Fixture', status='approved',
            sourceType='official', source='https://example.org/fixture', sourceTitle='Fixture only',
            sourceCheckedAt='2026-10-24', sourcePublicationDate='2026-01-01', description='Synthetic geometry fixture'),
            stations=[dict(id='test-'+n, name=n, latlng=[30, lon], coordinateSource='local_road_geometry',
                           coordinateNote='Synthetic test point') for n, lon in [('A',104),('C',104.02),('B',104.01)]],
            lineGroup=dict(historicalLineId='test-line-a', stationIds=['test-A','test-B','test-C'], precisionNote='Fixture'))

    def test_explicit_legacy_order_beats_declaration_order(self):
        self.assertEqual(validate(self.spec, self.city, set()), [])

    def test_unspecified_legacy_order_still_checks_declared_geometry(self):
        del self.spec['lineGroup']['stationIds']
        self.assertTrue(any('folds back' in e for e in validate(self.spec, self.city, set())))

    def multi_line(self):
        spec = deepcopy(self.spec)
        spec['lineGroups'] = [dict(spec.pop('lineGroup'), taskId='first'),
            dict(historicalLineId='test-line-b', taskId='second', stationIds=['test-A','test-B'], precisionNote='Fixture')]
        spec['transfers'] = [dict(id='interchange', sourceNote='Synthetic two-line interchange',
            lineIds=['test-line-a','test-line-b'], stationInstanceIds=['test-body-a','test-body-b'])]
        return spec

    def test_two_new_lines_in_one_project_can_interchange(self):
        self.assertEqual(validate(self.multi_line(), self.city, set()), [])

    def test_interchange_cannot_share_one_physical_body(self):
        spec = self.multi_line(); spec['transfers'][0]['stationInstanceIds'] = ['same','same']
        self.assertTrue(any('own physical body' in e for e in validate(spec,self.city,set())))

    def test_interchange_line_ids_must_be_distinct(self):
        spec = self.multi_line(); spec['transfers'][0]['lineIds'] = ['test-line-a','test-line-a']
        self.assertTrue(any('must be distinct' in e for e in validate(spec,self.city,set())))

    def test_unknown_existing_line_is_rejected(self):
        spec = self.multi_line(); spec['transfers'][0]['lineIds'][1] = 'unknown'
        self.assertTrue(any('unknown existing line' in e for e in validate(spec,self.city,set())))

    def test_transfer_without_project_line_is_rejected(self):
        spec = self.multi_line(); spec['transfers'][0]['lineIds'] = ['old-a','old-b']
        self.assertTrue(any('no line belongs' in e for e in validate(spec,self.city,{'old-a','old-b'})))


if __name__ == '__main__': unittest.main()
