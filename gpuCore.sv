module gpuCore(
    input [31:0] instruction,
    input executeInstruction,
    input clk,
    input [31:0] threadId,
    input reset

);
    enum logic [21:0] {
        Decode, 
        Add, //Opcode 0000
        Bitwise, //Opcode 0001
        Multiply, //Opcode 0010
        BitShift, //Opcode 0011
        CompareImmediate, //Opcode 0100
        CompareDual, //Opcode 0101
        LoadSharedImmediate, //Opcode 1000
        LoadSharedReg,  //Opcode 1001
        LoadGlobalImmediate, //Opcode 1010
        LoadGlobalReg, //Opcode 1011
        StoreSharedImmediate, //Opcode 1100
        StoreSharedReg, //Opcode 1101
        StoreGlobalImmediate, //Opcode 1110
        StoreGlobalReg, //Opcode 1111
        storeMemoryDataShared,
        storeMemoryDataGlobal,
        writeMemoryDataShared,
        writeMemoryDataGlobal,
        readMemoryDataShared,
        readMemoryDataGlobal,
        storeReadMemoryData
    } state;
    
    logic [31:0] sr1, sr2, mult_out, main_bus, add_in2, IR, add_out, bitShiftOut, bitwiseOut, comparatorOut, comparatorInput2;
    logic [5:0] countdown;
    logic countdownOn, comparatorPositive, comparatorNegative, comparatorZero, skipLines, readyForNextInstruction;
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= Decode;
            IR <= 0;
            countdown <= 0;
        end
        else begin
            if(state == Decode && executeInstruction) begin
                IR <= instruction;
                case(instruction[31:28])
                    4'b0000: state <= Add;
                    4'b0001: state <= Bitwise;
                    4'b0010: state <= Multiply;
                    4'b0011: state <= BitShift;
                    4'b0100: state <= CompareImmediate;
                    4'b0101: state <= CompareDual;
                    4'b1000: state <= LoadSharedImmediate;
                    4'b1001: state <= LoadSharedReg;
                    4'b1010: state <= LoadGlobalImmediate;
                    4'b1011: state <= LoadGlobalReg;
                    4'b1100: state <= StoreSharedImmediate;
                    4'b1101: state <= StoreSharedReg;
                    4'b1110: state <= StoreGlobalImmediate;
                    4'b1111: state <= StoreGlobalReg;
                    default: state <= Decode;
                endcase
            end
            else begin
                case(state)
                    Add: state <= Decode;
                    Bitwise: state <= Decode;
                    Multiply: state <= Decode;
                    BitShift: state <= Decode;
                endcase
            end
            if(skipLines && (CompareImmediate || CompareDual)) begin
                countdown <= IR[24:19];
            end
            else begin
                countdown <= countdownOn ? countdown - 1 : 0;
            end
        end

    end

    always_comb begin
        countdownOn = |countdown;
        mult_out = sr1 * sr2;
        add_in2 = ((IR[21]) ? {{16{IR[15]}}, IR[15:0]} : sr2) ^ {32{IR[20]}};
        add_out = sr1 + add_in2 + {{31{1'b0}}, IR[21]};
        case(IR[21:18])
            4'b0000: bitShiftOut = {1'b0, sr1[31:1]};
            4'b0001: bitShiftOut = {2'b0, sr1[31:2]};
            4'b0010: bitShiftOut = {4'b0, sr1[31:4]};
            4'b0011: bitShiftOut = {8'b0, sr1[31:8]};
            4'b0100: bitShiftOut = {16'b0, sr1[31:16]};
            4'b0101: bitShiftOut = {24'b0, sr1[31:24]};
            4'b1000: bitShiftOut = {sr1[30:0], 1'b0};
            4'b1001: bitShiftOut = {sr1[29:0], 2'b0};
            4'b1010: bitShiftOut = {sr1[27:0], 4'b0};
            4'b1011: bitShiftOut = {sr1[23:0], 8'b0};
            4'b1100: bitShiftOut = {sr1[15:0], 16'b0};
            4'b1101: bitShiftOut = {sr1[7:0], 24'b0};
            default: bitShiftOut = sr1;
        endcase
        case(IR[21:20])
            2'b00: bitwiseOut = sr1 & sr2;
            2'b01: bitwiseOut = sr1 & {{16{IR[19]}}, IR[15:0]};
            2'b10: bitwiseOut = sr1 | sr2;
            2'b11: bitwiseOut = sr1 | {{16{IR[19]}}, IR[15:0]};
        endcase
        comparatorInput2 = (state == CompareDual) ? sr2 : {{16{IR[15]}}, IR[15:0]};
        comparatorOut = sr1 - comparatorInput2;
        comparatorNegative = comparatorOut[31];
        comparatorZero = !(|comparatorOut);
        comparatorPositive = ~(comparatorZero | comparatorNegative);
        skipLines = (comparatorNegative & ~IR[25]) | (comparatorZero & ~IR[26]) | (comparatorPositive & ~IR[27]);
        readyForNextInstruction = state == Decode;
    end


endmodule
