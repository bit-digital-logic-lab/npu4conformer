"""Representation/layout only; unchanged W7p8/INT16/INT48 semantics."""
import numpy as np
def tiles(n):return (n+31)//32
def align(n,a=256):return (n+a-1)//a*a
def block_bytes(x,weights=False):
    r,c=x.shape;pad=np.zeros((tiles(r)*32,tiles(c)*32),dtype=np.uint8 if weights else '<i2')
    if weights:
        parity=np.zeros_like(x)
        for b in range(7):parity^=(x>>b)&1
        pad[:r,:c]=x|(parity<<7)
    else:pad[:r,:c]=x
    return pad.reshape(tiles(r),32,tiles(c),32).transpose(0,2,1,3).copy().tobytes()
def unpack_c(data,m,n):
    r,c=tiles(m),tiles(n);b=np.frombuffer(data,np.uint8).reshape(r,c,32,32,6)
    e=np.empty(b.shape[:-1]+(8,),np.uint8);e[...,:6]=b;e[...,6:]=np.where(b[...,5:6]&128,255,0).astype(np.uint8)
    return e.view('<i8').reshape(r,c,32,32).transpose(0,2,1,3).reshape(r*32,c*32)[:m,:n].copy()
