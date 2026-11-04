`timescale 1ns/1ps
// A matrix record fixes identity, shape, encoding and DDR base. Block shape is
// always 32x32. Padding is part of the storage representation, never a new tile.
module block_address_v020(
 input wire [31:0] base,
 input wire [15:0] rows,cols,block_row,block_col,
 input wire [1:0] encoding, // 0=A16, 1=W7p8, 2=INT48; 3 is unsupported
 output wire [31:0] address,
 output wire [15:0] valid_rows,valid_cols,
 output wire [39:0] extent_bytes,
 output wire valid
);
 wire [31:0] nrb=({16'd0,rows}+31)>>5;
 wire [31:0] ncb=({16'd0,cols}+31)>>5;
 wire [31:0] block_bytes=encoding==0?2048:encoding==1?1024:6144;
 wire [39:0] offset=(block_row*ncb+block_col)*block_bytes;
 wire [40:0] full={9'd0,base}+{1'b0,offset};
 assign extent_bytes=nrb*ncb*block_bytes;
 assign address=full[31:0];
 assign valid_rows=(rows-(block_row<<5))>=32?32:rows-(block_row<<5);
 assign valid_cols=(cols-(block_col<<5))>=32?32:cols-(block_col<<5);
 assign valid=rows!=0&&cols!=0&&encoding!=3&&block_row<nrb&&block_col<ncb&&full[40:32]==0;
endmodule
