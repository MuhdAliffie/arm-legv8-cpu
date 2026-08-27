`timescale 1ns/1ps

module ARM_CPU(
    input CLOCK,
    input [31:0] INSTRUCTION,
    input [63:0] REG_DATA1,
    input [63:0] REG_DATA2,
    input [63:0] data_memory_out,
    output reg CONTROL_REG2LOC,
    output reg CONTROL_REGWRITE,
    output reg CONTROL_MEMREAD,
    output reg CONTROL_MEMWRITE,
    output reg CONTROL_BRANCH,
    output reg [4:0] WRITE_REG,
    output [63:0] ALU_Result_Out,
    output[63:0] WRITE_REG_DATA,
    output reg [63:0] PC
);

reg [4:0] tempRegNum1;
reg [4:0] tempRegNum2;
reg [10:0] tempInstruction;

reg CONTROL_MEM2REG;
reg CONTROL_ALUSRC;
reg CONTROL_UNCON_BRANCH;
reg [1:0] CONTROL_ALU_OP;

wire tempALUZero;
wire [3:0] tempALUControl;
wire [63:0] tempALUInput2;
wire [63:0] tempImmediate;
wire [63:0] tempShiftedImmediate;

wire [63:0] nextnextPC;
reg CONTROL_JUMP;
wire [63:0] nextPC;
wire nextPCZero;
reg tempBranchZero;

/* Multiplexer for the Program Counter */
PCMux mux1(nextPC, shiftPC, CONTROL_JUMP, nextnextPC);