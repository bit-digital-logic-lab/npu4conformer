from pathlib import Path
import sys, struct, json, hashlib
r=Path(__file__).resolve().parents[2];sys.path.insert(0,str(r/'scripts/sim'));import graph_common as G
orig=[int(x,16) for x in (r/'sim/fixtures/mem_v024_fused.hex').read_text().split()]
P=0x10008000; off=(0xc0000+0x8000)//4
checks=[]
for name,n,dep in [('v024_bound128',128,False),('v024_over129',129,False),('v024_baddep128',2,True)]:
 nodes=[G.node(G.T_IN,i,(1<<128) if dep and i==1 else 0,base=0x10001000,count=512,flags=G.FLAG_ROOT|G.FLAG_EXTERNAL,input_base=0x10001000,input_bytes=2048,output_base=0x10001000,output_bytes=2048,version=1,epoch=1) for i in range(n)]
 blob,hw=G.emit(P,nodes,0x10040000)
 assert G.check_hash(blob)
 mem=list(orig);words=struct.unpack('<'+str(len(blob)//4)+'I',blob);mem[off:off+len(words)]=words
 path=r/'sim/fixtures'/('mem_'+name+'.hex');path.write_text('\n'.join(f'{w:08x}' for w in mem)+'\n',newline='\n')
 checks.append({'case':name,'node_count':n,'expected_error':0 if name.endswith('bound128') else 4,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(r/'reports/boundary_fixture_manifest.json').write_text(json.dumps(checks,indent=2)+'\n')
print('GENERATED_BOUNDARY_FIXTURES',len(checks))
