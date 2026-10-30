`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: 	xg 
// description:  top module
//////////////////////////////////////////////////////////////////////////////////

`define DEBUG

`include "../user_source/hdl_source/include/global_def.v"

module sdram(
    `ifdef SIMULATION
	output					SDRAM_CLK,
	output					SDR_CKE,
	output					SDR_RAS,
	output					SDR_CAS,
	output					SDR_WE,
	output	[`BA_WIDTH-1:0]	SDR_BA,
	output	[`ROW_WIDTH-1:0]SDR_ADDR,
	output	[`DM_WIDTH-1:0]	SDR_DM,
	inout	[`DATA_WIDTH-1:0]	SDR_DQ,	
	`endif
    input   					Clk,
    input						Clk_sft,
    input						Rst,
    
    output 						Sdr_init_done,
    output						Sdr_init_ref_vld,
    output						Sdr_busy,
    
    input						App_wr_en,
	input [`ADDR_WIDTH-1:0]		App_wr_addr,  	
	input [`DM_WIDTH-1:0]		App_wr_dm,
	input [`DATA_WIDTH-1:0]		App_wr_din,	//synthesis keep
    
    input 						App_rd_en,
	input [`ADDR_WIDTH-1:0]		App_rd_addr,
	output 						Sdr_rd_en,
	output [`DATA_WIDTH-1:0]	Sdr_rd_dout	//synthesis keep
    
    
    
);
`ifndef SIMULATION
wire  			SDRAM_CLK;
wire 			SDR_RAS;
wire  			SDR_CAS;
wire  			SDR_WE;
wire  [`BA_WIDTH-1:0]	SDR_BA; 
wire  [`ROW_WIDTH-1:0]	SDR_ADDR;
wire  [`DATA_WIDTH-1:0]	SDR_DQ ;
wire  [`DM_WIDTH-1:0]	SDR_DM; 
`endif

wire controller_ref_active;
wire refresh_request;
wire refresh_block;

// Stop accepting new application bursts before requesting refresh. Existing
// bursts drain first, including the controller's read-return pipeline.
sdram_refresh_guard u_refresh_guard (
    .clk(Clk), .rst(Rst), .init_done(Sdr_init_done),
    .app_access(App_rd_en || App_wr_en),
    .controller_busy(Sdr_busy),
    .controller_ref_active(controller_ref_active),
    .refresh_request(refresh_request), .block_access(refresh_block)
);
assign Sdr_init_ref_vld = controller_ref_active || refresh_block;

sdr_as_ram  #( .self_refresh_open(1'b0))
	u2_ram( 
		.Sdr_clk(Clk),
		.Sdr_clk_sft(Clk_sft),
		.Rst(Rst),
			  			  
		.Sdr_init_done(Sdr_init_done),
		.Sdr_init_ref_vld(controller_ref_active),
		.Sdr_busy(Sdr_busy),
		
		.App_ref_req(refresh_request),
		
        .App_wr_en(App_wr_en), 
        .App_wr_addr(App_wr_addr),  	
		.App_wr_dm(App_wr_dm),
		.App_wr_din(App_wr_din),

		.App_rd_en(App_rd_en),
		.App_rd_addr(App_rd_addr),
		.Sdr_rd_en	(Sdr_rd_en),
		.Sdr_rd_dout(Sdr_rd_dout),
	
		.SDRAM_CLK(SDRAM_CLK),
		.SDR_RAS(SDR_RAS),
		.SDR_CAS(SDR_CAS),
		.SDR_WE(SDR_WE),
		.SDR_BA(SDR_BA),
		.SDR_ADDR(SDR_ADDR),
		.SDR_DM(SDR_DM),
		.SDR_DQ(SDR_DQ)	
	);


assign SDR_CKE=1'b1;

//`ifndef SIMULATION
	EG_PHY_SDRAM_2M_32 sdram(
		.clk(SDRAM_CLK),
		.ras_n(SDR_RAS),
		.cas_n(SDR_CAS),
		.we_n(SDR_WE),
		.addr(SDR_ADDR[10:0]),
		.ba(SDR_BA),
		.dq(SDR_DQ),
		.cs_n(1'b0),
		.dm0(SDR_DM[0]),
		.dm1(SDR_DM[1]),
		.dm2(SDR_DM[2]),
		.dm3(SDR_DM[3]),
		.cke(1'b1)
		);
//`endif

endmodule 

// Periodic refresh is explicitly arbitrated with the application burst ports.
// A pending request blocks only NEW bursts; it never truncates an active one.
module sdram_refresh_guard #(
    parameter integer INTERVAL = `SELF_REFRESH_INTERVAL,
    parameter integer DRAIN_CYCLES = 16
) (
    input clk,
    input rst,
    input init_done,
    input app_access,
    input controller_busy,
    input controller_ref_active,
    output reg refresh_request,
    output block_access
);
localparam IDLE = 2'd0, DRAIN = 2'd1, WAIT_ACTIVE = 2'd2, WAIT_DONE = 2'd3;
reg [1:0] state;
reg [13:0] interval_count;
reg [5:0] quiet_count;

assign block_access = !init_done || (state != IDLE);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= IDLE;
        interval_count <= 14'd0;
        quiet_count <= 6'd0;
        refresh_request <= 1'b0;
    end else if (!init_done) begin
        state <= IDLE;
        interval_count <= 14'd0;
        quiet_count <= 6'd0;
        refresh_request <= 1'b0;
    end else begin
        refresh_request <= 1'b0;
        if (interval_count < INTERVAL - 1)
            interval_count <= interval_count + 1'b1;
        case (state)
            IDLE: begin
                quiet_count <= 6'd0;
                if (interval_count == INTERVAL - 1)
                    state <= DRAIN;
            end
            DRAIN: begin
                if (app_access || controller_busy || controller_ref_active)
                    quiet_count <= 6'd0;
                else if (quiet_count == DRAIN_CYCLES - 1) begin
                    refresh_request <= 1'b1;
                    state <= WAIT_ACTIVE;
                end else
                    quiet_count <= quiet_count + 1'b1;
            end
            WAIT_ACTIVE: begin
                if (controller_ref_active)
                    state <= WAIT_DONE;
            end
            WAIT_DONE: begin
                if (!controller_ref_active) begin
                    state <= IDLE;
                    interval_count <= 14'd0;
                end
            end
            default: state <= IDLE;
        endcase
    end
end
endmodule
