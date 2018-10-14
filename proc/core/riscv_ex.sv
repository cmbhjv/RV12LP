/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Execution Units (EX Stage)                                   //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2017-2018 ROA Logic BV                //
//             www.roalogic.com                                    //
//                                                                 //
//     Unless specifically agreed in writing, this software is     //
//   licensed under the RoaLogic Non-Commercial License            //
//   version-1.0 (the "License"), a copy of which is included      //
//   with this file or may be found on the RoaLogic website        //
//   http://www.roalogic.com. You may not use the file except      //
//   in compliance with the License.                               //
//                                                                 //
//     THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY           //
//   EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                    //
//   See the License for permissions and limitations under the     //
//   License.                                                      //
//                                                                 //
/////////////////////////////////////////////////////////////////////

import riscv_opcodes_pkg::ILEN;
import riscv_state_pkg::EXCEPTION_SIZE;
import biu_constants_pkg::*;

module riscv_ex #(
  parameter            XLEN           = 32,
  parameter [XLEN-1:0] PC_INIT        = 'h200,
  parameter            BP_GLOBAL_BITS = 2,
  parameter            HAS_RVC        = 0,
  parameter            HAS_RVA        = 0,
  parameter            HAS_RVM        = 0,
  parameter            MULT_LATENCY   = 0
)
(
  input                           rstn,
  input                           clk,

  input                           wb_stall,
  output                          ex_stall,

  //Program counter
  input      [XLEN          -1:0] id_pc,
  output reg [XLEN          -1:0] ex_pc,
                                  bu_nxt_pc,
  output                          bu_flush,
                                  bu_cacheflush,
  input      [               1:0] id_bp_predict,
  output     [               1:0] bu_bp_predict,
  output     [BP_GLOBAL_BITS-1:0] bu_bp_history,
  output                          bu_bp_btaken,
  output                          bu_bp_update,

  //Instruction
  input                           id_bubble,
  input      [ILEN          -1:0] id_instr,
  output                          ex_bubble,
  output reg [ILEN          -1:0] ex_instr,

  input      [EXCEPTION_SIZE-1:0] id_exception,
                                  mem_exception,
                                  wb_exception,
  output reg [EXCEPTION_SIZE-1:0] ex_exception,

  //from ID
  input                           id_userf_opA,
                                  id_userf_opB,
                                  id_bypex_opA,
                                  id_bypex_opB,
                                  id_bypmem_opA,
                                  id_bypmem_opB,
                                  id_bypwb_opA,
                                  id_bypwb_opB,
  input      [XLEN          -1:0] id_opA,
                                  id_opB,

  //from RF
  input      [XLEN          -1:0] rf_srcv1,
                                  rf_srcv2,

  //to MEM
  output reg [XLEN          -1:0] ex_r,

  //Bypasses
  input      [XLEN          -1:0] mem_r,
  input      [XLEN          -1:0] wb_r,

  //To State
  output     [              11:0] ex_csr_reg,
  output     [XLEN          -1:0] ex_csr_wval,
  output                          ex_csr_we,

  //From State
  input      [               1:0] st_prv,
                                  st_xlen,
  input                           st_flush,
  input      [XLEN          -1:0] st_csr_rval,

  //To DCACHE/Memory
  output     [XLEN          -1:0] dmem_adr,
                                  dmem_d,
  output                          dmem_req,
                                  dmem_we,
  output     biu_size_t           dmem_size,
  input                           dmem_ack,
  input      [XLEN          -1:0] dmem_q,
  input                           dmem_misaligned,
                                  dmem_page_fault,

  //Debug Unit
  input                           du_stall,
                                  du_stall_dly,
                                  du_flush,
  input                           du_we_pc,
  input      [XLEN          -1:0] du_dato,
  input      [              31:0] du_ie
);


  ////////////////////////////////////////////////////////////////
  //
  // Variables
  //

  //Operand generation
  logic [XLEN          -1:0] opA,opB;

  logic [XLEN          -1:0] alu_r,
                             lsu_r,
                             mul_r,
                             div_r;

  //Pipeline Bubbles
  logic                      alu_bubble,
                             lsu_bubble,
                             mul_bubble,
                             div_bubble;

  //Pipeline stalls
  logic                      lsu_stall,
                             mul_stall,
                             div_stall;

  //Exceptions
  logic [EXCEPTION_SIZE-1:0] bu_exception,
                             lsu_exception;


  ////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /*
   * Program Counter
   */
  always @(posedge clk, negedge rstn)
    if      (!rstn                 ) ex_pc <= PC_INIT;
    else if (!ex_stall && !du_stall) ex_pc <= id_pc;  //stall during DBG to retain PPC


  /*
   * Instruction
   */
  always @(posedge clk)
    if (!ex_stall) ex_instr <= id_instr;


  /*
   * Bypasses
   */

  //Ignore the bypasses during dbg_stall, use register-file instead
  //use du_stall_dly, because this is combinatorial
  //When the pipeline is longer than the time for the debugger to access the system, this fails
  always_comb
    casex ( {id_userf_opA, id_bypwb_opA, id_bypmem_opA, id_bypex_opA} )
      4'b???1: opA = du_stall_dly ? rf_srcv1 : ex_r;
      4'b??10: opA = du_stall_dly ? rf_srcv1 : mem_r;
      4'b?100: opA = du_stall_dly ? rf_srcv1 : wb_r;
      4'b1000: opA =                           rf_srcv1;
      default: opA =                           id_opA;
    endcase

  always_comb
    casex ( {id_userf_opB, id_bypwb_opB, id_bypmem_opB, id_bypex_opB} )
      4'b???1: opB = du_stall_dly ? rf_srcv2 : ex_r;
      4'b??10: opB = du_stall_dly ? rf_srcv2 : mem_r;
      4'b?100: opB = du_stall_dly ? rf_srcv2 : wb_r;
      4'b1000: opB =                           rf_srcv2;
      default: opB =                           id_opB;
    endcase


  /*
   * Execution Units
   */
  riscv_alu #(
    .XLEN ( XLEN ) )
  alu (
    .*
  );

  // Load-Store Unit
  riscv_lsu #(
    .XLEN           ( XLEN           ) )
  lsu (
    .*
  );

  // Branch Unit
  riscv_bu #(
    .XLEN           ( XLEN           ),
    .BP_GLOBAL_BITS ( BP_GLOBAL_BITS ) )
  bu (
    //Branch unit handles exceptions and relays ID-exceptions
    .bu_exception ( ex_exception ),
    .*
  );

generate
  if (HAS_RVM)
  begin
      riscv_mul #(
        .XLEN         ( XLEN         ),
        .MULT_LATENCY ( MULT_LATENCY )
      )
      mul (
        .*
      );

      riscv_div #(
        .XLEN ( XLEN ))
      div (
        .*
      );
  end
  else
  begin
      assign mul_bubble = 1'b1;
      assign mul_r      =  'h0;
      assign mul_stall  = 1'b0;

      assign div_bubble = 1'b1;
      assign div_r      =  'h0;
      assign div_stall  = 1'b0;
  end
endgenerate


  /*
   * Combine outputs into 1 single EX output
   */

  assign ex_bubble = alu_bubble & lsu_bubble & mul_bubble & div_bubble;
  assign ex_stall  = wb_stall | lsu_stall | mul_stall | div_stall;

  //result
  always_comb
    unique casex ( {mul_bubble,div_bubble,lsu_bubble} )
      3'b110 : ex_r = lsu_r;
      3'b101 : ex_r = div_r;
      3'b011 : ex_r = mul_r;
      default: ex_r = alu_r;
    endcase

endmodule 
