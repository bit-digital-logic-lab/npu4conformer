"""Independently review one completed partitioned implementation; no EDA/hardware.

Usage: python -I review_partitioned_physical.py <implement_*_process.json>
Writes PHYSICAL_IMPLEMENTATION_REVIEW.json then BOARD_READY.json only on full pass.
"""
from pathlib import Path
import argparse, datetime as dt, hashlib, json, math, re, zipfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent; OUT=ROOT/'partitioned_shared16'; SHARED=ROOT/'shared16_candidate'; P=OUT/'reports'; H=OUT/'hardware'; B=OUT/'build'
PART='xczu15eg-ffvb1156-2-i'; USER='0xA51A2491'
def need(test,msg):
 if not test: raise RuntimeError(msg)
def sha(path):
 need(path.is_file(),f'missing file: {path}'); return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def read(path): return path.read_text(encoding='utf-8-sig',errors='replace')
def within(path,root): return path.resolve().is_relative_to(root.resolve())
def fresh(path,start,end):
 need(path.is_file(),f'missing: {path}');need(start<=path.stat().st_mtime<=end+5,f'stale or wrong-run file: {path}')
def value(text,pattern,label):
 m=re.search(pattern,text,re.M);need(m,f'unsupported or missing {label}');return m

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

ap=argparse.ArgumentParser();ap.add_argument('--initial-receipt',type=Path,required=True);ap.add_argument('--resume-receipt',type=Path,required=True);ap.add_argument('--resume-plan',type=Path,required=True);a=ap.parse_args()
ip=a.initial_receipt.resolve();rp=a.resume_receipt.resolve();resume_plan_path=a.resume_plan.resolve();need(ip!=rp and within(ip,P) and within(rp,P) and resume_plan_path==(OUT/'resume_placement_v1/RESUME_PLAN.json').resolve(),'receipts/plan must be distinct and local');initial=load(ip);r=load(rp);resume_plan=load(resume_plan_path)
need(re.fullmatch(r'implement_\d{8}_\d{6}_process\.json',ip.name) and initial.get('stage')=='implement' and initial.get('status')=='PROCESS_EXITED' and type(initial.get('exit_code')) is int and initial['exit_code']==1,'initial process must retain actual exit1')
need(r.get('stage')=='resume_place' and r.get('status')=='PROCESS_EXITED' and type(r.get('exit_code')) is int and r['exit_code']==0,'resume process did not actually exit0')
is_=dt.datetime.fromisoformat(initial['started']).timestamp();ie=dt.datetime.fromisoformat(initial['finished']).timestamp();start=dt.datetime.fromisoformat(r['started']).timestamp();end=dt.datetime.fromisoformat(r['finished']).timestamp();need(is_<ie<=start<end,'two-stage receipt times inconsistent')

manifest=SHARED/'reports/SOURCE_MANIFEST.json';functional=SHARED/'reports/ROOT_FUNCTIONAL_ACCEPTANCE.json';shared_results=SHARED/'reports/SHARED16_RESULTS.json';leaf=P/'LEAF_ACCEPTANCE.json';ready=P/'READY_FOR_IMPLEMENTATION.json';iplan=P/'IMPLEMENTATION_PLAN.json';pp=P/'PARTITION_PLAN.json';hardware_plan=H/'HARDWARE_PLAN.json';m=load(manifest);f=load(functional);lg=load(leaf);sg=load(ready);plan=load(iplan);hp=load(hardware_plan)
need(f.get('status')=='PASS' and f.get('source_manifest_sha256')==sha(manifest) and f.get('acceptance_sha256')==sha(shared_results),'functional/source evidence mismatch');need(lg.get('status')=='PASS' and lg.get('partition_plan_sha256')==sha(pp) and lg.get('array_checkpoint_sha256')==sha(B/'array16_ooc_clockless.dcp'),'leaf evidence mismatch');need(sg.get('status')=='PASS' and sg.get('source_manifest_sha256')==sha(manifest) and sg.get('leaf_acceptance_sha256')==sha(leaf) and sg.get('leaf_checkpoint_sha256')==sha(B/'array16_ooc_clockless.dcp') and sg.get('partition_plan_sha256')==sha(pp),'partition synthesis gate mismatch')
need(initial.get('source_manifest_sha256')==sha(manifest) and initial.get('script_sha256')==sha(OUT/'implement.tcl') and r.get('source_manifest_sha256')==sha(manifest),'implementation receipt inputs mismatch');need(plan.get('part')==PART and plan.get('usr_access')==USER and plan.get('source_manifest_sha256')==sha(manifest) and plan.get('partition_plan_sha256')==sha(pp),'implementation plan mismatch');need(plan.get('script_sha256')==sha(OUT/'implement.tcl')==sg.get('implementation_script_sha256'),'implementation script differs');need(plan.get('platform_sha256')==sha(B/'platform_synth_copy.dcp')==sg.get('platform_checkpoint_sha256'),'platform checkpoint differs');need(sg.get('core_checkpoint_sha256')==sha(B/'candidate_synth.dcp'),'core checkpoint differs')
for rel,digest in m['frozen_files'].items():
 path=(SHARED/rel).resolve();need(within(path,SHARED) and sha(path)==digest,f'functional frozen input changed: {rel}')
