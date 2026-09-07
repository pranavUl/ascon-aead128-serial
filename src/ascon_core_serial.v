module ascon_core_serial (
	clk,
	reset,
	START,
	DECRYPT,
	KEY,
	NONCE,
	BDI_VALID,
	BDI_READY,
	BDI,
	BDI_BYTES,
	BDI_TYPE_AD,
	BDI_LAST,
	BDO_VALID,
	BDO_READY,
	BDO,
	BDO_BYTES,
	TAG_VALID,
	TAG,
	BUSY
);
	reg _sv2v_0;
	input wire clk;
	input wire reset;
	input wire START;
	input wire DECRYPT;
	input wire [127:0] KEY;
	input wire [127:0] NONCE;
	input wire BDI_VALID;
	output wire BDI_READY;
	input wire [127:0] BDI;
	input wire [4:0] BDI_BYTES;
	input wire BDI_TYPE_AD;
	input wire BDI_LAST;
	output wire BDO_VALID;
	input wire BDO_READY;
	output wire [127:0] BDO;
	output wire [4:0] BDO_BYTES;
	output wire TAG_VALID;
	output wire [127:0] TAG;
	output wire BUSY;
	reg [3:0] phase_q;
	reg [127:0] key_q;
	reg pad_pending_q;
	wire [127:0] bdi_padded;
	assign bdi_padded = BDI | (128'h00000000000000000000000000000001 << {BDI_BYTES, 3'b000});
	reg [127:0] bdi_q;
	reg [127:0] bdo_q;
	reg [4:0] bdo_bytes_q;
	reg bdo_valid_q;
	reg [127:0] tag_q;
	reg tag_valid_q;
	reg p_start;
	reg p_rounds_12;
	wire p_load_en;
	wire [4:0] p_bits_in;
	wire [4:0] p_bits_out;
	wire perm_busy;
	wire perm_done;
	ascon_permutation_serial u_ascon_permutation_serial(
		.clk(clk),
		.reset(reset),
		.LOAD_EN(p_load_en),
		.BITS_IN(p_bits_in),
		.START(p_start),
		.NUM_ROUNDS_12(p_rounds_12),
		.BUSY(perm_busy),
		.DONE(perm_done),
		.UNLOAD_EN(1'b0),
		.BITS_OUT(p_bits_out)
	);
	reg lap_arm_q;
	reg lap_run_q;
	reg [5:0] lap_cnt_q;
	reg lap_go_q;
	reg [5:0] pos_q;
	wire lap_begin;
	wire lap_last;
	assign lap_begin = lap_arm_q && (pos_q == 6'd63);
	assign lap_last = lap_run_q && (lap_cnt_q == 6'd63);
	always @(posedge clk) begin : lap_engine
		if (reset) begin
			lap_run_q <= 1'b0;
			lap_cnt_q <= 6'd0;
			pos_q <= 6'd0;
		end
		else begin
			if (perm_done)
				pos_q <= 6'd1;
			else if (!perm_busy && !lap_run_q)
				pos_q <= pos_q + 6'd1;
			else
				pos_q <= 6'd0;
			if (lap_begin) begin
				lap_run_q <= 1'b1;
				lap_cnt_q <= 6'd0;
			end
			else if (lap_run_q) begin
				lap_cnt_q <= lap_cnt_q + 6'd1;
				if (lap_last)
					lap_run_q <= 1'b0;
			end
		end
	end
	assign p_load_en = lap_run_q;
	reg [2:0] lap_sel_q;
	reg lap_is_pt_q;
	localparam [63:0] IV64 = 64'h00001000808c0001;
	wire [5:0] k;
	assign k = lap_cnt_q;
	wire [63:0] key_lo;
	wire [63:0] key_hi;
	wire [63:0] bdi_lo;
	wire [63:0] bdi_hi;
	wire [63:0] nonce_lo;
	wire [63:0] nonce_hi;
	assign key_lo = key_q[63:0];
	assign key_hi = key_q[127:64];
	assign bdi_lo = bdi_q[63:0];
	assign bdi_hi = bdi_q[127:64];
	assign nonce_lo = NONCE[63:0];
	assign nonce_hi = NONCE[127:64];
	reg [4:0] delta_col;
	always @(*) begin : delta_mux
		if (_sv2v_0)
			;
		case (lap_sel_q)
			3'd1: delta_col = {key_hi[k], key_lo[k], 3'b000};
			3'd2: delta_col = {3'b000, bdi_hi[k], bdi_lo[k]};
			3'd3: delta_col = {k == 6'd63, 4'b0000};
			3'd4: delta_col = {4'b0000, k == 6'd0};
			3'd5: delta_col = {1'b0, key_hi[k], key_lo[k], 2'b00};
			3'd6: delta_col = {key_hi[k], key_lo[k], 3'b000};
			default: delta_col = 5'b00000;
		endcase
	end
	wire [4:0] init_col;
	assign init_col = {nonce_hi[k], nonce_lo[k], key_hi[k], key_lo[k], IV64[k]};
	assign p_bits_in = (lap_sel_q == 3'd0 ? init_col : p_bits_out ^ delta_col);
	wire lap_idle;
	assign lap_idle = (!lap_arm_q && !lap_run_q) && !lap_go_q;
	assign BDI_READY = (((!perm_busy && !p_start) && !bdo_valid_q) && lap_idle) && (((phase_q == 4'd2) && BDI_TYPE_AD) || ((phase_q == 4'd4) && !BDI_TYPE_AD));
	assign BDO = bdo_q;
	assign BDO_BYTES = bdo_bytes_q;
	assign BDO_VALID = bdo_valid_q;
	assign TAG = tag_q;
	assign TAG_VALID = tag_valid_q;
	assign BUSY = (phase_q != 4'd0) && (phase_q != 4'd8);
	always @(posedge clk) begin : core_fsm
		if (reset) begin
			phase_q <= 4'd0;
			p_start <= 1'b0;
			pad_pending_q <= 1'b0;
			bdo_valid_q <= 1'b0;
			tag_valid_q <= 1'b0;
			lap_arm_q <= 1'b0;
			lap_go_q <= 1'b0;
		end
		else begin
			p_start <= 1'b0;
			if (BDO_READY)
				bdo_valid_q <= 1'b0;
			if (lap_begin)
				lap_arm_q <= 1'b0;
			if (lap_last && lap_go_q) begin
				p_start <= 1'b1;
				lap_go_q <= 1'b0;
			end
			if ((lap_run_q && (lap_sel_q == 3'd2)) && lap_is_pt_q) begin
				bdo_q[{1'b0, k}] <= p_bits_in[0];
				bdo_q[{1'b1, k}] <= p_bits_in[1];
				if (lap_last && (bdo_bytes_q != 5'd0))
					bdo_valid_q <= 1'b1;
			end
			if (lap_run_q && (lap_sel_q == 3'd6)) begin
				tag_q[{1'b0, k}] <= p_bits_in[3];
				tag_q[{1'b1, k}] <= p_bits_in[4];
				if (lap_last)
					tag_valid_q <= 1'b1;
			end
			case (phase_q)
				4'd0, 4'd8:
					if (START && lap_idle) begin
						key_q <= KEY;
						lap_sel_q <= 3'd0;
						lap_arm_q <= 1'b1;
						lap_go_q <= 1'b1;
						p_rounds_12 <= 1'b1;
						phase_q <= 4'd1;
						tag_valid_q <= 1'b0;
					end
				4'd1:
					if (perm_done) begin
						lap_sel_q <= 3'd1;
						lap_arm_q <= 1'b1;
						phase_q <= 4'd2;
					end
				4'd2:
					if (BDI_VALID && BDI_READY) begin
						bdi_q <= bdi_padded;
						lap_sel_q <= 3'd2;
						lap_is_pt_q <= 1'b0;
						lap_arm_q <= 1'b1;
						lap_go_q <= 1'b1;
						p_rounds_12 <= 1'b0;
						pad_pending_q <= BDI_LAST && (BDI_BYTES == 5'd16);
						phase_q <= 4'd3;
					end
					else if ((((BDI_VALID && !BDI_TYPE_AD) && lap_idle) && !perm_busy) && !p_start) begin
						lap_sel_q <= 3'd3;
						lap_arm_q <= 1'b1;
						phase_q <= 4'd4;
					end
				4'd3:
					if (perm_done) begin
						if (pad_pending_q) begin
							lap_sel_q <= 3'd4;
							lap_arm_q <= 1'b1;
							lap_go_q <= 1'b1;
							p_rounds_12 <= 1'b0;
							pad_pending_q <= 1'b0;
						end
						else
							phase_q <= 4'd2;
					end
				4'd4:
					if (BDI_VALID && BDI_READY) begin
						bdi_q <= bdi_padded;
						lap_sel_q <= 3'd2;
						lap_is_pt_q <= 1'b1;
						lap_arm_q <= 1'b1;
						bdo_bytes_q <= BDI_BYTES;
						if (!BDI_LAST || (BDI_BYTES == 5'd16)) begin
							lap_go_q <= 1'b1;
							p_rounds_12 <= 1'b0;
							pad_pending_q <= BDI_LAST && (BDI_BYTES == 5'd16);
							phase_q <= 4'd5;
						end
						else
							phase_q <= 4'd6;
					end
				4'd5:
					if (perm_done) begin
						if (pad_pending_q) begin
							lap_sel_q <= 3'd4;
							lap_arm_q <= 1'b1;
							lap_go_q <= 1'b0;
							pad_pending_q <= 1'b0;
							phase_q <= 4'd6;
						end
						else
							phase_q <= 4'd4;
					end
				4'd6:
					if (((!bdo_valid_q && lap_idle) && !perm_busy) && !p_start) begin
						lap_sel_q <= 3'd5;
						lap_arm_q <= 1'b1;
						lap_go_q <= 1'b1;
						p_rounds_12 <= 1'b1;
						phase_q <= 4'd7;
					end
				4'd7:
					if (perm_done) begin
						lap_sel_q <= 3'd6;
						lap_arm_q <= 1'b1;
						phase_q <= 4'd8;
					end
				default:
					;
			endcase
		end
	end
	initial _sv2v_0 = 0;
endmodule
