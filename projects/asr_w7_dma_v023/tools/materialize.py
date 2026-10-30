#!/usr/bin/env python3
"""Copy this archive and relocate historical source paths without editing evidence."""
from pathlib import Path
import argparse, shutil
parser=argparse.ArgumentParser()
parser.add_argument('output',type=Path)
a=parser.parse_args(); src=Path(__file__).resolve().parents[1]; dst=a.output.resolve()
if dst.exists(): parser.error('output must not exist')
if dst==src or src in dst.parents: parser.error('output must be outside the archive')
shutil.copytree(src,dst)
exts={'.py','.sh','.tcl','.f','.sv','.v','.sby','.xdc'}
count=0
for f in dst.rglob('*'):
    if not f.is_file() or f.suffix not in exts or f.name=='materialize.py': continue
    text=f.read_text(errors='strict'); new=text.replace('/home/yang/Desktop/项目',str(dst))
    if new!=text: f.write_text(new); count+=1
print(f'Created {dst}; relocated {count} source files. Restore external assets when required.')
