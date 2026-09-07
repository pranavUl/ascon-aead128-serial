/*
 * tt_um_pranavUl_ascon_aead128 -- streaming lap interface to the bit-serial
 * Ascon permutation. No data buffers on chip: the host supplies one 5-bit
 * column per cycle during a "lap" (64 cycles) and reads result columns live.
 *
 * ui[4:0]  COL_IN      column bits for the current lap cycle
 * ui[5]    LAP_GO      request a lap (hold until LAP_ACTIVE rises)
 * ui[6]    PERM_AFTER  start the permutation when this lap ends
 * ui[7]    PERM_12     1 = 12 rounds, 0 = 8 rounds
 * uio[0]   LAP_XOR     1 = XOR lap, 0 = RAW load lap
 * uo[4:0]  COL_OUT     write-back column = state ^ COL_IN (XOR) or COL_IN (RAW)
 * uo[5]    LAP_ACTIVE  a lap is running (cycle 0..63)
 * uo[6]    PERM_BUSY
 * uo[7]    PERM_DONE
 * uio[7]   READY       state aligned at column 63, idle: LAP_GO honored now
 */
 
`default_nettype none
module tt_um_pranavUl_ascon_aead128 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire reset = ~rst_n;

    wire [4:0] col_in     = ui_in[4:0];
    wire       lap_go     = ui_in[5];
    wire       perm_after = ui_in[6];
    wire       perm_12    = ui_in[7];
    wire       lap_xor    = uio_in[0];

    reg        lap_run_q;
    reg  [5:0] lap_cnt_q;
    reg        go_perm_q, rounds12_q, xor_q;
    reg  [5:0] pos_q;
    reg        p_start;

    wire [4:0] p_bits_out;
    wire       perm_busy, perm_done;

    wire lap_begin = lap_go && !lap_run_q && !perm_busy && !p_start && (pos_q == 6'd63);
    wire lap_last  = lap_run_q && (lap_cnt_q == 6'd63);
    wire [4:0] p_bits_in = xor_q ? (p_bits_out ^ col_in) : col_in;

    always @(posedge clk) begin
        if (reset) begin
            lap_run_q  <= 1'b0;
            lap_cnt_q  <= 6'd0;
            pos_q      <= 6'd0;
            p_start    <= 1'b0;
            go_perm_q  <= 1'b0;
            rounds12_q <= 1'b0;
            xor_q      <= 1'b0;
        end else begin
            p_start <= 1'b0;

            // head position of the idle-rotating state (same as the core)
            if (perm_done)
                pos_q <= 6'd1;
            else if (!perm_busy && !lap_run_q)
                pos_q <= pos_q + 6'd1;
            else
                pos_q <= 6'd0;

            if (lap_begin) begin
                lap_run_q  <= 1'b1;
                lap_cnt_q  <= 6'd0;
                go_perm_q  <= perm_after;
                rounds12_q <= perm_12;
                xor_q      <= lap_xor;
            end else if (lap_run_q) begin
                lap_cnt_q <= lap_cnt_q + 6'd1;
                if (lap_last) begin
                    lap_run_q <= 1'b0;
                    if (go_perm_q) p_start <= 1'b1;
                end
            end
        end
    end

    ascon_permutation_serial u_perm (
        .clk           (clk),
        .reset         (reset),
        .LOAD_EN       (lap_run_q),
        .BITS_IN       (p_bits_in),
        .START         (p_start),
        .NUM_ROUNDS_12 (rounds12_q),
        .BUSY          (perm_busy),
        .DONE          (perm_done),
        .UNLOAD_EN     (1'b0),
        .BITS_OUT      (p_bits_out)
    );

    assign uo_out  = {perm_done, perm_busy, lap_run_q, p_bits_in};
    assign uio_out = {(pos_q == 6'd63) && !perm_busy && !lap_run_q && !p_start, 7'b0000000};
    assign uio_oe  = 8'b1000_0000;

    wire _unused = &{ena, uio_in[7:1], 1'b0};
endmodule