`timescale 1ns/1ps
// fusion_c48_gearbox.sv
// Reassembles a contiguous 6-byte C48 tensor read back from DDR into 192-bit
// 4-value groups for the epilogue.
//
// This module exists only for the *unfused baseline*: the matrix stores C48 to
// DDR (6 bytes/value) and the baseline reads it back as 16-byte AXI beats.  LCM
// of 24-byte groups and 16-byte beats is 48 bytes (3 beats -> 2 groups), so a
// small streaming byte-packer is sufficient and no value is dropped.
//
// The fused top does NOT instantiate this module; it never writes or reads C48
// through DDR.
module fusion_c48_gearbox #(
  parameter integer GROUPS = 256          // 1024 C48 values per tile
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire         flush,
  input  wire         start,

  input  wire         in_valid,           // 128-bit read beat
  output wire         in_ready,
  input  wire [127:0] in_data,

  output wire         out_valid,
  input  wire         out_ready,
  output wire [191:0] out_data,
  output wire         out_last,

  output reg  [8:0]   group_count,
  output wire         done,
  output reg  [31:0]  stat_beats_in,
  output reg  [31:0]  stat_groups_out
);
  // 40-byte packing pkbuffer is enough: <=23B tail + 16B append = 39B.
  reg [319:0] pkbuf;
  reg [8:0]   nbytes;       // 0..39
  reg         g_valid;
  reg [191:0] g_data;
  reg         g_last;

  wire out_slot = !g_valid || out_ready;
  wire can_shift = out_slot && (nbytes >= 9'd24);
  wire take_beat = in_valid && in_ready;

  assign in_ready  = rst_n && !flush && out_slot && ((nbytes < 9'd24) || can_shift);
  assign out_valid = g_valid && !flush;
  assign out_data  = g_data;
  assign out_last  = g_last;
  assign done      = (group_count == GROUPS) && !g_valid;

  // combinational next pkbuffer: shift out one 24-byte group, then append beat
  wire [319:0] shifted = can_shift ? (pkbuf >> 192) : pkbuf;
  wire [8:0]   base_bytes = can_shift ? (nbytes - 9'd24) : nbytes;
  wire [319:0] appended = shifted | (take_beat ? ({192'd0, in_data} << (base_bytes * 8)) : 320'd0);
  wire [8:0]   appended_bytes = base_bytes + ((take_beat) ? 9'd16 : 9'd0);
  wire [191:0] shifted_group = pkbuf[191:0];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pkbuf <= 320'd0;
      nbytes <= 9'd0;
      g_valid <= 1'b0;
      g_data <= 192'd0;
      g_last <= 1'b0;
      group_count <= 9'd0;
      stat_beats_in <= 32'd0;
      stat_groups_out <= 32'd0;
    end else if (flush || start) begin
      pkbuf <= 320'd0;
      nbytes <= 9'd0;
      g_valid <= 1'b0;
      g_data <= 192'd0;
      g_last <= 1'b0;
      group_count <= 9'd0;
      if (start) begin
        stat_beats_in <= 32'd0;
        stat_groups_out <= 32'd0;
      end
    end else begin
      // consume the output register
      if (g_valid && out_ready) g_valid <= 1'b0;

      // emit one group whenever the pkbuffer holds >= 24 bytes and the output
      // slot is free (either empty now, or being consumed this cycle)
      if (can_shift) begin
        g_valid <= 1'b1;
        g_data  <= shifted_group;
        g_last  <= (group_count == (GROUPS-1));
        group_count <= group_count + 9'd1;
        stat_groups_out <= stat_groups_out + 32'd1;
      end

      // append the read beat after the shift
      pkbuf <= appended;
      nbytes <= appended_bytes;
      if (take_beat) stat_beats_in <= stat_beats_in + 32'd1;
    end
  end

endmodule
