set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build fma_ip_002]
file mkdir $out
create_project fma_probe [file join $out project] -part xc7a35tfgg484-2
create_ip -name floating_point -vendor xilinx.com -library ip -version 7.1 -module_name asr_fma_ip
set_property -dict [list CONFIG.Operation_Type {FMA} CONFIG.Add_Sub_Value {Add} \
    CONFIG.A_Precision_Type {Single} CONFIG.Result_Precision_Type {Single} \
    CONFIG.C_Mult_Usage {Full_Usage} CONFIG.Flow_Control {NonBlocking} \
    CONFIG.Has_ARESETn {true} CONFIG.Maximum_Latency {false} CONFIG.C_Latency {12}] [get_ips asr_fma_ip]
report_property [get_ips asr_fma_ip] -file [file join $out properties.txt]
generate_target all [get_ips asr_fma_ip]
export_ip_user_files -of_objects [get_ips asr_fma_ip] -no_script -sync
puts "FMA_IP_GENERATED [get_property IP_FILE [get_ips asr_fma_ip]]"
