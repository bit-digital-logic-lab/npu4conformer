from pathlib import Path
import json,re,hashlib
r=Path(__file__).resolve().parents[2];l=r/'logs'
a=(l/'v024_fused_out.hex').read_bytes();b=(l/'v024_reference1024_out.hex').read_bytes()
assert len(a.split())==len(b.split())==8192
assert a==b
ca=int(re.search(r'V024_END .*cycles=(\d+)',(l/'v024_fused.log').read_text())[1]);cb=int(re.search(r'V024_END .*cycles=(\d+)',(l/'v024_reference1024.log').read_text())[1]);assert ca==cb
fma=(l/'vendor_fma.log').read_text();assert 'VENDOR_FMA_PASS sent=64 seen=64 mismatch=0 latency=12' in fma
out={'status':'PASS','fma_vendor_vectors':64,'fma_bit_mismatches':0,'fma_latency_cycles':12,'same_xsim_fused_1024_vs_128':{'output_words':8192,'bit_exact':True,'sha256':hashlib.sha256(a).hexdigest(),'cycles_128':ca,'cycles_1024':cb},'timing_scope':'Both runs use XSim, same BFM/testbench. Historical Icarus result is a separate simulator run.'}
(r/'reports/SUPPLEMENTARY_CHECKS.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
