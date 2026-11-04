"""Build an independent profiling ELF from the SHA-pinned first acceptance sources."""
import hashlib
import json
from pathlib import Path
import shutil
import sys

HERE=Path(__file__).resolve().parent
PS=HERE.parent
PL=PS.parent/"native_pl"
GEN=HERE/"generated"
sys.path.insert(0,str(PS))
import build


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


PINS={PS/"build/encoder.elf":"682dfd8096d4e62e325b107857461fbfd85f53fe722e494025cfd7d4082d1068",
      PS/"firmware.c":"7be0d39b3ba02f38bbe3c5dc46731732dbcfbfda3495c95b4c932c251412db57",
      PS/"encoder.c":"5e11b8defd5882488ea8dbcd2769ccc781d793567e1fab428dad68139042e5fb",
      PS/"kernels.c":"ea683f8eeee479997923803e3fceed858b81b58b8842ee7c20b1cb077133913a",
      PL/"native_pl.c":"a670cb70374a43fca2e8c54b5be5f3dc6b9f8b6ba6d63025355a0f62bb30adbc"}


def once(source,a,b):
    if source.count(a)!=1:
        raise ValueError(f"profiling source anchor changed: {a}")
    return source.replace(a,b)


def insert(source,anchor,before="",after=""):
    return once(source,anchor,before+anchor+after)


def instrument_pl(s):
    s='#include "../native_ps/profile.h"\n'+s
    s=insert(s,"    float peak=0;\n    for (size_t",before="    uint64_t whole=perf_now(), phase=whole;\n")
    s=insert(s,"    for (unsigned row=0;row<m;row+=32) {",before="    perf_end(A_SCAN,phase);\n",after="\n        phase=perf_now();")
    s=insert(s,"        for (unsigned col=0;col<n;col+=4096) {",before="        perf_end(A_PACK,phase);\n")
    s=insert(s,"            if(nct!=nt) {",after="\n                phase=perf_now();")
    s=insert(s,"            }\n            uint32_t *queue",before="                perf_end(B_REPACK,phase);\n")
    s=insert(s,"            int rc=submit(parts,kt*2048,nct*6144);",before="            phase=perf_now();\n",after="\n            perf_end(WAIT_SUBMIT,phase);")
    s=insert(s,"            const uint8_t *out=PTR(uint8_t,C_ADDR);",before="            phase=perf_now();\n")
    s=once(s,"            }\n        }\n    }\n    return 0;\n}\n\nint native_pl_dynamic",
             "            }\n            perf_end(C_UNPACK,phase);\n        }\n    }\n    perf_end(LINEAR_TOTAL,whole);\n    return 0;\n}\n\nint native_pl_dynamic")
    s=insert(s,"    uint8_t values[64]",before="    uint64_t phase=perf_now();\n")
    s=insert(s,"    return native_pl_linear(x,m,k,n,packed",before="    perf_end(DYNAMIC_PACK,phase);\n")
    # RTL latches the high half when the low word is read, so sequence both volatile loads.
    return once(s,"native_pl_profile.cycles+=((uint64_t)csr_read(0x24)<<32)|csr_read(0x20);",
        "uint32_t lo=csr_read(0x20);\n    uint32_t hi=csr_read(0x24);\n    native_pl_profile.cycles+=((uint64_t)hi<<32)|lo;")


def instrument_kernels(s):
    # All five kernels are void, have no early returns, and end at file-scope brace.
    for fn,slot in (("ps_layernorm","PS_LN"),("ps_swish","PS_SWISH"),("ps_glu","PS_GLU"),
                    ("ps_softmax","PS_SOFTMAX"),("ps_depthwise","PS_DEPTHWISE")):
        a=s.index("void "+fn+"(")
        b=s.index("{",a)+1
        end=s.index("\n}",b)
        s=s[:b]+"\n    uint64_t phase=perf_now();"+s[b:end]+f"\n    perf_end({slot},phase);"+s[end:]
    return '#include "profile.h"\n'+s


def main():
    for path,expected in PINS.items():
        if digest(path)!=expected:
            raise ValueError(f"Baseline changed: {path}")
    gen_ps=GEN/"native_ps"; gen_pl=GEN/"native_pl"; model=GEN/"native_model"
    for d in (gen_ps,gen_pl,model):
        d.mkdir(parents=True,exist_ok=True)
    for f in ("mmu.S","firmware.ld","native_ps.h","selftest.c","encoder.c"):
        shutil.copyfile(PS/f,gen_ps/f)
    for f in ("profile.h","profile_controller.h"):
        shutil.copyfile(HERE/f,gen_ps/f)
    shutil.copyfile(PL/"native_pl.h",gen_pl/"native_pl.h")
    shutil.copyfile(PS.parent/"native_model/model_index.h",model/"model_index.h")
    (gen_pl/"native_pl.c").write_text(instrument_pl((PL/"native_pl.c").read_text()),encoding="utf-8")
    (gen_ps/"kernels.c").write_text(instrument_kernels((PS/"kernels.c").read_text()),encoding="utf-8")
    s=insert((PS/"firmware.c").read_text(),'#include "native_pl.h"',after='\n#include "profile_controller.h"')
    s=insert(s,"        uint64_t begin=ticks();",before="        if(cmd==ASR_ENCODE) perf_begin();\n")
    s=insert(s,"        box->result=result; box->elapsed_ticks=ticks()-begin;",after="\n        if(cmd==ASR_ENCODE) perf_publish(seq,result,box->elapsed_ticks);")
    (gen_ps/"firmware.c").write_text(s,encoding="utf-8")
    build.HERE=gen_ps
    build.run(True,False)
    elf=HERE/"encoder_profile.elf"
    shutil.copyfile(gen_ps/"build/encoder.elf",elf)
    provenance=dict(baseline={str(p):h for p,h in PINS.items()},candidate_sha256=digest(elf),
                    profile_bytes=136,sideband_addr="0x08000040",
                    profile_period_ns=20.625,qualified_on_board=False)
    (HERE/"build_receipt.json").write_text(json.dumps(provenance,indent=2),encoding="utf-8")
    print(elf,provenance["candidate_sha256"])


if __name__=="__main__":
    main()
