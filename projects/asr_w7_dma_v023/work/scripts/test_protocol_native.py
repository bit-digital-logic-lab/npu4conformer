"""Derive sealed async harness for V022; private mock peripherals only."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';ASYNC=ROOT.parent/'model_a_v0_21_1_board_20261013_001/async002'
s=(ASYNC/'scripts/test_protocol.py').read_text()
s=s.replace("BASE=ROOT.parent.parent/'model_a_v0_21_1'","BASE=ROOT.parent/'model_a_v0_21_1'")
s=s.replace("'protocol002'","'protocol_native001'").replace('V211_ASYNC_NATIVE_PROTOCOL_PASS','V022_ASYNC_NATIVE_PROTOCOL_PASS')
needle="h=h.replace('static int dispatch_native(',"
assert s.count(needle)==1
addition="""h=h.replace('volatile uint32_t *csr=(void *)(uintptr_t)0xa8000000;csr[0]=', 'p=VirtualAlloc((void *)(uintptr_t)0xa9000000,65536,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);check_native(p==(void *)(uintptr_t)0xa9000000,\"privatePLplanCSRmapping\");\\n volatile uint32_t *csr=(void *)(uintptr_t)0xa8000000;csr[0]=')
"""
s=s.replace(needle,addition+needle)
needle=' check_native(dispatch_native(0x42,0xe400,64,0)==1&&last_got==266&&get32_21(last_reply+8+49*4)==ASYNC_MAGIC,"full status async capability");'
assert s.count(needle)==1
s=s.replace(needle,needle+'''
 *(volatile uint32_t *)(uintptr_t)0xa9000004=1;
 check_native(dispatch_native(0x41,0xe000,1,&pointer)==V10_BUSY,"noDDRmutation whilePLbusy afterPSerror");
 check_native(dispatch_native(0x41,0xe210,5,begin)==V10_BUSY,"noparameterreload whilePLbusy");
 *(volatile uint32_t *)(uintptr_t)0xa9000004=0;
''')
# Every generated source and executable lives in this new report directory.
exec(compile(s,str(Path(__file__)),'exec'),{'__file__':str(Path(__file__)),'__name__':'__main__'})
