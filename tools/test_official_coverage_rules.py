"""Negative fixtures for coverage rules; not evidence of any city's completeness."""
import copy
import unittest
from official_coverage import check_project, cutoff_evidence_errors


class CoverageRules(unittest.TestCase):
    def setUp(self):
        self.target = dict(id='fixture', reviewStatus='verified', source='https://example.invalid/fixture', sourcePublicationDate='2026-01-01', groups=[dict(id='line', stationNames=['A', 'B', 'C'], loop=True)])
        self.plans = [dict(projectIds=['fixture'], lineGroups=[dict(historicalLineId='line', stationIds=['a', 'b', 'c'], loop=True)])]
        self.names = dict(a='A', b='B', c='C')

    def test_full_fixture_passes(self):
        self.assertEqual(check_project(self.target, self.plans, self.names), [])

    def test_known_middle_stop_cannot_be_omitted(self):
        self.plans[0]['lineGroups'][0]['stationIds'].remove('b')
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_half_ring_cannot_pass(self):
        self.plans[0]['lineGroups'][0]['loop'] = False
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_extension_missing_fails(self):
        self.target['groups'].append(dict(id='east', stationNames=['D', 'E']))
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_wrong_order_fails(self):
        self.plans[0]['lineGroups'][0]['stationIds'] = ['a', 'c', 'b']
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_policy_classification_does_not_exempt_construction(self):
        self.assertTrue(check_project(self.target, [], self.names))

    def test_duplicate_scope_fails(self):
        self.plans.append(copy.deepcopy(self.plans[0]))
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_corridor_exception_requires_evidence(self):
        self.target['groups'][0] = dict(id='line', scopeType='corridor', requiredPlaces=['A', 'C'], loop=True)
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_transfer_missing_fails(self):
        self.target['transfers'] = ['required-transfer']
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_unreviewed_target_fails(self):
        self.target['reviewStatus'] = 'pending'
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_documented_extension_can_be_contained_in_full_line(self):
        self.target['groups'][0].update(stationNames=['B', 'C'], matchScope='contiguous_subsequence')
        self.assertEqual(check_project(self.target, self.plans, self.names), [])

    def test_contained_extension_still_cannot_skip_intermediate_station(self):
        self.target['groups'][0].update(matchScope='contiguous_subsequence')
        self.plans[0]['lineGroups'][0]['stationIds'] = ['a', 'c']
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_later_timetable_is_not_cutoff_opening_evidence(self):
        network = dict(date='2026-10-01', groups=[self.target['groups'][0]],
                       sourceRetrievedAt='2026-10-23', temporalReviewStatus='pending')
        self.assertTrue(cutoff_evidence_errors(network, '2026-10-01'))

    def test_just_setting_reviewed_flag_is_insufficient(self):
        network = dict(date='2026-10-01', groups=[self.target['groups'][0]], temporalReviewStatus='verified')
        self.assertTrue(cutoff_evidence_errors(network, '2026-10-01'))

    def test_future_opening_cannot_enter_cutoff(self):
        network = dict(date='2026-10-01', groups=[self.target['groups'][0]], temporalReviewStatus='verified',
                       temporalEvidence=[dict(source='https://example.invalid/opening', effectiveDate='2026-10-02')])
        self.assertTrue(cutoff_evidence_errors(network, '2026-10-01'))

    def test_explicit_dated_cutoff_evidence(self):
        network = dict(date='2026-10-01', groups=[self.target['groups'][0]], temporalReviewStatus='verified',
                       temporalEvidence=[dict(source='https://example.invalid/opening', effectiveDate='2026-09-28')])
        self.assertEqual(cutoff_evidence_errors(network, '2026-10-01'), [])


if __name__ == '__main__':
    unittest.main()
