from pathlib import Path
import struct
r=Path(__file__).resolve().parents[2]
w=[int(x,16) for x in (r/'sim/fixtures/lane_vectors.hex').read_text().split()]
for i in range(0,len(w),3):
 signed=w[i]-(1<<32) if w[i]&(1<<31) else w[i]
 w[i]=struct.unpack('<I',struct.pack('<f',float(signed)))[0]
(r/'sim/fixtures/vendor_fma_vectors.hex').write_text('\n'.join(f'{x:08x}' for x in w)+'\n',newline='\n')
