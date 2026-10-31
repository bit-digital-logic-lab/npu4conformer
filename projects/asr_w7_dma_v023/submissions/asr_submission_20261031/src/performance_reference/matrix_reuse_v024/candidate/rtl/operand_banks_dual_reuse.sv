`timescale 1ns/1ps
// Two A16/W7 stage banks with independent A and W read-stage selects.
//
// v023 operand_banks_dual_v1 exposes one rd_stage for both A and W, so the
// array can only read A and W from the same stage index.  The 2x1 W-reuse
// schedule pins W(bk,bc) in one W bank while A(br) is replaced in the other
// A bank, therefore A and W need independent bank selects.
//
// Memory arrays and the DMA write format are unchanged from v023:
//   A stage: 16 row banks x 8 x 128b = 2048 B
//   W stage: 16 column banks x 64 x 8b = 1024 B
// Only the final 2:1 read muxes are duplicated (one for A, one for W).
module operand_banks_dual_reuse(
 input wire clk,
 input wire wr_en,input wire wr_stage,input wire wr_kind,
 input wire [7:0] wr_beat,input wire [127:0] wr_data,
 input wire rd_a_stage,input wire rd_w_stage,
 input wire rd_row_half,rd_col_half,
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
 assign a_values=rd_a_stage?a_stage_val[1]:a_stage_val[0];
 assign w_values=rd_w_stage?w_stage_val[1]:w_stage_val[0];
endmodule
