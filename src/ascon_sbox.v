module ascon_sbox (
	COL_IN,
	RC_BIT,
	COL_OUT
);
	reg _sv2v_0;
	input wire [4:0] COL_IN;
	input wire RC_BIT;
	output reg [4:0] COL_OUT;
	reg x0;
	reg x1;
	reg x2;
	reg x3;
	reg x4;
	reg t0;
	reg t1;
	reg t2;
	reg t3;
	reg t4;
	always @(*) begin : sbox_logic
		if (_sv2v_0)
			;
		x0 = COL_IN[0];
		x1 = COL_IN[1];
		x2 = COL_IN[2];
		x3 = COL_IN[3];
		x4 = COL_IN[4];
		x2 = x2 ^ RC_BIT;
		x0 = x0 ^ x4;
		x4 = x4 ^ x3;
		x2 = x2 ^ x1;
		t0 = ~x0 & x1;
		t1 = ~x1 & x2;
		t2 = ~x2 & x3;
		t3 = ~x3 & x4;
		t4 = ~x4 & x0;
		x0 = x0 ^ t1;
		x1 = x1 ^ t2;
		x2 = x2 ^ t3;
		x3 = x3 ^ t4;
		x4 = x4 ^ t0;
		x1 = x1 ^ x0;
		x0 = x0 ^ x4;
		x3 = x3 ^ x2;
		x2 = ~x2;
		COL_OUT = {x4, x3, x2, x1, x0};
	end
	initial _sv2v_0 = 0;
endmodule
