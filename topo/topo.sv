module topo #(
  //General
  parameter XLEN               = 32,
  parameter PLEN               = XLEN,
  //Memory buses
  parameter DMEM_SIZE          = 32*1024,   //Memory in Bytes
  parameter DMEM_DEPTH         = 256, 	 //Memory depth
  parameter IMEM_SIZE          = 16*1024,   //Memory in Bytes
  parameter IMEM_DEPTH         = 256, 	 //Memory depth  
  parameter HADDR_SIZE         = PLEN,
  parameter HDATA_SIZE         = XLEN,
  //Core
  parameter PC_INIT            = 'h200,
  parameter HAS_USER           = 1,
  parameter HAS_SUPER          = 1,
  parameter HAS_HYPER          = 1,
  parameter HAS_BPU            = 1,
  parameter HAS_FPU            = 0,
  parameter HAS_MMU            = 0,
  parameter HAS_RVM            = 1,
  parameter HAS_RVA            = 1,
  parameter HAS_RVC            = 1,
  parameter IS_RV32E           = 1,
  parameter MULT_LATENCY       = 0,
  parameter BREAKPOINTS        = 3,  //Number of hardware breakpoints
  parameter PMA_CNT            = 3,
  parameter PMP_CNT            = 16, //Number of Physical Memory Protection entries
  parameter BP_GLOBAL_BITS     = 2,
  parameter BP_LOCAL_BITS      = 10,
  //Caches
  parameter ICACHE_SIZE        = 0,  //in KBytes
  parameter ICACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter ICACHE_WAYS        = 2,  //'n'-way set associative
  parameter ICACHE_REPLACE_ALG = 0,
  parameter DCACHE_SIZE        = 0,  //in KBytes
  parameter DCACHE_BLOCK_SIZE  = 32, //in Bytes
  parameter DCACHE_WAYS        = 2,  //'n'-way set associative
  parameter DCACHE_REPLACE_ALG = 0,
  parameter WRITEBUFFER_SIZE   = 8  
)
(
  input                       		  HRESETn,
												  HCLK,
  input  pmacfg_t                     pma_cfg_i [PMA_CNT],
  input  logic    [XLEN         -1:0] pma_adr_i [PMA_CNT],
 
  //Interrupts
  input                               ext_nmi,
                                      ext_tint,
                                      ext_sint,
  input           [              3:0] ext_int,

  //Debug Interface
  input                               dbg_stall,
  input                               dbg_strb,
  input                               dbg_we,
  input           [DBG_ADDR_SIZE-1:0] dbg_addr,
  input           [XLEN         -1:0] dbg_dati,
  output          [XLEN         -1:0] dbg_dato,
  output                              dbg_ack,
  output                              dbg_bp
);


///////////////////////////////////////////////////////////
//									Signals								//
///////////////////////////////////////////////////////////
  
  //Data
  logic                       DHSEL;
  logic      [HADDR_SIZE-1:0] DHADDR;
  logic      [HDATA_SIZE-1:0] DHWDATA;
  logic 		 [HDATA_SIZE-1:0] DHRDATA;
  logic                       DHWRITE;
  logic      [           2:0] DHSIZE;
  logic      [           2:0] DHBURST;
  logic      [           3:0] DHPROT;
  logic      [           1:0] DHTRANS;
  logic  	                  DHREADYOUT;
  logic                       DHREADY;
  logic    	                  DHRESP;
  
  //Instructions
  logic                       IHSEL;
  logic      [HADDR_SIZE-1:0] IHADDR;
  logic      [HDATA_SIZE-1:0] IHWDATA;
  logic 		 [HDATA_SIZE-1:0] IHRDATA;
  logic                       IHWRITE;
  logic      [           2:0] IHSIZE;
  logic      [           2:0] IHBURST;
  logic      [           3:0] IHPROT;
  logic      [           1:0] IHTRANS;
  logic  	                  IHREADYOUT;
  logic                       IHREADY;
  logic    	                  IHRESP; 

  //Floating Signals
  logic 								IHMASTLOCK;
  logic 								DHMASTLOCK;



