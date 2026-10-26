from copy import deepcopy
import unittest
from transfer_scope import is_transfer_task


def task():
    return dict(operationType='transfer_connection',source='https://example.invalid/opening',lineGroups=[],eventOnly=False,
                requiredTransfers=[dict(id='pair',source='https://example.invalid/opening',lineIds=['city-one','city-two'],stationInstanceIds=['city-body1','city-body2'])])


class TransferScope(unittest.TestCase):
    def test_future_passage_must_remain_reserved_and_sourced(self):
        value=task();value.update(phase='future',requireOpen=False)
        pair=value['requiredTransfers'][0];pair.update(status='reserved',reservationEvidence='https://example.invalid/approval',reservationKind='pedestrian_passage')
        self.assertTrue(is_transfer_task(value,'city'))
        pair['status']='active';self.assertFalse(is_transfer_task(value,'city'))
        pair['status']='reserved';pair['reservationEvidence']='';self.assertFalse(is_transfer_task(value,'city'))

    def test_real_pair_is_a_construction_action_without_rail(self):self.assertTrue(is_transfer_task(task(),'city'))
    def test_no_pairs_is_not_playable(self):
        value=task();value['requiredTransfers']=[];self.assertFalse(is_transfer_task(value,'city'))
    def test_text_only_node_is_not_a_construction_action(self):
        value=task();value['eventOnly']=True;self.assertFalse(is_transfer_task(value,'city'))
    def test_shared_body_is_rejected(self):
        value=task();value['requiredTransfers'][0]['stationInstanceIds']=['city-body1','city-body1'];self.assertFalse(is_transfer_task(value,'city'))
    def test_same_line_is_not_an_interchange(self):
        value=task();value['requiredTransfers'][0]['lineIds']=['city-one','city-one'];self.assertFalse(is_transfer_task(value,'city'))
    def test_foreign_city_is_rejected(self):self.assertFalse(is_transfer_task(task(),'elsewhere'))
    def test_missing_source_is_not_a_complete_action(self):
        value=task();value['requiredTransfers'][0]['source']='';self.assertFalse(is_transfer_task(value,'city'))
    def test_duplicate_identity_is_rejected(self):
        value=task();value['requiredTransfers']*=2;self.assertFalse(is_transfer_task(value,'city'))
    def test_no_mutation(self):
        value=task();before=deepcopy(value);is_transfer_task(value,'city');self.assertEqual(value,before)


if __name__=='__main__':unittest.main()
