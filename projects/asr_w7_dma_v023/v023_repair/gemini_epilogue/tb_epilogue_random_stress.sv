`timescale 1ns/1ps
module tb_epilogue_random_stress;
  localparam TAG_WIDTH = 16;
  reg clk, rst_n, abort;
  reg cfg_valid; wire cfg_ready;
  reg cval_valid; wire cval_ready;
  reg [191:0] cval_data; reg [TAG_WIDTH-1:0] cval_tag; reg cval_last;
  wire a16_valid; reg a16_ready;
  wire [63:0] a16_data; wire [TAG_WIDTH-1:0] a16_tag; wire a16_last;
  wire [127:0] a16_packed; wire a16_packed_valid; reg a16_packed_ready; wire a16_packed_last;
  wire spill_valid; reg spill_ready; wire [191:0] spill_data; wire [TAG_WIDTH-1:0] spill_tag; wire spill_last;
  wire [31:0] stat_c48_beats_in, stat_a16_beats_out, stat_spill_beats, stat_ddr_bytes_saved;

  epilogue_stream_engine_v023 #(.TAG_WIDTH(TAG_WIDTH)) dut (
    .clk(clk), .rst_n(rst_n), .abort(abort),
    .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
    .cfg_fma_mode(2'd0), .cfg_relu_en(1'b0), .cfg_spill_c48(1'b0), .cfg_spill_fp32(1'b0),
    .cfg_scale(32'h3f800000), .cfg_bias(32'h00000000), .cfg_tag(16'hb001),
    .param_wr_valid(1'b0), .param_wr_ready(), .param_wr_addr(8'd0), .param_wr_data(32'd0),
    .cval_valid(cval_valid), .cval_ready(cval_ready), .cval_data(cval_data),
    .cval_tag(cval_tag), .cval_last(cval_last),
    .a16_valid(a16_valid), .a16_ready(a16_ready), .a16_data(a16_data),
    .a16_packed(a16_packed), .a16_packed_valid(a16_packed_valid), .a16_packed_ready(a16_packed_ready),
    .a16_packed_last(a16_packed_last), .a16_tag(a16_tag), .a16_last(a16_last),
    .spill_valid(spill_valid), .spill_ready(spill_ready), .spill_data(spill_data),
    .spill_tag(spill_tag), .spill_last(spill_last),
    .stat_c48_beats_in(stat_c48_beats_in), .stat_a16_beats_out(stat_a16_beats_out),
    .stat_spill_beats(stat_spill_beats), .stat_ddr_bytes_saved(stat_ddr_bytes_saved)
  );

  initial clk = 0; always #4 clk = ~clk;
  integer match_count = 0;
  integer total_elements = 0;
  initial begin
    rst_n = 0; abort = 0; cfg_valid = 0; cval_valid = 0;
    a16_ready = 1; a16_packed_ready = 1; spill_ready = 1;
    #20 rst_n = 1; #20;
    @(posedge clk); cfg_valid <= 1; @(posedge clk); cfg_valid <= 0;
  end

  // Stimulus process
  initial begin
    #50;
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffffff, 48'h000000002ec7, 48'h00000000552f, 48'hffffffff989a}; cval_tag <= 16'h1000; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000001766, 48'hffffffbc07ac, 48'h000000000000, 48'h000000002f64}; cval_tag <= 16'h1001; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'hffffffff8000, 48'hffffffffdf7f, 48'hffffffffcf3d}; cval_tag <= 16'h1002; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h1be5056ecc88, 48'h9083d891f8d6, 48'hffffffc0c96d}; cval_tag <= 16'h1003; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'he4462b031a63, 48'h124dfce6d917, 48'h000000000000, 48'hfffffff4ffed}; cval_tag <= 16'h1004; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'he73c28fd87ec, 48'h000000000001, 48'h000000000000}; cval_tag <= 16'h1005; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h9ad85d1d082d, 48'h9ae185b73e90, 48'h000000000254, 48'hffffffffffff}; cval_tag <= 16'h1006; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h730002ebdba4, 48'h34aeaaf87b50, 48'h000000007fff, 48'hffffffffffff}; cval_tag <= 16'h1007; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000010000, 48'h0000004ab3ec, 48'h000000007fff, 48'hffffff8ec254}; cval_tag <= 16'h1008; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000001, 48'hffffffffffff, 48'h000000006b65, 48'h000000000000}; cval_tag <= 16'h1009; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007fff, 48'h2f7bd4b83760, 48'hffffff97b25d, 48'h000000000000}; cval_tag <= 16'h100a; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hf1e692c14b94, 48'h0000007d16d6, 48'hffffffffffff, 48'h000000551de1}; cval_tag <= 16'h100b; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h00000044f20c, 48'h000000000000, 48'h0000004b6f89, 48'he3851b514dd1}; cval_tag <= 16'h100c; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffff8bc1d2, 48'h000000005a3d, 48'hffffff8511ca, 48'h5c50dabf0754}; cval_tag <= 16'h100d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007fff, 48'h000000007afc, 48'h000000000000, 48'h000000000000}; cval_tag <= 16'h100e; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h5ac50798c969, 48'h000000010000, 48'hffffffb4d92a, 48'hffffff69d314}; cval_tag <= 16'h100f; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007fff, 48'h000000007fff, 48'hffffffff0000, 48'h773a9047689e}; cval_tag <= 16'h1010; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007010, 48'h000000000000, 48'hffffffbba4a7, 48'h000000000000}; cval_tag <= 16'h1011; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000003f5c03, 48'hffffffff8000, 48'hffffff768446, 48'hffffffe5d72e}; cval_tag <= 16'h1012; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000004908, 48'h000000010000, 48'h000000000000, 48'h000000007fff}; cval_tag <= 16'h1013; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffa408, 48'h000000000000, 48'h000000007463, 48'hbb45f71bfd10}; cval_tag <= 16'h1014; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hb32b24f9a125, 48'hffffffd6cdc0, 48'hffffffff0000, 48'hffffffff0000}; cval_tag <= 16'h1015; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffde81ba, 48'h00000078b6a8, 48'hfffffffff273, 48'h000000007fff}; cval_tag <= 16'h1016; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffc11a4d, 48'h25dc5d64e4ee, 48'hffffffe853c9, 48'hff76963ea860}; cval_tag <= 16'h1017; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffff866d2d, 48'hffffffd6e2eb, 48'hffffffffb56c, 48'h0000002bf996}; cval_tag <= 16'h1018; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff8000, 48'hffffffff8000, 48'h15bb18ab4edd, 48'h000000007fff}; cval_tag <= 16'h1019; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffd7b5, 48'hffffff860ba4, 48'h00000051d7ac, 48'h000000000000}; cval_tag <= 16'h101a; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000001, 48'h000000007fff, 48'h000000007fff, 48'hbe8f60044cfc}; cval_tag <= 16'h101b; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h000000548dce, 48'h000000000000, 48'h000000000000}; cval_tag <= 16'h101c; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007fff, 48'hffffffff8000, 48'hffffff76544e, 48'h3fc7a097abcf}; cval_tag <= 16'h101d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff0000, 48'h000000000000, 48'h000000909f99, 48'h000000000000}; cval_tag <= 16'h101e; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffff992487, 48'h000000000000, 48'h22c4d463c354, 48'h000000007fff}; cval_tag <= 16'h101f; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000074c8, 48'hffffffab0372, 48'hffffffffbe4d, 48'he6afdef5ca6d}; cval_tag <= 16'h1020; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h41adfb6329f0, 48'h000000000000, 48'h000000000000, 48'h000000000000}; cval_tag <= 16'h1021; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000033ba, 48'hffffffff0000, 48'h00000073b472, 48'h000000007fff}; cval_tag <= 16'h1022; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000002682, 48'h000000007fff, 48'h4fc44f01ed53, 48'hffffffff8000}; cval_tag <= 16'h1023; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h000000006a19, 48'h7a20ad601713, 48'hfffffffff3bc}; cval_tag <= 16'h1024; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'hffffff81544b, 48'ha832d355cd7f, 48'h4dc8faf80191}; cval_tag <= 16'h1025; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000008e8310, 48'h000000019771, 48'h000000000000, 48'h3d65bffc315d}; cval_tag <= 16'h1026; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffaf3e, 48'h0000001030dc, 48'hdc54c7ce75e9, 48'h831f77c274b0}; cval_tag <= 16'h1027; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hd668c363bf8e, 48'hffffffffe57e, 48'hffffffffffff, 48'h000000000000}; cval_tag <= 16'h1028; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffa7eb55, 48'h0a9bf5456aa4, 48'h000000005cba, 48'h000000653cb6}; cval_tag <= 16'h1029; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h00000089e59d, 48'hffffffffa677, 48'hffffffff9051, 48'hffffffffb0df}; cval_tag <= 16'h102a; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfffffffffccf, 48'hffffff7a40e4, 48'h000000000001, 48'hf26532919374}; cval_tag <= 16'h102b; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffa54e04, 48'h0000006be9f7, 48'hffffffff84ca, 48'h2ba43cd92564}; cval_tag <= 16'h102c; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hb586da2f5225, 48'h000000004026, 48'h2969910a529f, 48'h000000010000}; cval_tag <= 16'h102d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hc71c6c55204a, 48'h000000000000, 48'hffffffcf0432, 48'h000000000001}; cval_tag <= 16'h102e; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h226d88ea34d6, 48'h000000439c8c, 48'h000000000001, 48'h000000524af1}; cval_tag <= 16'h102f; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'haacb651cb6a3, 48'hffffffffbba3, 48'h9079f22b147e, 48'hfffffff6aadc}; cval_tag <= 16'h1030; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff0000, 48'h000000000000, 48'h00000045f855, 48'h000000007fff}; cval_tag <= 16'h1031; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h95e32a611f74, 48'heb1e404b01cd, 48'h000000010000, 48'h000000000aa2}; cval_tag <= 16'h1032; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h000000007fff, 48'h000000000000, 48'h000000007fff}; cval_tag <= 16'h1033; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffd112d4, 48'h000000010000, 48'h0000008a73ff, 48'hb519c962e26e}; cval_tag <= 16'h1034; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfffffffff61a, 48'h55b990d3222f, 48'hffffffff0000, 48'h000000000000}; cval_tag <= 16'h1035; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h26f06f452b29, 48'h000000965ef5, 48'h6c9e23ad32fb, 48'hffffffff0000}; cval_tag <= 16'h1036; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h0000002a3bf2, 48'hfffffffef9da, 48'hffffff9fda27}; cval_tag <= 16'h1037; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfffffffcc555, 48'h00000000439c, 48'h000000000000, 48'h000000010000}; cval_tag <= 16'h1038; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000001f92c3, 48'h0000000049ee, 48'h000000010000, 48'h9905018ef9d7}; cval_tag <= 16'h1039; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007737, 48'h000000000000, 48'h000000007fff, 48'h000000001407}; cval_tag <= 16'h103a; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'hfffffff9f76d, 48'h00000000234a, 48'h23278a4dcc11}; cval_tag <= 16'h103b; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000002a75, 48'hffffffff8000, 48'h158ef6829d42, 48'h000000000462}; cval_tag <= 16'h103c; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000027bd, 48'h000000000000, 48'hffffffff842b, 48'hffffffffc74e}; cval_tag <= 16'h103d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000810448, 48'h000000492d8c, 48'hffffffbf857b, 48'hffffffde8ea0}; cval_tag <= 16'h103e; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffc3ad28, 48'h7a150766615f, 48'hffffffffffff, 48'h0000004cf24d}; cval_tag <= 16'h103f; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffd19229, 48'hac5ccc134964, 48'h000000000000, 48'hffffffffc97d}; cval_tag <= 16'h1040; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfffffff1c8e4, 48'h000000010000, 48'h000000000000, 48'hffffffff8000}; cval_tag <= 16'h1041; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff92b1, 48'hffffffff8000, 48'hfffffffffb7d, 48'h000000003e97}; cval_tag <= 16'h1042; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000010000, 48'hffffffffffff, 48'h000000000000, 48'h000000007fff}; cval_tag <= 16'h1043; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfb310bc2b39a, 48'h000000000000, 48'hffffff9a3ea8, 48'hffffffff96a4}; cval_tag <= 16'h1044; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffffff, 48'h9e2c7e758938, 48'hfb2e6fed71f1, 48'h685d9d1d68b0}; cval_tag <= 16'h1045; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h996585043593, 48'h000000000000, 48'hcf35d9c994df, 48'h1945298afaf4}; cval_tag <= 16'h1046; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h1d1c82a402b2, 48'h000000007fff, 48'hffffff876f34}; cval_tag <= 16'h1047; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hfffffffff0a4, 48'hffffffffffff, 48'h000000000000, 48'hffffffffa5c1}; cval_tag <= 16'h1048; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000001, 48'h0000004f0afb, 48'h000000000000, 48'hf84fc87c0217}; cval_tag <= 16'h1049; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h115195d54d0c, 48'hd210ec5328c6, 48'h38e63718bd36}; cval_tag <= 16'h104a; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hc8a7723cf8e2, 48'h000000010000, 48'h0000000029ec, 48'h000000010000}; cval_tag <= 16'h104b; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h9de05b4b1975, 48'hf6c3279db395, 48'h000000000000, 48'hffffffffdd19}; cval_tag <= 16'h104c; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000278ae4, 48'h00000080b000, 48'hd88bc5353697, 48'h000000000001}; cval_tag <= 16'h104d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h2c2fa8fc0c27, 48'h42ad6dae7fde, 48'hffffffef6a1a, 48'h00000061e611}; cval_tag <= 16'h104e; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h55f3bb306c45, 48'hffffffffffff, 48'h0000009852fd, 48'h000000671579}; cval_tag <= 16'h104f; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h578d12526cdf, 48'h000000000000, 48'h000000000000, 48'hffffffffb820}; cval_tag <= 16'h1050; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffe4a0, 48'hffffffff0000, 48'hffffff8fc6c7, 48'hffffffc6abf3}; cval_tag <= 16'h1051; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000007700, 48'h3ccac6a44dcc, 48'hffffffb8ab13, 48'hffffffffd704}; cval_tag <= 16'h1052; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff0000, 48'h000000000000, 48'h000000010000, 48'h000000000000}; cval_tag <= 16'h1053; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000009ad, 48'h000000000001, 48'h000000010000, 48'h000000007fff}; cval_tag <= 16'h1054; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000006653, 48'h000000010000, 48'h000000010000, 48'h000000000000}; cval_tag <= 16'h1055; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000010000, 48'h000000001776, 48'h000000000000, 48'h8407d725112a}; cval_tag <= 16'h1056; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000001, 48'hffffffff0000, 48'hfffffffffed4, 48'h000000000000}; cval_tag <= 16'h1057; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffba31cb, 48'h000000000000, 48'h00000083c8b1, 48'h05d22197ae2a}; cval_tag <= 16'h1058; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000002f1cef, 48'h00000002292a, 48'hffffffffffff, 48'hffffffd4e1d9}; cval_tag <= 16'h1059; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h000000000000, 48'h000000000001, 48'h000000000000}; cval_tag <= 16'h105a; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffc223, 48'hfffffffff61f, 48'hffffffff8000, 48'h919acb3e1e8c}; cval_tag <= 16'h105b; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000034bf, 48'h000000336381, 48'h000000000000, 48'h000000007d7a}; cval_tag <= 16'h105c; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffffab49, 48'h000000000000, 48'h000000007fff, 48'h000000007fff}; cval_tag <= 16'h105d; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffff0000, 48'hffffffffc7f4, 48'h000000000000, 48'h000000620241}; cval_tag <= 16'h105e; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h0000000043bd, 48'he41a7051d580, 48'hffffffec8233, 48'h547ddbc90f27}; cval_tag <= 16'h105f; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hd0e1d939876a, 48'hbcaf2f3252c4, 48'h000000000000, 48'h000000000000}; cval_tag <= 16'h1060; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000010000, 48'h000000000000, 48'h000000006fc6, 48'h8312f9767bb4}; cval_tag <= 16'h1061; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'hffffffa0417e, 48'h000000004fc0, 48'h000000000000, 48'h000000000000}; cval_tag <= 16'h1062; cval_last <= 1'b0;
    while (!cval_ready) @(posedge clk);
    @(posedge clk);
    cval_valid <= 1'b1; cval_data <= {48'h000000000000, 48'h9467a5f4ed65, 48'hffffffffdb70, 48'hffffff9fe571}; cval_tag <= 16'h1063; cval_last <= 1'b1;
    while (!cval_ready) @(posedge clk);
    @(posedge clk); cval_valid <= 1'b0; cval_last <= 1'b0;
  end

  // Checking process
  initial begin
    #50;
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hffff, 16'h2ec7, 16'h552f, 16'h989a}) begin
      $display("STRESS MISMATCH batch 0: got=%h, exp={16'hffff, 16'h2ec7, 16'h552f, 16'h989a}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h1766, 16'h8000, 16'h0000, 16'h2f64}) begin
      $display("STRESS MISMATCH batch 1: got=%h, exp={16'h1766, 16'h8000, 16'h0000, 16'h2f64}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h8000, 16'hdf7f, 16'hcf3d}) begin
      $display("STRESS MISMATCH batch 2: got=%h, exp={16'h0000, 16'h8000, 16'hdf7f, 16'hcf3d}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 3: got=%h, exp={16'h0000, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h0000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 4: got=%h, exp={16'h8000, 16'h7fff, 16'h0000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h8000, 16'h0001, 16'h0000}) begin
      $display("STRESS MISMATCH batch 5: got=%h, exp={16'h0000, 16'h8000, 16'h0001, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h0254, 16'hffff}) begin
      $display("STRESS MISMATCH batch 6: got=%h, exp={16'h8000, 16'h8000, 16'h0254, 16'hffff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h7fff, 16'hffff}) begin
      $display("STRESS MISMATCH batch 7: got=%h, exp={16'h7fff, 16'h7fff, 16'h7fff, 16'hffff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 8: got=%h, exp={16'h7fff, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0001, 16'hffff, 16'h6b65, 16'h0000}) begin
      $display("STRESS MISMATCH batch 9: got=%h, exp={16'h0001, 16'hffff, 16'h6b65, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 10: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'hffff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 11: got=%h, exp={16'h8000, 16'h7fff, 16'hffff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h0000, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 12: got=%h, exp={16'h7fff, 16'h0000, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h5a3d, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 13: got=%h, exp={16'h8000, 16'h5a3d, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7afc, 16'h0000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 14: got=%h, exp={16'h7fff, 16'h7afc, 16'h0000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 15: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 16: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7010, 16'h0000, 16'h8000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 17: got=%h, exp={16'h7010, 16'h0000, 16'h8000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h8000, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 18: got=%h, exp={16'h7fff, 16'h8000, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h4908, 16'h7fff, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 19: got=%h, exp={16'h4908, 16'h7fff, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'ha408, 16'h0000, 16'h7463, 16'h8000}) begin
      $display("STRESS MISMATCH batch 20: got=%h, exp={16'ha408, 16'h0000, 16'h7463, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 21: got=%h, exp={16'h8000, 16'h8000, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'hf273, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 22: got=%h, exp={16'h8000, 16'h7fff, 16'hf273, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 23: got=%h, exp={16'h8000, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'hb56c, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 24: got=%h, exp={16'h8000, 16'h8000, 16'hb56c, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 25: got=%h, exp={16'h8000, 16'h8000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hd7b5, 16'h8000, 16'h7fff, 16'h0000}) begin
      $display("STRESS MISMATCH batch 26: got=%h, exp={16'hd7b5, 16'h8000, 16'h7fff, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0001, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 27: got=%h, exp={16'h0001, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h0000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 28: got=%h, exp={16'h0000, 16'h7fff, 16'h0000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h8000, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 29: got=%h, exp={16'h7fff, 16'h8000, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h7fff, 16'h0000}) begin
      $display("STRESS MISMATCH batch 30: got=%h, exp={16'h8000, 16'h0000, 16'h7fff, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 31: got=%h, exp={16'h8000, 16'h0000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h74c8, 16'h8000, 16'hbe4d, 16'h8000}) begin
      $display("STRESS MISMATCH batch 32: got=%h, exp={16'h74c8, 16'h8000, 16'hbe4d, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h0000, 16'h0000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 33: got=%h, exp={16'h7fff, 16'h0000, 16'h0000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h33ba, 16'h8000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 34: got=%h, exp={16'h33ba, 16'h8000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h2682, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 35: got=%h, exp={16'h2682, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h6a19, 16'h7fff, 16'hf3bc}) begin
      $display("STRESS MISMATCH batch 36: got=%h, exp={16'h0000, 16'h6a19, 16'h7fff, 16'hf3bc}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h8000, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 37: got=%h, exp={16'h0000, 16'h8000, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 38: got=%h, exp={16'h7fff, 16'h7fff, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'haf3e, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 39: got=%h, exp={16'haf3e, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'he57e, 16'hffff, 16'h0000}) begin
      $display("STRESS MISMATCH batch 40: got=%h, exp={16'h8000, 16'he57e, 16'hffff, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h5cba, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 41: got=%h, exp={16'h8000, 16'h7fff, 16'h5cba, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'ha677, 16'h9051, 16'hb0df}) begin
      $display("STRESS MISMATCH batch 42: got=%h, exp={16'h7fff, 16'ha677, 16'h9051, 16'hb0df}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hfccf, 16'h8000, 16'h0001, 16'h8000}) begin
      $display("STRESS MISMATCH batch 43: got=%h, exp={16'hfccf, 16'h8000, 16'h0001, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h84ca, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 44: got=%h, exp={16'h8000, 16'h7fff, 16'h84ca, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h4026, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 45: got=%h, exp={16'h8000, 16'h4026, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h8000, 16'h0001}) begin
      $display("STRESS MISMATCH batch 46: got=%h, exp={16'h8000, 16'h0000, 16'h8000, 16'h0001}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h0001, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 47: got=%h, exp={16'h7fff, 16'h7fff, 16'h0001, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'hbba3, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 48: got=%h, exp={16'h8000, 16'hbba3, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 49: got=%h, exp={16'h8000, 16'h0000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h7fff, 16'h0aa2}) begin
      $display("STRESS MISMATCH batch 50: got=%h, exp={16'h8000, 16'h8000, 16'h7fff, 16'h0aa2}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 51: got=%h, exp={16'h0000, 16'h7fff, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 52: got=%h, exp={16'h8000, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hf61a, 16'h7fff, 16'h8000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 53: got=%h, exp={16'hf61a, 16'h7fff, 16'h8000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 54: got=%h, exp={16'h7fff, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 55: got=%h, exp={16'h0000, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h439c, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 56: got=%h, exp={16'h8000, 16'h439c, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h49ee, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 57: got=%h, exp={16'h7fff, 16'h49ee, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7737, 16'h0000, 16'h7fff, 16'h1407}) begin
      $display("STRESS MISMATCH batch 58: got=%h, exp={16'h7737, 16'h0000, 16'h7fff, 16'h1407}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h8000, 16'h234a, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 59: got=%h, exp={16'h0000, 16'h8000, 16'h234a, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h2a75, 16'h8000, 16'h7fff, 16'h0462}) begin
      $display("STRESS MISMATCH batch 60: got=%h, exp={16'h2a75, 16'h8000, 16'h7fff, 16'h0462}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h27bd, 16'h0000, 16'h842b, 16'hc74e}) begin
      $display("STRESS MISMATCH batch 61: got=%h, exp={16'h27bd, 16'h0000, 16'h842b, 16'hc74e}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 62: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'hffff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 63: got=%h, exp={16'h8000, 16'h7fff, 16'hffff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h0000, 16'hc97d}) begin
      $display("STRESS MISMATCH batch 64: got=%h, exp={16'h8000, 16'h8000, 16'h0000, 16'hc97d}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h0000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 65: got=%h, exp={16'h8000, 16'h7fff, 16'h0000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h92b1, 16'h8000, 16'hfb7d, 16'h3e97}) begin
      $display("STRESS MISMATCH batch 66: got=%h, exp={16'h92b1, 16'h8000, 16'hfb7d, 16'h3e97}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'hffff, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 67: got=%h, exp={16'h7fff, 16'hffff, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h8000, 16'h96a4}) begin
      $display("STRESS MISMATCH batch 68: got=%h, exp={16'h8000, 16'h0000, 16'h8000, 16'h96a4}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hffff, 16'h8000, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 69: got=%h, exp={16'hffff, 16'h8000, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 70: got=%h, exp={16'h8000, 16'h0000, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h7fff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 71: got=%h, exp={16'h0000, 16'h7fff, 16'h7fff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hf0a4, 16'hffff, 16'h0000, 16'ha5c1}) begin
      $display("STRESS MISMATCH batch 72: got=%h, exp={16'hf0a4, 16'hffff, 16'h0000, 16'ha5c1}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0001, 16'h7fff, 16'h0000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 73: got=%h, exp={16'h0001, 16'h7fff, 16'h0000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h7fff, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 74: got=%h, exp={16'h0000, 16'h7fff, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h7fff, 16'h29ec, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 75: got=%h, exp={16'h8000, 16'h7fff, 16'h29ec, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h0000, 16'hdd19}) begin
      $display("STRESS MISMATCH batch 76: got=%h, exp={16'h8000, 16'h8000, 16'h0000, 16'hdd19}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h0001}) begin
      $display("STRESS MISMATCH batch 77: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h0001}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 78: got=%h, exp={16'h7fff, 16'h7fff, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'hffff, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 79: got=%h, exp={16'h7fff, 16'hffff, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h0000, 16'h0000, 16'hb820}) begin
      $display("STRESS MISMATCH batch 80: got=%h, exp={16'h7fff, 16'h0000, 16'h0000, 16'hb820}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'he4a0, 16'h8000, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 81: got=%h, exp={16'he4a0, 16'h8000, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7700, 16'h7fff, 16'h8000, 16'hd704}) begin
      $display("STRESS MISMATCH batch 82: got=%h, exp={16'h7700, 16'h7fff, 16'h8000, 16'hd704}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h7fff, 16'h0000}) begin
      $display("STRESS MISMATCH batch 83: got=%h, exp={16'h8000, 16'h0000, 16'h7fff, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h09ad, 16'h0001, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 84: got=%h, exp={16'h09ad, 16'h0001, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h6653, 16'h7fff, 16'h7fff, 16'h0000}) begin
      $display("STRESS MISMATCH batch 85: got=%h, exp={16'h6653, 16'h7fff, 16'h7fff, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h1776, 16'h0000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 86: got=%h, exp={16'h7fff, 16'h1776, 16'h0000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0001, 16'h8000, 16'hfed4, 16'h0000}) begin
      $display("STRESS MISMATCH batch 87: got=%h, exp={16'h0001, 16'h8000, 16'hfed4, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h0000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 88: got=%h, exp={16'h8000, 16'h0000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h7fff, 16'hffff, 16'h8000}) begin
      $display("STRESS MISMATCH batch 89: got=%h, exp={16'h7fff, 16'h7fff, 16'hffff, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h0000, 16'h0001, 16'h0000}) begin
      $display("STRESS MISMATCH batch 90: got=%h, exp={16'h0000, 16'h0000, 16'h0001, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hc223, 16'hf61f, 16'h8000, 16'h8000}) begin
      $display("STRESS MISMATCH batch 91: got=%h, exp={16'hc223, 16'hf61f, 16'h8000, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h34bf, 16'h7fff, 16'h0000, 16'h7d7a}) begin
      $display("STRESS MISMATCH batch 92: got=%h, exp={16'h34bf, 16'h7fff, 16'h0000, 16'h7d7a}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'hab49, 16'h0000, 16'h7fff, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 93: got=%h, exp={16'hab49, 16'h0000, 16'h7fff, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'hc7f4, 16'h0000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 94: got=%h, exp={16'h8000, 16'hc7f4, 16'h0000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h43bd, 16'h8000, 16'h8000, 16'h7fff}) begin
      $display("STRESS MISMATCH batch 95: got=%h, exp={16'h43bd, 16'h8000, 16'h8000, 16'h7fff}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h8000, 16'h0000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 96: got=%h, exp={16'h8000, 16'h8000, 16'h0000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h7fff, 16'h0000, 16'h6fc6, 16'h8000}) begin
      $display("STRESS MISMATCH batch 97: got=%h, exp={16'h7fff, 16'h0000, 16'h6fc6, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h8000, 16'h4fc0, 16'h0000, 16'h0000}) begin
      $display("STRESS MISMATCH batch 98: got=%h, exp={16'h8000, 16'h4fc0, 16'h0000, 16'h0000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    @(posedge clk);
    while (!a16_valid) @(posedge clk);
    if (a16_data !== {16'h0000, 16'h8000, 16'hdb70, 16'h8000}) begin
      $display("STRESS MISMATCH batch 99: got=%h, exp={16'h0000, 16'h8000, 16'hdb70, 16'h8000}", a16_data);
      $fatal(1);
    end else begin
      match_count = match_count + 4;
    end
    #50;
    $display("STRESS TEST COMPLETE: %0d / %0d elements matched golden bit-exactly!", match_count, match_count);
    $finish;
  end
endmodule