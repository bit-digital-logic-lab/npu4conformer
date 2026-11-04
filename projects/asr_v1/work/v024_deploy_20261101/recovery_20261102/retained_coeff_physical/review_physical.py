from pathlib import Path
import argparse,datetime as dt,hashlib,json,math,re,zipfile
import xml.etree.ElementTree as ET
D=Path(__file__).resolve().parent; N=D/"physical"; FR=N/"reports"; FB=N/"build"; NL=N/"logs"; PART="xczu15eg-ffvb1156-2-i"
def need(x,m):
 if not x: raise RuntimeError(m)
def sha(p):
 need(p.is_file(),f"missing {p}");return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding="utf-8-sig",errors="replace")
def load(p):return json.loads(read(p))
def within(p,r):return p.resolve().is_relative_to(r.resolve())
def fresh(p,s,e):need(p.is_file() and s<=p.stat().st_mtime<=e+5,f"missing/stale {p}")
def value(t,p,l):
 m=re.search(p,t,re.M);need(m,f"missing {l}");return m
def parse_bitstream_axss(data, expected_axss, expected_design=None):
 """Decode .bit metadata and packet boundaries; never search raw payload for AXSS.

 Supports unencrypted big-endian Type-1/Type-2 packet streams; unknown,
 truncated or ambiguous streams fail closed. Type-2 payloads are skipped in
 their entirety, including FDRI configuration data.
 """
 import struct
 def fail_if(condition,message):
  if condition: raise ValueError(message)
 magic=bytes.fromhex('00090ff00ff00ff00ff0000001')
 fail_if(not data.startswith(magic),'unsupported bit header magic')
 i=len(magic);meta={}
 for key in b'abcd':
  fail_if(i+3>len(data) or data[i]!=key,'invalid bit metadata tag')
  n=struct.unpack_from('>H',data,i+1)[0];i+=3
  fail_if(n<1 or i+n>len(data) or data[i+n-1]!=0,'invalid bit metadata length')
  try:meta[chr(key)]=data[i:i+n-1].decode('ascii')
  except UnicodeDecodeError as e:raise ValueError('invalid bit metadata encoding') from e
  i+=n
 fail_if(i+5>len(data) or data[i]!=ord('e'),'missing bit payload tag')
 n=struct.unpack_from('>I',data,i+1)[0];i+=5;end=i+n
 fail_if(n==0 or end!=len(data),'invalid bit payload length')
 if expected_design is not None:fail_if(meta['a'].split(';',1)[0]!=expected_design,'wrong bitstream design')
 fail_if(meta['b'].lower()!='xczu15eg-ffvb1156-2-i','wrong bitstream part')
 fail_if('Version=2025.2' not in meta['a'],'wrong Vivado version in bit header')
 sync=data.find(bytes.fromhex('aa995566'),i,min(end,i+4096));fail_if(sync<0,'configuration sync missing')
 pos=sync+4;last=None;axss=[];type2_count=0;fdri_words=0;packets=0;desync=False
 while pos<end:
  fail_if(pos+4>end,'truncated packet header');off=pos;x=struct.unpack_from('>I',data,pos)[0];pos+=4;kind=x>>29;op=(x>>27)&3
  fail_if(op==3,'reserved packet operation')
  if kind==1:
   addr=(x>>13)&0x7ff;count=x&0x7ff
   fail_if(addr>31 or (x&0x1800)!=0,'unsupported Type-1 address/reserved bits')
   fail_if(op==0 and count!=0,'invalid NOOP payload')
   last=(addr,op,count)
  elif kind==2:
   count=x&0x7ffffff;type2_count+=1
   fail_if(last is None or last[1]!=op or last[2]!=0 or op not in (1,2),'unbound Type-2 payload')
   addr=last[0];last=None
  else:raise ValueError(f'unsupported packet type at byte {off}: 0x{x:08x}')
  fail_if(pos+4*count>end,'truncated packet payload')
  if op==2 and addr==2:fdri_words+=count
  if op==2 and addr==13:
   fail_if(kind!=1 or count!=1,'unsupported AXSS write shape')
   axss.append((off,struct.unpack_from('>I',data,pos)[0]))
  if op==2 and addr==4 and count==1 and struct.unpack_from('>I',data,pos)[0]==13:desync=True
  pos+=4*count;packets+=1
 fail_if(pos!=end or not desync or fdri_words==0,'incomplete configuration packet stream')
 fail_if(len(axss)!=1 or axss[0][1]!=expected_axss,'AXSS missing, ambiguous, or not expected')
 return {'metadata':meta,'sync_offset':sync,'axss_packet_offset':axss[0][0],'axss_value':f'0x{axss[0][1]:08X}','packet_count':packets,'type2_packets':type2_count,'fdri_words_skipped':fdri_words,'payload_end':end}


