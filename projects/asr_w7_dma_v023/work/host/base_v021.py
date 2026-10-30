"""V021 autonomous queues + unchanged V13 PL non-matrix operations.

CPU performs transport, exact code/layout conversion and ONNX graph control.
All K partial sums are loaded and accumulated by PL, never added on CPU.
"""
import struct, time
from collections import Counter
import numpy as np
from profiled_backend import ProfiledBackend

BASE = 0x03000000
END = 0x08000000

def tiles(x):
    return (x + 31) // 32

def align(x, n=256):
    return (x + n - 1) // n * n

def size_for(m, k, n):
    chunks = (k + 4095) // 4096
    return align(chunks * 64) + tiles(m) * tiles(k) * 2048 + tiles(k) * tiles(n) * 1024 + tiles(m) * tiles(n) * 6144

def column_step(m, k, n):
    available = END - BASE - align(((k + 4095) // 4096) * 64) - tiles(m) * tiles(k) * 2048
    columns = min(128, tiles(n), available // (tiles(k) * 1024 + tiles(m) * 6144))
    return min(n, columns * 32) if columns > 0 else 0

def choose_row_step(m, k, n):
    best = None
    candidates = sorted(set([min(m, 4096), *range(32, min(m, 4096) + 1, 32)]))
    for rows in candidates:
        uploads = queues = 0
        for row in range(0, m, rows):
            mr = min(rows, m - row)
            nc = column_step(mr, k, n)
            if not nc:
                break
            parts = (n + nc - 1) // nc
            uploads += parts * (64 * ((k + 4095) // 4096) + tiles(mr) * tiles(k) * 2048) + tiles(n) * tiles(k) * 1024
            queues += parts
        else:
            score = (uploads, queues, -rows)
            if best is None or score < best[0]:
                best = (score, rows)
    if best is None:
        raise ValueError('No positive M/N window fits the owned 80MiB DDR arena; no CPU fallback')
    return best[1]

def block_bytes(x, weights=False):
    r, c = x.shape
    pad = np.zeros((tiles(r) * 32, tiles(c) * 32), dtype=np.uint8 if weights else '<i2')
    if weights:
        parity = np.zeros_like(x)
        for bit in range(7):
            parity ^= (x >> bit) & 1
        pad[:r, :c] = x | (parity << 7)
    else:
        pad[:r, :c] = x
    return pad.reshape(tiles(r), 32, tiles(c), 32).transpose(0, 2, 1, 3).copy().tobytes()

def dynamic_pack_task(a, codes, positions, clip, first_cookie):
    if a.dtype != np.int16 or codes.dtype != np.uint8 or a.ndim != 2 or codes.ndim != 2:
        raise ValueError('Exact A16/W7 operands required')
    m, k = a.shape
    n = codes.shape[1]
    if codes.shape[0] != k or not 1 <= m <= 4096 or not 1 <= n <= 4096 or k < 1 or np.any(codes > 127):
        raise ValueError('V021 queue dimensions/codes')
    if len(positions) != 4 or any(type(p) not in (int, np.int64, np.int32) or not 0 <= p <= 12 for p in positions):
        raise ValueError('V021 original position table required')
    chunks = (k + 4095) // 4096
    if chunks > 4096 or first_cookie < 1 or first_cookie + chunks > 0xffffffff:
        raise ValueError('Queue/cookie limit')
    descriptors = bytearray(chunks * 64)
    cursor = BASE + align(len(descriptors))
    segments = []
    addresses = []
    for at in range(0, k, 4096):
        av = block_bytes(a[:, at:at+4096])
        wv = block_bytes(codes[at:at+4096, :], True)
        abase = cursor
        segments.append((cursor, av));cursor += len(av)
        bbase = cursor
        segments.append((cursor, wv));cursor += len(wv)
        addresses.append((abase, bbase, min(4096, k-at)))
    cbase = cursor
    cbytes = tiles(m) * tiles(n) * 6144
    if cbase + cbytes > END or cbase + cbytes - BASE != size_for(m, k, n):
        raise ValueError('Owned DDR capacity mismatch')
    table = sum(int(p) << (4*i) for i, p in enumerate(positions)) | (int(clip) << 16)
    for i, (abase, bbase, depth) in enumerate(addresses):
        cookie = first_cookie + i
        words = (0x51415352, (21 << 16) | 1, cookie, 0xffffffff if i == 0 else i-1,
                 abase, bbase, cbase, m, n, depth, cookie,
                 (1 << 16) | 7, (3 << 16) | 2, table, 1 << 16,
                 0 if i == 0 else (1 << 16) | 1)
        struct.pack_into('<16I', descriptors, i*64, *words)
    layout = dict(m=m, k=k, n=n, mt=tiles(m), nt=tiles(n), kt=tiles(k), cbase=cbase, cbytes=cbytes,
                  queue_base=BASE, queue_count=chunks, last_cookie=first_cookie+chunks-1,
                  uploaded_bytes=len(descriptors)+sum(len(b) for _,b in segments),
                  extent_bytes=cbase+cbytes-BASE, alignment_gap_not_uploaded=align(len(descriptors))-len(descriptors),
                  expected_compute_cycles=tiles(m)*tiles(n)*tiles(k)*264,
                  expected_read_bytes=64*chunks+tiles(m)*tiles(n)*tiles(k)*3072+(chunks-1)*cbytes,
                  expected_write_bytes=chunks*cbytes)
    return [(BASE, bytes(descriptors)), *segments], layout

def unpack_c(data, layout):
    b = np.frombuffer(data, np.uint8).reshape(layout['mt'], layout['nt'], 32, 32, 6)
    extended = np.empty(b.shape[:-1] + (8,), np.uint8)
    extended[..., :6] = b
    extended[..., 6:] = np.where(b[..., 5:6] & 128, 255, 0).astype(np.uint8)
    result = extended.view('<i8').reshape(layout['mt'], layout['nt'], 32, 32).transpose(0,2,1,3)
    return result.reshape(layout['mt']*32, layout['nt']*32)[:layout['m'], :layout['n']].copy()

class V021Base(ProfiledBackend):
    pack_task=staticmethod(dynamic_pack_task)
    name = 'V021-L1-banked-queued-DDR-matrix-plus-V13-PL-nonmatrix'
    def __init__(self, link):
        super().__init__(link)
        self.v21_stats = Counter();self.v21_tasks = []
        capability=self.telemetry21()
        if capability[0] != 0xa51a2202:
            raise RuntimeError('Full V021 gateway capability required')
        # Continue the board's last cookie across host instances; epochs must
        # not repeat while the PL C cache and gateway remain live.
        self.cookie21=capability[2]
    def telemetry21(self):
        return struct.unpack('<64I', self.link.request(0x42, struct.pack('<HH',0xe200,64)))
    def pointer21(self, address):
        self.link.request(0x41, struct.pack('<HHI',0xe000,1,address))
    def upload21(self, address, data):
        if len(data) % 4 or address % 4 or not BASE <= address < END or len(data) > END-address:
            raise ValueError('DDR upload bounds/alignment')
        self.pointer21(address)
        for pos in range(0, len(data), 1020):
            part = data[pos:pos+1020]
            self.link.request(0x41, struct.pack('<HH',0xe100,len(part)//4)+part)
        self.v21_stats['host_to_ddr_payload_bytes'] += len(data)
    def read21(self, address, size):
        if size % 4 or address % 4 or not BASE <= address < END or not 0 < size <= END-address:
            raise ValueError('DDR read bounds/alignment')
        self.pointer21(address);parts=[]
        for pos in range(0,size,1020):
            count=min(1020,size-pos)//4
            reply=self.link.request(0x42,struct.pack('<HH',0xe100,count))
            if len(reply)!=count*4:
                raise RuntimeError('DDR read size mismatch')
            parts.append(reply)
        self.v21_stats['ddr_to_host_payload_bytes']+=size
        return b''.join(parts)
    def native21(self, a, codes, positions, clip):
        start=time.perf_counter()
        segments,layout=self.pack_task(a,codes,positions,clip,self.cookie21+1)
        self.cookie21+=layout['queue_count']
        self.v21_stats['layout_seconds']+=time.perf_counter()-start
        start=time.perf_counter()
        for address,blob in segments:self.upload21(address,blob)
        self.v21_stats['upload_seconds']+=time.perf_counter()-start
        start=time.perf_counter()
        self.link.request(0x41,struct.pack('<HH2I',0xe200,2,BASE,layout['queue_count']))
        w=self.telemetry21()
        self.v21_stats['submit_wait_seconds']+=time.perf_counter()-start
        if w[0]!=0xa51a2202 or w[2]!=self.cookie21 or w[3]!=layout['queue_count'] or w[20]!=layout['queue_count']-1 or w[21] or w[22]!=0x10102131 or w[30]!=3:
            raise RuntimeError('V021 stale/failed queue completion')
        cycles=w[4]+(w[5]<<32);compute=w[6]+(w[7]<<32)
        if compute!=layout['expected_compute_cycles'] or w[8]!=layout['expected_read_bytes'] or w[9]!=layout['expected_write_bytes']:
            raise RuntimeError('V021 matrix execution counters disagree with layout')
        entry={**layout,'cookie':self.cookie21,'queue_cycles':cycles,'compute_cycles':compute,
               'dma_read_bytes':w[8],'dma_write_bytes':w[9],'dma_read_bursts':w[10],'dma_write_bursts':w[11],
               'last_task_cycles':w[12]+(w[13]<<32),'last_core_compute':w[14],'last_core_reads':w[15],
               'last_core_writes':w[16],'last_core_hits':w[17],'last_core_misses':w[18],
               'fetch_cycles':w[24]+(w[25]<<32),'engine_wait_cycles':w[26]+(w[27]<<32),
               'retire_wait_cycles':w[28]+(w[29]<<32),'cpu_mmio_writes':w[30]}
        self.v21_tasks.append(entry)
        for key in ('queue_cycles','compute_cycles','dma_read_bytes','dma_write_bytes','dma_read_bursts','dma_write_bursts','fetch_cycles','engine_wait_cycles','retire_wait_cycles','cpu_mmio_writes','alignment_gap_not_uploaded'):
            self.v21_stats[key]+=entry[key]
        self.v21_stats['native_matrix_queues']+=1;self.v21_stats['native_matrix_tasks']+=layout['queue_count']
        start=time.perf_counter();data=self.read21(layout['cbase'],layout['cbytes'])
        self.v21_stats['read_seconds']+=time.perf_counter()-start
        return unpack_c(data,layout)
    def matmul_special(self,a,b,positions=None):
        started=time.perf_counter();a=np.asarray(a);b=np.asarray(b)
        if a.dtype!=np.int16 or b.dtype!=np.int16 or a.ndim<2 or b.ndim<2:
            raise ValueError('INT16 QDQ MatMul required')
        m,k=a.shape[-2:];n=b.shape[-1]
        if b.shape[-2]!=k or min(m,k,n)<1:raise ValueError('MatMul shape')
        batch=np.broadcast_shapes(a.shape[:-2],b.shape[:-2])
        aa=np.broadcast_to(a,batch+(m,k));bb=np.broadcast_to(b,batch+(k,n))
        output=np.empty(batch+(m,n),np.int64)
        effective_k=k if positions is not None else 4*k
        row_step=choose_row_step(m,effective_k,n)
        for ix in np.ndindex(batch):
            for row in range(0,m,row_step):
                mr=min(row_step,m-row);av=aa[ix][row:row+mr]
                if positions is None:av=np.tile(av,(1,4))
                nc=column_step(mr,effective_k,n)
                for col in range(0,n,nc):
                    q=bb[ix][:,col:col+nc]
                    if positions is not None:
                        codes=self._encode(q,positions);p=positions;clip=True
                    else:
                        mag=np.abs(q.astype(np.int32));sign=(q<0).astype(np.uint8)<<6
                        codes=np.concatenate([sign|(digit<<4)|((mag>>(4*digit))&15).astype(np.uint8) for digit in range(4)],axis=0)
                        p=(0,4,8,12);clip=False
                    output[ix][row:row+mr,col:col+nc]=self.native21(np.ascontiguousarray(av),codes,p,clip)
        self.lowbit_stats['special7_matmuls' if positions is not None else 'dynamic_i16_decomposed_matmuls']+=1
        self.lowbit_stats['logical_int16_mac_terms']+=int(np.prod(batch,dtype=np.int64))*m*k*n
        self.lowbit_stats['matmul_wall_seconds']+=time.perf_counter()-started
        return output
    def matmul_i16(self,a,b):return self.matmul_special(a,b)
    def report(self):
        r=super().report()
        r.update(numerical_backend=self.name,cpu_numeric_fallback=False,ddr_bulk_dma=True,
                 v021=dict(getattr(self,'v21_stats',{})),
                 matrix_control='3 MMIO writes per autonomous K-split queue; no CPU per-tile control or K partial-sum arithmetic',
                 resident_scope='V021 DDR matrix tasks + unchanged V13 PL nonmatrix SRAM; host ONNX graph and inter-node tensors retained')
        return r
