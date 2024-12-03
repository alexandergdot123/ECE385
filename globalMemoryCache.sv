module globalMemoryCache(
    input logic [31:0] writingMemoryDataGlobal,
    output logic [31:0] finishedWritingMemoryDataGlobal,
    input logic [31:0] readingMemoryDataGlobal,
    output logic [31:0] finishedReadingMemoryDataGlobal, 
    input logic reset,
    input logic clk,
    input logic [1023:0] writeData,
    input logic [1023:0] mar,
    output logic [1023:0] dataOut,
    input logic globalMemFinishedRead,
    output logic [25:0] globalMemAddr,
    output logic [127:0] globalMemDataWrite,
    input logic [127:0] globalMemRead,
    output logic [7:0] globalMemoryWriteByteEnable
);

    //I'm also going to need to think about how to handle turned-off cores. I think this should only be very impactful for Writes?
    typedef enum logic [80:0] {
        Idle, 
        adjacentCheckRead,
        adjacentCheckWrite,

        adjacentReadOffAxisFirstLoadMasters,
        adjacentReadOffAxisFirstSearchHeader1,
        adjacentReadOffAxisFirstSearchHeader2,
        adjacentReadOffAxisFirstCheckHit,
        adjacentReadOffAxisFirstCacheHitDistributeData,
        adjacentReadOffAxisFirstCacheMissGlobalRead1,
        adjacentReadOffAxisFirstCacheMissGlobalRead2,
        adjacentReadOffAxisFirstCacheMissDistributeData, //in the case of a miss, write the data to cache

        adjacentReadRegularLoadMasters,
        adjacentReadRegularSearchHeader1,
        adjacentReadRegularSearchHeader2,
        adjacentReadRegularCheckHit,
        adjacentReadRegularCacheHitDistributeData,
        adjacentReadRegularCacheMissGlobalRead1,
        adjacentReadRegularCacheMissGlobalRead2,
        adjacentReadRegularCacheMissDistributeData, //in the case of a miss, write the data to cache
        //I may need more states to accommodate the last non-filled read if there was an off axis read. I don't think so though.

        nonAdjacentReadLoadMasters,
        nonAdjacentReadSearchHeader1,
        nonAdjacentReadSearchHeader2,
        nonAdjacentReadCheckHit,
        nonAdjacentReadCacheHitDistributeData,
        nonAdjacentReadCacheMissGlobalRead1,
        nonAdjacentReadCacheMissGlobalRead2,
        nonAdjacentReadCacheMissDistributeData,//I need to do this 32 times.

        //Now for writes
        adjacentWriteOffAxisFirstLoadMasters,
        adjacentWriteOffAxisFirstSearchHeader1,//also write to global here too.
        adjacentWriteOffAxisFirstSearchHeader2,
        adjacentWriteOffAxisFirstCheckHit,
        adjacentWriteOffAxisFirstPartialWrite,//and here, write to only PART of the data Bram if it hit. Otherwise don't update cache

        adjacentWriteRegularLoadMasters,
        adjacentWriteRegularAllRams,//write to every location (data, header, and ddr3)
                                    //In the future (probably not for this project) I should only update the cache for reads and writes which are in the cache already.
                                    //another possibility is I only update writes with addresses less than the boundary of the frame buffer.
        adjacentWriteOffAxisMiddleLoadMasters,
        adjacentWriteOffAxisMiddleAllRams,


        adjacentWriteOffAxisLastLoadMasters,
        adjacentWriteOffAxisLastSearchHeader1,//write to global here too!
        adjacentWriteOffAxisLastSearchHeader2,
        adjacentWriteOffAxisLastCheckHit,
        adjacentWriteOffAxisLastPartialWrite,
    
        nonAdjacentWriteLoadMasters, //I'm going to need to do this 32 times. So likely 32*5=160 cycles.
        nonAdjacentWriteSearchHeader1,
        nonAdjacentWriteSearchHeader2,
        nonAdjacentWriteCheckHit,
        nonAdjacentWritePartialWrite
    } memState;
    memState state;
    logic [4:0] nonAdjacentCounter, nonAdjacentCounterPlusOne;
    logic [2:0] adjacentCounter, adjacentCounterPlusOne;
    logic [2:0] adjacentOffAxisWriteCounter, adjacentOffAxisWriteCounterPlusOne;
    logic cacheHitBit;

    logic [31:0] masterMar;
    logic [127:0] nonAdjacentMasterDataIn;
    logic [127:0] masterDataIn;

    logic [127:0] globalMemReadRegister;

    logic [127:0] dataBramOut, dataBramIn;

    logic [15:0] bramHeaderDataIn, bramHeaderDataOut;
    logic [10:0] bramHeaderAddress;

    logic [3:0] dataBramIndividualEnable, dataBramSegmentsOn;

    logic [1:0] lateMarBits;

    logic [3:0] globalMemoryWriteByteEnableConcatenated;

    logic headerBramEnable, headerBramWriteEnable, dataBramEnable, dataBramWriteEnable, globalEnable, globalWriteEnable, loadDataBramFromGlobal, loadGlobalMemReadRegister;
    always_ff @(posedge clk) begin
        if(reset) begin
            state <= Idle;
            nonAdjacentCounter <= 0;
            adjacentCounter <= 0;
            adjacentOffAxisWriteCounter <= 0;
            globalMemReadRegister <= 0;
            lateMarBits <= 0;
        end
        else begin
            case(state)
                Idle: state <= (|writingMemoryDataGlobal) ? adjacentCheckWrite : ((|readingMemoryDataGlobal) ? adjacentCheckRead : Idle);

                //which state to go into
                adjacentCheckRead: state <= (mar[63:32] - mar[31:0] == 1) ? ((mar[1:0] == 2'b00) ? adjacentReadRegularLoadMasters : adjacentReadOffAxisFirstLoadMasters) : nonAdjacentReadLoadMasters;
                adjacentCheckWrite: state <= (mar[63:32] - mar[31:0] == 1) ? ((mar[1:0] == 2'b00) ? adjacentWriteRegularLoadMasters : adjacentWriteOffAxisFirstLoadMasters) : nonAdjacentReadLoadMasters;

                //reading off axis data. The first non-aligned data read.
                adjacentReadOffAxisFirstLoadMasters: state <= adjacentReadOffAxisFirstSearchHeader1;
                adjacentReadOffAxisFirstSearchHeader1: state <= adjacentReadOffAxisFirstSearchHeader2;
                adjacentReadOffAxisFirstSearchHeader2: state <= adjacentReadOffAxisFirstCheckHit;
                adjacentReadOffAxisFirstCheckHit: state <= (cacheHitBit) ? adjacentReadOffAxisFirstCacheHitDistributeData : adjacentReadOffAxisFirstCacheMissGlobalRead1;
                adjacentReadOffAxisFirstCacheHitDistributeData: state <= adjacentReadRegularLoadMasters;
                adjacentReadOffAxisFirstCacheMissGlobalRead1: state <= adjacentReadOffAxisFirstCacheMissGlobalRead2;
                adjacentReadOffAxisFirstCacheMissGlobalRead2: state <= (globalMemFinishedRead) ? adjacentReadOffAxisFirstCacheMissDistributeData : adjacentReadOffAxisFirstCacheMissGlobalRead2;
                adjacentReadOffAxisFirstCacheMissDistributeData: state <= adjacentReadRegularLoadMasters;

                //Occurs 8 times. The last time it occurs, I need to have special care for reading off axis data.
                adjacentReadRegularLoadMasters: state <= adjacentReadRegularSearchHeader1;
                adjacentReadRegularSearchHeader1: state <= adjacentReadRegularSearchHeader2;
                adjacentReadRegularSearchHeader2: state <= adjacentReadRegularCheckHit;
                adjacentReadRegularCheckHit: state <= (cacheHitBit) ? adjacentReadRegularCacheHitDistributeData : adjacentReadRegularCacheMissGlobalRead1;
                adjacentReadRegularCacheHitDistributeData: state <= (&adjacentCounter) ? Idle : adjacentReadRegularLoadMasters;
                adjacentReadRegularCacheMissGlobalRead1: state <= adjacentReadRegularCacheMissGlobalRead2;
                adjacentReadRegularCacheMissGlobalRead2: state <= (globalMemFinishedRead) ? adjacentReadRegularCacheMissDistributeData : adjacentReadRegularCacheMissGlobalRead2;
                adjacentReadRegularCacheMissDistributeData: state <= (&adjacentCounter) ? Idle : adjacentReadRegularLoadMasters;

                //Non adjacent reads. Loops 32 times.
                nonAdjacentReadLoadMasters: state <= nonAdjacentReadSearchHeader1;
                nonAdjacentReadSearchHeader1: state <= nonAdjacentReadSearchHeader2;
                nonAdjacentReadSearchHeader2: state <= nonAdjacentReadCheckHit;
                nonAdjacentReadCheckHit: state <= (cacheHitBit) ? nonAdjacentReadCacheHitDistributeData : nonAdjacentReadCacheMissGlobalRead1;
                nonAdjacentReadCacheHitDistributeData: state <= (&nonAdjacentCounter) ? Idle : nonAdjacentReadLoadMasters;
                nonAdjacentReadCacheMissGlobalRead1: state <= nonAdjacentReadCacheMissGlobalRead2;
                nonAdjacentReadCacheMissGlobalRead2: state <= (globalMemFinishedRead) ? nonAdjacentReadCacheMissDistributeData : nonAdjacentReadCacheMissGlobalRead2;
                nonAdjacentReadCacheMissDistributeData: state <= (&nonAdjacentCounter) ? Idle : nonAdjacentReadLoadMasters;


                //Adjacent, off axis writes
                adjacentWriteOffAxisFirstLoadMasters: state <= adjacentWriteOffAxisFirstSearchHeader1;
                adjacentWriteOffAxisFirstSearchHeader1: state <= adjacentWriteOffAxisFirstSearchHeader2;
                adjacentWriteOffAxisFirstSearchHeader2: state <= adjacentWriteOffAxisFirstCheckHit;
                adjacentWriteOffAxisFirstCheckHit: state <= (cacheHitBit) ? adjacentWriteOffAxisFirstPartialWrite : adjacentWriteRegularLoadMasters;
                adjacentWriteOffAxisFirstPartialWrite: state <= adjacentWriteOffAxisMiddleLoadMasters;
                //regular writes. This will occur 8 times.
                adjacentWriteRegularLoadMasters: state <= adjacentWriteRegularAllRams;
                adjacentWriteRegularAllRams: state <= (&adjacentCounter) ? Idle : adjacentWriteRegularLoadMasters;

                //middle of off axis writes. This will occur seven times.
                adjacentWriteOffAxisMiddleLoadMasters: state <= adjacentWriteOffAxisMiddleAllRams;
                adjacentWriteOffAxisMiddleAllRams: state <= (adjacentOffAxisWriteCounter == 7) ? adjacentWriteOffAxisLastLoadMasters : adjacentWriteOffAxisMiddleLoadMasters;

                //adjcent, off axis write. Just writes the last segment of data.
                adjacentWriteOffAxisLastLoadMasters: state <= adjacentWriteOffAxisLastSearchHeader1;
                adjacentWriteOffAxisLastSearchHeader1: state <= adjacentWriteOffAxisLastSearchHeader2;
                adjacentWriteOffAxisLastSearchHeader2: state <= adjacentWriteOffAxisLastCheckHit;
                adjacentWriteOffAxisLastCheckHit: state <=  (cacheHitBit) ? adjacentWriteOffAxisLastPartialWrite : Idle;
                adjacentWriteOffAxisLastPartialWrite: state <= Idle;

                //loops 32 times. Writes all core data streams.
                nonAdjacentWriteLoadMasters: state <= nonAdjacentWriteSearchHeader1;
                nonAdjacentWriteSearchHeader1: state <= nonAdjacentWriteSearchHeader2;
                nonAdjacentWriteSearchHeader2: state <= nonAdjacentWriteCheckHit;
                nonAdjacentWriteCheckHit: state <= (cacheHitBit) ? ((&nonAdjacentCounter) ? Idle : nonAdjacentWriteLoadMasters) : nonAdjacentWritePartialWrite;
                nonAdjacentWritePartialWrite: state <= (&nonAdjacentCounter) ? Idle : nonAdjacentWriteLoadMasters;
            endcase
            if(state == Idle) begin
                nonAdjacentCounter <= 0;
                adjacentCounter <= 0;
                adjacentOffAxisWriteCounter <= 0;
            end
            else begin
                if(state == adjacentReadRegularCacheHitDistributeData || state == adjacentReadRegularCacheMissDistributeData || state == adjacentWriteRegularAllRams) begin
                    adjacentCounter <= adjacentCounterPlusOne;
                end
                if((state == nonAdjacentWriteCheckHit && cacheHitBit) || state == nonAdjacentWritePartialWrite || 
                state == nonAdjacentReadCacheHitDistributeData || state == nonAdjacentReadCacheMissDistributeData) begin
                    nonAdjacentCounter <= nonAdjacentCounterPlusOne;
                end
                if(state == adjacentWriteOffAxisMiddleAllRams) begin
                    adjacentOffAxisWriteCounter <= adjacentOffAxisWriteCounterPlusOne;
                end
            end

            if(state == adjacentReadOffAxisFirstLoadMasters) begin 
                masterMar <= mar[31:0];
            end
            else if (state == adjacentReadRegularLoadMasters) begin
                masterMar <= mar[ { adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0], 5'b00000} +: 32];
            end
            else if (state == nonAdjacentReadLoadMasters) begin
                masterMar <= mar[{nonAdjacentCounter[4:0], 5'b00000} +:32];
            end
            else if (state == adjacentWriteOffAxisFirstLoadMasters) begin
                masterMar <= mar[31:0];
            end
            else if (state == adjacentWriteRegularLoadMasters) begin
                masterMar <= mar[{ adjacentCounter[2:0], 2'b00, 5'b00000} +: 32];
            end
            else if (state == adjacentWriteOffAxisMiddleLoadMasters) begin
                masterMar <= mar[{ adjacentOffAxisWriteCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0], 5'b00000} +: 32]; //I need to be careful with these two different counters...  
            end
            else if (state == adjacentWriteOffAxisLastLoadMasters) begin
                masterMar <= mar[{3'b111, mar[1] ^ lateMarBits[0], lateMarBits[0], 5'b00000} +: 32];
            end
            else if (state == nonAdjacentWriteLoadMasters) begin
                masterMar <= mar[{nonAdjacentCounter[4:0], 5'b00000} +:32];
            end


            if (state == adjacentWriteOffAxisFirstLoadMasters) begin
                case(mar[1:0])
                    2'b01: masterDataIn[127:32] <= writeData[95:0];
                    2'b10: masterDataIn[127:64] <= writeData[63:0];
                    2'b11: masterDataIn[127:96] <= writeData[31:0];
                endcase
            end
            else if (state == adjacentWriteRegularLoadMasters) begin
                masterDataIn <= writeData[{adjacentCounter[2:0], 2'b00, 5'b00000} +: 128];
            end
            else if (state == adjacentWriteOffAxisMiddleLoadMasters) begin
                masterDataIn <= writeData[{adjacentOffAxisWriteCounter[2:0], ~mar[1:0], 5'b00000}];
            end
            else if (state == adjacentWriteOffAxisLastLoadMasters) begin
                case(mar[1:0])
                    2'b01: masterDataIn[31:0] <= writeData[1023:992];
                    2'b10: masterDataIn[63:0] <= writeData[1023:960];
                    2'b11: masterDataIn[95:0] <= writeData[1023:928];
                endcase
            end
            else if (state == nonAdjacentWriteLoadMasters) begin
                masterDataIn <= nonAdjacentMasterDataIn;
            end

            if(loadGlobalMemReadRegister) begin
                globalMemReadRegister <= globalMemRead;
            end

            if(state == Idle) begin
                lateMarBits <= mar[1:0];
            end

        end
    end

    always_comb begin
        nonAdjacentCounterPlusOne = nonAdjacentCounter + 1;
        adjacentCounter = adjacentCounter + 1;
        adjacentOffAxisWriteCounterPlusOne = adjacentOffAxisWriteCounter + 1;
        case(mar[{nonAdjacentCounter[4:0], 5'b00000}+: 2]) //maybe I should add in another state to reduce the number of LUTs. ( up to 3 states for this branch, so still not a lot.)
            2'b00: nonAdjacentMasterDataIn[31:0] = writeData[{nonAdjacentCounter[4:0], 5'b00000} +: 32];
            2'b01: nonAdjacentMasterDataIn[63:32] = writeData[{nonAdjacentCounter[4:0], 5'b00000} +: 32];
            2'b10: nonAdjacentMasterDataIn[95:64] = writeData[{nonAdjacentCounter[4:0], 5'b00000} +: 32];
            2'b11: nonAdjacentMasterDataIn[127:96] = writeData[{nonAdjacentCounter[4:0], 5'b00000} +: 32];
        endcase



        headerBramEnable = 0;
        if (state inside {
            adjacentReadOffAxisFirstSearchHeader1, 
            adjacentReadOffAxisFirstCacheMissDistributeData, 
            adjacentReadRegularSearchHeader1, 
            adjacentReadRegularCacheMissDistributeData,
            nonAdjacentReadSearchHeader1,
            nonAdjacentReadCacheMissDistributeData,
            adjacentWriteOffAxisFirstSearchHeader1,
            adjacentWriteOffAxisFirstPartialWrite,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastSearchHeader1,
            adjacentWriteOffAxisLastPartialWrite,
            nonAdjacentWriteSearchHeader1,
            nonAdjacentWritePartialWrite
        }) begin
            headerBramEnable = 1;
        end

        case (state)
            // States where headerBramWriteEnable = 0
            adjacentReadOffAxisFirstSearchHeader1,
            adjacentReadRegularSearchHeader1,
            nonAdjacentReadSearchHeader1,
            adjacentWriteOffAxisFirstSearchHeader1,
            adjacentWriteOffAxisLastSearchHeader1,
            nonAdjacentWriteSearchHeader1: headerBramWriteEnable = 0;
    
            // States where headerBramWriteEnable = 1
            adjacentReadOffAxisFirstCacheMissDistributeData,
            adjacentReadRegularCacheMissDistributeData,
            nonAdjacentReadCacheMissDistributeData,
            adjacentWriteOffAxisFirstPartialWrite,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastPartialWrite,
            nonAdjacentWritePartialWrite: headerBramWriteEnable = 1;
    
            // Default case (optional)
            default: headerBramWriteEnable = 1'bx;
        endcase

        dataBramEnable = 0;
        if (state inside {
            adjacentReadOffAxisFirstSearchHeader1, 
            adjacentReadOffAxisFirstCacheMissDistributeData, 
            adjacentReadRegularSearchHeader1, 
            adjacentReadRegularCacheMissDistributeData,
            nonAdjacentReadSearchHeader1,
            nonAdjacentReadCacheMissDistributeData,
            adjacentWriteOffAxisFirstPartialWrite,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastPartialWrite,
            nonAdjacentWritePartialWrite
        }) begin
            dataBramEnable = 1;
        end

        case (state)
        // States where headerBramWriteEnable = 0
            adjacentReadOffAxisFirstSearchHeader1,
            adjacentReadRegularSearchHeader1,
            nonAdjacentReadSearchHeader1: dataBramWriteEnable = 0;

            // States where headerBramWriteEnable = 1
            adjacentReadOffAxisFirstCacheMissDistributeData,
            adjacentReadRegularCacheMissDistributeData,
            nonAdjacentReadCacheMissDistributeData,
            adjacentWriteOffAxisFirstPartialWrite,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastPartialWrite,
            nonAdjacentWritePartialWrite: dataBramWriteEnable = 1;

            // Default case (optional)
            default: dataBramWriteEnable = 1'bx;
        endcase

        globalEnable = 0;

        if(state inside {
            adjacentReadOffAxisFirstCacheMissGlobalRead1,
            adjacentReadRegularCacheMissGlobalRead1,
            nonAdjacentReadCacheMissGlobalRead1,
            adjacentWriteOffAxisFirstSearchHeader1,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastSearchHeader1,
            nonAdjacentWriteSearchHeader1
        }) begin
            globalEnable = 1;
        end
        
        case (state)
        // States where headerBramWriteEnable = 0
            adjacentReadOffAxisFirstCacheMissGlobalRead1,
            adjacentReadRegularCacheMissGlobalRead1,
            nonAdjacentReadCacheMissGlobalRead1: globalWriteEnable = 0;

            // States where headerBramWriteEnable = 1
            adjacentWriteOffAxisFirstSearchHeader1,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastSearchHeader1,
            nonAdjacentWriteSearchHeader1: globalWriteEnable = 1;

            // Default case (optional)
            default: globalWriteEnable = 1'bx;
        endcase

        case(state)
            adjacentReadOffAxisFirstCacheMissDistributeData,
            adjacentReadRegularCacheMissDistributeData,
            nonAdjacentReadCacheMissDistributeData: loadDataBramFromGlobal = 1;

            adjacentWriteOffAxisFirstPartialWrite,
            adjacentWriteRegularAllRams,
            adjacentWriteOffAxisMiddleAllRams,
            adjacentWriteOffAxisLastPartialWrite,
            nonAdjacentWritePartialWrite: loadDataBramFromGlobal = 0;

            default: loadDataBramFromGlobal = 1'bx;
        endcase

       
        case(state)
            adjacentReadOffAxisFirstCacheMissGlobalRead2,
            adjacentReadRegularCacheMissGlobalRead2,
            nonAdjacentReadCacheMissGlobalRead2: loadGlobalMemReadRegister = 1;
            default: loadGlobalMemReadRegister = 0;
        endcase

        dataBramIn = (loadDataBramFromGlobal) ? globalMemReadRegister : masterDataIn;

        globalMemAddr = {masterMar[24:2], 3'b0}; //Bits [3:1] should always be 0. If they aren't I fucked up (unless there is a non-consecutive write, in which case it is expected)
        
        globalMemDataWrite = masterDataIn;
        
        bramHeaderDataIn = {4'b0000, masterMar[24:13]}; //Twelve bits in the data
        
        bramHeaderAddress = masterMar[12:2]; //Eleven bits in the address. I have enough room I think if I wanted to to double this.
        
        cacheHitBit = bramHeaderDataOut[11:0] == masterMar[24:13];


        if(state == adjacentReadOffAxisFirstCacheMissDistributeData) begin
            case(lateMarBits)
                2'b01: dataBramSegmentsOn = {writingMemoryDataGlobal[2:0], 1'b0};
                2'b10: dataBramSegmentsOn = {writingMemoryDataGlobal[1:0], 2'b00};
                2'b11: dataBramSegmentsOn = {writingMemoryDataGlobal[0], 3'b000};
            endcase
        end
        else if (state == adjacentReadRegularCacheMissDistributeData) begin
            if(adjacentCounter!=3'b111) begin
                dataBramSegmentsOn = writingMemoryDataGlobal[{adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0]} +: 4];
            end
            else begin
                case(lateMarBits)
                    2'b01: dataBramSegmentsOn = {3'b000, writingMemoryDataGlobal[31]};
                    2'b10: dataBramSegmentsOn = {2'b00, writingMemoryDataGlobal[31:30]};
                    2'b11: dataBramSegmentsOn = {1'b0, writingMemoryDataGlobal[31:29]};
                endcase
            end
        end
        else if (state == nonAdjacentReadCacheMissDistributeData) begin
            dataBramSegmentsOn = 0;
            dataBramSegmentsOn[masterMar[1:0]] = writingMemoryDataGlobal[nonAdjacentCounter];
        end
        else if (state == adjacentWriteOffAxisFirstPartialWrite) begin
            case(lateMarBits)
                2'b01: dataBramSegmentsOn = {writingMemoryDataGlobal[2:0], 1'b0};
                2'b10: dataBramSegmentsOn = {writingMemoryDataGlobal[1:0], 2'b00};
                2'b11: dataBramSegmentsOn = {writingMemoryDataGlobal[0], 3'b000};
            endcase
        end
        else if (state == adjacentWriteRegularAllRams) begin
            dataBramSegmentsOn = writingMemoryDataGlobal[{adjacentCounter[2:0], 2'b00} +: 4];
        end
        else if (state == adjacentWriteOffAxisMiddleAllRams) begin
            dataBramSegmentsOn = writingMemoryDataGlobal[{adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0]} +: 4];
        end
        else if (state == adjacentWriteOffAxisLastPartialWrite) begin 
            case(lateMarBits)
                2'b01: dataBramSegmentsOn = {3'b000, writingMemoryDataGlobal[31]};
                2'b10: dataBramSegmentsOn = {2'b00, writingMemoryDataGlobal[31:30]};
                2'b11: dataBramSegmentsOn = {1'b0, writingMemoryDataGlobal[31:29]};
            endcase
        end
        else if (state == nonAdjacentWritePartialWrite) begin
            dataBramSegmentsOn = 0;
            dataBramSegmentsOn[masterMar[1:0]] = writingMemoryDataGlobal[nonAdjacentCounter];
        end
        else begin
            dataBramSegmentsOn = 4'bxxxx;
        end



        if(state == adjacentWriteOffAxisFirstSearchHeader1) begin
            case(lateMarBits)
                2'b01: globalMemoryWriteByteEnableConcatenated = {writingMemoryDataGlobal[2:0], 1'b0};
                2'b10: globalMemoryWriteByteEnableConcatenated = {writingMemoryDataGlobal[1:0], 2'b00};
                2'b11: globalMemoryWriteByteEnableConcatenated = {writingMemoryDataGlobal[0], 3'b000};
            endcase
        end
        else if (state == adjacentWriteRegularAllRams) begin
            globalMemoryWriteByteEnableConcatenated = writingMemoryDataGlobal[{adjacentCounter[2:0], 2'b00} +: 4];
        end
        else if (state == adjacentWriteOffAxisMiddleAllRams) begin
            globalMemoryWriteByteEnableConcatenated = writingMemoryDataGlobal[{adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0]} +: 4];
        end
        else if (state == adjacentWriteOffAxisLastSearchHeader1) begin
            case(lateMarBits)
                2'b01: globalMemoryWriteByteEnableConcatenated = {3'b000, writingMemoryDataGlobal[31]};
                2'b10: globalMemoryWriteByteEnableConcatenated = {2'b00, writingMemoryDataGlobal[31:30]};
                2'b11: globalMemoryWriteByteEnableConcatenated = {1'b0, writingMemoryDataGlobal[31:29]};
            endcase
        end
        else if (state == nonAdjacentWriteSearchHeader1) begin
            globalMemoryWriteByteEnableConcatenated = 0;
            globalMemoryWriteByteEnableConcatenated[masterMar[1:0]] = writingMemoryDataGlobal[nonAdjacentCounter];
        end
        else begin
            globalMemoryWriteByteEnableConcatenated = 4'bxxxx;
        end

        globalMemoryWriteByteEnable[1:0] = {2{globalMemoryWriteByteEnableConcatenated[0]}};
        globalMemoryWriteByteEnable[3:2] = {2{globalMemoryWriteByteEnableConcatenated[1]}};
        globalMemoryWriteByteEnable[5:4] = {2{globalMemoryWriteByteEnableConcatenated[2]}};
        globalMemoryWriteByteEnable[7:6] = {2{globalMemoryWriteByteEnableConcatenated[3]}};


        dataBramIndividualEnable = {4{dataBramWriteEnable}} & dataBramSegmentsOn;


        if(state == adjacentReadOffAxisFirstCacheHitDistributeData) begin //I'm going to double wire all of these. This is wasteful, and if I'm out of space I should redo this.
            case(mar[1:0])                                                //Otherwise, just load the masterDataOut and distribute it there.
                2'b01: dataOut[95:0] = dataBramOut[95:0];
                2'b10: dataOut[63:0] = dataBramOut[63:0];
                2'b11: dataOut[31:0] = dataBramOut[31:0];
            endcase
        end
        else if (state == adjacentReadRegularCacheHitDistributeData) begin
            dataOut[{adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0], 5'b00000} +: 128] = dataBramOut;
        end
        else if (state == nonAdjacentReadCacheHitDistributeData) begin
            dataOut[{nonAdjacentCounter[4:0], 5'b00000} +: 32] = dataBramOut[{masterMar[1:0], 5'b00000} +: 32];
        end 
        else if (state == adjacentReadOffAxisFirstCacheMissDistributeData) begin
            case(mar[1:0])                                                
                2'b01: dataOut[95:0] = globalMemReadRegister[95:0];
                2'b10: dataOut[63:0] = globalMemReadRegister[63:0];
                2'b11: dataOut[31:0] = globalMemReadRegister[31:0];
            endcase
        end
        else if (state == adjacentReadRegularCacheMissDistributeData) begin
            dataOut[{adjacentCounter[2:0], lateMarBits[1] ^ lateMarBits[0], lateMarBits[0], 5'b00000} +: 128] = globalMemReadRegister;
        end
        else if (state == nonAdjacentReadCacheMissDistributeData) begin
            dataOut[{nonAdjacentCounter[4:0], 5'b00000} +: 32] = globalMemReadRegister[{masterMar[1:0], 5'b00000} +: 32];
        end



        finishedWritingMemoryDataGlobal = 0;
        if(state == adjacentWriteOffAxisFirstCheckHit) begin
            case(lateMarBits)
                2'b01: finishedWritingMemoryDataGlobal[2:0] = 3'b111;
                2'b10: finishedWritingMemoryDataGlobal[2:0] = 3'b011;
                2'b11: finishedWritingMemoryDataGlobal[2:0] = 3'b001;
            endcase        
        end
        else if (state == adjacentWriteRegularAllRams) begin
            finishedWritingMemoryDataGlobal[{adjacentCounter, 2'b00} +: 4] = 4'b1111;
        end
        else if (state == adjacentWriteOffAxisMiddleAllRams) begin
            finishedWritingMemoryDataGlobal[{adjacentCounter, lateMarBits[1:0]} +: 4] = 4'b1111;
        end
        else if (state == adjacentWriteOffAxisLastCheckHit) begin
            case(lateMarBits)
                2'b01: finishedWritingMemoryDataGlobal[31:29] = 3'b111;
                2'b10: finishedWritingMemoryDataGlobal[31:29] = 3'b110;
                2'b11: finishedWritingMemoryDataGlobal[31:29] = 3'b100;
            endcase       
        end
        else if (state == nonAdjacentWriteCheckHit) begin
            finishedWritingMemoryDataGlobal[nonAdjacentCounter] = 1'b1;
        end


        finishedReadingMemoryDataGlobal = 0;
        if(state == adjacentReadOffAxisFirstCacheHitDistributeData) begin
            case(lateMarBits)
                2'b01: finishedReadingMemoryDataGlobal[2:0] = 3'b111;
                2'b10: finishedReadingMemoryDataGlobal[2:0] = 3'b001;
                2'b11: finishedReadingMemoryDataGlobal[2:0] = 3'b001;
            endcase        
        end
        else if (state == adjacentReadOffAxisFirstCacheMissDistributeData) begin
            case(lateMarBits)
                2'b01: finishedReadingMemoryDataGlobal[2:0] = 3'b111;
                2'b10: finishedReadingMemoryDataGlobal[2:0] = 3'b001;
                2'b11: finishedReadingMemoryDataGlobal[2:0] = 3'b001;
            endcase           
        end
        else if (state == adjacentReadRegularCacheHitDistributeData) begin
            finishedReadingMemoryDataGlobal[{adjacentCounter, lateMarBits[1:0]} +: 4] = 4'b1111;
        end
        else if (state == adjacentReadRegularCacheMissDistributeData) begin
            finishedReadingMemoryDataGlobal[{adjacentCounter, lateMarBits[1:0]} +: 4] = 4'b1111;    
        end
        else if (state == nonAdjacentReadCacheHitDistributeData) begin
            finishedReadingMemoryDataGlobal[nonAdjacentCounter] = 1'b1;
        end

    end
    genvar dataBram; // Generate loop variable
    generate
        for(dataBram = 0; dataBram < 4; dataBram+=1) begin //This is going to need to be 4 BRAMs because I can't make a 128 bit wide BRAM
            blk_mem_gen_2 u_blk_mem_gen_2 (
                .clka  (clk),      
                .ena   (dataBramIndividualEnable[dataBram]),       
                .wea   (dataBramWriteEnable),        
                .addra (masterMar[12:2]),    
                .dina  (dataBramIn[dataBram * 32 +: 32]),    
                .douta (dataBramOut[dataBram * 32 +: 32])
            );
        end
    endgenerate
    blk_mem_gen_3 u_blk_mem_gen_3 (
        .clka  (clk),      
        .ena   (headerBramEnable),       
        .wea   (headerBramWriteEnable),        
        .addra (bramHeaderAddress),    
        .dina  (bramHeaderDataIn),    
        .douta (bramHeaderDataOut)
    );
endmodule
