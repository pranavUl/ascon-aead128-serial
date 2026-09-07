module ascon_permutation_serial (
	clk,
	reset,
	LOAD_EN,
	BITS_IN,
	START,
	NUM_ROUNDS_12,
	BUSY,
	DONE,
	UNLOAD_EN,
	BITS_OUT
);
	reg _sv2v_0;
	input wire clk;
	input wire reset;
	input wire LOAD_EN;
	input wire [4:0] BITS_IN;
	input wire START;
	input wire NUM_ROUNDS_12;
	output wire BUSY;
	output wire DONE;
	input wire UNLOAD_EN;
	output wire [4:0] BITS_OUT;
	reg [63:0] x0_q;
	reg [63:0] x1_q;
	reg [63:0] x2_q;
	reg [63:0] x3_q;
	reg [63:0] x4_q;
	reg busy_q;
	reg done_q;
	reg lap_z_q;
	reg [5:0] cnt_q;
	reg [3:0] round_q;
	reg [7:0] rc;
	reg rc_bit;
	wire slap_active;
	assign slap_active = (busy_q && !lap_z_q) || (START && !busy_q);
	wire [3:0] round_eff;
	assign round_eff = (START && !busy_q ? (NUM_ROUNDS_12 ? 4'd0 : 4'd4) : round_q);
	always @(*) begin : round_constant
		if (_sv2v_0)
			;
		rc = {4'hf - round_eff, round_eff};
		if (slap_active && (cnt_q < 6'd8))
			rc_bit = rc[cnt_q[2:0]];
		else
			rc_bit = 1'b0;
	end
	wire [4:0] col_out;
	ascon_sbox u_ascon_sbox(
		.COL_IN({x4_q[0], x3_q[0], x2_q[0], x1_q[0], x0_q[0]}),
		.RC_BIT(rc_bit),
		.COL_OUT(col_out)
	);
	localparam signed [159:0] R1 = 160'h0000001300000027000000010000000a00000007;
	localparam signed [159:0] R2 = 160'h0000001c0000003d000000060000001100000029;
	wire [63:0] st [0:4];
	assign st[0] = x0_q;
	assign st[1] = x1_q;
	assign st[2] = x2_q;
	assign st[3] = x3_q;
	assign st[4] = x4_q;
	wire [4:0] z_bits;
	genvar _gv_w_1;
	function automatic [5:0] sv2v_cast_6;
		input reg [5:0] inp;
		sv2v_cast_6 = inp;
	endfunction
	generate
		for (_gv_w_1 = 0; _gv_w_1 < 5; _gv_w_1 = _gv_w_1 + 1) begin : g_zlap
			localparam w = _gv_w_1;
			wire tap1;
			wire tap2;
			if (R1[(4 - w) * 32+:32] > 1) begin : g_f1
				reg [R1[(4 - w) * 32+:32] - 1:0] fifo1;
				always @(posedge clk) begin : f1
					if (slap_active && (cnt_q < sv2v_cast_6(R1[(4 - w) * 32+:32])))
						fifo1 <= {fifo1[R1[(4 - w) * 32+:32] - 2:0], col_out[w]};
					else if ((busy_q && lap_z_q) && (cnt_q >= sv2v_cast_6(64 - R1[(4 - w) * 32+:32])))
						fifo1 <= {fifo1[R1[(4 - w) * 32+:32] - 2:0], 1'b0};
				end
				assign tap1 = (cnt_q < sv2v_cast_6(64 - R1[(4 - w) * 32+:32]) ? st[w][R1[(4 - w) * 32+:32]] : fifo1[R1[(4 - w) * 32+:32] - 1]);
			end
			else begin : g_f1s
				reg fifo1;
				always @(posedge clk) begin : f1
					if (slap_active && (cnt_q < sv2v_cast_6(R1[(4 - w) * 32+:32])))
						fifo1 <= col_out[w];
				end
				assign tap1 = (cnt_q < sv2v_cast_6(64 - R1[(4 - w) * 32+:32]) ? st[w][R1[(4 - w) * 32+:32]] : fifo1);
			end
			reg [R2[(4 - w) * 32+:32] - 1:0] fifo2;
			always @(posedge clk) begin : f2
				if (slap_active && (cnt_q < sv2v_cast_6(R2[(4 - w) * 32+:32])))
					fifo2 <= {fifo2[R2[(4 - w) * 32+:32] - 2:0], col_out[w]};
				else if ((busy_q && lap_z_q) && (cnt_q >= sv2v_cast_6(64 - R2[(4 - w) * 32+:32])))
					fifo2 <= {fifo2[R2[(4 - w) * 32+:32] - 2:0], 1'b0};
			end
			assign tap2 = (cnt_q < sv2v_cast_6(64 - R2[(4 - w) * 32+:32]) ? st[w][R2[(4 - w) * 32+:32]] : fifo2[R2[(4 - w) * 32+:32] - 1]);
			assign z_bits[w] = (st[w][0] ^ tap1) ^ tap2;
		end
	endgenerate
	always @(posedge clk) begin : state_shift
		if (LOAD_EN) begin
			x0_q <= {BITS_IN[0], x0_q[63:1]};
			x1_q <= {BITS_IN[1], x1_q[63:1]};
			x2_q <= {BITS_IN[2], x2_q[63:1]};
			x3_q <= {BITS_IN[3], x3_q[63:1]};
			x4_q <= {BITS_IN[4], x4_q[63:1]};
		end
		else if (slap_active) begin
			x0_q <= {col_out[0], x0_q[63:1]};
			x1_q <= {col_out[1], x1_q[63:1]};
			x2_q <= {col_out[2], x2_q[63:1]};
			x3_q <= {col_out[3], x3_q[63:1]};
			x4_q <= {col_out[4], x4_q[63:1]};
		end
		else if (busy_q && lap_z_q) begin
			x0_q <= {z_bits[0], x0_q[63:1]};
			x1_q <= {z_bits[1], x1_q[63:1]};
			x2_q <= {z_bits[2], x2_q[63:1]};
			x3_q <= {z_bits[3], x3_q[63:1]};
			x4_q <= {z_bits[4], x4_q[63:1]};
		end
		else begin
			x0_q <= {x0_q[0], x0_q[63:1]};
			x1_q <= {x1_q[0], x1_q[63:1]};
			x2_q <= {x2_q[0], x2_q[63:1]};
			x3_q <= {x3_q[0], x3_q[63:1]};
			x4_q <= {x4_q[0], x4_q[63:1]};
		end
	end
	always @(posedge clk) begin : ctrl
		if (reset) begin
			busy_q <= 1'b0;
			done_q <= 1'b0;
			lap_z_q <= 1'b0;
			cnt_q <= 6'd0;
		end
		else if (START && !busy_q) begin
			round_q <= (NUM_ROUNDS_12 ? 4'd0 : 4'd4);
			lap_z_q <= 1'b0;
			cnt_q <= 6'd1;
			busy_q <= 1'b1;
			done_q <= 1'b0;
		end
		else if (busy_q) begin
			cnt_q <= cnt_q + 6'd1;
			if (cnt_q == 6'd63) begin
				lap_z_q <= !lap_z_q;
				if (lap_z_q) begin
					round_q <= round_q + 4'd1;
					if (round_q == 4'd11) begin
						busy_q <= 1'b0;
						done_q <= 1'b1;
					end
				end
			end
		end
		else
			done_q <= 1'b0;
	end
	assign BITS_OUT = {x4_q[0], x3_q[0], x2_q[0], x1_q[0], x0_q[0]};
	assign BUSY = busy_q;
	assign DONE = done_q;
	initial _sv2v_0 = 0;
endmodule
