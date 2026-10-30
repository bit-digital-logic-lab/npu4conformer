"""Separate warm-board runner. Never changes the prior task's files."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';ASYNC=ROOT.parent/'model_a_v0_21_1_board_20261013_001/async002';OTHER=ROOT.parent/'model_a_v0_20_opt_20261013'
def emit(p,s):
    if p.exists():raise ValueError('Fresh board entry '+str(p))
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
s=(OTHER/'scripts/audit_autonomy_board.tcl').read_text()
emit(ROOT/'scripts/audit_warm_handoff.tcl',s)
s=(ASYNC/'scripts/run_case0000.py').read_text()
start=s.index("ASYNC=Path(__file__)");end=s.index('\np=argparse',start)
s=s[:start]+"ASYNC=Path(__file__).resolve().parents[1];ROOT=ASYNC;BASE=ROOT.parent/'model_a_v0_21_1';OLD=ROOT.parent/'model_a_v0_21';sys.dont_write_bytecode=True"+s[end:]
s=s.replace("str(ROOT/'host'),str(OLD/'host')","str(BASE/'host'),str(OLD/'host')")
s=s.replace("image=ParameterImage(ROOT/'assets/parameters003')","image=ParameterImage(ROOT/'assets/parameters002')")
s=s.replace('seal=verify()',"seal=verify('full002')")
s=s.replace('V211_ASYNC_GATEWAY_STARTED','V022_PHASE1_GATEWAY_STARTED').replace('USR_ACCESS=A51A2114','USR_ACCESS=A51A2201')
s=s.replace('gateway_async002.elf','gateway_v022.elf').replace('v0211_full.bit','v022_full.bit').replace('vm211_async.c','vm_pl.c')
s=s.replace("out=ROOT/'reports'/a.out","out=ROOT/'reports'/a.out")
s=s.replace("seal['sha256']['release/v022_full.bit']","seal['bit_sha256']")
s=s.replace("carrier='V211 original125MHz bit + ASYNC002 board-test firmware; not originalrev003'","carrier='V022 phase1 PL plans+DDR arithmetic/layout,125MHz candidate'")
s=s.replace("async_derivation=str(ASYNC/'DERIVATION.json')","runtime_derivation=str(ROOT/'scripts/derive_runtime_v022.py')")
s=s.replace("base_numerical_vm_sha256=sha(ROOT/'ps/vm211.c')","base_numerical_vm_sha256=sha(BASE/'ps/vm211.c')")
s=s.replace("str(ROOT.parent/'model_a_lowbit_v9/scripts/golden_common.py')","str(ROOT.parent/'model_a_lowbit_v9/scripts/golden_common.py')")
s=s.replace('all38CONV+30FFN includingQDQ board-local; outside nodes retain host DAG','all38CONV+30FFN PL plans includingQDQ directDDR; outside nodes retain host DAG. Phase1: integer matrix storage still serial, not wholegraphPL')
s=s.replace("r'", "r'")
emit(ROOT/'scripts/run_case0000.py',s)
print('V022_BOARD_RUNTIME_ENTRIES_PREPARED; status/load/run separate; receipt and sealed bit required')
