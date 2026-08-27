# ARM LEGv8 Pipelined Processor: Comprehensive Verilog Module Documentation

This document provides a line-by-line and block-by-block technical explanation of every Verilog module located in `src-ref/`. 

The core design implements a **5-stage pipelined 64-bit ARM LEGv8 processor** (Instruction Fetch $\rightarrow$ Instruction Decode $\rightarrow$ Execute $\rightarrow$ Memory $\rightarrow$ Write-Back) featuring:
- Hazard detection and pipeline stalls (for Load-Use data hazards).
- Data forwarding / bypassing (from EX/MEM and MEM/WB stages to the ALU).
- Branch prediction / resolution at the Memory stage.
- 64-bit register file and 64-bit datapath with 32-bit instruction encoding.

---

## Table of Contents

1. [Architectural Overview & Pipeline Structure](#1-architectural-overview--pipeline-structure)
2. [Instruction Fetch (IF) Stage Modules](#2-instruction-fetch-if-stage-modules)
   - [2.1 ProgramCounter.v](#21-programcounterv)
   - [2.2 Adder.v](#22-adderv)
   - [2.3 ProgramCounterMUX.v](#23-programcountermuxv)
   - [2.4 InstructionMemory.v](#24-instructionmemoryv)
   - [2.5 IFID.v](#25-ifidv)
3. [Instruction Decode & Register Read (ID) Stage Modules](#3-instruction-decode--register-read-id-stage-modules)
   - [3.1 RegisterMux.v](#31-registermuxv)
   - [3.2 RegisterModule.v](#32-registermodulev)
   - [3.3 SignExtend.v](#33-signextendv)
   - [3.4 ControlUnit.v](#34-controlunitv)
   - [3.5 ControlUnitMUX.v](#35-controlunitmuxv)
   - [3.6 HazardDetectionUnit.v](#36-hazarddetectionunitv)
   - [3.7 IDEX.v](#37-idexv)
4. [Execution (EX) Stage Modules](#4-execution-ex-stage-modules)
   - [4.1 ShiftLeft2.v](#41-shiftleft2v)
   - [4.2 ALUControl.v](#42-alucontrolv)
   - [4.3 ForwardingUnit.v](#43-forwardingunitv)
   - [4.4 ForwardingUnitALUMuxA.v](#44-forwardingunitalumuxav)
   - [4.5 ForwardingUnitALUMuxB.v](#45-forwardingunitalumuxbv)
   - [4.6 ALUMux.v](#46-alumuxv)
   - [4.7 ALU.v](#47-aluv)
   - [4.8 EXMEM.v](#48-exmemv)
5. [Memory Access (MEM) Stage Modules](#5-memory-access-mem-stage-modules)
   - [5.1 DataMemory.v](#51-datamemoryv)
   - [5.2 MEMWB.v](#52-memwbv)
6. [Write-Back (WB) Stage Modules](#6-write-back-wb-stage-modules)
   - [6.1 DataMemoryMUX.v](#61-datamemorymuxv)
7. [Top-Level Processor & Simulation Testbench](#7-top-level-processor--simulation-testbench)
   - [7.1 ARMLEG.v](#71-armlegv)
   - [7.2 Clock.v](#72-clockv)
   - [7.3 ARMLEGvtf.v](#73-armlegvtfv)
8. [Supplementary Reference Implementation](#8-supplementary-reference-implementation)
   - [8.1 MIPS.v](#81-mipsv)
9. [Hardware Engineering & Synthesis Analysis](#9-hardware-engineering--synthesis-analysis)

---

## 1. Architectural Overview & Pipeline Structure

The processor follows the classic RISC 5-stage pipeline:

```
[ IF Stage ] --------> [ ID Stage ] --------> [ EX Stage ] --------> [ MEM Stage ] --------> [ WB Stage ]
 ProgramCounter         RegisterModule         ALU                    DataMemory             DataMemoryMUX
 InstructionMemory      ControlUnit            ALUControl
 Adder (PC + 4)         SignExtend             Branch Adder
                        HazardDetection        ForwardingUnit
      ||                     ||                     ||                     ||
   [ IF/ID ]              [ ID/EX ]              [ EX/MEM ]             [ MEM/WB ]
```

- **IF (Instruction Fetch):** The PC provides the address to Instruction Memory to fetch a 32-bit instruction. An adder computes `PC + 4`.
- **ID (Instruction Decode):** The 32-bit instruction is decoded into control signals. Register operands are read from the 32-entry $\times$ 64-bit Register File. Immediates are sign-extended. Hazard Detection stalls the pipeline if a load-use conflict arises.
- **EX (Execute):** The ALU performs arithmetic/logical operations. Forwarding multiplexers select between register operands and forwarded results. The branch target address (`PC + (Imm << 2)`) is calculated.
- **MEM (Memory):** Read/write operations take place in Data Memory. Branch decisions (`isBranch & zeroFlag`) redirect the PC if taken.
- **WB (Write-Back):** The result (from the ALU or Data Memory) is committed back to the destination register in the Register File.

---

## 2. Instruction Fetch (IF) Stage Modules

### 2.1 `ProgramCounter.v`
Holds the 64-bit address of the currently executing instruction.

#### Interface:
- `input CLOCK`: Master system clock.
- `input RESET`: Asynchronous reset signal.
- `input PCWire`: PC Write Enable (stalls PC when `0`).
- `input [63:0] programCounter_in`: Next PC address (`PC + 4` or branch target).
- `output reg [63:0] programCounter_out`: Current PC value.

#### Code & Block-by-Block Explanation:
```verilog
always @(posedge CLOCK) begin
    if(PCWire) begin
        if (programCounter_in === 64'bx) begin
            programCounter_out  <= 0;
        end else begin
            programCounter_out <= programCounter_in;
        end
    end
end
```
- **`always @(posedge CLOCK)`:** Sequential logic triggered on the rising clock edge.
- **`if (PCWire)`:** Write-enable gate. If `PCWire == 0` (hazard stall asserted), PC holds its previous value.
- **`if (programCounter_in === 64'bx)`:** Case equality test (`===`). In simulation startup, uninitialized signals default to `x`. If undefined, it initializes `programCounter_out` to 0.
- **`else programCounter_out <= programCounter_in;`:** Non-blocking synchronous transfer of the next instruction address.

```verilog
always @(RESET) begin
    programCounter_out = 0;
end
```
- **`always @(RESET)`:** Triggers on any transition of `RESET` to clear the program counter to `0`.

---

### 2.2 `Adder.v`
Dedicated combinational 64-bit adder used for:
1. `PC + 4` sequential address computation in the IF stage.
2. Branch target calculation (`PC + shiftedOffset`) in the EX stage.

#### Interface:
- `input [63:0] incrementBy`: Offset to add (e.g., `64'd4` or shifted immediate).
- `input [63:0] programCounter`: Base address.
- `output reg [63:0] adderResult`: Resulting 64-bit address.

#### Code & Explanation:
```verilog
always @ (*) begin
    adderResult = programCounter + incrementBy;
end
```
- Continuous combinational addition. Triggers on any input change (`@*`) and performs 64-bit unsigned binary addition.

---

### 2.3 `ProgramCounterMUX.v`
2-to-1 64-bit multiplexer choosing the next Program Counter source.

#### Interface:
- `input [63:0] adderResult`: Sequential address (`PC + 4`).
- `input [63:0] branch`: Branch destination address (`PC + offset`).
- `input PCsrc`: Branch selection flag (`EXMEM_isBranch & EXMEM_ALUzero`).
- `output reg [63:0] programCounterMUXout`: Selected address routed to `programCounter_in`.

#### Code & Explanation:
```verilog
always @(*) case (PCsrc)
    0: programCounterMUXout = adderResult;
    1: programCounterMUXout = branch;
    default: programCounterMUXout = adderResult;
endcase
```
- When `PCsrc == 0`: Normal sequential execution (`PC + 4`).
- When `PCsrc == 1`: Branch taken; redirect PC to branch address.
- `default`: Failsafe defaults to `adderResult` to prevent latch synthesis.

---

### 2.4 `InstructionMemory.v`
Byte-addressed ROM modeling instruction storage. Contains preloaded machine code test cases for datapath, forwarding, and hazard tests.

#### Interface:
- `input [63:0] programCounter`: 64-bit address from PC.
- `output reg [31:0] CPU_Instruction`: 32-bit instruction fetched from memory.

#### Code & Explanation:
```verilog
reg [8:0] instructionMemoryData[63:0]; // 64 memory cells (byte storage)
```
- **`initial` block (lines 9–106):** Initializes memory with LEGv8 machine instructions:
  - *Datapath tests:* `LDUR X10, [X1, #40]`, `SUB X11, X2, X3`, `ADD X12, X3, X4`, `LDUR X13, [X1, #48]`, `ADD X14, X5, X6`.
  - *Forwarding unit tests:* `SUB X2, X1, X3`, `AND X12, X2, X5`, `ORR X13, X6, X2`, `ADD X14, X2, X2`, `STUR X15, [X2, #100]`.
  - *Hazard tests:* Consecutive dependent instructions exercising load-use stalls.

```verilog
always @(programCounter) begin
    CPU_Instruction[8:0]   = instructionMemoryData[programCounter+3];
    CPU_Instruction[16:8]  = instructionMemoryData[programCounter+2];
    CPU_Instruction[24:16] = instructionMemoryData[programCounter+1];
    CPU_Instruction[31:24] = instructionMemoryData[programCounter];
end
```
- Combines 4 consecutive bytes in big-endian order to form a 32-bit instruction word when `programCounter` updates.

---

### 2.5 `IFID.v`
Pipeline register separating the **Instruction Fetch (IF)** and **Instruction Decode (ID)** stages.

#### Interface:
- `input CLOCK`: Clock signal.
- `input IFID_Write`: Pipeline register write enable from Hazard Detection Unit.
- `input [63:0] programCounter_in`: Current PC value from IF stage.
- `input [31:0] CPUInstruction_in`: Fetched instruction word.
- `output reg [63:0] programCounter_out`: Registered PC forwarded to ID stage.
- `output reg [31:0] CPUInstruction_out`: Registered instruction word for decode.

#### Code & Explanation:
```verilog
always @(posedge CLOCK) begin
    if(IFID_Write) begin
        programCounter_out <= programCounter_in;
        CPUInstruction_out <= CPUInstruction_in;
    end
end
```
- Synchronously latches the PC and instruction on the rising clock edge.
- If `IFID_Write == 0` (load-use hazard detected), the register contents remain unchanged, preserving the current instruction for another cycle (stall).

---

## 3. Instruction Decode & Register Read (ID) Stage Modules

### 3.1 `RegisterMux.v`
2-to-1 5-bit multiplexer for selecting the second register read address (`ReadAddress2`).

#### Interface:
- `input [4:0] instructionMemory`: Register field `Rm` (`Instruction[20:16]`).
- `input [4:0] targetAddress`: Register field `Rd` (`Instruction[4:0]`).
- `input reg2Loc`: Control signal from Control Unit.
- `output reg [4:0] registerMUXout`: 5-bit register index routed to `readAddress2` of the Register File.

#### Code & Explanation:
```verilog
always @(*) case (reg2Loc)
    0: registerMUXout = instructionMemory; // Rm (R-type instructions)
    1: registerMUXout = targetAddress;     // Rd (Store STUR and CBZ instructions)
    default: registerMUXout = instructionMemory;
endcase
```
- In R-type instructions (e.g. `ADD`, `SUB`), the second operand is register `Rm` (`Instruction[20:16]`).
- In store (`STUR`) and conditional branch (`CBZ`) instructions, the data to be written or tested is in `Rd` (`Instruction[4:0]`), so `reg2Loc = 1` selects `Rd` as the second register to read.

---

### 3.2 `RegisterModule.v`
32-entry $\times$ 64-bit general-purpose Register File (registers `X0` to `X30`, with `XZR` at index 31).

#### Interface:
- `input CLOCK`: Master clock.
- `input [4:0] readAddress1`: 5-bit address for operand 1 (`Rn`).
- `input [4:0] readAddress2`: 5-bit address for operand 2 (`Rm` or `Rd`).
- `input [4:0] writeAddress`: 5-bit destination register index (`Rd`).
- `input [63:0] writeData`: 64-bit data to write (from WB stage).
- `input regWrite`: Write enable control signal.
- `output reg [63:0] regData1`: 64-bit data read from `readAddress1`.
- `output reg [63:0] regData2`: 64-bit data read from `readAddress2`.

#### Code & Explanation:
```verilog
reg [63:0] registerData[31:0];
```
- Internal storage array containing thirty-two 64-bit registers.
- Initialized with test values (`X31 = 0`, `X1 = 16`, `X2 = 12`, etc.) in lines 17–26.

```verilog
always @(*) begin
    if (regWrite == 1) begin
        registerData[writeAddress] <= writeData;
    end
end
```
- Writes incoming data to `registerData[writeAddress]` when `regWrite` is asserted.

```verilog
always @(negedge CLOCK) begin
    regData1 <= registerData[readAddress1];
    regData2 <= registerData[readAddress2];
end
```
- **Read on Negative Clock Edge:** Reading registers on the falling edge (`negedge CLOCK`) allows written data from the first half of the cycle to be read during the second half, preventing read-before-write race conditions in pipelined execution.

---

### 3.3 `SignExtend.v`
Sign-extension unit that converts instruction immediate fields into 64-bit two's complement values.

#### Interface:
- `input [31:0] inputInstruction`: 32-bit raw instruction.
- `output reg [63:0] signExtendedInstruction`: 64-bit sign-extended immediate.

#### Code & Explanation:
```verilog
always @(*) begin
    if (inputInstruction[31:26] == 6'b000101) begin // B (Unconditional Branch)
        signExtendedInstruction[25:0] = inputInstruction[25:0];
        signExtendedInstruction[63:26] = {63{signExtendedInstruction[25]}};

    end else if (inputInstruction[31:24] == 8'b10110100) begin // CBZ (Compare & Branch on Zero)
        signExtendedInstruction[19:0] = inputInstruction[23:5];
        signExtendedInstruction[63:20] = {63{signExtendedInstruction[19]}};

    end else begin // D-Type (Load LDUR / Store STUR)
        signExtendedInstruction[9:0] = inputInstruction[20:12];
        signExtendedInstruction[63:10] = {63{signExtendedInstruction[9]}};
    end
end
```
- **Branch (`B`):** 26-bit immediate field `[25:0]`, sign-extended to bit 63 using bit 25.
- **Compare and Branch on Zero (`CBZ`):** 19-bit immediate field `[23:5]`, sign-extended to bit 63 using bit 19.
- **D-Type Format (`LDUR`/`STUR`):** 9-bit address offset `[20:12]`, sign-extended to bit 63 using bit 9.

---

### 3.4 `ControlUnit.v`
Main combinational decoder that decodes the instruction opcode and generates control signals for all stages.

#### Interface:
- `input [10:0] controlInstruction_in`: 11-bit opcode field (`Instruction[31:21]`).
- `output reg reg2Loc`: Selects `Rm` (0) vs `Rd` (1) for Register Read 2.
- `output reg ALUsrc`: Selects Register Data (0) vs Sign-Extended Immediate (1) for ALU input B.
- `output reg memtoReg`: Selects ALU result (0) vs Memory Read Data (1) to write to register.
- `output reg regWrite`: Enables register write-back.
- `output reg memRead`: Enables Data Memory read.
- `output reg memWrite`: Enables Data Memory write.
- `output reg branch`: Branch control signal (`1` for `CBZ`).
- `output reg [1:0] ALUop`: 2-bit code telling ALUControl how to decode the operation.

#### Instruction Decoding Table:

| Instruction | Opcode Pattern | `reg2Loc` | `ALUsrc` | `memtoReg` | `regWrite` | `memRead` | `memWrite` | `branch` | `ALUop` |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **`B`** | `000101xxxxx` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | `2'b01` |
| **`CBZ`** | `10110100xxx` | 1 | 0 | 0 | 0 | 0 | 0 | 1 | `2'b01` |
| **`LDUR`** | `11111000010` | 1 | 1 | 1 | 1 | 1 | 0 | 0 | `2'b00` |
| **`STUR`** | `11111000000` | 1 | 1 | X | 0 | 0 | 1 | 0 | `2'b00` |
| **R-Type (`ADD`, `SUB`, `AND`, `ORR`)** | `10001011000` etc. | 0 | 0 | 0 | 1 | 0 | 0 | 0 | `2'b10` |

---

### 3.5 `ControlUnitMUX.v`
Multiplexer that injects a pipeline bubble (NOP) during a hazard stall.

#### Interface:
- `input [10:0] controlInstruction_in`: Raw opcode from `IF/ID`.
- `input ControlWire`: Signal from `HazardDetectionUnit`.
- `output reg [10:0] controlMuxout`: Opcode passed to `ControlUnit`.

#### Code & Explanation:
```verilog
always @(*) case (ControlWire)
    0: controlMuxout = zeroData;                 // Stall: clear opcode to 0 (forces all control signals to 0)
    1: controlMuxout = controlInstruction_in;    // Normal: pass instruction opcode
    default: controlMuxout = controlInstruction_in;
endcase
```
- When `ControlWire == 0`, it forces `controlMuxout = 11'b0`. In `ControlUnit.v`, a `0` opcode falls through to `default:`, deasserting `regWrite`, `memWrite`, `branch`, etc., effectively inserting a **NOP bubble**.

---

### 3.6 `HazardDetectionUnit.v`
Detects **Load-Use Data Hazards** where an instruction immediately following a `LDUR` depends on the loaded value before it is available from memory.

#### Interface:
- `input IDEX_MemRead`: Set if the instruction in EX stage is a load (`LDUR`).
- `input EXMEM_RegWrite`: Destination write enable from EX/MEM stage.
- `input [4:0] IDEX_RegisterRd`: Destination register of instruction in EX stage.
- `input [4:0] IFID_RegisterRm`: Source register 2 of instruction in ID stage.
- `input [4:0] IFID_RegisterRn`: Source register 1 of instruction in ID stage.
- `output reg IFID_Write`: Enables/disables update of IF/ID pipeline register.
- `output reg PCWire`: Enables/disables update of Program Counter register.
- `output reg ControlWire`: Clears control signals to 0 (bubble insertion).

#### Code & Logic Explanation:
```verilog
always @(*) begin
    if (((EXMEM_RegWrite==1'b0) || IDEX_MemRead) && 
        ((IDEX_RegisterRd == IFID_RegisterRn) || (IDEX_RegisterRd == IFID_RegisterRm))) begin
        IFID_Write = 1'b0;   // Freeze IF/ID register
        PCWire = 1'b0;       // Freeze PC
        ControlWire = 1'b0;  // Inject bubble (zero out control signals)
    end else begin
        IFID_Write = 1'b1;   // Normal execution
        PCWire = 1'b1;
        ControlWire = 1'b1;
    end
end
```
- If the instruction currently in `EX` stage is loading a register (`IDEX_MemRead == 1`) and its destination (`IDEX_RegisterRd`) matches either source register of the instruction in `ID` stage (`IFID_RegisterRn` or `IFID_RegisterRm`):
  1. **Stall PC (`PCWire = 0`):** Prevents fetching a new instruction.
  2. **Stall IF/ID (`IFID_Write = 0`):** Keeps the current instruction in the Decode stage.
  3. **Zero Controls (`ControlWire = 0`):** Injects a NOP into the EX stage for one cycle so the load can complete.

---

### 3.7 `IDEX.v`
Pipeline register separating the **Instruction Decode (ID)** and **Execution (EX)** stages.

#### Latching Structure:
Carries control signals and datapath values grouped by their consumption stage:
- **EX Stage Signals:** `ALUop`, `ALUsrc`.
- **MEM Stage Signals:** `isBranch`, `memRead`, `memWrite`.
- **WB Stage Signals:** `regWrite`, `memToReg`.
- **Datapath Data:** `programCounter`, `regData1`, `regData2`, `signExtend`, `ALUcontrol` (11-bit opcode), source registers `registerRm`, `registerRn`, and destination register `writeReg`.

All values are synchronously latched on `posedge CLOCK` using non-blocking assignments (`<=`).

---

## 4. Execution (EX) Stage Modules

### 4.1 `ShiftLeft2.v`
Combinational word alignment shifter for branch offsets.

#### Code & Explanation:
```verilog
always @(*) begin
    outputData = inputData << 2;
end
```
- Shifts the 64-bit sign-extended immediate left by 2 bit positions (multiplying by 4), converting the instruction-count offset into a 4-byte-aligned byte address for the branch adder.

---

### 4.2 `ALUControl.v`
Decodes the 2-bit `ALUop` from the main Control Unit combined with the 11-bit `opcodeField` to generate the 4-bit `ALUoperation` control code.

#### Code & Explanation:
```verilog
always @(*) case (ALUop)
    2'b00 : ALUoperation = 4'b0010; // Memory access (LDUR/STUR: ADD)
    2'b01 : ALUoperation = 4'b0111; // Branch (CBZ: pass operand B to test zero)
    2'b10 : case (opcodeField)       // R-Type instructions
        11'b10001011000 : ALUoperation = 4'b0010; // ADD
        11'b11001011000 : ALUoperation = 4'b0110; // SUB
        11'b10001010000 : ALUoperation = 4'b0000; // AND
        11'b10101010000 : ALUoperation = 4'b0001; // ORR
    endcase
endcase
```

---

### 4.3 `ForwardingUnit.v`
Resolves **Data Hazards (RAW - Read After Write)** by detecting when an ALU operand depends on a result calculated by an earlier instruction currently in the `EX/MEM` or `MEM/WB` stage.

#### Interface:
- `input [4:0] IDEX_RegisterRm`: Source register 2 in EX stage.
- `input [4:0] IDEX_RegisterRn`: Source register 1 in EX stage.
- `input [4:0] EXMEM_RegisterRd`: Destination register in MEM stage.
- `input [4:0] MEMWB_RegisterRd`: Destination register in WB stage.
- `input EXMEM_RegWrite`: Destination write enable in MEM stage.
- `input MEMWB_RegWrite`: Destination write enable in WB stage.
- `output reg [1:0] ForwardA`: Forwarding selector for ALU input A.
- `output reg [1:0] ForwardB`: Forwarding selector for ALU input B.

#### Forwarding Conditions:
```verilog
// EX Hazard (Forward from EX/MEM stage - Prior instruction)
if ((EXMEM_RegWrite) && (EXMEM_RegisterRd != 31) && (EXMEM_RegisterRd == IDEX_RegisterRn))
    ForwardA = 2'b10;
if ((EXMEM_RegWrite) && (EXMEM_RegisterRd != 31) && (EXMEM_RegisterRd == IDEX_RegisterRm))
    ForwardB = 2'b10;

// MEM Hazard (Forward from MEM/WB stage - 2 instructions prior)
if ((MEMWB_RegWrite) && (MEMWB_RegisterRd != 31) && (MEMWB_RegisterRd == IDEX_RegisterRn))
    ForwardA = 2'b01;
if ((MEMWB_RegWrite) && (MEMWB_RegisterRd != 31) && (MEMWB_RegisterRd == IDEX_RegisterRm))
    ForwardB = 2'b01;
```
*(Note: Checking `RegisterRd != 31` ensures register `XZR` / zero register is never erroneously forwarded).*

---

### 4.4 `ForwardingUnitALUMuxA.v` & 4.5 `ForwardingUnitALUMuxB.v`
3-to-1 64-bit multiplexers that select the source of operands entering the ALU.

#### Mux Encoding:
- `2'b00`: Original register data read from Register File (`IDEX_RegData`).
- `2'b01`: Data forwarded from `MEM/WB` stage (`dataMemoryMUXout`).
- `2'b10`: Data forwarded from `EX/MEM` stage (`EXMEM_InputAddress`).

---

### 4.6 `ALUMux.v`
2-to-1 64-bit multiplexer for ALU input B. Selects between forwarded register data (for R-type) and the sign-extended immediate (for `LDUR`/`STUR` address calculations) based on `ALUsrc`.

---

### 4.7 `ALU.v`
64-bit Arithmetic Logic Unit.

#### Interface:
- `input [63:0] A`: 64-bit primary operand.
- `input [63:0] B`: 64-bit secondary operand.
- `input [3:0] control`: 4-bit operation control code.
- `output reg [63:0] result`: 64-bit calculation result.
- `output reg zeroFlag`: Active-high flag asserted when `result == 0`.

#### Supported Operations:
```verilog
case (control)
    4'b0000 : result = A & B;       // Bitwise AND
    4'b0001 : result = A | B;       // Bitwise OR
    4'b0010 : result = A + B;       // Addition
    4'b0110 : result = A - B;       // Subtraction
    4'b0111 : result = B;           // Pass input B (used for CBZ zero testing)
    4'b1100 : result = ~(A | B);     // Bitwise NOR
endcase

if (result == 0) zeroFlag = 1'b1;
else             zeroFlag = 1'b0;
```

---

### 4.8 `EXMEM.v`
Pipeline register separating the **Execution (EX)** and **Memory Access (MEM)** stages.

Transfers:
- Control signals: `isBranch`, `memRead`, `memWrite` (for MEM stage); `regWrite`, `memToReg` (for WB stage).
- Datapath signals: `shiftedProgramCounter` (branch target address), `ALUzero` (zero flag), `ALUresult` (memory address or calculation result), `writeDataMem` (data to store), `writeReg` (destination register index).

---

## 5. Memory Access (MEM) Stage Modules

### 5.1 `DataMemory.v`
Synchronous 128-entry $\times$ 64-bit data RAM.

#### Interface:
- `input CLOCK`: System clock.
- `input [63:0] inputAddress`: 64-bit memory address (from ALU result).
- `input [63:0] inputData`: 64-bit data to store (from register `Rt`/`Rm`).
- `input memRead`: Read enable control.
- `input memWrite`: Write enable control.
- `output reg [63:0] outputData`: 64-bit data read from memory.

#### Code & Timing Analysis:
```verilog
always @(posedge CLOCK) begin
    if (memWrite == 1) begin
        memoryData[inputAddress] <= inputData;
    end
end

always @(negedge CLOCK) begin
    if (memRead == 1) begin
        outputData <= memoryData[inputAddress];
    end
end
```
- **Synchronous Write (`posedge CLOCK`):** Writes data into `memoryData[inputAddress]` on the rising clock edge when `memWrite` is active.
- **Falling-Edge Read (`negedge CLOCK`):** Samples memory on the falling clock edge when `memRead` is active, allowing data to be ready before the subsequent WB stage.

---

### 5.2 `MEMWB.v`
Pipeline register separating the **Memory Access (MEM)** and **Write-Back (WB)** stages.

Synchronously latches:
- `regWrite`, `memToReg` control lines.
- `memAddress` (ALU calculation result).
- `memData` (read data from Data Memory).
- `writeReg` (destination register index).

---

## 6. Write-Back (WB) Stage Modules

### 6.1 `DataMemoryMUX.v`
2-to-1 64-bit multiplexer for selecting the write-back data.

#### Code & Explanation:
```verilog
always @(*) case (memToReg)
    0: dataMemoryMUXout = ALUresult; // Arithmetic/Logical results
    1: dataMemoryMUXout = readData;  // Data loaded from memory (LDUR)
    default: dataMemoryMUXout = ALUresult;
endcase
```
- When `memToReg == 0`: Routes the ALU result to `writeAddress`.
- When `memToReg == 1`: Routes data loaded from memory (`LDUR`) to `writeAddress`.

---

## 7. Top-Level Processor & Simulation Testbench

### 7.1 `ARMLEG.v`
Top-level structural integration module. It includes and wires together all 25 submodules via Verilog `` `include `` directives:
1. Instantiates all datapath elements (`ProgramCounter`, `InstructionMemory`, `RegisterModule`, `ALU`, `DataMemory`, adders, and muxes).
2. Instantiates the four pipeline boundary registers (`IFID`, `IDEX`, `EXMEM`, `MEMWB`).
3. Connects the feedback paths for `ForwardingUnit` and `HazardDetectionUnit`.
4. Connects branch resolution in the MEM stage:
   ```verilog
   ProgramCounterMUX programCounterMUX(
       adderResult,
       EXMEM_shiftedprogramCounter_out,
       (EXMEM_isBranch & EXMEM_ALUzero),
       programCounter_in
   );
   ```
   If `EXMEM_isBranch` is active and `EXMEM_ALUzero` is true, the branch condition is met and `programCounter_in` receives the branch target address.

---

### 7.2 `Clock.v`
Simulation clock generator producing asymmetric clock edges:
```verilog
always @(posedge CLOCK) begin
    #0.07 CLOCK <= ~CLOCK;
end
always @(negedge CLOCK) begin
    #0.03 CLOCK <= ~CLOCK;
end
initial begin
    CLOCK <= 1;
    #5;
    $finish;
end
```
- Simulates clock oscillation with a 0.10 ns period (10 GHz simulation rate) and calls `$finish` after 5 ns.

---

### 7.3 `ARMLEGvtf.v`
Top-level test fixture / testbench.
- Instantiates `Clock` and `ARMLEG`.
- Configures VCD wave dumping via `$dumpfile("ARMLEGvtf.vcd")` and `$dumpvars(0, ARMLEGvtf)`.
- Toggles `RESET` at `#2.5` to test reset behavior.

---

## 8. Supplementary Reference Implementation

### 8.1 `MIPS.v`
A self-contained behavioral and structural reference implementation of a **Multicycle MIPS Processor** from *Computer Organization and Design: The Hardware/Software Interface* by David A. Patterson and John L. Hennessy.

Included components inside `MIPS.v`:
1. `module CPU`: A complete finite state machine (FSM) multi-cycle MIPS CPU using a 5-step state controller:
   - State 1: Instruction Fetch (`IR <= Memory[PC>>2]`, `PC <= PC + 4`).
   - State 2: Instruction Decode & Register Fetch (`A <= Regs[rs]`, `B <= Regs[rt]`, branch target calculation).
   - State 3: Execution / Memory address calculation / Branch completion.
   - State 4: Memory access or R-type register write-back.
   - State 5: Load word (`LW`) register completion.
2. `module Datapath`: Structural multi-cycle datapath with shared memory (`IorD`), internal temporary registers (`IR`, `MDR`, `A`, `B`, `ALUOut`), and multiplexers.
3. `module MIPSCPU`: Structural top-level combining FSM controller logic with `Datapath`.
4. `module Mult4to1` & `module Mult3to1`: Parametric 32-bit multiplexers.
5. `module MIPSALU`: 32-bit ALU with zero flag.
6. `module registerfile`: 32-entry MIPS register file.

---

## 9. Hardware Engineering & Synthesis Analysis

When reviewing the modules in `src-ref/` against industry HDL best practices and FPGA/ASIC synthesis requirements, the following technical notes apply:

1. **Multi-Driven Nets in `ProgramCounter.v`:**
   `programCounter_out` is assigned in both `always @(posedge CLOCK)` and `always @(RESET)`. In physical synthesis, assigning to the same net from multiple procedural blocks results in a multi-driver conflict. The standard pattern combines them:
   ```verilog
   always @(posedge CLOCK or posedge RESET) begin
       if (RESET) programCounter_out <= 64'd0;
       else if (PCWire) programCounter_out <= programCounter_in;
   end
   ```

2. **Simulation-Only Case Equality (`===`) in `ProgramCounter.v`:**
   Hardware gates cannot test for high-impedance (`z`) or unknown (`x`). Synthesis tools will translate `===` to `==` or issue a warning.

3. **Continuous Write in `RegisterModule.v`:**
   `always @(*) if (regWrite) registerData[writeAddress] <= writeData;` creates transparent latches for registers rather than edge-triggered flip-flops. Moving register writing to `always @(posedge CLOCK)` matches standard hardware register files.

4. **Replication Syntax in `SignExtend.v`:**
   Expressions like `{63{signExtendedInstruction[25]}}` evaluate to 63 replicated bits assigned to a 38-bit slice (`[63:26]`), which relies on implicit truncation. Precise bit-width replication (e.g., `{38{...}}`) avoids compiler warnings.

5. **`timescale` Uniformity:**
   Modules like `ALU.v` and `ControlUnit.v` omit the `` `timescale `` directive, defaulting to whatever timescale was previously declared. In top-level designs, keeping a consistent timescale header across all included files avoids simulator warnings.
