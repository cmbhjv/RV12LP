module topo (
	input clk , rst
);


//Data Memory signals
logic [31:0] dmem_q,dmem_adr;
logic dmem_we,dmem_ack;

//IF Memory signals
logic [31:0] if_nxt_pc,if_parcel;

dataRAM	dataRAM_inst (
	.clock ( clk ),
	.init ( rst ),
	.dataout ( dmem_q ),
	.init_busy ( ~dmem_ack ),
	.ram_address ( dmem_adr ),
	.ram_wren ( dmem_we )
	);

prog	ROM_inst (
	.address ( if_nxt_pc ),
	.clock ( clk ),
	.q ( if_parcel )
	);
	
	
endmodule