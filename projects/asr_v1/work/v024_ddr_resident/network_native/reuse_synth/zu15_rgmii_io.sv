// Board-specific RGMII I/O. The retained V0.22 top netlist supplies the
// primitive options; the packet stack and the timing-independent MAC are
// compiled from the project's existing sources.
`default_nettype none
module rgmii_rx_delay (
    input wire cal_clk, cal_rst,
    input wire [4:0] raw,
    output wire [4:0] delayed,
    output wire ready
);
    (* IODELAY_GROUP = "ZU15_RGMII_RX" *)
    IDELAYCTRL #(.SIM_DEVICE("ULTRASCALE")) calibration (
        .REFCLK(cal_clk), .RST(cal_rst), .RDY(ready)
    );
    for (genvar n = 0; n < 5; n++) begin : data_delays
        (* IODELAY_GROUP = "ZU15_RGMII_RX" *)
        IDELAYE3 #(
            .CASCADE("NONE"), .DELAY_FORMAT("TIME"), .DELAY_SRC("IDATAIN"),
            .DELAY_TYPE("FIXED"), .DELAY_VALUE(700), .UPDATE_MODE("ASYNC"),
            .REFCLK_FREQUENCY(333.333333), .SIM_DEVICE("ULTRASCALE_PLUS")
        ) delay_inst (
            .IDATAIN(raw[n]), .DATAOUT(delayed[n]), .EN_VTC(1'b1),
            .CLK(1'b0), .CE(1'b0), .RST(1'b0), .INC(1'b0), .LOAD(1'b0),
            .CASC_IN(1'b0), .CASC_RETURN(1'b0), .DATAIN(1'b0),
            .CNTVALUEIN(9'd0), .CNTVALUEOUT(), .CASC_OUT()
        );
    end
endmodule

module iddr #(
    parameter TARGET = "GENERIC", IODDR_STYLE = "IODDR2", WIDTH = 1
) (
    input wire clk, input wire [WIDTH-1:0] d,
    output wire [WIDTH-1:0] q1, q2
);
    if (TARGET == "XILINX" && IODDR_STYLE == "IODDRE1") begin
        for (genvar n = 0; n < WIDTH; n++) begin : iddr
            IDDRE1 #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED"), .IS_CB_INVERTED(1'b1))
                iddr_inst (.C(clk), .CB(clk), .R(1'b0), .D(d[n]), .Q1(q1[n]), .Q2(q2[n]));
        end
    end else begin
        unsupported_zu15_ioddr_configuration unsupported();
    end
endmodule

module oddr #(
    parameter TARGET = "GENERIC", IODDR_STYLE = "IODDR2", WIDTH = 1
) (
    input wire clk, input wire [WIDTH-1:0] d1, d2,
    output wire [WIDTH-1:0] q
);
    if (TARGET == "XILINX" && IODDR_STYLE == "IODDRE1") begin
        for (genvar n = 0; n < WIDTH; n++) begin : oddr
            ODDRE1 #(.SIM_DEVICE("ULTRASCALE_PLUS"))
                oddr_inst (.C(clk), .D1(d1[n]), .D2(d2[n]), .Q(q[n]), .SR(1'b0));
        end
    end else begin
        unsupported_zu15_ioddr_configuration unsupported();
    end
endmodule
`default_nettype wire