core=SHARED/'core/rtl/matrix'; leafrtl=OUT/'rtl'
for n in ['array16_w7_c48_cfg.sv','pe_w7_c48_cfg.sv']:need(sha(core/n)==sha(leafrtl/n),'array/PE source mismatch')
need(f.get('original_pe_array_source_hashes_unchanged') is True and sg.get('array_count')==1 and sg.get('pe_count')==256 and sg.get('blackboxes')==0,'array/PE evidence incomplete')
need(hp.get('status')=='PREPARED_NOT_BOARD_READY' and hp.get('usr_access')==USER and hp.get('cable_serial')=='210512180081' and hp.get('device_part')=='xczu15','hardware plan differs');need(hp.get('program_tcl_sha256')==sha(H/'program_partitioned_and_verify.tcl') and hp.get('runner_sha256')==sha(H/'run_partitioned.py'),'hardware scripts changed')
for path,digest in hp['pinned_inputs'].items(): need(sha(Path(path))==digest,f'hardware reference changed: {path}')
# Independently validate first-stage post-core gate bound by the real failed receipt.
import importlib.util
post_gate=ROOT/'post_core_gate.py';need(initial.get('post_core_gate_script_sha256')==sha(post_gate),'first-stage post-core gate script mismatch')
post_receipts=[q for q in P.glob('postcore_*/PROCESS_RECEIPT.json') if sha(q)==initial.get('post_core_receipt_sha256')];need(len(post_receipts)==1,'expected exactly one first-stage post-core receipt')
spec=importlib.util.spec_from_file_location('post_gate',post_gate);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);post=module.verify_postcore(post_receipts[0],OUT,sg);need(post['acceptance_sha256']==initial.get('post_core_acceptance_sha256'),'first-stage post-core review mismatch')
initial_log=Path(initial['vivado_log']).resolve();need(within(initial_log,OUT/'logs'),'initial log outside candidate');fresh(initial_log,is_,ie);it=read(initial_log)
errors=re.findall(r'^ERROR:.*$',it,re.M);need(len(errors)==1 and re.search(r'\[Vivado_Tcl 4-2310\].*-subdirective.*not supported',errors[0]),'initial process failed for reason other than expected unsupported subdirective')
need('opt_design completed successfully' in it and re.search(r'^# place_design -subdirective',it,re.M) and 'place_design completed successfully' not in it,'first-stage optimization/placement boundary not proven')
initial_files=[B/'linked.dcp',B/'optimized.dcp',B/'platform_timing.xdc',B/'restored_timing.xdc',P/'linked_clocks.rpt',P/'platform_clocks_before.rpt',P/'platform_exceptions_before.rpt',P/'linked_exceptions_after.rpt',P/'linked_check_timing.rpt']
for item in initial_files:fresh(item,is_,ie)
for name in ['linked.dcp','optimized.dcp']:
 need(re.search(r"\[Common 17-1381\] The checkpoint '[^']*/"+re.escape(name)+r"' has been generated",it,re.I),'first-stage checkpoint write missing: '+name)
