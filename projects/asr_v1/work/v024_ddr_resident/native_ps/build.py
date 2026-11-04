"""Build the board's AArch64 EL3 firmware; never touches the target."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import struct

HERE=Path(__file__).resolve().parent
TOOLS=Path("C:/Academic_Application/Vivado/2025.2/gnu/aarch64/nt/aarch64-none/bin")
START=HERE.parent.parent/"v024_deploy_20261101/ps_benchmark/pl_transfer_cached_bram/startup.S"

def run(encoder,pltest):
    out=HERE/"build"
    out.mkdir(exist_ok=True)
    stem="encoder" if encoder else ("pltest" if pltest else "selftest")
    elf=out/(stem+".elf")
    source=[START,HERE/"mmu.S",HERE/"firmware.c",HERE/"kernels.c",HERE/"selftest.c"]
    extra=[]
    if encoder or pltest:
        source += [HERE.parent/"native_pl/native_pl.c"]
        extra=["-DASR_PL_ENABLED","-I"+str(HERE.parent/"native_pl")]
    if encoder:
        source += [HERE/"encoder.c"]
        extra+=["-DASR_ENCODER_ENABLED", "-I"+str(HERE.parent/"native_model")]
    cc=TOOLS/"aarch64-none-elf-gcc.exe"
    args=[cc, "-std=c11","-O3","-mcpu=cortex-a53","-ffreestanding","-ffunction-sections","-fdata-sections",
          "-fno-math-errno","-fno-stack-protector","-Wall","-Wextra","-Werror","-nostdlib","-DV024_EXPECTED_CNTFRQ=33333000",
          "-Wl,--gc-sections,--build-id=none","-Wl,-T,"+str(HERE/"firmware.ld"),"-Wl,-Map,"+str(out/(stem+".map")),
          *extra,*source,"-Wl,--start-group","-lm","-lc","-lgcc","-Wl,--end-group","-o",elf]
    subprocess.run(args,check=True)
    binary=elf.read_bytes()
    h=struct.unpack_from("<16sHHIQQQIHHHHHH",binary)
    if h[0][:6]!=b"\x7fELF\x02\x01" or h[2]!=183 or h[4]!=0xfffc0000: raise RuntimeError("Invalid AArch64 ELF entry")
    loads=[]
    for idx in range(h[10]):
        seg=struct.unpack_from("<IIQQQQQQ",binary,h[5]+idx*h[9])
        if seg[0]==1:
            addr=seg[4]; size=seg[6]
            if not any(lo<=addr<addr+size<=hi for lo,hi in ((0xfffc0000,0xfffe0000),(0x0f000000,0x0f800000))):
                raise RuntimeError(f"Unexpected ELF load segment: {addr:#x} {size}")
            loads.append([hex(addr),size])
    if len(loads)<2: raise RuntimeError("OCM or DDR code missing")
    data={"elf":str(elf), "sha256":hashlib.sha256(elf.read_bytes()).hexdigest(),"load_segments":loads,
          "encoder_compiled":encoder,"hardware_executed":False,"entry":"0xfffc0000","mailbox":"0x08000000"}
    (out/(stem+"_build.json")).write_text(json.dumps(data,indent=2))
    print(json.dumps(data))

if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__);g=ap.add_mutually_exclusive_group()
    g.add_argument("--encoder",action="store_true");g.add_argument("--pltest",action="store_true")
    args=ap.parse_args();run(args.encoder,args.pltest)
