import copy
import json
import tempfile
import unittest
from pathlib import Path
from render import prepare, render


def example():
    return [dict(type='metadata',schema=1,scope='synthetic selftest',resources={
        'array':dict(unit='cycle',clock_hz=100,timebase='clk',start=0,end=10),
        'dma':dict(unit='cycle',clock_hz=100,timebase='clk',start=0,end=10),
        'valid':dict(unit='cycle',clock_hz=100,timebase='clk',start=0,end=10,kind='signal')}),
        dict(type='interval',resource='array',start=2,end=7,state='compute'),
        dict(type='interval',resource='dma',start=0,end=4,state='payload',reason='weights'),
        dict(type='interval',resource='valid',start=0,end=5,state='0'),
        dict(type='interval',resource='valid',start=5,end=6,state='1'),
        dict(type='interval',resource='valid',start=6,end=10,state='0')]


class Tests(unittest.TestCase):
    def test_shared_time_and_unknown(self):
        d=prepare(example());self.assertEqual(len(d['groups']),1)
        self.assertEqual(d['lanes'][0]['states'],{'unknown':5,'compute':5})
        self.assertEqual(d['lanes'][1]['known_coverage'],.4)

    def test_signals_preserve_pulse(self):
        lane=prepare(example())['lanes'][2]
        self.assertEqual(lane['states'],{'0':9,'1':1})

    def test_same_frequency_not_autoaligned(self):
        e=example()
        for cfg in e[0]['resources'].values():del cfg['timebase']
        self.assertEqual(len(prepare(e)['groups']),3)

    def test_different_domain_rejected(self):
        e=example();e[0]['resources']['dma']['clock_hz']=200
        with self.assertRaises(ValueError):prepare(e)

    def test_overlap_rejected(self):
        e=example();e.append(dict(type='interval',resource='array',start=6,end=9,state='idle_no_work'))
        with self.assertRaises(ValueError):prepare(e)

    def test_window_rejected(self):
        e=example();e[1]['end']=11
        with self.assertRaises(ValueError):prepare(e)

    def test_html_json_injection(self):
        e=example();e[1]['reason']='</script><script>alert(1)</script>'
        with tempfile.TemporaryDirectory() as p:
            src=Path(p)/'trace.jsonl';out=Path(p)/'wave.html'
            src.write_text('\n'.join(json.dumps(x) for x in e))
            render(src,out,'test')
            self.assertNotIn(e[1]['reason'],out.read_text())
            self.assertTrue(out.with_suffix('.summary.json').exists())


if __name__=='__main__':unittest.main(verbosity=2)
