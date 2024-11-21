module gpuCore(
    input logic [31:0] instruction,
    input logic executeInstruction,
    input logic clk,
    input logic [31:0] threadId,
    input logic reset,
    input logic finishedReadMemoryDataShared,
    input logic finishedReadMemoryDataGlobal,
    input logic finishedWriteMemoryDataShared,
    input logic finishedWriteMemoryDataGlobal,
    input logic [31:0] MDRIn,
    output logic readyForNextInstruction,
    output logic writingMemoryDataShared,
    output logic writingMemoryDataGlobal,
    output logic readingMemoryDataShared,
    output logic readingMemoryDataGlobal,
    output logic [31:0] marOut,
    output logic [31:0] mdrOut,
    output logic [3:0] writeBytes
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
        StoreMemoryDataShared,
        StoreMemoryDataGlobal,
        WriteMemoryDataShared,
        WriteMemoryDataGlobal,
        ReadMemoryDataShared,
        ReadMemoryDataGlobal,
        StoreReadMemoryData,
        Bad
    } state;
    
    logic [31:0] SR1Out, SR2Out, multOut, mainBus, addIn2, addOut, bitShiftOut, bitwiseOut, comparatorOut, comparatorInput2, DRIn;
    logic [31:0] IR, mdr, mar;
    logic [5:0] countdown;
    logic countdownOn, comparatorPositive, comparatorNegative, comparatorZero, skipLines;
    logic [2:0] chooseSR1, chooseSR2, chooseDR;
    logic loadReg, loadMar, loadMdr, gateMultOut, gateBitwiseOut, gateBitshiftOut, gateAddOut, gateMdrOut, loadIR, gateSR1Out, externalMdrGate; 
    logic [3:0] writeBits;
    regFile regFileInst(
        .clk(clk), 
        .reset(reset),
        .loadReg(loadReg),
        .sr1(chooseSR1),
        .sr2(chooseSR2),
        .dr(chooseDR),
        .dataIn(mainBus),
        .sr1Out(SR1Out),
        .sr2Out(SR2Out),
        .threadID(threadId)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= Decode;
            IR <= 0;
            countdown <= 0;
            mar <= 0;
            mdr <= 0;
            writeBits <= 0;
        end
        else begin

            //state transitions
            if(state == Decode && executeInstruction && !countdownOn) begin
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
                    CompareImmediate: state <= Decode;
                    CompareDual: state <= Decode;
                    LoadSharedImmediate: state <= ReadMemoryDataShared;
                    LoadGlobalImmediate: state <= ReadMemoryDataGlobal;
                    LoadSharedReg: state <= ReadMemoryDataShared;
                    LoadGlobalReg: state <= ReadMemoryDataGlobal;
                    StoreMemoryDataShared: state <= WriteMemoryDataShared;
                    StoreMemoryDataGlobal: state <= WriteMemoryDataGlobal;
                    StoreSharedImmediate: state <= StoreMemoryDataShared;
                    StoreSharedReg: state <= StoreMemoryDataShared;
                    StoreGlobalImmediate: state <= StoreMemoryDataGlobal;
                    StoreGlobalReg: state <= StoreMemoryDataGlobal;
                    ReadMemoryDataShared: state <= (finishedReadMemoryDataShared) ? StoreReadMemoryData : ReadMemoryDataShared;
                    ReadMemoryDataGlobal: state <= (finishedReadMemoryDataGlobal) ? StoreReadMemoryData : ReadMemoryDataGlobal;
                    StoreReadMemoryData: state <= Decode;
                    WriteMemoryDataGlobal: state <= (finishedWriteMemoryDataGlobal) ? Decode : WriteMemoryDataGlobal;
                    WriteMemoryDataShared: state <= (finishedWriteMemoryDataShared) ? Decode : WriteMemoryDataShared;
                    Decode: state <= Decode;
                    default: state <= Bad; //this should never happen
                endcase
            end

            //For the Countdown
            if(skipLines && (state == CompareImmediate || state == CompareDual)) begin
                countdown <= IR[24:19];
            end
            else begin
                if(executeInstruction && countdownOn) begin
                    countdown <= countdown - 1;
                end
                else begin
                    countdown <= countdown;
                end
            end

            //For Mar
            if(loadMDR) begin
                mdr <= (externalMdrGate) ? MDRIn : mainBus; //if externalMDRGate is 1, then get the MDR value from external to the module
            end

            mar <= (loadMar) ? mainBus : mar;

            if(state == StoreGlobalImmediate) begin
                writeBits <= IR[21:18]
            end
            else if (state == StoreGlobalReg) begin
                writeBits <= IR[18:15];
            end
        end
    end

    always_comb begin
        writeBytes = writeBits;
        countdownOn = |countdown;
        multOut = SR1Out * SR2Out;
        addIn2 = ((IR[21]) ? {{16{IR[15]}}, IR[15:0]} : SR2Out) ^ {32{IR[20]}};
        addOut = SR1Out + addIn2 + {{31{1'b0}}, IR[20]};
        case(IR[21:18])
            4'b0000: bitShiftOut = {1'b0, SR1Out[31:1]};
            4'b0001: bitShiftOut = {2'b0, SR1Out[31:2]};
            4'b0010: bitShiftOut = {4'b0, SR1Out[31:4]};
            4'b0011: bitShiftOut = {8'b0, SR1Out[31:8]};
            4'b0100: bitShiftOut = {16'b0, SR1Out[31:16]};
            4'b0101: bitShiftOut = {24'b0, SR1Out[31:24]};
            4'b1000: bitShiftOut = {SR1Out[30:0], 1'b0};
            4'b1001: bitShiftOut = {SR1Out[29:0], 2'b0};
            4'b1010: bitShiftOut = {SR1Out[27:0], 4'b0};
            4'b1011: bitShiftOut = {SR1Out[23:0], 8'b0};
            4'b1100: bitShiftOut = {SR1Out[15:0], 16'b0};
            4'b1101: bitShiftOut = {SR1Out[7:0], 24'b0};
            default: bitShiftOut = SR1Out;
        endcase
        case(IR[21:20])
            2'b00: bitwiseOut = SR1Out & SR2Out;
            2'b01: bitwiseOut = SR1Out & {{16{IR[19]}}, IR[15:0]};
            2'b10: bitwiseOut = SR1Out | SR2Out;
            2'b11: bitwiseOut = SR1Out | {{16{IR[19]}}, IR[15:0]};
        endcase
        comparatorInput2 = (state == CompareDual) ? SR2Out : {{16{IR[15]}}, IR[15:0]};
        comparatorOut = SR1Out - comparatorInput2;
        comparatorNegative = comparatorOut[31];
        comparatorZero = !(|comparatorOut);
        comparatorPositive = ~(comparatorZero | comparatorNegative);
        skipLines = (comparatorNegative & ~IR[25]) | (comparatorZero & ~IR[26]) | (comparatorPositive & ~IR[27]);
        readyForNextInstruction = state == Decode;
    end





    always_comb begin
        // Default values for control signals
        loadReg = 1'b0;
        loadMar = 1'b0;
        loadMdr = 1'b0;
        gateMultOut = 1'b0;
        gateBitwiseOut = 1'b0;
        gateBitshiftOut = 1'b0;
        gateAddOut = 1'b0;
        gateMdrOut = 1'b0;
        gateSR1Out = 1'b0;
        writingMemoryDataGlobal = 1'b0;
        writingMemoryDataShared = 1'b0;
        readingMemoryDataGlobal = 1'b0;
        readingMemoryDataShared = 1'b0;
        externalMdrGate = 1'b0;
        // State-based control signal assignments
        case (state)
            Decode: begin
            end
            Add: begin
                loadReg = 1; // Load result into register
                gateAddOut = 1; // Enable ALU add output
            end
            Bitwise: begin
                loadReg = 1; // Load result into register
                gateBitwiseOut = 1; // Enable bitwise operation output
            end
            Multiply: begin
                loadReg = 1; // Load result into register
                gateMultOut = 1; // Enable multiplier output
            end
            BitShift: begin
                loadReg = 1; // Load result into register
                gateBitshiftOut = 1; // Enable bit shift output
            end
            CompareImmediate: begin

            end
            CompareDual: begin

            end
            LoadSharedImmediate: begin
                loadMar = 1; // Load address into MAR
                gateAddOut = 1;
            end
            LoadSharedReg: begin
                loadMar = 1; // Load memory data register
                gateAddOut = 1; 
            end
            LoadGlobalImmediate: begin
                loadMar = 1; // Load global address into MAR
                gateAddOut = 1; 
            end
            LoadGlobalReg: begin
                loadMar = 1; // Load global data into MDR
                gateAddOut = 1; 
            end
            StoreSharedImmediate: begin
                loadMar = 1; // Load address into MAR
                gateAddOut = 1; 
            end
            StoreSharedReg: begin
                loadMar = 1; // Load address into MAR
                gateAddOut = 1; 
            end
            StoreGlobalImmediate: begin
                loadMar = 1; // Load address into MAR
                gateAddOut = 1; 
            end
            StoreGlobalReg: begin
                loadMar = 1; // Load address into MAR
                gateAddOut = 1; 
            end
            StoreMemoryDataShared: begin
                loadMdr = 1; // Load address into MAR
                gateSR1Out = 1; 
            end
            StoreMemoryDataGlobal: begin
                loadMdr = 1; // Load address into MAR
                gateSR1Out = 1; 
            end
            WriteMemoryDataShared: begin
                writingMemoryDataShared = 1;
            end
            WriteMemoryDataGlobal: begin
                writingMemoryDataGlobal = 1;
            end
            ReadMemoryDataShared: begin
                readingMemoryDataShared = 1;
                externalMdrGate = 1;
            end
            ReadMemoryDataGlobal: begin
                readingMemoryDataGlobal = 1;
                externalMdrGate = 1;
            end
            StoreReadMemoryData: begin
                loadReg = 1;
                gateMdrOut = 1;
            end
            default: begin

            end
        endcase
        
        marOut = mar;
        mdrOut = mdr;
           
        case (1'b1)
            gateMultOut: mainBus = multOut;
            gateBitwiseOut: mainBus = bitwiseOut;
            gateBitshiftOut: mainBus = bitShiftOut;
            gateAddOut: mainBus = addOut;
            gateMdrOut: mainBus = mdr;
            gateSR1Out: mainBus = SR1Out;
            default: mainBus = 32'hXXXX;
        endcase
    end

endmodule


module regFile(
    input logic clk,
    input logic reset,
    input logic loadReg,
    input logic [2:0] sr1,
    input logic [2:0] sr2,
    input logic [2:0] dr,
    input logic [31:0] threadID,
    input logic [31:0] dataIn,
    output logic [31:0] sr1Out,
    output logic [31:0] sr2Out
);
    logic [31:0] registers [7];
    int resetI;
    always_ff @(posedge clk) begin
        if(reset) begin
            for(resetI = 0; resetI < 7; resetI += 1) begin
                registers[resetI] <= 0;
            end
        end
        else begin
            if(loadReg) begin
                registers[dr] <= dataIn;
            end
        end
    end
    always_comb begin
        sr1Out = (&sr1) ? threadID : registers[sr1];
        sr2Out = (&sr2) ? threadID : registers[sr2];
    end
endmodule

