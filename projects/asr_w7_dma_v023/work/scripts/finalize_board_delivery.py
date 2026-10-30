"""Post-board immutable evidence supplement; preserve offline release manifest."""
import hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'model_a_v0_21_1';ASYNC=ROOT.parent/'model_a_v0_21_1_board_20261013_001/async002'
sys.path.insert(0,str(ROOT/'scripts'));from seal_runtime import verify
release=verify('full002');report=json.loads((ROOT/'BOARD_RESULT.json').read_text())
if not report['hardware_executed'] or not report['repeat_bit_exact'] or any(not c['bit_exact'] for r in report['runs'] for c in r['vs_v21_hardware'].values()):raise ValueError('WholeCASE correctness not confirmed')
stopped=ROOT/'board/run001/stopped.txt'
if not stopped.exists() or 'V022_PHASE1_GATEWAY_STOPPED_CACHE_RESTORED' not in stopped.read_text():raise ValueError('Clean stopped receipt required')
tag=sys.argv[1] if len(sys.argv)>1 else 'final_check001'
if not tag.replace('_','').isalnum():raise ValueError('Safe tag')
out=ROOT/'reports'/tag;out.mkdir(exist_ok=False)
env=os.environ.copy();env.update(TEMP=str(ROOT/'tmp'),TMP=str(ROOT/'tmp'),XILINX_LOCAL_USER_DATA='NO',XILINX_TCLAPP_REPO=r'D:\fpga\new2025\vitis\2025.2\Vivado\data\XilinxTclStore')
cp=subprocess.run([r'D:\fpga\new2025\vitis\2025.2\Vitis\bin\xsdb.bat',str(ROOT/'scripts/final_readonly_status.tcl')],cwd=ROOT,env=env,capture_output=True,text=True,timeout=60)
(out/'hardware_status.log').write_text(cp.stdout+cp.stderr,encoding='utf-8');cp.check_returncode()
if 'V022_FINAL_READONLY_STOPPED_DRAINED_CACHE_READY_PASS' not in cp.stdout:raise ValueError('Final readonly hardware state not confirmed')
dump=subprocess.run([r'D:\fpga\new2025\vitis\2025.2\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-objdump.exe','-d',str(ROOT/'ps/gateway_v022.elf')],cwd=ROOT,capture_output=True,text=True,timeout=60);dump.check_returncode()
instructions=re.findall(r'\t(f(?:add|sub|mul|div|sqrt|madd|msub|neg|abs|cmp|cv|mla|mls)\w*)\s',dump.stdout)
if instructions:raise ValueError('Unexpected ARM FP arithmetic '+str(instructions))
old_seals=[]
for script in (BASE/'scripts/seal_runtime.py',ASYNC/'scripts/seal_variant.py'):
    check=subprocess.run([sys.executable,'-I','-B','-X','utf8',str(script),'--verify'],cwd=ROOT,capture_output=True,text=True,timeout=180);check.check_returncode();old_seals.append(dict(script=str(script),output=check.stdout.strip()))
