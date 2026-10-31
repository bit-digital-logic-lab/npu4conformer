"""独立可手算例；不是目标工程性能结果。"""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from analyze import analyze, render
from ledger import Ledger


def fixture():
    meta = dict(type='metadata', schema=1, scope='synthetic cycle example; not project measurement',
                resources={'axi_r':dict(unit='cycle', clock_hz=100000000, start=0, end=20, capacity_bytes_per_tick=4, evidence='synthetic'),
                           'axi_w':dict(unit='cycle', start=0, end=20, capacity_bytes_per_tick=4, evidence='synthetic')})
    events = [meta]
    for ident, version, offset, start in [('r0','v1',0,2), ('r1','v1',4,6), ('r2','v2',0,10)]:
        events.append(dict(type='transfer', id=ident, resource='axi_r', start=start, end=start+2,
                           tensor='X', version=version, format='A16', src='DDR', dst='Abank',
                           op='matmul', phase='load', reason='first_load' if ident!='r1' else 'capacity_reload',
                           logical_offset=offset, logical_bytes=8, valid_bytes=8, bus_bytes=8))
    for a,b,state,ident in [(0,2,'wait_memory','r0'),(2,4,'payload','r0'),(4,6,'backpressure','r1'),
                            (6,8,'payload','r1'),(8,10,'wait_memory','r2'),(10,12,'payload','r2'),(12,20,'idle_no_work','')]:
        events.append(dict(type='interval',resource='axi_r',start=a,end=b,state=state,
                           bytes=8 if state=='payload' else 0,transfer_id=ident, reason=state,
                           blocked_by='DDR' if state=='wait_memory' else 'consumer' if state=='backpressure' else '', evidence='synthetic fixture'))
    # W与R同拍活动合法；W尾拍只有2有效字节，线宽承载4字节。
    events += [dict(type='transfer', id='w0', resource='axi_w',start=2,end=4,tensor='Y',version='v1',format='C48',
                    src='Cbank',dst='DDR',op='matmul',phase='writeback',reason='result',logical_offset=0,logical_bytes=6,valid_bytes=6,bus_bytes=8),
               dict(type='interval',resource='axi_w',start=2,end=4,state='payload',bytes=6,wire_bytes=8,transfer_id='w0',reason='result',evidence='synthetic WSTRB')]
    return events


class Tests(unittest.TestCase):
    def test_busy_sample_not_effective_compute(self):
        from analyze import normalize_interval
        e = {'state':'compute', 'start':1, 'end':4, 'reason':'matrix child busy'}
        fixed = normalize_interval(e, {'kind':'module'})
        self.assertEqual(fixed['state'], 'busy')
        self.assertEqual(e['state'], 'compute')
        self.assertEqual(normalize_interval({'state':'compute'}, {'evidence':'FSM arithmetic phase'})['state'], 'compute')

    def test_partial_repeats_and_versions(self):
        s,_,_=analyze(fixture())
        t=next(t for t in s['tensors'] if t['tensor']=='X' and t['version']=='v1')
        self.assertEqual((t['unique_logical_bytes'],t['repeat_candidate_bytes']),(12,4))
        self.assertEqual(next(t for t in s['tensors'] if t['version']=='v2')['repeat_candidate_bytes'],0)

    def test_coverage_units_and_parallel(self):
        s,_,_=analyze(fixture())
        r,w=s['resources']
        self.assertEqual(sum(r['states'].values()),20)
        self.assertEqual((r['payload_fraction'],r['valid_bytes'],r['known_coverage']),(0.3,24,1))
        self.assertAlmostEqual(r['effective_B_per_s'],120000000)
        self.assertEqual(w['states']['unknown'],18)
        self.assertEqual((w['valid_bytes'],w['wire_bytes']),(6,8))
        self.assertIsNone(w['effective_B_per_s'])
        self.assertEqual(r['ledger_minus_interval_valid_bytes'],0)

    def test_overlap_rejected(self):
        e=fixture();e.append(dict(type='interval',resource='axi_r',start=3,end=5,state='unknown'))
        with self.assertRaises(ValueError):analyze(e)

    def test_capacity_rejected(self):
        e=fixture();e[-1]['wire_bytes']=9
        with self.assertRaises(ValueError):analyze(e)

    def test_window_and_id_rejected(self):
        e=fixture();e[-1]['end']=21
        with self.assertRaises(ValueError):analyze(e)
        e=fixture();e.append(copy.deepcopy(e[1]))
        with self.assertRaises(ValueError):analyze(e)

    def test_failed_transfer_not_deduplicated(self):
        e=fixture();e[2]['status']='failed'
        s,_,_=analyze(e)
        t=next(t for t in s['tensors'] if t['tensor']=='X' and t['version']=='v1')
        self.assertEqual((t['repeat_candidate_bytes'],t['unclassified_transfers']),(0,1))

    def test_formats_not_deduplicated(self):
        e=fixture();e[2]['format']='A16_transposed'
        s,_,_=analyze(e)
        self.assertEqual(sum(t['repeat_candidate_bytes'] for t in s['tensors']),0)

    def test_non_payload_cannot_count_bytes(self):
        e=fixture();e[-1]['state']='backpressure'
        with self.assertRaises(ValueError):analyze(e)

    def test_logger_and_report(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'trace.jsonl';meta=dict(scope='wall only',resources={'host':dict(unit='ns',start=0,end=10**10,evidence='python_wall')})
            with Ledger(p,meta) as log:
                with log.python_call('host','test'):
                    sum(range(100))
            events=[json.loads(l) for l in p.read_text().splitlines()]
            s,t,i=analyze(events);self.assertEqual(s['resources'][0]['valid_bytes'],0)
            render(Path(d)/'out',s,t,i)
            self.assertTrue((Path(d)/'out/timeline.html').exists())


if __name__=='__main__':
    unittest.main(verbosity=2)