a=argparse.ArgumentParser();a.add_argument("--receipt",required=True,type=Path);args=a.parse_args();rp=args.receipt.resolve();need(within(rp,FR),"receipt path");r=load(rp);plan=N/"PLAN.json";need(r.get("exit_code")==0 and r.get("status")=="PROCESS_EXITED" and r.get("plan_sha256")==sha(plan),"physical process failed or unbound");p=load(plan)
for path,digest in p["inputs"].items():need(sha(Path(path))==digest,"changed physical input "+path)
start=dt.datetime.fromisoformat(r["started"]).timestamp();end=dt.datetime.fromisoformat(r["finished"]).timestamp();need(start<end,"bad process times")
need(load(D/"reports/READY_FOR_IMPLEMENTATION.json").get("status")=="PASS","core not accepted")
import importlib.util
g=load(D/'reports/READY_FOR_IMPLEMENTATION.json');q=load(D/'reports/POST_CORE_ACCEPTANCE.json');need(q.get('status')=='PASS' and q.get('core_checkpoint_sha256')==sha(D/'build/candidate_synth.dcp'),'postcore mismatch');sp=importlib.util.spec_from_file_location('postgate',D.parent/'post_core_gate.py');mod=importlib.util.module_from_spec(sp);sp.loader.exec_module(mod);pr=Path(q['underlying_receipt']);need(sha(pr)==q['underlying_receipt_sha256'],'postcore receipt changed');z=mod.verify_postcore(pr,D,g);need(z['acceptance_sha256']==q['underlying_acceptance_sha256'],'postcore acceptance changed')
log=Path(r['vivado_log']).resolve();need(within(log,NL),'actual log outside independent implementation directory');fresh(log,start,end);t=read(log);need('Vivado v2025.2' in t and re.search(r'^INFO: \[Common 17-206\] Exiting Vivado',t,re.M) and not re.search(r'^ERROR:',t,re.M),'actual Vivado completion missing or error')
need(re.search(r'Command: open_checkpoint .*platform_synth_copy\.dcp',t,re.I) and re.search(r'Command: read_checkpoint -strict -cell .*core_i .*candidate_synth\.dcp',t,re.I),'actual platform/core linking missing')
for command in ['opt_design','place_design -directive AltSpreadLogic_high','phys_opt_design -directive AggressiveExplore','route_design -directive AlternateCLBRouting']:
 need(re.search(r'^Command: '+re.escape(command)+r'\s*$',t,re.M),f'actual command missing: {command}')
for stage in ['opt_design','place_design','phys_opt_design','route_design']:need(stage+' completed successfully' in t,f'actual stage incomplete: {stage}')
need('write_bitstream' in t and 'write_debug_probes' in t,'actual bit/LTX write missing')
def normalized_xdc(path):return sorted(line.strip() for line in read(path).splitlines() if line.strip() and not line.strip().startswith('#'))
for item in [FB/'platform_timing.xdc',FB/'restored_timing.xdc',FR/'linked_clocks.rpt',FR/'linked_exceptions_after.rpt',FR/'linked_check_timing.rpt'] :fresh(item,start,end)
original_xdc=normalized_xdc(FB/'platform_timing.xdc');need(len(original_xdc)==303 and original_xdc==normalized_xdc(FB/'restored_timing.xdc'),'complete linked-time platform constraints differ or original 303 entries missing')
for name in ['linked.dcp','optimized.dcp','placed.dcp','physopt.dcp','routed.dcp']:
 item=FB/name;fresh(item,start,end);need(re.search(r"\[Common 17-1381\] The checkpoint '[^']*/"+re.escape(name)+r"' has been generated",t,re.I),'checkpoint write missing: '+name)

files={k:FR/v for k,v in {'pass':'implementation_pass.txt','route':'route.rpt','timing':'timing_routed.rpt','check':'check_timing_routed.rpt','drc':'drc_routed.rpt','skew':'bus_skew.rpt','io':'io.rpt','clocks':'linked_clocks.rpt','util':'utilization_routed.rpt'}.items()};files.update(routed=FB/'routed.dcp',bit=FB/'candidate_A51A2492.bit',ltx=FB/'candidate_A51A2492.ltx')
for item in files.values():fresh(item,start,end)
need(re.fullmatch(r'PASS STATIC ONLY USR_ACCESS=0xA51A2492 NO_HARDWARE_TEST\s*',read(files['pass'])),'implementation pass marker mismatch')
route=read(files['route']);counts={}
for key,phrase in [('routable','routable nets'),('routed','fully routed nets'),('errors','nets with routing errors')]:counts[key]=int(value(route,r'^\s*# of '+re.escape(phrase)+r'\.+\s*:\s*(\d+)\s*:',key)[1])
need(counts['routable']>0 and counts['routable']==counts['routed'] and counts['errors']==0,'route incomplete')
timing=read(files['timing']);need('All user specified timing constraints are met.' in timing,'timing constraints not met');section=value(timing,r'(?s)\| Design Timing Summary\s*\n.*?WNS\(ns\).*?\n\s*-+[^\n]*\n\s*([^\n]+)','timing summary')[1];nums=section.split();need(len(nums)>=8,'unsupported timing summary row');wns=float(nums[0]);whs=float(nums[4]);need(math.isfinite(wns) and math.isfinite(whs) and wns>=0 and whs>=0 and int(nums[3])>0 and int(nums[7])>0,'setup/hold failed or vacuous')
need(re.search(r'^\s*sys_clk_p\s+\{[^}]+\}\s+5\.0+\s+200\.0+',timing,re.M),'200 MHz input clock missing');need(re.search(r'^\s*clk_out1\S*\s+\{[^}]+\}\s+20\.0+\s+50\.0+',timing,re.M),'50 MHz output clock missing')
check=read(files['check']);kinds=['no_clock','unconstrained_internal_endpoints','no_input_delay','no_output_delay','multiple_clock','generated_clocks','loops','latch_loops'];coverage={}
for k in kinds:
 matches=re.findall(r'checking\s+'+re.escape(k)+r'\s*\((\d+)\)',check);need(matches and all(int(v)==0 for v in matches),f'timing coverage failed/missing: {k}');coverage[k]=0
