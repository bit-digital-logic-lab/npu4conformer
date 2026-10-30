"""Live output + immutable fresh log, no shell command interpolation."""
import json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];tag=sys.argv[1]
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
path=ROOT/'reports'/(tag+'.log')
if path.exists():raise ValueError('Fresh log')
with path.open('x',encoding='utf-8') as log:
    child=subprocess.Popen([sys.executable,'-B','-X','utf8',str(ROOT/'scripts/run_case0000.py'),*sys.argv[2:]],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    lines=[]
    for line in child.stdout:
        log.write(line);log.flush();print(line,end='',flush=True);lines.append(line)
    rc=child.wait()
    if rc==0:
        text=''.join(lines);at=text.rfind('\n{');at=at+1 if at>=0 else text.find('{')
        if at>=0:
            try:result=json.loads(text[at:])
            except json.JSONDecodeError:result=None
            if result is not None:(ROOT/'reports'/(tag+'.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
sys.exit(rc)