def normalized_xdc(path):return sorted(line.strip() for line in read(path).splitlines() if line.strip() and not line.strip().startswith('#'))
original_xdc=normalized_xdc(B/'platform_timing.xdc');need(original_xdc and original_xdc==normalized_xdc(B/'restored_timing.xdc'),'first-stage full timing constraints differ')
need(Path(resume_plan.get('prefix_receipt','')).resolve()==ip and resume_plan.get('prefix_receipt_sha256')==sha(ip) and resume_plan.get('prefix_log_sha256')==sha(initial_log) and resume_plan.get('source_manifest_sha256')==sha(manifest) and resume_plan.get('optimized_checkpoint_sha256')==sha(B/'optimized.dcp'),'resume plan does not bind actual failed stage, sources and optimized DCP')
for name,digest in resume_plan['inputs'].items():need(sha(Path(name))==digest,f'resume plan input changed: {name}')
resume_script=Path(resume_plan['script']).resolve();need(within(resume_script,OUT) and resume_plan.get('script_sha256')==sha(resume_script),'resume script/plan mismatch')
need(Path(r.get('prefix_receipt','')).resolve()==ip and r.get('prefix_receipt_sha256')==sha(ip) and r.get('optimized_checkpoint_sha256')==sha(B/'optimized.dcp') and r.get('resume_plan_sha256')==sha(resume_plan_path) and r.get('script_sha256')==sha(resume_script),'resume receipt does not bind first stage, script and plan')
log=Path(r['vivado_log']).resolve();need(within(log,OUT/'logs'),'resume log outside candidate');fresh(log,start,end);t=read(log);need('Vivado v2025.2' in t and re.search(r'^INFO: \[Common 17-206\] Exiting Vivado',t,re.M),'Vivado resume completion missing');need(not re.search(r'^ERROR:',t,re.M),'resume log has ERROR')
need(re.search(r'Command: open_checkpoint .*optimized\.dcp',t,re.I),'resume log does not open optimized DCP');placement=resume_plan.get('placement_command');need(isinstance(placement,str) and re.fullmatch(r'place_design -directive [A-Za-z0-9_]+',placement) and re.search(r'^Command: '+re.escape(placement)+r'\s*$',t,re.M),'unsupported/unproven placement command');need(placement=='place_design -directive AltSpreadLogic_high' and resume_plan.get('physical_optimization_command')=='phys_opt_design -directive AggressiveExplore' and resume_plan.get('routing_command')=='route_design -directive AlternateCLBRouting','unexpected implementation directives');need(re.search(r'^Command: phys_opt_design -directive AggressiveExplore\s*$',t,re.M) and re.search(r'^Command: route_design -directive AlternateCLBRouting\s*$',t,re.M),'resume phys-opt/route directives missing');need('place_design completed successfully' in t and 'phys_opt_design completed successfully' in t and 'route_design completed successfully' in t,'implementation stage completion missing');need('write_bitstream' in t and 'write_debug_probes' in t,'bit/LTX writes missing')
resume_xdc=P/'resume_timing.xdc';fresh(resume_xdc,start,end);fresh(P/'resume_clocks.rpt',start,end);fresh(P/'resume_exceptions.rpt',start,end);need(normalized_xdc(resume_xdc)==original_xdc,'resumed full timing constraints differ')
resume_clocks=read(P/'resume_clocks.rpt');need(re.search(r'^sys_clk_p\s+5\.0+\s+\{',resume_clocks,re.M) and re.search(r'^clk_out1\S*\s+20\.0+\s+\{',resume_clocks,re.M) and not re.search(r'^\S*core_clk\s',resume_clocks,re.M),'resume clock report mismatch')
need(re.search(r'^RESUME_OPTIMIZED_PLATFORM_CLOCKS_ACCEPTED\s*$',t,re.M),'resume clock/XDC acceptance marker absent')
for name in ['placed.dcp','physopt.dcp','routed.dcp']:
 item=B/name;fresh(item,start,end);need(re.search(r"\[Common 17-1381\] The checkpoint '[^']*/"+re.escape(name)+r"' has been generated",t,re.I),'resume checkpoint write missing: '+name)

