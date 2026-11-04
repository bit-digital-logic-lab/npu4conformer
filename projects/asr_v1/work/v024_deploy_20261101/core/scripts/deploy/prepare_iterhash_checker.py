from pathlib import Path
r=Path(__file__).resolve().parents[2]
s=(r/'scripts/deploy/check_core128_strict.py').read_text()
s=s.replace("L=R/'logs'","L=R/'analysis/iterhash_logs'")
s=s.replace("'v024_baddep128','base_normal'", "'v024_baddep128','v024_badcrc_stored','v024_badcrc_header','v024_badcrc_node','base_normal'")
a=s.index('p=subprocess.run(');b=s.index("report={'status':'PASS'",a)
s=s[:a]+'''import importlib.util
spec=importlib.util.spec_from_file_location('original_judge',R/'scripts/analysis/check_export.py')
judge=importlib.util.module_from_spec(spec);spec.loader.exec_module(judge);judge.LOG=L
need(judge.main()==0,'Independent numerical judge failed')
need(words(L/'v024_fused_out.hex',8192)==words(R/'logs/v024_fused_out.hex',8192),'Candidate fused differs from original 128-node result')
for name in ['v024_fused','v024_bound128']:
 log=(L/(name+'.log')).read_text()
 m=re.search(r'ITERHASH_FINAL computed=([0-9a-f]+) expected=([0-9a-f]+) header_steps=(\\d+) node_steps=(\\d+)',log)
 need(m is not None and m[1]==m[2],name+': hash mismatch')
 need(int(m[3])==16,name+': header traversal count wrong')
 need(int(m[4])==(7 if name=='v024_fused' else 128)*48,name+': node traversal count wrong')
for name in ['v024_badcrc_stored','v024_badcrc_header','v024_badcrc_node']:
 log=(L/(name+'.log')).read_text()
 m=re.search(r'ITERHASH_FINAL computed=([0-9a-f]+) expected=([0-9a-f]+)',log)
 need(m is not None and m[1]!=m[2],name+': mutation not rejected by final checksum')
 need('completed=0' in log and 'V024_END done=1 fault=1 error=04' in log,name+': checksum rejection wrong terminal state')
''' + s[b:]
s=s.replace('MAX_NODES=128 real vendor FMA IP XSim; original eleven and three boundary cases; no board claim','ITERATIVE HASH CANDIDATE, MAX_NODES=128, real vendor FMA IP XSim; original11+boundary3+checksum3; no synthesis or board claim')
s=s.replace("(R/'reports/REGRESSION128_STRICT.json')","(R/'analysis/REGRESSION_ITERHASH.json')")
s=s.replace("print('V024_CORE128_REGRESSION_STRICT_PASS'","print('V024_ITERHASH_REGRESSION_STRICT_PASS'")
s=s.replace("report={'status':'PASS',", "report={'status':'PASS','candidate_sha256':hashlib.sha256((R/'analysis/wc_graph_ctrl_iterhash.sv').read_bytes()).hexdigest(),'fused_8192_words_bit_exact_vs_original128':True,")
(r/'scripts/deploy/check_iterhash_strict.py').write_text(s,newline='\n')