report=read(files['drc']);summary=value(report,r'(?s)1\. REPORT SUMMARY\s*\n-+\s*(.*?)\n2\. REPORT DETAILS','DRC summary')[1];found=int(value(summary,r'Checks found:\s*(\d+)','DRC count')[1]);rows=re.findall(r'^\|\s*([\w-]+)\s*\|\s*(Error|Critical Warning|Warning|Advisory|Info)\s*\|[^\n]*?\|\s*(\d+)\s*\|',summary,re.M|re.I);need(sum(int(x[2]) for x in rows)==found,'DRC summary format incomplete');need(not any(x[1].lower() in ('error','critical warning') for x in rows),'blocking DRC violation')
skew_all=read(files['skew']);skew=value(skew_all,r'(?s)1\. Bus Skew Report Summary\s*\n-+\s*(.*?)\n2\. Bus Skew Report Per Constraint','bus skew summary')[1];corner_lines=re.findall(r'^\s*(?:Slow|Fast)\s+.*$',skew,re.M);vals=re.findall(r'^\s*(?:Slow|Fast)\s+[-+]?\d+(?:\.\d+)?\s+[-+]?\d+(?:\.\d+)?\s+([-+]?\d+(?:\.\d+)?)\s*$',skew,re.M);need(corner_lines and len(vals)==len(corner_lines) and all(math.isfinite(float(x)) and float(x)>=0 for x in vals),'bus skew missing, unparsed, or negative')
io=read(files['io']);need(re.search(r'\|\s*Total User IO\s*\|\s*\n\+[-+]+\+\s*\n\|\s*2\s*\|',io),'total I/O count is not exactly 2')
for name,pin in [('sys_clk_p','AL8'),('sys_clk_n','AL7')]: need(re.search(r'^\|\s*'+pin+r'\s*\|\s*'+name+r'\s*\|[^\n]*\|\s*INPUT\s*\|\s*DIFF_SSTL12\s*\|',io,re.M),f'wrong pin/standard: {name}')
need('v024_platform_wrapper' in read(files['util']) and 'xczu15eg-ffvb1156-2-i' in read(files['util']).lower() and re.search(r'Design State\s*:\s*(?:Fully )?Routed',read(files['util'])),'routed utilization report identity/state mismatch')
with zipfile.ZipFile(files['routed']) as z:
 x=ET.fromstring(z.read('dcp.xml'));need(x.find('Part').get('Name').lower()==PART and x.find('Top').get('Name')=='v024_platform_wrapper' and x.find('OutOfContext').get('Name')=='0','routed checkpoint identity mismatch')
bit=files['bit'].read_bytes();need(len(bit)>100000,'bitstream too small');
try:bit_info=parse_bitstream_axss(bit,0xA51A2492,'v024_platform_wrapper')
except ValueError as e:raise RuntimeError(f'bitstream/AXSS parse failed: {e}') from e

ltx=load(files['ltx']);debug=[c for block in ltx['ltx_root']['ltx_data'] for c in block.get('debug_cores',[])];need(debug and all(isinstance(c,dict) and c.get('type') for c in debug),'debug probes format invalid')
need(re.search(r'^# write_bitstream -force',t,re.M) and re.search(r'^# write_debug_probes -force',t,re.M),'actual bitstream/probes write commands missing')

report={"status":"PASS","scope":"2492 full physical implementation; no board result", "receipt_sha256":sha(rp),"plan_sha256":sha(plan),"routed_checkpoint_sha256":sha(files["routed"]),"bitstream_sha256":sha(files["bit"]),"debug_probes_sha256":sha(files["ltx"]),"route_counts":counts,"setup_wns_ns":wns,"hold_whs_ns":whs,"timing_coverage":coverage,"drc_checks":found,"minimum_bus_skew_slack_ns":min(map(float,vals)),"bitstream_static_axss":bit_info,"report_sha256":{k:sha(v) for k,v in files.items()}}
out=D/"reports/PHYSICAL_REVIEW.json";need(not out.exists(),"physical review already exists");out.write_text(json.dumps(report,indent=2)+"\n");print("PHYSICAL_REVIEW_PASS NO_HARDWARE_TEST")

