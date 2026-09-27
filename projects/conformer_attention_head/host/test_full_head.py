"""中文说明：验证固定点边界、原始模型接口、mask 隔离与纯传输客户端。"""
import ast,math,struct,unittest,zlib
from pathlib import Path
import torch
from host.integer_reference import round_shift,select_shift,from_bits,to_bits,reference
from host.export_image import build_image
from host.source_model import ROOT,load_source,make_fixture
from host.transport import packet

class WholeHeadTests(unittest.TestCase):
    def test_rounding_and_signed_edges(self):
        for a in (-7,-5,-3,-1,0,1,3,5,7):
            self.assertEqual(round_shift(a,1),round(a/2))
        self.assertEqual(round_shift(-123,-3),-984)
        self.assertEqual(round_shift(99,64),0)
    def test_quant_shift_bounds(self):
        for m in (0,1,32766,32767,32768,65535,65536,2**32+7,2**46):
            s=select_shift(m)
            self.assertLessEqual(abs(round_shift(m,s)),32767)
    def test_float_converters(self):
        for v in (0.,-0.,1.,-2.5,0.125,63.75,2**-22,-2**-21):
            w=struct.unpack("<I",struct.pack("<f",v))[0]
            fixed=from_bits(w,64)
            self.assertEqual(fixed,round(v*(1<<20)))
            bits=to_bits(fixed)
            expected=struct.unpack("<I",struct.pack("<f",fixed/(1<<20)))[0]
            self.assertEqual(bits,expected)
        for v in (float("inf"),float("nan"),1000.):
            with self.assertRaises(ValueError):from_bits(struct.unpack("<I",struct.pack("<f",v))[0],64)
    def test_probability_converter(self):
        for q in (0,1,1<<15,1<<29,1<<30):
            expected=struct.unpack("<I",struct.pack("<f",q/(1<<30)))[0]
            self.assertEqual(to_bits(q,30),expected)
    def test_exp_lut_interpolation_accuracy(self):
        lut=[round(math.exp(-i/256)*(1<<30)) for i in range(4097)]
        error=0.
        for n in range(16001):
            x=n/1000
            delta=round(x*(1<<20))
            if delta>=16*(1<<20):approx=0
            else:
                i,r=divmod(delta,4096)
                approx=(lut[i]-(((lut[i]-lut[i+1])*r+2048)>>12))/(1<<30)
            error=max(error,abs(approx-math.exp(-x)))
        # 线性插值误差 <= h²/8；还需计入 Q20 输入舍入和 Q30 查表/插值舍入。
        # 单看插值误差会漏掉约 0.477e-6 的输入量化误差。
        bound=(1/256)**2/8 + 0.5/(1<<20) + 2/(1<<30)
        self.assertLessEqual(error,bound)
    def test_packet_crc_and_sequence(self):
        body=struct.pack("<3I",0,0xffffffff,0x12345678)
        frame=packet(77,body,True)
        self.assertEqual(frame[:2],b"\xa5\xc3")
        self.assertEqual(struct.unpack("<BHHB",frame[2:8]),(0x41,77,3,1))
        self.assertEqual(struct.unpack("<I",frame[-4:])[0],zlib.crc32(frame[2:-4]))
        for invalid in (b"",b"x",bytes(2052)):
            with self.assertRaises(ValueError):packet(0,invalid)
    def test_client_has_no_inference_dependencies(self):
        tree=ast.parse((ROOT/"host/transport.py").read_text(encoding="utf-8"))
        modules=[]
        for node in ast.walk(tree):
            if isinstance(node,ast.Import):modules.extend(a.name for a in node.names)
            elif isinstance(node,ast.ImportFrom):modules.append(node.module)
        self.assertFalse(set(modules)&{"torch","numpy","math","host.integer_reference","host.source_model"})
    def test_raw_export_and_reference_reproduce_default(self):
        r=torch.load(ROOT/"fixtures/reference.pt",weights_only=True)
        m,_,_=load_source()
        self.assertEqual(build_image(m,r["x"],r["mask"]),(ROOT/"fixtures/input.bin").read_bytes())
        b,_=reference((ROOT/"fixtures/input.bin").read_bytes())
        self.assertEqual(b,(ROOT/"artifacts/csim_output.bin").read_bytes())
    def test_masked_token_does_not_change_other_tokens(self):
        m,n,_=load_source();x,_,_=make_fixture(n,3)
        mask=torch.tensor([[[True,True,False]]])
        y=x.clone();y[:,-1]*=10
        a,_=reference(build_image(m,x,mask));b,_=reference(build_image(m,y,mask))
        # 对比前两个 query 的 context、contribution、含 bias 输出；不比改变了的 query 本身。
        for offset,width in ((0,64),(3*64,512),(3*64+3*512,512)):
            start=12+offset*4
            self.assertEqual(a[start:start+2*width*4],b[start:start+2*width*4])
    def test_t8_all_masked_row(self):
        r,_=reference((ROOT/"fixtures/t8_masks/input.bin").read_bytes())
        a=struct.unpack("<"+str((len(r)-12)//4)+"f",r[12:])
        self.assertTrue(all(v==0 for v in a[2*64:3*64]))
        self.assertTrue(all(v==0 for v in a[-64+2*8:-64+3*8]))

if __name__=="__main__":
    torch.set_num_threads(1)
    unittest.main()
