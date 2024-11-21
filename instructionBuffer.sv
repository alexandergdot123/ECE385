module instructionBuffer(
    input logic clk,
    input logic reset,
    input logic coresReady,
    input logic newInstruction,
    input logic [31:0] instructionIn,
    output logic [31:0] instructionOut,
    output logic [4:0] bufferFill,
    output logic sentInstruction
);

    //can only have maximum 31 items in the buffer

    logic [31:0] currentInstruction;
    logic [4:0] counter;
    logic [4:0] counterUp, counterDown;
    logic [31:0] instructions[32];
    int i;
    always_ff @(posedge clk) begin

        //instruction buffer logic
        if(reset) begin
            instructions[31] <= 0;
        end
        for(i = 0; i<31; i+=1) begin
            if(reset) begin
                instructions[i] <= 32'b0;
            end
            else begin
                if(coresReady && i != counter && newInstruction) begin //if the cores are ready and a new instruction is ready, shift down except for the counter
                    instructions[i] <= instructions[i+1];
                end
                else if (coresReady && newInstruction) begin //this is an else-if, so it assumes i== counter and there is a new instruction
                    instructions[counter] <= instructionIn;
                end
                else if (newInstruction && counter == i) begin //if the cores are busy and a new instruction is ready
                    instructions[counter] <= instructionIn;
                end
                else if (coresReady) begin
                    instructions[i] <= instructions[i+1];
                end
            end
        end

        //counter logic
        if(reset) begin
            counter <= 0;
        end
        else if(coresReady && !newInstruction && |counter) begin
            counter <= counterDown;
        end
        else if(!coresReady && newInstruction) begin
            counter <= counterUp;
        end

        //currentInstruction logic
        if(reset) begin
            currentInstruction <= 0;
        end
        else if (coresReady && !sentInstruction) begin
            currentInstruction <= instructions[0];
        end
        else if (coresReady) begin
            currentInstruction <= 32'b0;
        end

        //sentInstruction logic
        if (reset) begin
            sentInstruction <= 1'b0;  // Reset `sentInstruction` on reset.
        end
        else if (coresReady && !sentInstruction && (counter != 0 || newInstruction)) begin
            sentInstruction <= 1'b1;  // Assert `sentInstruction` for one cycle if cores are ready and there's work to do.
        end
        else begin
            sentInstruction <= 1'b0;  // Automatically deassert `sentInstruction` after one cycle.
        end       
        
    end
    always_comb begin
        counterUp = counter + 1;
        counterDown = counter - 1;
        bufferFill = counter;
        instructionOut = currentInstruction;
    end
endmodule
