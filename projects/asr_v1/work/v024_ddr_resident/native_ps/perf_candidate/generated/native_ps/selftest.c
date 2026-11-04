#include <math.h>
#include "native_ps.h"
/* Every bit is produced by executing the named helper, without any PL access. */
int ps_selftest(void) {
    const float g[2]={1,1}, z[2]={0,0}, x[4]={1,3,-1,1}, w[6]={1,2,3,2,1,-1};
    float y[4];
    int ok=0;
    ps_layernorm(x,y,2,2,g,z);
    if(fabsf(y[0]+1.f)<0.0001f && fabsf(y[3]-1.f)<0.0001f) ok|=1;
    y[0]=0; y[1]=0; ps_softmax(y,1,2);
    if(y[0]==0.5f && y[1]==0.5f) ok|=2;
    y[0]=1; ps_swish(y,1); if(fabsf(y[0]-0.7310586f)<1e-5f) ok|=4;
    ps_glu(x,y,1,2); if(fabsf(y[0]-0.2689414f)<1e-5f && fabsf(y[1]-2.1931758f)<1e-5f) ok|=8;
    ps_depthwise(x,y,2,2,w,z,3);
    if(y[0]==-1 && y[1]==2 && y[2]==-1 && y[3]==7) ok|=16;
    return ok;
}
