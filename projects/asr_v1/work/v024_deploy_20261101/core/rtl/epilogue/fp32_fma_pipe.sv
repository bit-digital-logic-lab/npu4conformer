`timescale 1ns/1ps
// fp32_fma_pipe.sv  (V0.24 deep-pipeline variant)
//
// IEEE-754 binary32 fused multiply-add, single rounding (RNE), FTZ.
// Evaluates: result = (a * b) + c
//
// This is a *retimed* derivative of the trusted gemini_fma_round2 unit
// (SHA-256 1ed8801a4536ad79c385b90033d5dbd76ad58eed04288a7c500a26e0a740ab12).
// The arithmetic datapath and all special-value rules are preserved bit for
// bit.  The former 4-stage split is re-partitioned into 7 register stages so
// that no single stage carries a multiply + 129-bit align + 129-bit add, or a
// 129-bit linear leading-zero priority, or normalize + round + pack together.
//
// Stage map (combinational work *before* each register bank):
//   S1 : unpack / FTZ / special detect / 24x24 multiply / exponent add
//   S2 : product normalize + dominant-operand select + shift / exp_base calc
//   S3 : 128-bit right alignment shift + shifted-out sticky OR tree
//   S4 : 129-bit add/sub with sticky-borrow injection
//   S5 : grouped/tree leading-zero count of the 129-bit accumulator
//   S6 : normalization shift + 24-bit mantissa / round / sticky / exponent
//   S7 : RNE round-up + overflow-underflow FTZ + special/zero/bypass mux
//
// Throughput is still II=1; latency is 7 cycles.  Full valid/ready
// backpressure, tag/last tracking and synchronous flush are preserved.
// AR-001 repair: while flush (or reset) is asserted, in_ready and out_valid
// are forced low, so no element is silently accepted and discarded and the
// flush cycle itself never presents a downstream transfer.
//
// NOTE: this file deliberately makes no timing (ns / MHz) claim.  Only local
// logic simulation is performed by this task.

module fp32_fma_pipe #(
    parameter TAG_WIDTH = 16
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  flush,

    // Upstream handshake & operands
    input  wire                  in_valid,
    output wire                  in_ready,
    input  wire [31:0]           in_a,
    input  wire [31:0]           in_b,
    input  wire [31:0]           in_c,
    input  wire [TAG_WIDTH-1:0]  in_tag,
    input  wire                  in_last,

    // Downstream handshake & result
    output wire                  out_valid,
    input  wire                  out_ready,
    output wire [31:0]           out_result,
    output wire [TAG_WIDTH-1:0]  out_tag,
    output wire                  out_last
);

    // =========================================================================
    // Handshake chain (7 stages, elastic)
    // =========================================================================
    reg  s1_valid, s2_valid, s3_valid, s4_valid, s5_valid, s6_valid, s7_valid;

    wire s7_ready = !s7_valid || out_ready;
    wire s6_ready = !s6_valid || s7_ready;
    wire s5_ready = !s5_valid || s6_ready;
    wire s4_ready = !s4_valid || s5_ready;
    wire s3_ready = !s3_valid || s4_ready;
    wire s2_ready = !s2_valid || s3_ready;
    wire s1_ready = !s1_valid || s2_ready;

    // AR-001 minimal handshake repair (logic unchanged elsewhere):
    //   * flush is a full barrier: in_ready=0 while flush=1, so an upstream
    //     element offered during flush is never reported as transferred.
    //   * out_valid=0 on the flush cycle: flush explicitly cancels the
    //     current-cycle output beat (including a result parked in S7).
    //   * reset is also a barrier: no transfer is recognised while rst_n=0.
    // The flop reset style stays asynchronous-assert / synchronous-release.
    assign in_ready  = rst_n && !flush && s1_ready;
    assign out_valid = rst_n && !flush && s7_valid;

    // =========================================================================
    // Grouped / tree leading-one detector
    // 129 bits are split into 9 groups of 16 bits (group 8 = bit 128 only).
    // Group selection is a 9-entry priority (small), and the within-group
    // search is a 16-bit tree (lzc16 -> two lzc8 halves).  This avoids the
    // 129-deep linear priority chain of the original find_msb().
    // =========================================================================
    function automatic [2:0] lzc8(input [7:0] w);
        reg [2:0] r;
        begin
            if (w[7:4] != 4'd0) begin
                casez (w[7:4])
                    4'b1???: r = 3'd0;
                    4'b01??: r = 3'd1;
                    4'b001?: r = 3'd2;
                    default: r = 3'd3;   // 4'b0001
                endcase
            end else begin
                casez (w[3:0])
                    4'b1???: r = 3'd4;
                    4'b01??: r = 3'd5;
                    4'b001?: r = 3'd6;
                    default: r = 3'd7;   // 4'b0001 or 0000
                endcase
            end
            lzc8 = r;
        end
    endfunction

    function automatic [3:0] lzc16(input [15:0] w);
        begin
            if (w[15:8] != 8'd0)
                lzc16 = {1'b0, lzc8(w[15:8])};
            else
                lzc16 = 4'd8 + {1'b0, lzc8(w[7:0])};
        end
    endfunction

    function automatic [7:0] msb129(input [128:0] v);
        reg [8:0]  gv;
        reg [3:0]  gsel;
        reg [15:0] gword;
        reg [3:0]  lz;
        begin
            gv[0] = |v[15:0];
            gv[1] = |v[31:16];
            gv[2] = |v[47:32];
            gv[3] = |v[63:48];
            gv[4] = |v[79:64];
            gv[5] = |v[95:80];
            gv[6] = |v[111:96];
            gv[7] = |v[127:112];
            gv[8] =  v[128];

            // 9-entry priority: highest non-empty group wins.
            if      (gv[8]) gsel = 4'd8;
            else if (gv[7]) gsel = 4'd7;
            else if (gv[6]) gsel = 4'd6;
            else if (gv[5]) gsel = 4'd5;
            else if (gv[4]) gsel = 4'd4;
            else if (gv[3]) gsel = 4'd3;
            else if (gv[2]) gsel = 4'd2;
            else if (gv[1]) gsel = 4'd1;
            else            gsel = 4'd0;

            case (gsel)
                4'd0: gword = v[15:0];
                4'd1: gword = v[31:16];
                4'd2: gword = v[47:32];
                4'd3: gword = v[63:48];
                4'd4: gword = v[79:64];
                4'd5: gword = v[95:80];
                4'd6: gword = v[111:96];
                4'd7: gword = v[127:112];
                default: gword = {15'd0, v[128]};
            endcase

            lz = lzc16(gword);                    // 0..15 leading zeros in group
            // msb = gsel*16 + (15 - lz)
            msb129 = {gsel, 4'b0000} + {4'd0, (4'd15 - lz)};
        end
    endfunction

    // =========================================================================
    // S1 register boundary: decode, FTZ, specials, 24x24 multiply
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s1_tag;
    reg                  s1_last;

    reg                  s1_is_nan;
    reg                  s1_is_inf;
    reg                  s1_special_sign;
    reg                  s1_is_zero;      // product and addend both FTZ-zero
    reg                  s1_bypass_c;     // product is FTZ-zero -> return c

    reg [31:0]           s1_c_raw;
    reg [47:0]           s1_c_norm;       // addend signif, MSB at bit47
    reg [47:0]           s1_prod;         // 24x24 raw product
    reg signed [9:0]     s1_exp_p;        // raw product exponent
    reg signed [9:0]     s1_exp_c;        // raw addend exponent
    reg                  s1_sign_p;
    reg                  s1_sign_c;
    reg                  s1_zero_c;       // addend is FTZ-zero

    // Combinational decode of the current input
    wire        sa = in_a[31];
    wire        sb = in_b[31];
    wire        sc = in_c[31];
    wire [7:0]  ea = in_a[30:23];
    wire [7:0]  eb = in_b[30:23];
    wire [7:0]  ec = in_c[30:23];
    wire [22:0] ma = in_a[22:0];
    wire [22:0] mb = in_b[22:0];
    wire [22:0] mc = in_c[22:0];

    wire is_nan_a = (&ea) && (|ma);
    wire is_nan_b = (&eb) && (|mb);
    wire is_nan_c = (&ec) && (|mc);

    wire is_inf_a = (&ea) && (ma == 23'd0);
    wire is_inf_b = (&eb) && (mb == 23'd0);
    wire is_inf_c = (&ec) && (mc == 23'd0);

    wire is_zero_a = (ea == 8'd0);   // FTZ
    wire is_zero_b = (eb == 8'd0);   // FTZ
    wire is_zero_c = (ec == 8'd0);   // FTZ

    wire sign_p   = sa ^ sb;
    wire is_inf_p = is_inf_a || is_inf_b;
    wire is_zero_p = is_zero_a || is_zero_b;

    wire inf_zero_prod = (is_inf_a && (in_b[30:0] == 31'd0)) ||
                         (is_inf_b && (in_a[30:0] == 31'd0));
    wire inf_sub_inf   = is_inf_p && is_inf_c && (sign_p != sc);

    wire comb_is_nan = is_nan_a || is_nan_b || is_nan_c ||
                       inf_zero_prod || inf_sub_inf;
    wire comb_is_inf = !comb_is_nan && (is_inf_p || is_inf_c);
    wire comb_inf_sign = is_inf_p ? sign_p : sc;

    wire [23:0] mant_a = {1'b1, ma};
    wire [23:0] mant_b = {1'b1, mb};
    wire [23:0] mant_c = is_zero_c ? 24'd0 : {1'b1, mc};

    wire [47:0] raw_prod = mant_a * mant_b;
    wire signed [9:0] raw_exp_p = $signed({2'b0, ea}) + $signed({2'b0, eb}) - 10'sd127;
    wire signed [9:0] raw_exp_c = $signed({2'b0, ec});

    wire [47:0] c_norm_comb = {mant_c, 24'd0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid        <= 1'b0;
            s1_tag          <= {TAG_WIDTH{1'b0}};
            s1_last         <= 1'b0;
            s1_is_nan       <= 1'b0;
            s1_is_inf       <= 1'b0;
            s1_special_sign <= 1'b0;
            s1_is_zero      <= 1'b0;
            s1_bypass_c     <= 1'b0;
            s1_c_raw        <= 32'd0;
            s1_c_norm       <= 48'd0;
            s1_prod         <= 48'd0;
            s1_exp_p        <= 10'sd0;
            s1_exp_c        <= 10'sd0;
            s1_sign_p       <= 1'b0;
            s1_sign_c       <= 1'b0;
            s1_zero_c       <= 1'b0;
        end else if (flush) begin
            s1_valid <= 1'b0;
        end else if (s1_ready) begin
            s1_valid <= in_valid;
            if (in_valid) begin
                s1_tag   <= in_tag;
                s1_last  <= in_last;
                s1_c_raw <= in_c;

                s1_is_nan       <= comb_is_nan;
                s1_is_inf       <= comb_is_inf;
                s1_special_sign <= comb_inf_sign;

                if (comb_is_nan || comb_is_inf) begin
                    s1_is_zero  <= 1'b0;
                    s1_bypass_c <= 1'b0;
                end else if (is_zero_p && is_zero_c) begin
                    s1_is_zero      <= 1'b1;
                    s1_bypass_c     <= 1'b0;
                    s1_special_sign <= sc;
                end else if (is_zero_p) begin
                    s1_is_zero  <= 1'b0;
                    s1_bypass_c <= 1'b1;
                end else begin
                    s1_is_zero  <= 1'b0;
                    s1_bypass_c <= 1'b0;
                end

                s1_c_norm <= c_norm_comb;
                s1_prod   <= raw_prod;
                s1_exp_p  <= raw_exp_p;
                s1_exp_c  <= raw_exp_c;
                s1_sign_p <= sign_p;
                s1_sign_c <= sc;
                s1_zero_c <= is_zero_c;
            end
        end
    end

    // =========================================================================
    // S2 register boundary: product normalize, dominant select, shift calc
    // (no wide add, no wide shift here -- only a 1-bit product normalize)
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s2_tag;
    reg                  s2_last;
    reg                  s2_is_nan;
    reg                  s2_is_inf;
    reg                  s2_special_sign;
    reg                  s2_is_zero;
    reg                  s2_bypass_c;
    reg [31:0]           s2_c_raw;

    reg [47:0]           s2_d_val;
    reg [47:0]           s2_s_val;
    reg [9:0]            s2_shift;
    reg signed [9:0]     s2_exp_base;
    reg                  s2_d_sign;
    reg                  s2_eff_sub;

    wire [47:0] p_norm = s1_prod[47] ? s1_prod : {s1_prod[46:0], 1'b0};
    wire signed [9:0] exp_p_norm = s1_prod[47] ? (s1_exp_p + 10'sd1) : s1_exp_p;
    wire signed [9:0] exp_c_norm = s1_exp_c;

    wire c_is_dom = !s1_zero_c && (
        (exp_c_norm > exp_p_norm) ||
        ((exp_c_norm == exp_p_norm) && (s1_c_norm > p_norm))
    );

    wire [47:0] comb_d_val = c_is_dom ? s1_c_norm : p_norm;
    wire [47:0] comb_s_val = c_is_dom ? p_norm    : s1_c_norm;
    wire comb_d_sign       = c_is_dom ? s1_sign_c : s1_sign_p;
    wire comb_s_sign       = c_is_dom ? s1_sign_p : s1_sign_c;
    wire signed [9:0] comb_exp_base = c_is_dom ? exp_c_norm : exp_p_norm;

    wire signed [9:0] diff_exp = c_is_dom ? (exp_c_norm - exp_p_norm) :
                                 (s1_zero_c ? 10'sd500 : (exp_p_norm - exp_c_norm));
    wire [9:0] comb_shift = (diff_exp < 10'sd0)  ? 10'd0 :
                            (diff_exp > 10'sd500) ? 10'd500 : diff_exp;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid        <= 1'b0;
            s2_tag          <= {TAG_WIDTH{1'b0}};
            s2_last         <= 1'b0;
            s2_is_nan       <= 1'b0;
            s2_is_inf       <= 1'b0;
            s2_special_sign <= 1'b0;
            s2_is_zero      <= 1'b0;
            s2_bypass_c     <= 1'b0;
            s2_c_raw        <= 32'd0;
            s2_d_val        <= 48'd0;
            s2_s_val        <= 48'd0;
            s2_shift        <= 10'd0;
            s2_exp_base     <= 10'sd0;
            s2_d_sign       <= 1'b0;
            s2_eff_sub      <= 1'b0;
        end else if (flush) begin
            s2_valid <= 1'b0;
        end else if (s2_ready) begin
            s2_valid <= s1_valid;
            if (s1_valid) begin
                s2_tag          <= s1_tag;
                s2_last         <= s1_last;
                s2_is_nan       <= s1_is_nan;
                s2_is_inf       <= s1_is_inf;
                s2_special_sign <= s1_special_sign;
                s2_is_zero      <= s1_is_zero;
                s2_bypass_c     <= s1_bypass_c;
                s2_c_raw        <= s1_c_raw;
                s2_d_val        <= comb_d_val;
                s2_s_val        <= comb_s_val;
                s2_shift        <= comb_shift;
                s2_exp_base     <= comb_exp_base;
                s2_d_sign       <= comb_d_sign;
                s2_eff_sub      <= (comb_d_sign != comb_s_sign);
            end
        end
    end

    // =========================================================================
    // S3 register boundary: 128-bit right alignment shift + sticky OR
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s3_tag;
    reg                  s3_last;
    reg                  s3_is_nan;
    reg                  s3_is_inf;
    reg                  s3_special_sign;
    reg                  s3_is_zero;
    reg                  s3_bypass_c;
    reg [31:0]           s3_c_raw;

    reg [47:0]           s3_d_val;
    reg [127:0]          s3_s_acc;
    reg                  s3_sticky;
    reg signed [9:0]     s3_exp_base;
    reg                  s3_d_sign;
    reg                  s3_eff_sub;

    wire [127:0] full_s = {s2_s_val, 80'd0};

    reg [127:0] align_acc;
    reg         align_sticky;

    // The shifted-out bits are reduced with a wide AND followed by a tree OR
    // (synthesis reduces |(...) as a balanced OR tree, not a linear chain).
    always @(*) begin
        if (s2_shift > 10'd120) begin
            align_acc    = 128'd0;
            align_sticky = (s2_s_val != 48'd0);
        end else if (s2_shift == 10'd0) begin
            align_acc    = full_s;
            align_sticky = 1'b0;
        end else begin
            align_acc    = full_s >> s2_shift[6:0];
            align_sticky = |(full_s & ((128'd1 << s2_shift[6:0]) - 128'd1));
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid        <= 1'b0;
            s3_tag          <= {TAG_WIDTH{1'b0}};
            s3_last         <= 1'b0;
            s3_is_nan       <= 1'b0;
            s3_is_inf       <= 1'b0;
            s3_special_sign <= 1'b0;
            s3_is_zero      <= 1'b0;
            s3_bypass_c     <= 1'b0;
            s3_c_raw        <= 32'd0;
            s3_d_val        <= 48'd0;
            s3_s_acc        <= 128'd0;
            s3_sticky       <= 1'b0;
            s3_exp_base     <= 10'sd0;
            s3_d_sign       <= 1'b0;
            s3_eff_sub      <= 1'b0;
        end else if (flush) begin
            s3_valid <= 1'b0;
        end else if (s3_ready) begin
            s3_valid <= s2_valid;
            if (s2_valid) begin
                s3_tag          <= s2_tag;
                s3_last         <= s2_last;
                s3_is_nan       <= s2_is_nan;
                s3_is_inf       <= s2_is_inf;
                s3_special_sign <= s2_special_sign;
                s3_is_zero      <= s2_is_zero;
                s3_bypass_c     <= s2_bypass_c;
                s3_c_raw        <= s2_c_raw;
                s3_d_val        <= s2_d_val;
                s3_s_acc        <= align_acc;
                s3_sticky       <= align_sticky;
                s3_exp_base     <= s2_exp_base;
                s3_d_sign       <= s2_d_sign;
                s3_eff_sub      <= s2_eff_sub;
            end
        end
    end

    // =========================================================================
    // S4 register boundary: 129-bit add / subtract
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s4_tag;
    reg                  s4_last;
    reg                  s4_is_nan;
    reg                  s4_is_inf;
    reg                  s4_special_sign;
    reg                  s4_is_zero;
    reg                  s4_bypass_c;
    reg [31:0]           s4_c_raw;

    reg [128:0]          s4_sum_acc;
    reg                  s4_sticky;
    reg signed [9:0]     s4_exp_base;
    reg                  s4_d_sign;

    wire [128:0] d_acc = {1'b0, s3_d_val, 80'd0};

    reg [128:0] comb_sum_acc;

    always @(*) begin
        if (!s3_eff_sub) begin
            comb_sum_acc = d_acc + {1'b0, s3_s_acc};
        end else begin
            comb_sum_acc = d_acc - {1'b0, s3_s_acc} - (s3_sticky ? 129'd1 : 129'd0);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s4_valid        <= 1'b0;
            s4_tag          <= {TAG_WIDTH{1'b0}};
            s4_last         <= 1'b0;
            s4_is_nan       <= 1'b0;
            s4_is_inf       <= 1'b0;
            s4_special_sign <= 1'b0;
            s4_is_zero      <= 1'b0;
            s4_bypass_c     <= 1'b0;
            s4_c_raw        <= 32'd0;
            s4_sum_acc      <= 129'd0;
            s4_sticky       <= 1'b0;
            s4_exp_base     <= 10'sd0;
            s4_d_sign       <= 1'b0;
        end else if (flush) begin
            s4_valid <= 1'b0;
        end else if (s4_ready) begin
            s4_valid <= s3_valid;
            if (s3_valid) begin
                s4_tag          <= s3_tag;
                s4_last         <= s3_last;
                s4_is_nan       <= s3_is_nan;
                s4_is_inf       <= s3_is_inf;
                s4_special_sign <= s3_special_sign;
                s4_is_zero      <= s3_is_zero;
                s4_bypass_c     <= s3_bypass_c;
                s4_c_raw        <= s3_c_raw;
                s4_sum_acc      <= comb_sum_acc;
                s4_sticky       <= s3_sticky;
                s4_exp_base     <= s3_exp_base;
                s4_d_sign       <= s3_d_sign;
            end
        end
    end

    // =========================================================================
    // S5 register boundary: grouped/tree leading-zero count
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s5_tag;
    reg                  s5_last;
    reg                  s5_is_nan;
    reg                  s5_is_inf;
    reg                  s5_special_sign;
    reg                  s5_is_zero;
    reg                  s5_zero_sign;
    reg                  s5_bypass_c;
    reg [31:0]           s5_c_raw;

    reg [128:0]          s5_sum_acc;
    reg [7:0]            s5_msb;
    reg                  s5_sticky;
    reg signed [9:0]     s5_exp_base;
    reg                  s5_d_sign;

    wire [7:0] comb_msb = msb129(s4_sum_acc);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s5_valid        <= 1'b0;
            s5_tag          <= {TAG_WIDTH{1'b0}};
            s5_last         <= 1'b0;
            s5_is_nan       <= 1'b0;
            s5_is_inf       <= 1'b0;
            s5_special_sign <= 1'b0;
            s5_is_zero      <= 1'b0;
            s5_zero_sign    <= 1'b0;
            s5_bypass_c     <= 1'b0;
            s5_c_raw        <= 32'd0;
            s5_sum_acc      <= 129'd0;
            s5_msb          <= 8'd0;
            s5_sticky       <= 1'b0;
            s5_exp_base     <= 10'sd0;
            s5_d_sign       <= 1'b0;
        end else if (flush) begin
            s5_valid <= 1'b0;
        end else if (s5_ready) begin
            s5_valid <= s4_valid;
            if (s4_valid) begin
                s5_tag          <= s4_tag;
                s5_last         <= s4_last;
                s5_is_nan       <= s4_is_nan;
                s5_is_inf       <= s4_is_inf;
                s5_special_sign <= s4_special_sign;
                s5_bypass_c     <= s4_bypass_c;
                s5_c_raw        <= s4_c_raw;
                s5_sum_acc      <= s4_sum_acc;
                s5_msb          <= comb_msb;
                s5_sticky       <= s4_sticky;
                s5_exp_base     <= s4_exp_base;
                s5_d_sign       <= s4_d_sign;

                if (s4_is_zero) begin
                    s5_is_zero   <= 1'b1;
                    s5_zero_sign <= s4_special_sign;
                end else if (s4_sum_acc == 129'd0 && !s4_sticky) begin
                    // Exact cancellation of finite non-zero operands -> +0
                    s5_is_zero   <= 1'b1;
                    s5_zero_sign <= 1'b0;
                end else begin
                    s5_is_zero   <= 1'b0;
                    s5_zero_sign <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // S6 register boundary: normalization shift + round/sticky extraction
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s6_tag;
    reg                  s6_last;
    reg                  s6_is_nan;
    reg                  s6_is_inf;
    reg                  s6_special_sign;
    reg                  s6_is_zero;
    reg                  s6_zero_sign;
    reg                  s6_bypass_c;
    reg [31:0]           s6_c_raw;

    reg [23:0]           s6_mant24;
    reg                  s6_round_bit;
    reg                  s6_sticky;
    reg signed [9:0]     s6_exp_res;
    reg                  s6_d_sign;

    reg [23:0] comb_mant24;
    reg        comb_round_b;
    reg        comb_final_sticky;

    always @(*) begin
        if (s5_msb >= 8'd24) begin
            comb_mant24       = (s5_sum_acc >> (s5_msb - 8'd23)) & 24'hffffff;
            comb_round_b      = s5_sum_acc[s5_msb - 8'd24];
            comb_final_sticky = (|(s5_sum_acc &
                                   ((129'd1 << (s5_msb - 8'd24)) - 129'd1))) |
                                s5_sticky;
        end else begin
            comb_mant24       = (s5_sum_acc << (8'd23 - s5_msb)) & 24'hffffff;
            comb_round_b      = 1'b0;
            comb_final_sticky = s5_sticky;
        end
    end

    wire signed [9:0] comb_exp_res = s5_exp_base + $signed({2'b0, s5_msb}) - 10'sd127;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s6_valid        <= 1'b0;
            s6_tag          <= {TAG_WIDTH{1'b0}};
            s6_last         <= 1'b0;
            s6_is_nan       <= 1'b0;
            s6_is_inf       <= 1'b0;
            s6_special_sign <= 1'b0;
            s6_is_zero      <= 1'b0;
            s6_zero_sign    <= 1'b0;
            s6_bypass_c     <= 1'b0;
            s6_c_raw        <= 32'd0;
            s6_mant24       <= 24'd0;
            s6_round_bit    <= 1'b0;
            s6_sticky       <= 1'b0;
            s6_exp_res      <= 10'sd0;
            s6_d_sign       <= 1'b0;
        end else if (flush) begin
            s6_valid <= 1'b0;
        end else if (s6_ready) begin
            s6_valid <= s5_valid;
            if (s5_valid) begin
                s6_tag          <= s5_tag;
                s6_last         <= s5_last;
                s6_is_nan       <= s5_is_nan;
                s6_is_inf       <= s5_is_inf;
                s6_special_sign <= s5_special_sign;
                s6_is_zero      <= s5_is_zero;
                s6_zero_sign    <= s5_zero_sign;
                s6_bypass_c     <= s5_bypass_c;
                s6_c_raw        <= s5_c_raw;
                s6_d_sign       <= s5_d_sign;

                if (s5_is_zero) begin
                    s6_mant24    <= 24'd0;
                    s6_round_bit <= 1'b0;
                    s6_sticky    <= 1'b0;
                    s6_exp_res   <= 10'sd0;
                end else begin
                    s6_mant24    <= comb_mant24;
                    s6_round_bit <= comb_round_b;
                    s6_sticky    <= comb_final_sticky;
                    s6_exp_res   <= comb_exp_res;
                end
            end
        end
    end

    // =========================================================================
    // S7 register boundary: RNE round + overflow/underflow + result mux
    // =========================================================================
    reg [TAG_WIDTH-1:0]  s7_tag;
    reg                  s7_last;
    reg [31:0]           s7_result;

    wire round_up = s6_round_bit && (s6_sticky || s6_mant24[0]);
    wire [24:0] mant_rounded = {1'b0, s6_mant24} + (round_up ? 25'd1 : 25'd0);
    wire [22:0] final_mant = mant_rounded[24] ? mant_rounded[23:1] : mant_rounded[22:0];
    wire signed [9:0] final_exp = mant_rounded[24] ? (s6_exp_res + 10'sd1) : s6_exp_res;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s7_valid  <= 1'b0;
            s7_tag    <= {TAG_WIDTH{1'b0}};
            s7_last   <= 1'b0;
            s7_result <= 32'd0;
        end else if (flush) begin
            s7_valid <= 1'b0;
        end else if (s7_ready) begin
            s7_valid <= s6_valid;
            if (s6_valid) begin
                s7_tag  <= s6_tag;
                s7_last <= s6_last;

                if (s6_is_nan) begin
                    s7_result <= 32'h7fc00000;
                end else if (s6_is_inf) begin
                    s7_result <= {s6_special_sign, 8'hff, 23'd0};
                end else if (s6_bypass_c) begin
                    s7_result <= s6_c_raw;
                end else if (s6_is_zero) begin
                    s7_result <= {s6_zero_sign, 31'd0};
                end else if (final_exp >= 10'sd255) begin
                    // Overflow to Inf
                    s7_result <= {s6_d_sign, 8'hff, 23'd0};
                end else if (final_exp <= 10'sd0) begin
                    // Underflow / FTZ
                    s7_result <= {s6_d_sign, 31'd0};
                end else begin
                    s7_result <= {s6_d_sign, final_exp[7:0], final_mant};
                end
            end
        end
    end

    assign out_result = s7_result;
    assign out_tag    = s7_tag;
    assign out_last   = s7_last;

endmodule