///////////////////////////////////////////////////////////
//								Data Memory								//
///////////////////////////////////////////////////////////

  ahb3lite_sram1rw #(
	.MEM_SIZE			(DMEM_SIZE),
	.MEM_DEPTH			(DMEM_DEPTH),
	.HADDR_SIZE 		(HADDR_SIZE),
	.HDATA_SIZE 		(HDATA_SIZE)
  ) 
  dataRAM (
	.HRESETn,
	.HCLK,
	.HSEL					(DHSEL),
	.HADDR				(DHADDR),
	.HWDATA				(DHWDATA),
	.HRDATA				(DHRDATA),
	.HWRITE				(DHWRITE),
	.HSIZE				(DHSIZE),
	.HBURST				(DHBURST),
	.HPROT				(DHPROT),
	.HTRANS				(DHTRANS),
	.HREADYOUT			(DHREADYOUT),
	.HREADY				(1'b1), // TESTE
	.HRESP				(DHRESP)
  );


///////////////////////////////////////////////////////////
//							Instruction Memory						//
///////////////////////////////////////////////////////////

  ahb3lite_rom1rw #(
	.MEM_SIZE			(IMEM_SIZE),
	.MEM_DEPTH			(IMEM_DEPTH),
	.HADDR_SIZE 		(HADDR_SIZE),
	.HDATA_SIZE 		(HDATA_SIZE)
  ) 
  instROM (
	.HRESETn,
	.HCLK,
	.HSEL					(IHSEL),
	.HADDR				(IHADDR),
	.HWDATA				(IHWDATA),
	.HRDATA				(IHRDATA),
	.HWRITE				(IHWRITE),
	.HSIZE				(IHSIZE),
	.HBURST				(IHBURST),
	.HPROT				(IHPROT),
	.HTRANS				(IHTRANS),
	.HREADYOUT			(IHREADYOUT),
	.HREADY				(1'b1), //TESTE
	.HRESP				(IHRESP)
  );


///////////////////////////////////////////////////////////
//							RV12 - Core & Buses						//
///////////////////////////////////////////////////////////

  riscv_top_ahb3lite #(
  .PC_INIT					(PC_INIT),
  .HAS_USER					(HAS_USER),
  .HAS_SUPER				(HAS_SUPER),
  .HAS_HYPER				(HAS_HYPER),
  .HAS_BPU					(HAS_BPU),
  .HAS_FPU					(HAS_FPU),
  .HAS_MMU					(HAS_MMU),
  .HAS_RVM					(HAS_RVM),
  .HAS_RVA					(HAS_RVA),
  .HAS_RVC					(HAS_RVC),
  .IS_RV32E					(IS_RV32E),
  .MULT_LATENCY			(MULT_LATENCY),
  .BREAKPOINTS				(BREAKPOINTS),
  .PMA_CNT					(PMA_CNT),
  .PMP_CNT					(PMP_CNT),
  .BP_GLOBAL_BITS			(BP_GLOBAL_BITS),
  .BP_LOCAL_BITS			(BP_LOCAL_BITS),
  .ICACHE_SIZE				(ICACHE_SIZE),
  .ICACHE_BLOCK_SIZE		(ICACHE_BLOCK_SIZE),
  .ICACHE_WAYS				(ICACHE_WAYS),
  .ICACHE_REPLACE_ALG	(ICACHE_REPLACE_ALG),
  .DCACHE_SIZE				(DCACHE_SIZE),
  .DCACHE_BLOCK_SIZE		(DCACHE_BLOCK_SIZE),
  .DCACHE_WAYS				(DCACHE_WAYS),
  .DCACHE_REPLACE_ALG	(DCACHE_REPLACE_ALG),
  .WRITEBUFFER_SIZE		(WRITEBUFFER_SIZE)
  ) 
  rv12 (
  .HRESETn,
  .HCLK,
  .pma_cfg_i,
  .pma_adr_i, 
  .ins_HSEL					(IHSEL),
  .ins_HADDR				(IHADDR),
  .ins_HWDATA				(IHWDATA),
  .ins_HRDATA				(IHRDATA),
  .ins_HWRITE				(IHWRITE),
  .ins_HSIZE				(IHSIZE),
  .ins_HBURST				(IHBURST),
  .ins_HPROT				(IHPROT),
  .ins_HTRANS				(IHTRANS),
  .ins_HMASTLOCK			(IHMASTLOCK),
  .ins_HREADY				(IHREADYOUT),
  .ins_HRESP				(IHRESP),
  
  .dat_HSEL					(DHSEL),
  .dat_HADDR				(DHADDR),
  .dat_HWDATA				(DHWDATA),
  .dat_HRDATA				(DHRDATA),
  .dat_HWRITE				(DHWRITE),
  .dat_HSIZE				(DHSIZE),
  .dat_HBURST				(DHBURST),
  .dat_HPROT				(DHPROT),
  .dat_HTRANS				(DHTRANS),
  .dat_HMASTLOCK			(DHMASTLOCK),
  .dat_HREADY				(DHREADYOUT),
  .dat_HRESP				(DHRESP),
    
  .ext_nmi,
  .ext_tint,
  .ext_sint,
  .ext_int,

  .dbg_stall,
  .dbg_strb,
  .dbg_we,
  .dbg_addr,
  .dbg_dati,
  .dbg_dato,
  .dbg_ack,
  .dbg_bp
  );
  
  endmodule