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

