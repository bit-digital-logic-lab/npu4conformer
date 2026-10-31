from pathlib import Path
import json,numpy as np,matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
O=Path(__file__).resolve().parents[1]/'report'; DATA=Path(__file__).resolve().parents[1]/'data';(O/'images').mkdir(exist_ok=True)
x=json.load(open(DATA/'roofline_data.json'));P=x['peak_ops_per_cycle'];B=x['bandwidth_bytes_per_cycle']
plt.rcParams.update({'font.family':'Noto Sans CJK SC','font.size':14,'axes.titlesize':19,'axes.labelsize':15,'axes.spines.top':False,'axes.spines.right':False,'svg.fonttype':'none'})
f,a=plt.subplots(figsize=(14.4,7.7));f.subplots_adjust(left=.1,right=.97,top=.9,bottom=.23)
ii=np.geomspace(.5,128,400);a.plot(ii,np.minimum(P,B*ii),color='#244F66',lw=3,label='接口理论 Roofline：min(512, 16 × I)')
a.axvline(32,color='#BCC5C9',ls=':',lw=1.4);a.text(34,320,'拐点 I = 32 OP/B',fontsize=12,color='#62717a');a.text(45,570,'阵列理论峰值 512 OP/周期',fontsize=13,color='#244F66');a.text(1.1,24,'共享读写上限 16 B/周期',rotation=28,fontsize=13,color='#244F66')
cols=['#BE8242','#7A8B94','#17877D'];marks=['o','s','D'];locs=[(3.5,75),(6.5,25),(18,43)]
for c,col,m,loc in zip(x['cases'],cols,marks,locs):
 xx,yy=c['intensity_ops_per_byte'],c['throughput_ops_per_cycle'];a.scatter(xx,yy,s=110,color=col,marker=m,zorder=5)
 label=c['name']+f'\nI={xx:.2f}，P={yy:.2f}'
 a.annotate(label,xy=(xx,yy),xytext=loc,fontsize=12,color=col,arrowprops={'arrowstyle':'-','color':col,'lw':1},ha='left')
c=x['cases'][0];a.vlines(c['intensity_ops_per_byte'],c['throughput_ops_per_cycle'],c['roof_ops_per_cycle'],color='#BE8242',ls='--',lw=1.3)
a.annotate('该强度下理论上限 146.29\n当前点为上限的 30.86%',xy=(9.14,146.29),xytext=(13,185),fontsize=12,color='#9C6A33',arrowprops={'arrowstyle':'-','color':'#BE8242'})
a.set_xscale('log',base=2);a.set_yscale('log',base=2);a.set_xlim(.5,128);a.set_ylim(4,900);a.set_xticks([.5,1,2,4,8,16,32,64,128],[.5,1,2,4,8,16,32,64,128]);a.set_yticks([4,8,16,32,64,128,256,512],[4,8,16,32,64,128,256,512]);a.grid(alpha=.16,which='major');a.set_axisbelow(True)
a.set_xlabel('计算强度 I = 有用运算数 / 实际读写字节  [整数 OP/B]',labelpad=10);a.set_ylabel('实际吞吐 P = 有用运算数 / 完成周期  [整数 OP/周期]');a.set_title('项目矩阵计算的 Roofline 定位',loc='left',fontweight='bold',pad=15)
f.text(.1,.13,'1 MAC = 2整数OP；16×16 PE；128位共享读写BFM；纵轴按周期归一，不代入未经验证的板级频率。',fontsize=12,color='#53656F')
f.text(.1,.075,'橙点：M64 N32 K96，C初值有效；方形与菱形：同维度C初值无效的复用候选A/B，未合入整机。',fontsize=12,color='#53656F')
f.text(.1,.025,'此图为局部RTL与接口理论上限；距离屋顶的差距需由活动波形分析等待、收集和排空，不能全部归因于DDR带宽。',fontsize=11,color='#53656F')
f.savefig(O/'images/roofline.png',dpi=200);f.savefig(O/'images/roofline.svg');plt.close(f)
