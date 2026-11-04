from pathlib import Path
import difflib,hashlib,json
r=Path(__file__).resolve().parents[2];out=r/'analysis';out.mkdir(exist_ok=True)
p=r/'rtl/graph/wc_graph_ctrl.sv';old=p.read_text();s=old
s=s.replace('  SCAN=7,DISPATCH=8,FINISH=9;', '  SCAN=7,DISPATCH=8,FINISH=9,HHASH=10,NHASH=11;')
s=s.replace(' reg [31:0] hash;',' reg [31:0] hash;\n // One word per cycle; buffers remain stable until their hash completes.\n reg [5:0] hash_word;')
a=s.index(' function [31:0] hash_header(');b=s.index(' // Explicit fusion descriptor gate.',a)
s=s[:a]+''' // The same FNV-1a recurrence, shared by header and node hashing.
 // Header word 7 stores the expected whole-plan checksum and is excluded.
 wire [31:0] hash_data = (state==HHASH) ?
  header[hash_word*32+:32] : node_buf[hash_word*32+:32];
 wire [31:0] hash_next = fnv(hash,hash_data);
'''+s[b:]
s=s.replace('payload_type<=0;hash<=HASH_SEED;','payload_type<=0;hash<=HASH_SEED;hash_word<=0;')
s=s.replace('     hash<=HASH_SEED;gen_latched<=generation;irq<=0;','     hash<=HASH_SEED;hash_word<=0;gen_latched<=generation;irq<=0;')
needle='''       node_count<=header[95:64];hash<=hash_header(header);nfetch_index<=0;
       ngot<=0;nbad<=0;state<=NREQ;'''
assert needle in s
s=s.replace(needle,'''       node_count<=header[95:64];hash<=HASH_SEED;hash_word<=0;nfetch_index<=0;
       ngot<=0;nbad<=0;state<=HHASH;''')
needle='''    NREQ:if(fetch_req_ready)begin ngot<=0;nbad<=0;state<=NFETCH;end'''
assert s.count(needle)==1
s=s.replace(needle,'''    HHASH:begin
     if(fault_latched||!parameter_ready||generation!=gen_latched)state<=FINISH;
     else begin
      if(hash_word!=6'd7)hash<=hash_next;
      if(hash_word==6'd15)begin hash_word<=0;state<=NREQ;end
      else hash_word<=hash_word+1'b1;
     end
    end
'''+needle)
a=s.index('       hash<=hash_node(hash,node_buf);');b=s.index('\n      end\n     end\n    end\n    SCAN:begin',a)
oldfinish=s[a:b]
assert 'hash_node(hash,node_buf)!=header[255:224]' in oldfinish
s=s[:a]+'''       hash_word<=0;state<=NHASH;'''+s[b:]
needle='''    SCAN:begin'''
assert s.count(needle)==1
s=s.replace(needle,'''    NHASH:begin
     if(fault_latched||!parameter_ready||generation!=gen_latched)state<=FINISH;
     else begin
      hash<=hash_next;
      if(hash_word==6'd47)begin
       if(nfetch_index+1==header[95:64])begin
        if(hash_next!=header[255:224])begin set_fault(8'h04);state<=FINISH;end
        else begin nfetch_index<=0;scan_idx<=0;state<=SCAN;end
       end else begin nfetch_index<=nfetch_index+1;state<=NREQ;end
      end else hash_word<=hash_word+1'b1;
     end
    end
'''+needle)
assert 'hash_node(' not in s and 'hash_header(' not in s
candidate=out/'wc_graph_ctrl_iterhash.sv';candidate.write_text(s,newline='\n')
(out/'wc_graph_ctrl_iterhash.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile='rtl/graph/wc_graph_ctrl.sv',tofile='analysis/wc_graph_ctrl_iterhash.sv')),newline='\n')
meta={'status':'CANDIDATE_NOT_APPLIED','base_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(candidate.read_bytes()).hexdigest(),'state_changes':['HHASH=10:16 cycles, skip word7','NHASH=11:48 cycles, all 48 words included'],'known_latency_addition':'16 + 48*node_count hashing states; seven nodes 352 states; total runtime changes with AXI stalls','unchanged':['DMA firstcapture in HFETCH/NFETCH','header/node prior validation','complete FNV checksum and final compare before SCAN','existing production RTL and current OOC process']}
(out/'ITERHASH_MANIFEST.json').write_text(json.dumps(meta,indent=2)+'\n')
print('CANDIDATE_PREPARED',meta['candidate_sha256'])
