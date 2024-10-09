//------------------------------------------------------------------------------
// Company: 		 UIUC ECE Dept.
// Engineer:		 Stephen Kempf
//
// Create Date:    
// Design Name:    ECE 385 Given Code - SLC-3 core
// Module Name:    SLC3
//
// Comments:
//    Revised 03-22-2007
//    Spring 2007 Distribution
//    Revised 07-26-2013
//    Spring 2015 Distribution
//    Revised 09-22-2015 
//    Revised 06-09-2020
//	  Revised 03-02-2021
//    Xilinx vivado
//    Revised 07-25-2023 
//    Revised 12-29-2023
//    Revised 09-25-2024
//------------------------------------------------------------------------------

module cpu (
    input   logic        clk,
    input   logic        reset,

    input   logic        run_i,
    input   logic        continue_i,
    output  logic [15:0] hex_display_debug,
    output  logic [15:0] led_o,
   
    input   logic [15:0] mem_rdata,
    output  logic [15:0] mem_wdata,
    output  logic [15:0] mem_addr,
    output  logic        mem_mem_ena,
    output  logic        mem_wr_ena
);


//// Internal connections, follow the datapath block diagram and add the additional needed signals
//logic ld_mar; 
//logic ld_mdr; 
//logic ld_ir; 
//logic ld_pc; 
//logic ld_led;

//logic gate_pc;
//logic gate_mdr;

//logic [1:0] pcmux;

//logic [15:0] mar; 
//logic [15:0] mdr;
//logic [15:0] ir;
//logic [15:0] pc;
//logic ben;


//assign mem_addr = mar;
//assign mem_wdata = mdr;

//// State machine, you need to fill in the code here as well
//// .* auto-infers module input/output connections which have the same name
//// This can help visually condense modules with large instantiations, 
//// but can also lead to confusing code if used too commonly
//control cpu_control (
//    .*
//);


//assign led_o = ir;
//assign hex_display_debug = ir;

//load_reg #(.DATA_WIDTH(16)) ir_reg (
//    .clk    (clk),
//    .reset  (reset),

//    .load   (ld_ir),
//    .data_i (),

//    .data_q (ir)
//);

//load_reg #(.DATA_WIDTH(16)) pc_reg (
//    .clk(clk),
//    .reset(reset),

//    .load(ld_pc),
//    .data_i(),

//    .data_q(pc)
//);
logic [5:0] stateOutput;
logic [15:0] mainBusOutput;
logic [15:0] MAROutput;
logic [15:0] MDROutput;
logic [15:0] PCOutput;
logic [15:0] IROutput;
logic [15:0] SR1Output;
logic [2:0] control;


logic [1:0] memoryReadyCounter;
always @(posedge clk) begin
    if(~mem_mem_ena) begin
        memoryReadyCounter<=2'b00;
    end
    else begin
        case (memoryReadyCounter)
            2'b00: memoryReadyCounter<=2'b10;
            2'b10: memoryReadyCounter<=2'b01;
            2'b01: memoryReadyCounter<=2'b00;
            default: memoryReadyCounter<=3'b00;
        endcase
    end
end
logic [15:0] debug_bits;
LC3Simulation lc3implementation(clk, reset,
stateOutput,  mainBusOutput, MAROutput,
MDROutput,PCOutput,  IROutput,
SR1Output, control,

//below here is where the beginning of the memory interactions begin
mem_addr, mem_wdata, mem_wr_ena, mem_mem_ena, memoryReadyCounter[0],  mem_rdata, 

//these are output debugs
continue_i, debug_bits
);
assign led_o = {PCOutput[9:0],stateOutput};
assign hex_display_debug = IROutput;

endmodule
