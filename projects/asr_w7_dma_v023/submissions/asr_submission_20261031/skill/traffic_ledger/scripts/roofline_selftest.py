import sys,unittest
sys.path.insert(0,str(__import__('pathlib').Path(__file__).resolve().parent))
from roofline import calculate
class Test(unittest.TestCase):
 def fixture(self):return dict(scope='synthetic',memory_boundary='shared128',peak_source='16x16',bandwidth_source='port',bandwidth_basis='interface_contract',traffic_basis='bus_bytes',clock_relation='same_cycle_domain',peak_ops_per_cycle=512,bandwidth_bytes_per_cycle=16,cases=[dict(M=16,N=16,K=16,read_bytes=512,write_bytes=512,cycles=128,source='synthetic')])
 def test_units_and_readwrite(self):
  c=calculate(self.fixture())['cases'][0];self.assertEqual(c['useful_ops'],8192);self.assertEqual(c['intensity_ops_per_byte'],8);self.assertEqual(c['throughput_ops_per_cycle'],64);self.assertEqual(c['roof_fraction'],.5)
 def test_circular_bandwidth_rejected(self):
  s=self.fixture();s['bandwidth_basis']='workload_average'
  with self.assertRaises(ValueError):calculate(s)
 def test_exceeds_roof(self):
  s=self.fixture();s['cases'][0]['cycles']=1
  with self.assertRaises(ValueError):calculate(s)
 def test_clock_not_guessed(self):
  s=self.fixture();s['clock_relation']='unknown'
  with self.assertRaises(ValueError):calculate(s)
if __name__=='__main__':unittest.main()
