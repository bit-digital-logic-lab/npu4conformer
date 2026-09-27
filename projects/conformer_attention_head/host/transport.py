"""中文说明：实物推理只发送原始字节、接收 FPGA 已完成的 FP32 输出；不执行模型计算。"""
import argparse,json,struct,time,zlib,hashlib
from pathlib import Path
import serial
ROOT=Path(__file__).resolve().parents[1]

def packet(tag,data,last=False):
    if len(data)%4 or not 0<len(data)<=2048:raise ValueError("packet payload")
    body=struct.pack("<BHHB",0x41,tag,len(data)//4,int(last))
    body+=data
    return b"\xa5\xc3"+body+struct.pack("<I",zlib.crc32(body))
def exact(port,count,timeout):
    end=time.monotonic()+timeout;out=bytearray()
    while len(out)<count:
        if time.monotonic()>end:raise TimeoutError(f"{len(out)}/{count} received")
        port.timeout=max(.001,end-time.monotonic())
        out.extend(port.read(count-len(out)))
    return bytes(out)

def run(port_name,input_file,output_folder,inject_crc_at=None,duplicate_at=None):
    data=Path(input_file).read_bytes()
    if len(data)%4 or struct.unpack_from("<I",data)[0]!=0x48454144:raise ValueError("input image")
    t=struct.unpack_from("<I",data,4)[0]
    if not 1<=t<=8:raise ValueError("T must be 1..8")
    if len(data)!=4*(10+t*512+164736):raise ValueError("input image length does not match complete head")
    output_folder=Path(output_folder);output_folder.mkdir(parents=True,exist_ok=True)
    events=[];started=time.monotonic();attempts=0
    with serial.Serial(port_name,115200,timeout=5,write_timeout=5,rtscts=False,dsrdtr=False,xonxoff=False) as port:
        time.sleep(.15);port.reset_input_buffer()
        chunks=[data[i:i+2048] for i in range(0,len(data),2048)]
        for tag,chunk in enumerate(chunks):
            last=tag==len(chunks)-1
            request=packet(tag,chunk,last)
            for attempt in range(3):
                attempts+=1
                try:
                    send=request
                    if tag==inject_crc_at and attempt==0:
                        send=request[:-1]+bytes([request[-1]^1])
                    if port.write(send)!=len(send):raise IOError("short write")
                    ack=exact(port,9,5)
                    if ack[:2]!=b"\x5a\xc4":raise IOError("ACK header")
                    if zlib.crc32(ack[2:5])!=struct.unpack_from("<I",ack,5)[0]:raise IOError("ACK CRC")
                    status,seen=struct.unpack_from("<BH",ack,2)
                    if seen!=tag or status!=0:raise IOError(f"ACK status={status} tag={seen}, expected={tag}")
                    break
                except (IOError,TimeoutError) as e:
                    events.append(dict(tag=tag,attempt=attempt+1,error=str(e),injected=(tag==inject_crc_at and attempt==0)))
                    print("TRANSPORT_RETRY",events[-1],flush=True)
                    if attempt==2:raise
                    time.sleep(.2);port.reset_input_buffer()
            if tag==duplicate_at:
                if last:raise ValueError("duplicate diagnostic needs a non-final packet")
                port.write(request)
                ack=exact(port,9,5)
                assert ack[:2]==b"\x5a\xc4" and ack[2]==0
                assert struct.unpack_from("<H",ack,3)[0]==tag
                assert zlib.crc32(ack[2:5])==struct.unpack_from("<I",ack,5)[0]
                print("DUPLICATE_ACK_PASS",tag,flush=True)
            if tag%16==0:print(f"INPUT_PROGRESS {tag+1}/{len(chunks)}",flush=True)
        if exact(port,2,5)!=b"\x5a\xc5":raise IOError("result header")
        header=exact(port,12,5)
        magic,status,count=struct.unpack("<3I",header)
        if magic!=0x46504741 or count!=t*64+2*t*512+t*t:raise IOError("result metadata")
        raw=header+exact(port,count*4,30)
        crc=struct.unpack("<I",exact(port,4,5))[0]
        if crc!=zlib.crc32(raw):raise IOError("result CRC")
        if status:raise RuntimeError(f"FPGA rejected invalid/out-of-range float values: {status}")
    (output_folder/"fpga_output.bin").write_bytes(raw)
    # 只解包 IEEE754 字节，没有主机 scale、Softmax、bias 或矩阵运算。
    decoded=struct.unpack("<"+str(count)+"f",raw[12:])
    result={"context":decoded[:t*64],"contribution":decoded[t*64:t*64+t*512],
            "with_output_bias":decoded[t*64+t*512:t*64+2*t*512],
            "probability":decoded[-t*t:]}
    (output_folder/"fpga_output.json").write_text(json.dumps(result),encoding="utf-8")
    report={"backend":"ALL_FPGA_HLS_INT16","port":port_name,"status":"TRANSFER_PASS",
            "input_bytes":len(data),"packets":len(chunks),"wire_attempts":attempts,
            "transport_events":events,"elapsed_seconds":time.monotonic()-started,
            "output_words":count,"host_operations":"binary I/O, CRC, IEEE754 unpack only",
            "injected_crc_at":inject_crc_at,"duplicate_checked_at":duplicate_at,
            "bitstream_sha256":hashlib.sha256((ROOT/"artifacts/ax7035_top.bit").read_bytes()).hexdigest()}
    (output_folder/"transport.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print("FPGA_TRANSFER_PASS",json.dumps(report,ensure_ascii=False),flush=True)

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--port",required=True)
    p.add_argument("--input",type=Path,default=ROOT/"fixtures/input.bin")
    p.add_argument("--output",type=Path,default=ROOT/"artifacts/hardware")
    p.add_argument("--inject-crc-at",type=int)
    p.add_argument("--duplicate-at",type=int)
    a=p.parse_args();run(a.port,a.input,a.output,a.inject_crc_at,a.duplicate_at)
