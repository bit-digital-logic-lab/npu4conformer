`timescale 1ns/1ps
// Two independent A16/W7 stage banks for true A/W double-buffer prefetch.
// Stage 0 and stage 1 each hold one complete 32x32 logical block.  A DMA beat
// (128b = 8 A16 of one row, or 16 W8 of one k-row half) is written into the
// stage selected by wr_stage, while the systolic array reads the *other*
// stage.  Storage owns the write port; compute owns the read port.
//
// A read is 16 independent per-row k addresses (the systolic skew is
// k = run_cycle-row), mapped to 16 small row banks.  W read is 16 independent
// per-column k addresses mapped to 16 column banks.  Both use distributed
// asynchronous read exactly like the V020 operand_banks; only the bank
// selection and DMA-friendly 128b write format are new.
module operand_banks_dual_v1(
 input wire clk,
 input wire wr_en,input wire wr_stage,input wire wr_kind,
 input wire [7:0] wr_beat,input wire [127:0] wr_data,
 input wire rd_stage,input wire rd_row_half,rd_col_half,
 input wire [79:0] a_k,input wire [79:0] w_k,
 output wire [255:0] a_values,output wire [111:0] w_values
);
 // A write: beat b (0..127) = row b[6:2], k-chunk b[1:0].  Each row bank holds
 // two rows (row[4]) and four 8-k chunks -> 8 x 128b per bank.
 wire [3:0] aw_rowbank=wr_beat[5:2];
 wire [2:0] aw_entry={wr_beat[6],wr_beat[1:0]};
 // W write: beat b (0..63) = k b[6:1], n-half b[0].  Each column bank holds
 // 2 n-halves x 32 k bytes.
 wire [4:0] ww_k=wr_beat[6:1];
 wire ww_half=wr_beat[0];

 genvar s,r,c;
 wire [255:0] a_stage_val[0:1];
 wire [111:0] w_stage_val[0:1];
 generate
  for(s=0;s<2;s=s+1)begin:astage
   (* ram_style="distributed" *) reg [127:0] mem[0:15][0:7];
   always @(posedge clk)
    if(wr_en&&wr_kind==1'b0&&wr_stage==s)mem[aw_rowbank][aw_entry]<=wr_data;
   for(r=0;r<16;r=r+1)begin:arow
    wire [4:0] kk=a_k[r*5+:5];
    wire [127:0] chunk=mem[r][{rd_row_half,kk[4:3]}];
    wire [15:0] value=chunk[kk[2:0]*16+:16];
    assign a_stage_val[s][r*16+:16]=value;
   end
  end
  for(s=0;s<2;s=s+1)begin:wstage
   (* ram_style="distributed" *) reg [7:0] mem[0:15][0:63];
   always @(posedge clk)
    if(wr_en&&wr_kind==1'b1&&wr_stage==s)begin
     for(integer q=0;q<16;q=q+1)mem[q][{ww_half,ww_k}]<=wr_data[q*8+:8];
    end
   for(c=0;c<16;c=c+1)begin:wcol
    wire [4:0] kk=w_k[c*5+:5];
    wire [7:0] value=mem[c][{rd_col_half,kk}];
    assign w_stage_val[s][c*7+:7]=value[6:0];
   end
  end
 endgenerate
 assign a_values=rd_stage?a_stage_val[1]:a_stage_val[0];
 assign w_values=rd_stage?w_stage_val[1]:w_stage_val[0];
endmodule
