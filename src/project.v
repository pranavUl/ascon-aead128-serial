/* Tiny Tapeout wrapper for the bit-serial
 * Ascon-AEAD128 core. Marshals the core's wide ports over TT's 8-in / 8-out /
 * 8-bidir pins with a byte-wide command bus.
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

    // ---- input register + edge detect (host may be slow/async) ----
    reg [7:0] ui_q;
    reg [4:0] uio_q;    // uio[7:5] are outputs, never sampled
    reg [4:2] uio_qq;   // only the edge-detected bits
    always @(posedge clk) begin
        if (reset) begin
            ui_q   <= 8'h00;
            uio_q  <= 5'b00000;
            uio_qq <= 3'b000;
        end else begin
            ui_q   <= ui_in;
            uio_q  <= uio_in[4:0];
            uio_qq <= uio_q[4:2];
        end
    end
    wire [1:0] cmd      = uio_q[1:0];
    wire       strobe_e = uio_q[2] & ~uio_qq[2];
    wire       start_e  = uio_q[3] & ~uio_qq[3];
    wire       go_e     = uio_q[4] & ~uio_qq[4];

    // ---- host-facing registers ----
    reg [127:0] key_r, nonce_r;
    reg [127:0] bdi_r;
    reg [4:0]   bdi_cnt;
    reg         bdi_valid_r;
    reg [4:0]   bdi_bytes_r;
    reg         bdi_ad_r, bdi_last_r;
    reg         start_r, dec_r;
    reg [127:0] out_r;
    reg [4:0]   out_cnt;
    reg         tag_taken;

    // ---- core signals ----
    wire         core_bdi_ready;
    wire         core_bdo_valid;
    wire [127:0] core_bdo;
    wire [4:0]   core_bdo_bytes;
    wire         core_tag_valid;
    wire [127:0] core_tag;
    wire         core_busy;

    wire out_empty = (out_cnt == 5'd0);

    always @(posedge clk) begin
        if (reset) begin
            key_r       <= 128'd0;
            nonce_r     <= 128'd0;
            bdi_r       <= 128'd0;
            bdi_cnt     <= 5'd0;
            bdi_valid_r <= 1'b0;
            bdi_bytes_r <= 5'd0;
            bdi_ad_r    <= 1'b0;
            bdi_last_r  <= 1'b0;
            start_r     <= 1'b0;
            dec_r       <= 1'b0;
            out_r       <= 128'd0;
            out_cnt     <= 5'd0;
            tag_taken   <= 1'b0;
        end else begin
            start_r <= 1'b0;

            // key / nonce: shift in from the top, 16 bytes each, byte 0 first
            if (strobe_e && cmd == 2'b01) key_r   <= {ui_q, key_r[127:8]};
            if (strobe_e && cmd == 2'b10) nonce_r <= {ui_q, nonce_r[127:8]};

            // data staging: byte-addressed, 0..16 bytes
            if (strobe_e && cmd == 2'b11 && !bdi_valid_r && bdi_cnt != 5'd16) begin
                bdi_r[{bdi_cnt[3:0], 3'b000} +: 8] <= ui_q;
                bdi_cnt <= bdi_cnt + 5'd1;
            end

            // hand the staged block to the core
            if (go_e && !bdi_valid_r) begin
                bdi_valid_r <= 1'b1;
                bdi_bytes_r <= bdi_cnt;
                bdi_ad_r    <= ui_q[0];
                bdi_last_r  <= ui_q[1];
            end
            if (bdi_valid_r && core_bdi_ready) begin
                bdi_valid_r <= 1'b0;
                bdi_r       <= 128'd0;   // unused bytes must be zero for padding
                bdi_cnt     <= 5'd0;
            end

            if (start_e) begin
                start_r <= 1'b1;
                dec_r   <= ui_q[0];
            end

            // output FIFO: pop on read, else capture BDO or TAG when empty
            if (strobe_e && cmd == 2'b00 && !out_empty) begin
                out_r   <= {8'h00, out_r[127:8]};
                out_cnt <= out_cnt - 5'd1;
            end else if (out_empty) begin
                if (core_bdo_valid) begin
                    out_r   <= core_bdo;
                    out_cnt <= core_bdo_bytes;
                end else if (core_tag_valid && !tag_taken) begin
                    out_r     <= core_tag;
                    out_cnt   <= 5'd16;
                    tag_taken <= 1'b1;
                end
            end
            if (!core_tag_valid) tag_taken <= 1'b0;
        end
    end

    ascon_core_serial u_core (
        .clk         (clk),
        .reset       (reset),
        .START       (start_r),
        .DECRYPT     (dec_r),
        .KEY         (key_r),
        .NONCE       (nonce_r),
        .BDI_VALID   (bdi_valid_r),
        .BDI_READY   (core_bdi_ready),
        .BDI         (bdi_r),
        .BDI_BYTES   (bdi_bytes_r),
        .BDI_TYPE_AD (bdi_ad_r),
        .BDI_LAST    (bdi_last_r),
        .BDO_VALID   (core_bdo_valid),
        .BDO_READY   (out_empty),
        .BDO         (core_bdo),
        .BDO_BYTES   (core_bdo_bytes),
        .TAG_VALID   (core_tag_valid),
        .TAG         (core_tag),
        .BUSY        (core_busy)
    );

    assign uo_out  = out_r[7:0];
    assign uio_out = {~out_empty, core_busy, ~bdi_valid_r, 5'b00000};
    assign uio_oe  = 8'b1110_0000;

    wire _unused = &{ena, uio_in[7:5], 1'b0};
endmodule