files={k:P/v for k,v in {'pass':'implementation_pass.txt','route':'route.rpt','timing':'timing_routed.rpt','check':'check_timing_routed.rpt','drc':'drc_routed.rpt','skew':'bus_skew.rpt','io':'io.rpt','clocks':'linked_clocks.rpt','util':'utilization_routed.rpt'}.items()};files.update(routed=B/'routed.dcp',bit=B/'candidate_A51A2491.bit',ltx=B/'candidate_A51A2491.ltx')
for key,item in files.items():fresh(item,is_,ie) if key=='clocks' else fresh(item,start,end)
need(re.fullmatch(r'PASS STATIC ONLY USR_ACCESS=0xA51A2491 NO_HARDWARE_TEST\s*',read(files['pass'])),'implementation pass marker mismatch')
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
try:bit_info=parse_bitstream_axss(bit,0xA51A2491,'v024_platform_wrapper')
except ValueError as e:raise RuntimeError(f'bitstream/AXSS parse failed: {e}') from e

ltx=load(files['ltx']);debug=[c for block in ltx['ltx_root']['ltx_data'] for c in block.get('debug_cores',[])];need(debug and all(isinstance(c,dict) and c.get('type') for c in debug),'debug probes format invalid')
need(re.search(r'^# write_bitstream -force',t,re.M) and re.search(r'^# write_debug_probes -force',t,re.M),'actual bitstream/probes write commands missing')
review={'status':'PASS','scope':'two-stage resumed partitioned physical implementation only; no hardware test','part':PART,'usr_access':USER,'synthesis_gate_sha256':sha(ready),'implementation_receipt_sha256':sha(rp),'implementation_log_sha256':sha(log),'initial_receipt_sha256':sha(ip),'initial_log_sha256':sha(initial_log),'initial_exit_code':1,'resume_exit_code':0,'resume_plan_sha256':sha(resume_plan_path),'resume_script_sha256':sha(resume_script),'linked_checkpoint_sha256':sha(B/'linked.dcp'),'optimized_checkpoint_sha256':sha(B/'optimized.dcp'),'platform_timing_sha256':sha(B/'platform_timing.xdc'),'restored_timing_sha256':sha(B/'restored_timing.xdc'),'resume_timing_sha256':sha(resume_xdc),'post_core_acceptance_sha256':post['acceptance_sha256'],'routed_checkpoint_sha256':sha(files['routed']),'bitstream_sha256':sha(files['bit']),'debug_probes_sha256':sha(files['ltx']),'source_manifest_sha256':sha(manifest),'route_counts':counts,'setup_wns_ns':wns,'hold_whs_ns':whs,'timing_coverage':coverage,'drc_checks':found,'bus_skew_entries':len(vals),'minimum_bus_skew_slack_ns':min(map(float,vals)),'bitstream_static_axss':bit_info,'board_usr_access_readback_required':True,'report_sha256':{k:sha(v) for k,v in files.items() if k not in ('bit','ltx','routed')}}
review_path=P/'PHYSICAL_IMPLEMENTATION_REVIEW.json';board=H/'BOARD_READY.json';need(not review_path.exists() and not board.exists(),'existing review/gate must be preserved');review_path.write_text(json.dumps(review,indent=2)+'\n',encoding='utf-8')
gate={'status':'PASS','scope':'PARTITIONED_SHARED16_SEVEN_NODE','part':PART,'device_part':'xczu15','cable_serial':'210512180081','usr_access':USER,'blackbox_count':0,'route_complete':True,'setup_met':True,'hold_met':True,'drc_pass':True,'clock_coverage_pass':True,'bus_skew_pass':True,'io_pass':True,'original_pe_array_sources_unchanged':True,'candidate_functional_review_pass':True,'hardware_plan_sha256':sha(hardware_plan),'source_manifest_sha256':sha(manifest),'functional_acceptance_sha256':sha(functional),'leaf_acceptance_sha256':sha(leaf),'synthesis_gate_sha256':sha(ready),'physical_review_sha256':sha(review_path),'implementation_plan_sha256':sha(iplan),'bitstream_sha256':sha(files['bit']),'debug_probes_sha256':sha(files['ltx'])};board.write_text(json.dumps(gate,indent=2)+'\n',encoding='utf-8');print('PHYSICAL_REVIEW_AND_BOARD_READY_PASS no hardware accessed')
