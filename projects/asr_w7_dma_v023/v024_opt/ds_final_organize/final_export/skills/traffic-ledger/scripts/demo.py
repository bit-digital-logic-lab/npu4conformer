"""生成可查看的合成周期账本与时间轴，不代表项目实测。"""
import argparse
import json
from pathlib import Path
from selftest import fixture
from analyze import analyze, render

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    args=p.parse_args()
    args.out.mkdir(parents=True,exist_ok=True)
    events=fixture()
    (args.out/'trace.jsonl').write_text(''.join(json.dumps(e,ensure_ascii=False)+'\n' for e in events))
    s,t,i=analyze(events)
    render(args.out,s,t,i)
    print(args.out/'timeline.html')
