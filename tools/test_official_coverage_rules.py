"""Negative fixtures for coverage rules; not evidence of any city's completeness."""
import copy
import unittest
from official_coverage import ROOT, read, check_project, cutoff_evidence_errors
from engineering_scope import coverage_errors as engineering_errors


class CoverageRules(unittest.TestCase):
    def test_unreviewed_shared_running_cannot_be_hidden_by_interchange_completion(self):
        network=dict(date='2026-10-01',groups=[dict(id='line')],temporalReviewStatus='verified',transferReviewStatus='verified',
                     temporalEvidence=[dict(source='https://example.invalid/dated',effectiveDate='2026-06-28')],sharedRunningReviewStatus='pending')
        self.assertEqual(cutoff_evidence_errors(network,'2026-10-01'),['cutoff shared-running geometry not independently reviewed'])
        network['sharedRunningReviewStatus']='verified'
        self.assertEqual(cutoff_evidence_errors(network,'2026-10-01'),[])

    def reservation_fixture(self):
        pair=dict(id='reserved-interface',status='reserved',complexId='complex',lineIds=['line-a','line-b'],stationInstanceIds=['body-a','body-b'],source='https://example.invalid/plan',reservationEvidence='https://example.invalid/interface')
        self.target['reservedTransfers']=[copy.deepcopy(pair)]
        self.plans[0].update(requireOpen=False,requiredTransfers=[pair])
        return pair

    def test_reserved_interface_is_a_separate_unopened_requirement(self):
        self.reservation_fixture()
        self.assertEqual(check_project(self.target,self.plans,self.names),[])
        self.plans[0]['requiredTransfers']=[]
        self.assertTrue(any('reserved interface missing' in e for e in check_project(self.target,self.plans,self.names)))

    def test_reserved_interface_cannot_be_counted_as_active_or_open(self):
        pair=self.reservation_fixture();pair['status']='active'
        self.assertTrue(any('misrepresented as open' in e for e in check_project(self.target,self.plans,self.names)))
        pair['status']='reserved';self.plans[0]['requireOpen']=True
        self.assertTrue(any('misrepresented as open' in e for e in check_project(self.target,self.plans,self.names)))

    def test_reservation_identity_and_source_cannot_be_substituted(self):
        pair=self.reservation_fixture();pair['stationInstanceIds']=['body-a','other-body']
        self.assertTrue(any('stationInstanceIds differs' in e for e in check_project(self.target,self.plans,self.names)))
        pair=self.reservation_fixture();pair['reservationEvidence']=''
        self.assertTrue(any('reservationEvidence differs' in e for e in check_project(self.target,self.plans,self.names)))

    def test_invalid_independent_reservation_cannot_pass_by_matching_bad_data(self):
        pair=self.reservation_fixture();pair['stationInstanceIds']=['body-a','body-a']
        self.target['reservedTransfers']=[copy.deepcopy(pair)]
        self.assertTrue(any('distinct line bodies' in e for e in check_project(self.target,self.plans,self.names)))

    def setUp(self):
        self.target = dict(id='fixture', reviewStatus='verified', source='https://example.invalid/fixture', sourcePublicationDate='2026-01-01', groups=[dict(id='line', stationNames=['A', 'B', 'C'], loop=True)])
        self.plans = [dict(projectIds=['fixture'], lineGroups=[dict(historicalLineId='line', stationIds=['a', 'b', 'c'], loop=True)])]
        self.names = dict(a='A', b='B', c='C')

    def test_rebuilt_body_cannot_be_replaced_by_same_name_old_body(self):
        self.target['groups'][0]['requiredStationInstances']={'B':'rebuilt-b'}
        self.assertTrue(any('physical body differs' in e for e in check_project(self.target,self.plans,self.names)))
        self.plans[0]['lineGroups'][0]['stationInstances']={'b':'rebuilt-b'}
        self.assertEqual(check_project(self.target,self.plans,self.names), [])

    def test_required_rebuilt_body_without_matching_station_name_fails(self):
        self.target['groups'][0]['requiredStationInstances']={'D':'rebuilt-d'}
        self.assertTrue(any('physical body differs' in e for e in check_project(self.target,self.plans,self.names)))

    def engineering_fixture(self):
        return dict(taskKind='engineering_track', source='https://example.invalid/engineering-fixture', stationIds=['existing'],
                    engineeringEndpoints=[dict(id='anchor', name='Existing station end', stationId='existing', stationInstanceId='existing-body'),
                                          dict(id='boundary', name='Boundary, not a station', latlng=[22.8, 113.8], toleranceM=40)],
                    engineeringSegments=[dict(fromId='anchor', toId='boundary', points=[[22.79, 113.8], [22.8, 113.8]], corridorToleranceM=80)])

    def test_engineering_scope_needs_no_invented_passenger_stop(self):
        expected = self.engineering_fixture()
        self.assertEqual(engineering_errors(copy.deepcopy(expected), expected), [])

    def test_engineering_interfaces_cannot_be_replaced_by_passenger_stops(self):
        expected = self.engineering_fixture(); actual = copy.deepcopy(expected)
        actual['stationIds'].append('fake-boundary-station')
        self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_scope_cannot_omit_physical_track(self):
        expected = self.engineering_fixture(); actual = copy.deepcopy(expected)
        actual['engineeringSegments'] = []
        self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_scope_cannot_widen_tolerance_to_pass(self):
        expected = self.engineering_fixture()
        for section, key in [('engineeringEndpoints', 'toleranceM'), ('engineeringSegments', 'corridorToleranceM')]:
            actual = copy.deepcopy(expected); actual[section][-1][key] = 100000
            self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_scope_cannot_add_or_remove_a_real_station_body(self):
        expected = self.engineering_fixture(); actual = copy.deepcopy(expected)
        actual['newStationIds'] = ['existing']
        self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_scope_rejects_nonfinite_tolerances(self):
        expected = self.engineering_fixture()
        for value in [float('nan'), float('inf'), True, '100']:
            actual = copy.deepcopy(expected); actual['engineeringSegments'][0]['corridorToleranceM'] = value
            self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_scope_rejects_duplicate_or_nonfinite_geometry(self):
        expected = self.engineering_fixture()
        actual = copy.deepcopy(expected); actual['engineeringEndpoints'].append(copy.deepcopy(actual['engineeringEndpoints'][0]))
        self.assertTrue(engineering_errors(actual, expected))
        actual = copy.deepcopy(expected); actual['engineeringSegments'][0]['points'][0] = [float('nan'), 113.8]
        self.assertTrue(engineering_errors(actual, expected))

    def test_engineering_coverage_uses_the_independent_definition(self):
        expected = self.engineering_fixture(); expected.update(id='line', scopeType='engineering')
        self.target['groups'] = [expected]
        actual = copy.deepcopy(expected); actual['coverageGroupId'] = 'line'
        self.plans[0]['lineGroups'] = [actual]
        self.assertEqual(check_project(self.target, self.plans, self.names), [])
        actual['engineeringSegments'][0]['points'][-1][0] += 0.01
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_full_fixture_passes(self):
        self.assertEqual(check_project(self.target, self.plans, self.names), [])

    def test_known_middle_stop_cannot_be_omitted(self):
        self.plans[0]['lineGroups'][0]['stationIds'].remove('b')
        self.assertTrue(check_project(self.target, self.plans, self.names))

    def test_historical_extension_checks_new_scope_separately_from_full_service(self):
        self.target['groups'][0].update(fullServiceOrder=True, constructionStationNames=['B', 'C'])
        self.plans[0]['lineGroups'][0]['stationIds']=['b','c']
        self.assertEqual(check_project(self.target,self.plans,self.names,historical_construction=True),[])
        self.assertTrue(check_project(self.target,self.plans,self.names))

    def test_historical_construction_cannot_bypass_its_service_order(self):
        self.target['groups'][0].update(fullServiceOrder=True, constructionStationNames=['A', 'C'])
        self.plans[0]['lineGroups'][0]['stationIds']=['a','c']
        self.assertTrue(check_project(self.target,self.plans,self.names,historical_construction=True))

    def test_official_yearbook_needs_a_precise_bibliographic_locator(self):
        self.target['sourcePublicationDate']=None
        self.target['bibliographicCitation']=dict(kind='official_yearbook',edition='Official history',locator='Dated event, page 154')
        self.assertEqual(check_project(self.target,self.plans,self.names,historical_construction=True),[])
        self.assertTrue(check_project(self.target,self.plans,self.names))
        self.target['bibliographicCitation'].pop('locator')
        self.assertTrue(check_project(self.target,self.plans,self.names,historical_construction=True))

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

    def test_reviewed_station_order_does_not_certify_missing_transfer_inventory(self):
        self.target['transferReviewStatus'] = 'pending'
        self.assertIn('independent transfer coverage incomplete', check_project(self.target, self.plans, self.names))

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
                       transferReviewStatus='verified',
                       temporalEvidence=[dict(source='https://example.invalid/opening', effectiveDate='2026-09-28')])
        self.assertEqual(cutoff_evidence_errors(network, '2026-10-01'), [])

    def test_station_order_and_dates_do_not_prove_interchange_completeness(self):
        network=dict(date='2026-10-01',groups=[self.target['groups'][0]],temporalReviewStatus='verified',
                     temporalEvidence=[dict(source='https://example.invalid/opening',effectiveDate='2026-09-28')])
        self.assertIn('cutoff interchange inventory not independently reviewed',cutoff_evidence_errors(network,'2026-10-01'))

    def test_beijing_first_opening_cannot_stand_for_the_approved_full_project(self):
        targets=read(ROOT/'data/official_targets_2026-10-01.json')['cities']['beijing']['projects']
        expected=next(p for p in targets if p['id']=='bj-line22')
        plan=next(p for p in read(ROOT/'data/campaigns.json')['cities']['beijing']['futurePlans'] if p['id']=='bj-line22-build')
        stations=next(c for c in read(ROOT/'data/cities.json')['cities'] if c['id']=='beijing')['stations']
        names={s['id']:s['name'] for s in stations}
        # Keep the independent pending-transfer warning in both comparisons;
        # this test specifically requires an additional missing-west failure.
        complete=check_project(expected,[plan],names)
        self.assertFalse(any('beijing-line22-west:' in issue for issue in complete))
        only_first=copy.deepcopy(plan)
        only_first['lineGroups']=only_first['lineGroups'][:1]
        self.assertTrue(any('beijing-line22-west:' in issue for issue in check_project(expected,[only_first],names)))


if __name__ == '__main__':
    unittest.main()
