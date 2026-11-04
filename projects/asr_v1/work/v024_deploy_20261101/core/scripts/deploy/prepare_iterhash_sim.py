from pathlib import Path
import json,hashlib
r=Path(__file__).resolve().parents[2];d=r/'analysis';(d/'iterhash_logs').mkdir(exist_ok=True)
base=[int(x,16) for x in (r/'sim/fixtures/mem_v024_fused.hex').read_text().split()]
o=(0xc0000+0x8000)//4
changes=[('v024_badcrc_stored',o+7,1),('v024_badcrc_header',o+3,0x200),('v024_badcrc_node',o+16+6,1)]
items=[]
for name,index,mask in changes:
 w=list(base);w[index]^=mask;p=d/('mem_'+name+'.hex');p.write_text('\n'.join(f'{x:08x}' for x in w)+'\n',newline='\n')
 items.append({'case':name,'changed_flat_word':index,'xor':mask,'rehash':False,'expected_error':4,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(d/'HASH_NEGATIVE_FIXTURES.json').write_text(json.dumps(items,indent=2)+'\n')
script=(r/'scripts/deploy/sim_core128_all.tcl').read_text()
script=script.replace('set_param general.maxThreads 2','set_param general.maxThreads 1')
script=script.replace('v024_sim128','v024_hashsim').replace('sim_project128','hashsim')
script=script.replace('if {$source ne ""} {read_verilog -sv [file join $root $source]}','if {$source eq "rtl/graph/wc_graph_ctrl.sv"} {read_verilog -sv [file join $root analysis wc_graph_ctrl_iterhash.sv]} elseif {$source ne ""} {read_verilog -sv [file join $root $source]}')
script=script.replace('set_property xsim.simulate.runtime all','add_files -fileset sim_1 [file join $root analysis tb_v024_iterhash.sv]\nset_property xsim.elaborate.debug_level off [get_filesets sim_1]\nset_property xsim.simulate.runtime all')
script=script.replace(' tb_v024_unified ', ' tb_v024_iterhash ')
needle=' {v024_bound128 tb_v024_iterhash'
insert='\n'.join(' {'+name+' tb_v024_iterhash ../../analysis/mem_'+name+'.hex {watchdog=100000 mode=3 expect_error=4}}' for name,_,_ in changes)+'\n'
script=script.replace(needle,insert+needle)
script=script.replace('$root/logs/', '$root/analysis/iterhash_logs/').replace('$root logs ${name}.log','$root analysis iterhash_logs ${name}.log')
script=script.replace('MAX_NODES=128 REAL_FMA_IP=1','MAX_NODES=128 REAL_FMA_IP=1 HASH=ITERATIVE_CANDIDATE')
(r/'scripts/deploy/sim_iterhash_all.tcl').write_text(script,newline='\n')
