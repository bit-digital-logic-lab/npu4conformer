from pathlib import Path
import struct,hashlib,json
r=Path(__file__).resolve().parents[2];out=r/'inputs';out.mkdir(exist_ok=True)
w=[int(x,16) for x in (r/'sim/fixtures/mem_v024_fused.hex').read_text().split()]
assert len(w)==262144
flat=struct.pack('<262144I',*w)
meta={'scope':'V024 fused seven-node graph only; address mapping from wc_safety_bfm','regions':[]}
for name,logical,offset,size in [('arena64k',0x04000000,0x40000,65536),('param64k',0x10000000,0xc0000,65536),('pc64',0x10003000,0xc3000,256)]:
 b=flat[offset:offset+size];p=out/('fused_'+name+'.bin');p.write_bytes(b)
 mem=out/('fused_'+name+'_128.mem');mem.write_text('\n'.join(f'{int.from_bytes(b[i:i+16],"little"):032x}' for i in range(0,len(b),16))+'\n',newline='\n')
 meta['regions'].append({'logical_address':f'0x{logical:08x}','bfm_flat_byte_offset':f'0x{offset:x}','size':size,'binary':str(p.relative_to(r)),'sha256':hashlib.sha256(b).hexdigest(),'ram128_init':str(mem.relative_to(r)),'endianness':'AXI byte lane 0 at lowest logical address; 128-bit mem word written MSB-first hex'})
(out/'MEMORY_MAP.json').write_text(json.dumps(meta,indent=2)+'\n')
print('PACKED_FUSED_INPUTS',len(meta['regions']))
