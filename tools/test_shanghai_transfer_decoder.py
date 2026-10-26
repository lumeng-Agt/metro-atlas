import unittest
from copy import deepcopy
from review_shanghai_operator_transfers import decode_lines,extract,LINES


def rows():
    return {n:[dict(line=int(n),stat_id=n+'11',name='独立'+n,station_code=format(1<<(int(n)-1),'X')+'-TEST')] for n in LINES}


class DecoderChecks(unittest.TestCase):
    def test_hex_is_a_bitmask_not_decimal_concatenated_line_numbers(self):
        self.assertEqual(decode_lines('83-RMGC'),['1','2','8'])
        self.assertEqual(decode_lines('4005-SHNZ'),['1','3','15'])
        self.assertEqual(decode_lines('1801-HZL'),['1','12','13'])

    def test_outside_scope_high_bits_are_not_truncated_into_metro_lines(self):
        self.assertEqual(decode_lines(format((1<<40)|(1<<50),'X')+'-TEST'),['41','51'])

    def test_invalid_masks_fail(self):
        for code in ['','ZZ-name','0-name',None,'12']:
            with self.assertRaises(ValueError):decode_lines(code)

    def test_missing_line_fails(self):
        value=rows();value.pop('18')
        with self.assertRaises(ValueError):extract(value)

    def test_own_line_must_be_in_mask(self):
        value=rows();value['1'][0]['station_code']='2-TEST'
        with self.assertRaises(ValueError):extract(value)

    def test_unilateral_interchange_is_not_silently_accepted(self):
        value=rows();value['1'][0].update(name='换乘',station_code='3-TEST')
        with self.assertRaises(ValueError):extract(value)

    def test_duplicate_directions_are_deduplicated_and_input_unchanged(self):
        value=rows()
        for n in ['1','2']:
            value[n][0].update(name='换乘',station_code='3-TEST')
            value[n].append(deepcopy(value[n][0]))
        before=deepcopy(value)
        self.assertEqual(len(extract(value)),1);self.assertEqual(value,before)

    def test_disagreeing_directions_fail(self):
        value=rows();value['1'].append(dict(line=1,stat_id='111',name='独立1',station_code='3-TEST'))
        with self.assertRaises(ValueError):extract(value)


if __name__=='__main__':unittest.main()
