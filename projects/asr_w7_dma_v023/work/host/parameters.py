"""V21 canonical DRAM image, ABI and independent load/run transport stages."""
import hashlib,json,mmap,struct,zlib
from pathlib import Path
import numpy as np

class ParameterImage:
    def __init__(self,folder):
        self.folder=Path(folder);self.meta=json.loads((self.folder/'manifest.json').read_text(encoding='utf-8'))
        self.file=(self.folder/'parameters.bin').open('rb');self.data=mmap.mmap(self.file.fileno(),0,access=mmap.ACCESS_READ)
        m=self.meta
        if len(self.data)!=m['image_bytes'] or hashlib.sha256(self.data).hexdigest()!=m['image_sha256'] or zlib.crc32(self.data)!=m['image_crc32']:
            raise ValueError('Parameter image length/SHA256/CRC32 mismatch')
        expected=(0x41503231,21,m['model_tag_lo'],m['model_tag_hi'],m['image_bytes'],len(m['directory']),m['original_initializer_catalog_count'],m['weight_views'])
        if struct.unpack_from('<8I',self.data)!=expected:raise ValueError('Parameter image header mismatch')
        self.by_name={r['name']:r for r in m['directory']};self.weight_cache={}
        for r in m['directory']:
            if r['address']!=m['param_base']+r['offset'] or r['offset']<256 or r['offset']+r['bytes']>len(self.data):raise ValueError('Directory address bounds')
            if hashlib.sha256(self.blob(r)).hexdigest()!=r['sha256']:raise ValueError('Directory hash: '+r['name'])
    def blob(self,r):return self.data[r['offset']:r['offset']+r['bytes']]
    def array(self,r):return np.frombuffer(self.data,dtype=r['dtype'],count=int(np.prod(r['shape'])),offset=r['offset']).reshape(r['shape'])
    def weight(self,ref):
        key=tuple(v['id'] for v in ref['views'])
        if key in self.weight_cache:return self.weight_cache[key]
        chunks=[]
        for v in ref['views']:
            k,n=v['k'],v['n'];kt,nt=(k+31)//32,(n+31)//32
            raw=np.frombuffer(self.blob(v),np.uint8).reshape(kt,nt,32,32).transpose(0,2,1,3).reshape(kt*32,nt*32)[:k,:n]
            parity=np.zeros(raw.shape,np.uint8)
            for bit in range(8):parity^=(raw>>bit)&1
            if np.any(parity):raise ValueError('DDR W7 byte parity')
            code=raw&127;p=np.asarray(v['positions_lsb'],np.int64)
            mag=(code&15).astype(np.int64)<<p[(code>>4)&3]
            if v['clip']:mag=np.minimum(mag,32767)
            q=np.where(code&64,-mag,mag).astype(np.int16);chunks.append(q)
        value=np.concatenate(chunks,axis=1);value.flags.writeable=False
        if value.shape!=(ref['k'],ref['n']):raise ValueError('DRAM decoded matrix shape')
        self.weight_cache[key]=value;return value

class LoadState:
    """Functional oracle, not hardware: BEGIN/verified bytes/COMMIT/READY."""
    def __init__(self):self.ready=False;self.generation=0;self.upload_bytes=0;self.meta=None
    def begin(self,meta):self.ready=False;self.meta=meta;self.verified=0;self.crc=0
    def verify(self,offset,blob):
        if self.ready or self.meta is None or offset!=self.verified or not blob or offset+len(blob)>self.meta['image_bytes']:raise ValueError('Load sequence/bounds')
        self.crc=zlib.crc32(blob,self.crc);self.verified+=len(blob)
    def commit(self):
        if self.meta is None or self.verified!=self.meta['image_bytes'] or self.crc!=self.meta['image_crc32']:raise ValueError('Incomplete/bad CRC load')
        self.ready=True;self.generation+=1
    def require(self,meta):
        if not self.ready or any(self.meta[k]!=meta[k] for k in ('model_tag_lo','model_tag_hi','image_bytes','image_crc32')):raise ValueError('Model not committed / wrong image')

class ParameterTransport:
    def __init__(self,link,image):self.link=link;self.image=image
    def state(self):return struct.unpack('<64I',self.link.request(0x42,struct.pack('<HH',0xe200,64)))
    def require_ready(self):
        s=self.state();m=self.image.meta
        if s[0]!=0xa51a2202 or s[22]!=0x10102131 or s[32]!=1 or list(s[33:37])!=[m['model_tag_lo'],m['model_tag_hi'],m['image_bytes'],m['image_crc32']]:raise RuntimeError('V21 READY model identity mismatch; run never loads parameters')
        return s
    def load(self,adopt_existing=False,progress=None):
        m=self.image.meta
        # Explicit load phase. CRC is computed from volatile DDR read-back by firmware.
        self.link.request(0x41,struct.pack('<HH5I',0xe210,5,1,m['model_tag_lo'],m['model_tag_hi'],m['image_bytes'],m['image_crc32']))
        if adopt_existing:
            for offset in range(0,m['image_bytes'],65536):
                count=min(65536,m['image_bytes']-offset)
                self.link.request(0x41,struct.pack('<HH3I',0xe210,3,3,offset,count))
                if progress:progress(offset+count,m['image_bytes'])
        else:
            self.link.request(0x41,struct.pack('<HHI',0xe000,1,m['param_base']))
            for offset in range(0,m['image_bytes'],1020):
                blob=self.image.data[offset:offset+1020]
                self.link.request(0x41,struct.pack('<HH',0xe100,len(blob)//4)+blob)
                if progress:progress(offset+len(blob),m['image_bytes'])
        self.link.request(0x41,struct.pack('<HHI',0xe210,1,2))
        return self.require_ready()
