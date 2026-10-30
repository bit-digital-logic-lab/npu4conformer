# 集成变化
唯一新增端口 output [TAG_WIDTH-1:0] a16_packed_tag，表示packed beat第一半的tag。a16_tag始终表示A16寄存器当前beat。其余端口不变。
参数addr0=广播scale、addr1=广播bias，分别valid；addr>=2 ready=0。param_wr_ready只在idle且没有cfg_valid时为1。所有控制按valid&&ready握手，valid等待不阻止旧burst排空。
未预装的参数使用cfg值；预装值覆盖cfg，reset/abort清valid。无per-channel、无cfg_spill_fp32实现。两输出消费者独立，未使用通道ready置1。
接入前重跑本目录run_regression.py，冻结候选SHA；仅模块级通过。