load=json.loads((ROOT/'reports/parameter_load001.json').read_text());image=json.loads((ROOT/'assets/parameters002/manifest.json').read_text());build=(ROOT/'soc_full/build/full002/result.txt').read_text()
text=[
 'V0.22 第一阶段运行指南（此次温态板测已完成）',
 '当前板卡：V0.22易失PL保留；参数已提交在DRAM；本任务网关已安全停止并恢复缓存，A53#0已halt。',
 '当前board/run001已经停止，不能重用其START收据或直接重放START。再次测试须先确认板卡独占并开新受控会话。',
 '',
 '发布文件：',
 '  soc_full/build/full002/v022_full.bit（125MHz，USR_ACCESS=A51A2201）',
 '  ps/gateway_v022.elf（PS启动/完成/异常；CONV/FFN内部无PS数值命令及im2col）',
 '  assets/parameters002/parameters.bin + manifest.json（唯一部署镜像）',
 '  reports/release_full002.json（离线封存，保留当时hardware_tested=false，不篡改）',
 f'  reports/{tag}/board_release.json（此次真正完成板测的补充发布记录）',
 '  BOARD_RESULT.json / BOARD_RESULT_zh.txt（两次真实CASE、计时、正确性、数据路径）',
 '',
 '编码：'+report['encoding'],
 '位置P[J]表示有效数字的最低位所在二进制位置，不是最高位位置。存储字节多出的第7位用于偶校验。',
 '算术仍为W7p8/A16/C48，原始权重/scale/bias字节未改。新增8.14MB是PL计划/字节布局元数据，不是精度变化。',
 '',
 '运行环境：D:\\app\\ananconda\\envs\\asronnx312_int16\\python.exe，所有Python入口带 -B -X utf8。',
 '所有新建/修改/构建产物都在software4npu/temp/model_a_v0_22下；旧工程及旧封存文件只读。',
 '',
 '此次温态操作顺序（用于审计，不得绕过收据检查直接重放已完成会话）：',
 '  1. scripts/seal_runtime.py full002 --verify',
 '  2. scripts/program_warm_board.tcl run001 --board-released：仅接受已明确释放的A51A2070，检查CPU/DDR/矩阵/COPY/job均idle后替换易失PL。',
 '  3. scripts/control_board.tcl start run001 --board-released：下载A53 ELF，不执行PS复位/DDR初始化/时钟/MIO/启动介质写入。',
 '  4. scripts/run_logged.py parameter_load001 load --allow-hardware --board-receipt board/run001/started.txt',
 '  5. scripts/first_conv_smoke.py --allow-hardware --board-receipt board/run001/started.txt --out first_conv_board001',
 '  6. scripts/run_logged.py case0000_run001 run --out case0000_board001 --allow-hardware --board-receipt board/run001/started.txt',
 '  7. 同一参数generation再跑case0000_board002，参数不重载。',
 '  8. scripts/control_board.tcl stop run001 --board-released，验证排空、恢复缓存并halt。',
 f"此次参数独立装载{load['seconds']:.6f}s，写入/回读验证{load['image_bytes']}B；它不计入两次CASE运行。",
 'load与run分开；run禁止重装参数。adopt-existing只用于本版本同镜像且经过全CRC的保留数据，不能盲用另一版本DRAM。',
 '',
 '固定测试范围：CASE0000的128帧features及16个给定prefix token，encoder真实输出送decoder；非自由首token、非CTC/beam、非WER。',
 '第一阶段：68个CONV/FFN子图由PL计划执行；板内DDR数值和布局，中间量不绕PS/SRAM帧。',
 '外层DAG和591次旧矩阵队列仍在主机控制；整数矩阵A/W预取、C重叠回写仍是下一阶段。',
 'CPU浮点推理fallback=false；FP32/FMA/QDQ及整数矩阵实际在PL。',
 '与旧实板逐位一致不等于严格ONNX通过：encoder仍有2278/15872超阈值，最大偏差0.004179753363132477，和旧版相同。',
 '',
 '下一阶段建议优先减少外层中间张量往返，尤其embed CONV→Relu/QDQ→CONV与norm/softmax；',
 '矩阵PE仅0.34704384s/CASE，单纯提升PE主频或A/W预取不能同比降低约153.8s的主机墙钟耗时。',
 '整数矩阵DMA/缓存优化仍值得做，但要同时用算子计时和整链墙钟验证，不能用小算子速度冒充整链。',
 '',
 '这些入口是已审计的温态流程，不是通用冷启动部署器。若断电后PS/DDR未训练，应先做独立冷启动方案审计，禁止删检查强制复位。',
 ]
(ROOT/'RUN_PHASE1_zh.txt').write_text('\n'.join(text)+'\n',encoding='utf-8')
summary=dict(version='V0.22_phase1',hardware_tested=True,whole_case_runs=2,repeat_bit_exact=True,vs_v21_hardware_bit_exact=True,strict_onnx_encoder_pass=False,parameter_load_included=False,gateway_safely_stopped=True,ps_cache_restored=True,original_seals_verified=old_seals,arm_fp_arithmetic_instruction_matches=instructions,build=build,bit_sha256=release['bit_sha256'],elf_sha256=release['elf_sha256'],image_sha256=image['image_sha256'],parameter_load=load,final_status_log=str(out/'hardware_status.log'),comparison=report['vs_v211'],scope=report['scope'])
artifacts=[ROOT/'BOARD_RESULT.json',ROOT/'BOARD_RESULT_zh.txt',ROOT/'RUN_PHASE1_zh.txt',stopped,out/'hardware_status.log',ROOT/'reports/release_full002.json']
summary['evidence_sha256']={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in artifacts}
(out/'board_release.json').write_text(json.dumps(summary,indent=2,allow_nan=False)+'\n',encoding='utf-8');print('V022_PHASE1_REAL_BOARD_DELIVERY_PASS',json.dumps(summary['comparison']))
