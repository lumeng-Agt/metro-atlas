from copy import deepcopy
import unittest
from unittest.mock import patch
import test_campaign_task_integrity as checker


class HistoricalStationReferences(unittest.TestCase):
    def setUp(self):
        self.group=deepcopy(next(c for c in checker.CAMPAIGNS['cities']['guangzhou']['chapters'] if c['id']=='guangzhou-line3-airport-opening-2010')['lineGroups'][0])
    def errors(self,group):
        errors=[]
        with patch.object(checker,'errors',errors):checker.check_group('guangzhou','fixture',group,'lineGroups[0]')
        return errors
    def test_documented_closed_station_can_have_no_modern_relation(self):self.assertEqual(self.errors(self.group),[])
    def test_exception_requires_the_station_opening_source(self):
        self.group['historicalStationSources']['guangzhou-h3-airport-south']='https://example.invalid/unrelated'
        self.assertTrue(self.errors(self.group))
    def test_no_blanket_historical_exception(self):
        self.group['historicalStationSources']={}
        self.assertTrue(self.errors(self.group))
    def test_evidence_does_not_allow_foreign_line_ownership(self):
        self.group['historicalLineId']='guangzhou-line2-2'
        self.assertTrue(self.errors(self.group))


if __name__=='__main__':unittest.main()
