// 中文说明：直接把二进制原始输入和权重送给 HLS C 仿真；输出位模式供 Python 独立核对。
#include <fstream>
#include <iostream>
#include <ap_int.h>
#include <hls_stream.h>
void conformer_head(hls::stream<ap_uint<32>>&,hls::stream<ap_uint<32>>&);
int main(){
    std::ifstream file("input.bin",std::ios::binary);
    if(!file)return 1;
    hls::stream<ap_uint<32>> input,output;
    unsigned word;
    while(file.read(reinterpret_cast<char*>(&word),4))input.write(word);
    conformer_head(input,output);
    if(!input.empty()){std::cerr<<"input not exhausted";return 2;}
    std::ofstream out("csim_output.bin",std::ios::binary);
    unsigned count=0;
    while(!output.empty()){word=output.read().to_uint();out.write(reinterpret_cast<char*>(&word),4);++count;}
    std::cout<<"CSIM_DONE words="<<count<<std::endl;
    return 0;
}
