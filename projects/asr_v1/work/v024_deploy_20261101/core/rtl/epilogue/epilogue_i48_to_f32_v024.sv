`timescale 1ns/1ps
// epilogue_i48_to_f32_v024.sv
// V0.24 per-channel extension: the I48->F32 stage also carries the per-beat
// scale/bias pair down the pipeline so the FMA stage sees the value that
// belongs to the same element, independent of stalls.  Arithmetic is the
// byte-identical packed RNE logic of the V0.23 primary candidate.
module epilogue_i48_to_f32_v024 #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire signed [47:0]    in_data,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,
    input  wire [31:0]           in_scale,
    input  wire [31:0]           in_bias,

    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [31:0]           out_data,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last,
    output wire [31:0]           out_scale,
    output wire [31:0]           out_bias
);

    reg                  s1_valid;
    wire                 s1_ready;
    reg                  s1_sign;
    reg [47:0]           s1_mag;
    reg [5:0]            s1_top;
    reg [TAG_WIDTH-1:0]  s1_tag;
    reg                  s1_last;
    reg [31:0]           s1_scale, s1_bias;

    wire [47:0] in_mag = in_data[47] ? (~in_data + 48'd1) : in_data;

    function automatic [5:0] find_top(input [47:0] m);
        integer i;
        reg [5:0] t;
        begin
            t = 6'd0;
            for (i = 0; i < 48; i = i + 1) begin
                if (m[i]) t = i[5:0];
            end
            find_top = t;
        end
    endfunction

    wire s1_fire = in_valid && in_ready;
    assign in_ready = !s1_valid || s1_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_sign  <= 1'b0;
            s1_mag   <= 48'd0;
            s1_top   <= 6'd0;
            s1_tag   <= {TAG_WIDTH{1'b0}};
            s1_last  <= 1'b0;
            s1_scale <= 32'h3f800000;
            s1_bias  <= 32'd0;
        end else if (flush) begin
            s1_valid <= 1'b0;
        end else if (in_ready) begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_sign <= in_data[47];
                s1_mag  <= in_mag;
                s1_top  <= find_top(in_mag);
                s1_tag  <= in_tag;
                s1_last <= in_last;
                s1_scale <= in_scale;
                s1_bias  <= in_bias;
            end
        end
    end

    reg                  s2_valid;
    reg [31:0]           s2_data;
    reg [TAG_WIDTH-1:0]  s2_tag;
    reg                  s2_last;
    reg [31:0]           s2_scale, s2_bias;

    assign s1_ready = !s2_valid || out_ready;
    assign out_valid = s2_valid;
    assign out_data  = s2_data;
    assign out_tag   = s2_tag;
    assign out_last  = s2_last;
    assign out_scale = s2_scale;
    assign out_bias  = s2_bias;

    function automatic [31:0] pack_float(
        input sign,
        input [47:0] mag,
        input [5:0] top
    );
        reg [26:0] sig;
        reg sticky;
        reg [5:0] sh;
        integer i;
        reg [7:0] exp;
        reg [22:0] mant;
        reg round_bit;
        begin
            if (mag == 48'd0) begin
                pack_float = 32'd0;
            end else begin
                sig = 27'd0;
                sticky = 1'b0;
                if (top > 6'd26) begin
                    sh = top - 6'd26;
                    sig = mag >> sh;
                    for (i = 0; i < 48; i = i + 1) begin
                        if (i < sh) sticky = sticky | mag[i];
                    end
                    sig[0] = sig[0] | sticky;
                end else begin
                    sig = mag << (6'd26 - top);
                end
                exp = 8'd127 + {2'b0, top};
                mant = sig[25:3];
                round_bit = sig[2];
                if (round_bit && ((sig[1:0] != 2'b00) || mant[0])) begin
                    mant = mant + 23'd1;
                    if (mant == 23'd0) exp = exp + 8'd1;
                end
                pack_float = {sign, exp, mant};
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_data  <= 32'd0;
            s2_tag   <= {TAG_WIDTH{1'b0}};
            s2_last  <= 1'b0;
            s2_scale <= 32'h3f800000;
            s2_bias  <= 32'd0;
        end else if (flush) begin
            s2_valid <= 1'b0;
        end else if (s1_ready) begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_data <= pack_float(s1_sign, s1_mag, s1_top);
                s2_tag  <= s1_tag;
                s2_last <= s1_last;
                s2_scale <= s1_scale;
                s2_bias  <= s1_bias;
            end
        end
    end

endmodule
