module video_delay
#(
	parameter DATA_WIDTH = 24                       // Video data one clock data width
)
(
	input                       video_clk,          // Video pixel clock
	input                       rst,
	input                       thumbnail_mode,
	output                      read_en,            // Read data enable
	input                       read_valid,         // FIFO data valid for the delayed read request
	input[DATA_WIDTH - 1:0]     read_data,          // Read data
	input                      hs,                 // horizontal synchronization
	input                      vs,                 // vertical synchronization
	input                      de,                 // video valid

	output                      hs_r,                 // horizontal synchronization
	output                      vs_r,                 // vertical synchronization
	output                      de_r,                 // video valid
	output[DATA_WIDTH - 1:0]    vout_data           // video data

);
reg [20:0] hs_d;
reg [20:0] vs_d;
reg [20:0] de_d;
reg[DATA_WIDTH - 1:0]  vout_data_r;
reg full_pixel_phase;

assign read_en = de_d[18] && (thumbnail_mode || !full_pixel_phase);
assign hs_r = hs_d[20];
assign vs_r = vs_d[20];
assign de_r = de_d[20];
assign vout_data = vout_data_r;
always @(posedge video_clk or posedge rst) begin
	if (rst)
		full_pixel_phase <= 1'b0;
	else if (!de_d[18])
		full_pixel_phase <= 1'b0;
	else
		full_pixel_phase <= !full_pixel_phase;
end
always@(posedge video_clk or posedge rst)
begin
	if(rst == 1'b1)
		vout_data_r <= {DATA_WIDTH{1'b0}};
	else if(de_d[19] && read_valid)
		vout_data_r <= read_data;
	// Keep the last valid pixel during a FIFO bubble.  Clearing the pixel
	// on every missing read creates visible black stripes when SDRAM/FIFO
	// latency briefly exceeds one video clock.
	else
		vout_data_r <= vout_data_r;
end
always @(posedge video_clk or posedge rst)begin
	if(rst)begin
    	hs_d <= 20'b0;
        vs_d <= 20'b0;
        de_d <= 20'b0;
    end
	else begin
    	
    	hs_d <= {hs_d[19:0],hs};
        vs_d <= {vs_d[19:0],vs};
        de_d <= {de_d[19:0],de};
    end
end
endmodule
