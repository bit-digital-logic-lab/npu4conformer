from pathlib import Path
import difflib,hashlib,json
r=Path(__file__).resolve().parents[2];a=r/'analysis';p=a/'wc_graph_ctrl_iterhash.sv';old=p.read_text();s=old
x=' reg [1023:0] nd_dep[0:MAX_NODES-1];';y=' reg [MAX_NODES-1:0] nd_dep[0:MAX_NODES-1];';assert s.count(x)==1;s=s.replace(x,y)
x='       nd_dep[nfetch_index]<=node_buf[16*32+:1024];';y='       nd_dep[nfetch_index]<=node_buf[16*32+:MAX_NODES];';assert s.count(x)==1;s=s.replace(x,y)
q=a/'wc_graph_ctrl_iterhash_narrowdep.sv';q.write_text(s,newline='\n')
(a/'wc_graph_ctrl_iterhash_narrowdep.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile='analysis/wc_graph_ctrl_iterhash.sv',tofile='analysis/wc_graph_ctrl_iterhash_narrowdep.sv')),newline='\n')
(a/'NARROW_DEP_NOT_APPLIED.json').write_text(json.dumps({'status':'PREPARED_ONLY_NOT_COMPILED_NOT_SELECTED','base_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(q.read_bytes()).hexdigest(),'theoretical_removed_storage_bits_for_128':(1024-128)*128,'changed_lines':2,'production_current_source_unchanged':True},indent=2)+'\n')
