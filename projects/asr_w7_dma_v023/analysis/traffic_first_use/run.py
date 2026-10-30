from pathlib import Path
import sys,subprocess,csv,json,hashlib
ROOT=Path('/home/yang/Desktop/项目');OUT=Path(__file__).resolve().parent
SKILL=Path('/home/yang/.codex/skills/traffic-ledger/scripts');sys.path.insert(0,str(SKILL))
from analyze import analyze,render
from ledger import Ledger
B=ROOT/'tasks/ds_ddr/bench';C=ROOT/'tasks/ds_ddr/candidate/axi_dma_v020_multi.sv';BASE=ROOT/'work/rtl/axi_dma_v019.sv'
mon=OUT/'monitor.sv'
mon.write_text('''module ledger_monitor;
 integer fd,c=0;
 initial begin fd=$fopen("signals.csv","w");$fdisplay(fd,"cycle,reqr,reqw,doner,donew,ar,arlen,rv,rr,rl,aw,awlen,wv,wr,ws,b");end
 always @(posedge tb_dma_compare.clk) if(tb_dma_compare.rst_n)begin
 $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",c,
 tb_dma_compare.rd_req_valid&&tb_dma_compare.rd_req_ready,tb_dma_compare.wr_req_valid&&tb_dma_compare.wr_req_ready,
 tb_dma_compare.rd_done,tb_dma_compare.wr_done,tb_dma_compare.ar0_valid&&tb_dma_compare.ar0_ready,tb_dma_compare.ar0_len,
 tb_dma_compare.r0_valid,tb_dma_compare.r0_ready,tb_dma_compare.r0_last,
 tb_dma_compare.aw1_valid&&tb_dma_compare.aw1_ready,tb_dma_compare.aw1_len,
 tb_dma_compare.w1_valid,tb_dma_compare.w1_ready,tb_dma_compare.w1_strb,tb_dma_compare.b1_valid&&tb_dma_compare.b1_ready);
 c=c+1;$fflush(fd);
 end
 endmodule
''')
results=[]
for tag,source in [('before',BASE),('after',C)]:
 d=OUT/tag;d.mkdir(exist_ok=True)
 cmd=['iverilog','-g2012','-s','tb_dma_compare','-s','ledger_monitor','-DLATMIN=32','-DLATMAX=32','-DBP=0','-DSEED=7','-DMAXOUT=8']
 if tag=='after':cmd+=['-DCAND']
 cmd+=['-o',str(d/'sim.vvp'),str(B/'tb_dma_compare.sv'),str(B/'bfm/axi128_ddr_bfm.sv'),str(source),str(mon)]
 cp=subprocess.run(cmd,capture_output=True,text=True);(d/'compile.log').write_text(cp.stdout+cp.stderr);assert cp.returncode==0,cp.stderr
 run=['vvp',str(d/'sim.vvp'),'+mode=2','+beats=256']
 cp=subprocess.run(run,cwd=d,capture_output=True,text=True);(d/'run.log').write_text(cp.stdout+cp.stderr);assert cp.returncode==0 and 'pass=1' in cp.stdout,cp.stdout
 (d/'commands.json').write_text(json.dumps([cmd,run]))
 raw=[]
 for row in csv.DictReader((d/'signals.csv').open()):
  for field,gate in [('arlen',row['ar']=='1'),('awlen',row['aw']=='1'),('ws',row['wv']=='1' and row['wr']=='1')]:
   if 'x' in row[field].lower():
    assert not gate, 'unknown active payload'
    row[field]='0'
  raw.append({k:int(v) for k,v in row.items()})
 start=min(x['cycle'] for x in raw if x['reqr'] or x['reqw']);end=max(x['cycle'] for x in raw if x['doner'] or x['donew'])+1
 samples=[x for x in raw if start<=x['cycle']<end]
 meta=dict(scope='actual AXI handshakes of RTL DMA BFM microbenchmark, 256 beats each direction; not full model; no matrix IDs inferred',resources={n:dict(unit='cycle',clock_hz=100000000,start=start,end=end,capacity_bytes_per_tick=16,evidence='RTL_handshake_100MHz_simclock_not_achieved_Fmax') for n in ['axi_r','axi_w']})
 pending_r=pending_w=0;active_r=active_w=False;intervals=[];bytes_r=bytes_w=wire_w=0
 with Ledger(d/'trace.jsonl',meta) as log:
  for x in samples:
   t=x['cycle'];active_r=active_r or bool(x['reqr']);active_w=active_w or bool(x['reqw'])
   for n in ['axi_r','axi_w']:
    read=n=='axi_r';v=x['rv'] if read else x['wv'];ready=x['rr'] if read else x['wr'];pending=pending_r if read else pending_w;active=active_r if read else active_w
    fire=v and ready
    state='payload' if fire else 'backpressure' if v and not ready else 'wait_memory' if read and pending>0 else 'starved_producer' if not read and pending>0 else 'dispatch_or_drain' if active else 'idle_no_request'
    valid=16 if read and fire else x['ws'].bit_count() if fire else 0;wire=16 if fire else 0
    e=dict(resource=n,start=t,end=t+1,state=state,bytes=valid,wire_bytes=wire,transfer_id='operand_read' if read else 'result_write',reason=state,blocked_by='memory_model' if state=='wait_memory' else 'upstream_pack_or_dma' if state=='starved_producer' else '',evidence='sampled at RTL posedge; pending accepted beat accounting')
    intervals.append(e)
    if read:bytes_r+=valid
    else:bytes_w+=valid;wire_w+=wire
   pending_r+=x['ar']*(x['arlen']+1)-int(bool(x['rv'] and x['rr']))
   pending_w+=x['aw']*(x['awlen']+1)-int(bool(x['wv'] and x['wr']))
   assert pending_r>=0 and pending_w>=0
   if x['doner']:active_r=False
   if x['donew']:active_w=False
  assert bytes_r==4096 and bytes_w==4096 and pending_r==0 and pending_w==0
  # 仅合并相同归因与同一传输的连续拍；总字节精确保留。
  compressed=[]
  for n in ['axi_r','axi_w']:
   for e in [i for i in intervals if i['resource']==n]:
    if compressed and all(compressed[-1].get(k)==e.get(k) for k in ['resource','state','reason','transfer_id','blocked_by','evidence']) and compressed[-1]['end']==e['start']:
     compressed[-1]['end']=e['end'];compressed[-1]['bytes']+=e['bytes'];compressed[-1]['wire_bytes']+=e['wire_bytes']
    else:compressed.append(dict(e))
  for e in compressed:log.interval(**e)
  for n,tensor,src,dst,count,wire in [('axi_r','BFM_operand','DDR_model','DMA_read_sink',bytes_r,bytes_r),('axi_w','BFM_result','DMA_write_source','DDR_model',bytes_w,wire_w)]:
   log.transfer(id='operand_read' if n=='axi_r' else 'result_write',resource=n,start=start,end=end,tensor=tensor,version='fixture_seed7',format='raw128_fixture',src=src,dst=dst,op='dma_microbench',phase='stream',reason='test_fixture_transfer_not_model_tensor',logical_offset=0,logical_bytes=count,valid_bytes=count,bus_bytes=wire)
 events=[json.loads(l) for l in (d/'trace.jsonl').read_text().splitlines()];s,tx,ints=analyze(events);render(d/'report',s,tx,ints)
 assert all(x['ledger_minus_interval_valid_bytes']==0 and x['known_coverage']==1 for x in s['resources'])
 results.append(dict(tag=tag,window=end-start,read_bytes=bytes_r,write_bytes=bytes_w,resources=s['resources'],source_sha256=hashlib.sha256(source.read_bytes()).hexdigest()))
(OUT/'result.json').write_text(json.dumps(results,indent=2))
for r in results:print(r['tag'],r['window'],[(x['resource'],x['payload_fraction'],x['states']) for x in r['resources']])
