module gpuLinker(
    input logic clk,
    input logic reset,
    input logic [31:0] instruction,
    input logic executeInstruction,

);
    int core;
    logic [31:0] finishedReadMemoryDataShared, finishedReadMemoryDataGlobal, finishedWriteMemoryDataShared, 
        finishedWriteMemoryDataGlobal, readyForNextInstruction, writingMemoryDataShared, writingMemoryDataGlobal, 
        readingMemoryDataShared, readingMemoryDataGlobal;
    logic [127:0] writeBytes;
    logic [1023:0] MdrIn, MarOut, MdrOut; 
    logic [31:0] sharedMemory[128];
    always_comb begin
        for(core = 0; core < 32; core +=1) begin
            gpuCore coreInst(
                .instruction(instruction),
                .executeInstruction(executeInstruction),
                .clk(clk),
                .reset(reset),
                .threadID(i),
                .MDRIn(MdrIn[core*32 +: 32]),
                .marOut(MarOut[core*32 +: 32]),
                .mdrOut(MdrOut[core*32 +:32]),
                .readyForNextInstruction(readyForNextInstruction[core]),
                .writingMemoryDataShared(writingMemoryDataShared[core]),
                .writingMemoryDataGlobal(writingMemoryDataGlobal[core]),
                .readingMemoryDataShared(readingMemoryDataShared[core]),
                .readingMemoryDataGlobal(readingMemoryDataGlobal[core]),
                .writeBytes(writeBytes[core*4 +: 4])
            );
            MdrIn[core*32 +: 32] = (readingMemoryDataShared[core]) ? sharedMemory[MarOut[core*32 + 2 +: 7]] : 32'b0 ; 
            //the right side of above equation needs to be changed when interfacing with global memory
        end
    end
    int sharedMemoryLoop;
    always_ff @(posedge clk) begin
        for(sharedMemoryLoop = 0; sharedMemoryLoop < 32; sharedMemoryLoop +=1) begin
            if(writingMemoryDataShared[sharedMemoryLoop]) begin
                sharedMemory[MarOut[sharedMemoryLoop * 32 + 2 +:7]] <= MdrOut[sharedMemoryLoop * 32 +: 32];
            end
        end
    end
endmodule
