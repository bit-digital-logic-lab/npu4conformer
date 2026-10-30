from pathlib import Path
import subprocess,json
p=Path(__file__).parent;c=p/'candidate'; rows=[]
args=sum((['--'+k,str(c/v)] for k,v in [('i48','epilogue_i48_to_f32.sv'),('fma','epilogue_fma_stage.sv'),('f32i16','epilogue_f32_to_i16.sv'),('relu','epilogue_relu.sv'),('lane','epilogue_lane.sv'),('fma-pipe','fp32_fma_pipe.sv')]),[])
for variant in ['negative_old','gemini','primary']:
 src=(p.parent/'gemini_epilogue/epilogue_stream_engine_v023.sv') if variant=='negative_old' else ((p.parent/'gemini_stream_round2/candidate/epilogue_stream_engine_v023.sv') if variant=='gemini' else c/'epilogue_stream_engine_v023.sv')
 for bp in ([2] if variant=='negative_old' else [0,1,2,3,4]):
  label=f'{variant}_bp{bp}'
  cmd=['python3','scripts/run_suite.py','--label',label,'--only','stream','--bp',str(bp)]+args+['--stream',str(src)]
  (p/('result_'+label+'.json')).unlink(missing_ok=True)
  with (p/(label+'.log')).open('w') as f:r=subprocess.run(cmd,cwd=p,stdout=f,stderr=subprocess.STDOUT,timeout=180)
  out=p/('result_'+label+'.json');data=json.loads(out.read_text()) if out.exists() else {}
  failed=[k for k,v in data.get('tests',{}).items() if not v.get('pass')]
  rows.append({'label':label,'rc':r.returncode,'pass':data.get('pass'),'failed':failed})
  print(rows[-1],flush=True)
(p/'regression_summary.json').write_text(json.dumps(rows,indent=2))
if any(r['rc'] != 0 or not r['pass'] for r in rows if r['label'].startswith('primary')):raise SystemExit(1)
