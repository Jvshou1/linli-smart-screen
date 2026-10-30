`timescale 1ns/1ps
module frame_fifo_read
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,
	parameter FIFO_DEPTH             = 512,
	parameter BURST_SIZE             = 128
)               
(
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
    input							 Sdr_rd_en,
	input							 App_wr_busy,
    output							 O_rd_busy,
	/*
    output reg                       rd_burst_req,               // to external memory controller,send out a burst read request  
	output reg[BURST_BITS - 1:0]     rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes 
	output reg[ADDR_BITS - 1:0]      rd_burst_addr,              // to external memory controller,base address of the burst read request
	input                            rd_burst_data_valid,        // from external memory controller,read request data valid    
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output 							 App_rd_en,
	output  [ADDR_BITS - 1:0]		 App_rd_addr,
	
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output reg                       read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[ADDR_BITS - 1:0]           read_addr_4,
	input[ADDR_BITS - 1:0]           read_addr_5,
	input[2:0]                       read_addr_index,
	input                            thumbnail_mode,
	input                            thumbnail_page,
	input[15:0]                      image_width_0,
	input[15:0]                      image_height_0,
	input[15:0]                      image_width_1,
	input[15:0]                      image_height_1,
	input[15:0]                      image_width_2,
	input[15:0]                      image_height_2,
	input[15:0]                      image_width_3,
	input[15:0]                      image_height_3,
	input[15:0]                      image_width_4,
	input[15:0]                      image_height_4,
	input[15:0]                      image_width_5,
	input[15:0]                      image_height_5,
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	output reg                       fifo_aclr,                  // to fifo asynchronous clear
	input[9:0]                      wrusedw                     // from fifo write used words

);
localparam ONE                       = 256'd1;                   //256 bit '1'   you can use ONE[n-1:0] for n bit '1'
localparam ZERO                      = 256'd0;                   //256 bit '0'
//read state machine code
localparam S_IDLE                    = 0;                        //idle state,waiting for frame read
localparam S_ACK                     = 1;                        //read request response
localparam S_CHECK_FIFO              = 2;                        //check the FIFO status, ensure that there is enough space to burst read
localparam S_READ_BURST              = 3;                        //begin a burst read
localparam S_READ_BURST_END          = 4;                        //a burst read complete
localparam S_END                     = 5;                        //a frame of data is read to complete

reg                                  read_req_d0;                //asynchronous read request, synchronize to 'mem_clk' clock domain,first beat
reg                                  read_req_d1;                //second
reg                                  read_req_d2;                //third,Why do you need 3 ? Here's the design habit
reg[ADDR_BITS - 1:0]                 read_len_d0;                //asynchronous read_len(read data length), synchronize to 'mem_clk' clock domain first
reg[ADDR_BITS - 1:0]                 read_len_d1;                //second
reg[ADDR_BITS - 1:0]                 read_len_latch;             //lock read data length
reg[ADDR_BITS - 1:0]                 read_cnt;                   //read data counter
reg[3:0]                             state;                      //state machine
reg[2:0]                             read_addr_index_d0;
reg[2:0]                             read_addr_index_d1;
reg                                  thumbnail_mode_d0;
reg                                  thumbnail_mode_d1;
reg                                  thumbnail_mode_latch;
reg                                  thumbnail_page_d0;
reg                                  thumbnail_page_d1;
reg                                  thumbnail_page_latch;
reg [10:0]                           output_x;
reg [9:0]                            output_y;
reg [ADDR_BITS - 1:0]	 App_rd_addr_r;

reg [15:0] image_width_0_d0, image_width_0_d1;
reg [15:0] image_height_0_d0, image_height_0_d1;
reg [15:0] image_width_1_d0, image_width_1_d1;
reg [15:0] image_height_1_d0, image_height_1_d1;
reg [15:0] image_width_2_d0, image_width_2_d1;
reg [15:0] image_height_2_d0, image_height_2_d1;
reg [15:0] image_width_3_d0, image_width_3_d1;
reg [15:0] image_height_3_d0, image_height_3_d1;
reg [15:0] image_width_4_d0, image_width_4_d1;
reg [15:0] image_height_4_d0, image_height_4_d1;
reg [15:0] image_width_5_d0, image_width_5_d1;
reg [15:0] image_height_5_d0, image_height_5_d1;

reg [15:0] source_x_index;
reg [16:0] x_scale_error;
reg [16:0] full_y_scale_error;
reg [ADDR_BITS - 1:0] full_row_offset;
reg [ADDR_BITS - 1:0] full_base_latch;
reg [15:0] full_width_latch;
reg [15:0] full_height_latch;
reg [15:0] thumb_width_latch;
reg [16:0] thumb_y_error_0, thumb_y_error_1;
reg [16:0] thumb_y_error_2, thumb_y_error_3;
reg [ADDR_BITS - 1:0] thumb_row_offset_0, thumb_row_offset_1;
reg [ADDR_BITS - 1:0] thumb_row_offset_2, thumb_row_offset_3;

reg [ADDR_BITS - 1:0] thumb_base_0, thumb_base_1, thumb_base_2, thumb_base_3;
reg [15:0] thumb_width_0, thumb_width_1, thumb_width_2, thumb_width_3;
reg [15:0] thumb_height_0, thumb_height_1, thumb_height_2, thumb_height_3;

wire [16:0] x_error_sum = x_scale_error + thumb_width_latch;
// Thumbnail cells are 640 pixels wide in the 1280x720 output. The source
// banks remain 640 pixels wide, so one source pixel normally maps to one
// output pixel (and the same logic still supports narrower source images).
wire [1:0] thumb_x_step = (x_error_sum >= 17'd1280) ? 2'd2 :
                          (x_error_sum >= 17'd640) ? 2'd1 : 2'd0;
wire [16:0] full_x_error_sum = x_scale_error + full_width_latch;
wire       full_x_step = (full_x_error_sum >= 17'd640);
wire [16:0] full_y_error_sum = full_y_scale_error + full_height_latch;

wire [16:0] thumb_y_sum_0 = thumb_y_error_0 + thumb_height_0;
wire [16:0] thumb_y_sum_1 = thumb_y_error_1 + thumb_height_1;
wire [16:0] thumb_y_sum_2 = thumb_y_error_2 + thumb_height_2;
wire [16:0] thumb_y_sum_3 = thumb_y_error_3 + thumb_height_3;
wire [1:0] thumb_y_step_0 = (thumb_y_sum_0 >= 17'd720) ? 2'd2 :
                            (thumb_y_sum_0 >= 17'd360) ? 2'd1 : 2'd0;
wire [1:0] thumb_y_step_1 = (thumb_y_sum_1 >= 17'd720) ? 2'd2 :
                            (thumb_y_sum_1 >= 17'd360) ? 2'd1 : 2'd0;
wire [1:0] thumb_y_step_2 = (thumb_y_sum_2 >= 17'd720) ? 2'd2 :
                            (thumb_y_sum_2 >= 17'd360) ? 2'd1 : 2'd0;
wire [1:0] thumb_y_step_3 = (thumb_y_sum_3 >= 17'd720) ? 2'd2 :
                            (thumb_y_sum_3 >= 17'd360) ? 2'd1 : 2'd0;
reg [1:0] thumb_y_step_0_q, thumb_y_step_1_q;
reg [1:0] thumb_y_step_2_q, thumb_y_step_3_q;
reg       full_y_step_q;

// Row state changes only once per 1280 output pixels. Register the next
// row's scale decision ahead of the boundary to shorten the SDRAM address path.
always @(posedge mem_clk or posedge rst) begin
	if (rst) begin
		thumb_y_step_0_q <= 2'd0; thumb_y_step_1_q <= 2'd0;
		thumb_y_step_2_q <= 2'd0; thumb_y_step_3_q <= 2'd0;
		full_y_step_q <= 1'b0;
	end else begin
		thumb_y_step_0_q <= thumb_y_step_0;
		thumb_y_step_1_q <= thumb_y_step_1;
		thumb_y_step_2_q <= thumb_y_step_2;
		thumb_y_step_3_q <= thumb_y_step_3;
		full_y_step_q <= (full_y_error_sum >= 17'd720);
	end
end

reg [BURST_BITS - 1:0]				burst_cnt;
wire								rd_burst_finish;
reg App_rd_en_r;
reg App_rd_en_d0;


wire rd_vld;
reg [3:0] rd_delay;
reg [BURST_BITS:0] returned_count;
// Keep ownership until the controller has returned every requested word.
always @(posedge mem_clk or posedge rst) begin
    if (rst) returned_count <= 0;
    else if (state != S_READ_BURST) returned_count <= 0;
    else if (Sdr_rd_en) returned_count <= returned_count + 1'b1;
end

assign App_rd_addr = {App_rd_addr_r[ADDR_BITS - 1:0]};
assign rd_vld = (state == S_READ_BURST && burst_cnt >= BURST_SIZE);

assign O_rd_busy = (state == S_READ_BURST);//读指令期间
//burst_cnt代表发送的读指令
//但rd_burst_finish需要在发送完十个时钟后拉高，此时数据全部读出
assign rd_burst_finish = (rd_vld && rd_delay == 4'd10 && returned_count >= BURST_SIZE);
assign read_finish = (state == S_END) ? 1'b1 : 1'b0;             //read finish at state 'S_END'
assign App_rd_en = App_rd_en_d0;
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		read_req_d0    <=  1'b0;
		read_req_d1    <=  1'b0;
		read_req_d2    <=  1'b0;
		read_len_d0    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d0 <= 0;
		read_len_d1    <=  ZERO[ADDR_BITS - 1:0];               //equivalent to read_len_d1 <= 0;
		read_addr_index_d0 <= 3'b000;
		read_addr_index_d1 <= 3'b000;
		thumbnail_mode_d0 <= 1'b0;
		thumbnail_mode_d1 <= 1'b0;
		thumbnail_page_d0 <= 1'b0;
		thumbnail_page_d1 <= 1'b0;
		image_width_0_d0 <= 16'd640; image_width_0_d1 <= 16'd640;
		image_height_0_d0 <= 16'd480; image_height_0_d1 <= 16'd480;
		image_width_1_d0 <= 16'd640; image_width_1_d1 <= 16'd640;
		image_height_1_d0 <= 16'd480; image_height_1_d1 <= 16'd480;
		image_width_2_d0 <= 16'd640; image_width_2_d1 <= 16'd640;
		image_height_2_d0 <= 16'd480; image_height_2_d1 <= 16'd480;
		image_width_3_d0 <= 16'd640; image_width_3_d1 <= 16'd640;
		image_height_3_d0 <= 16'd480; image_height_3_d1 <= 16'd480;
		image_width_4_d0 <= 16'd640; image_width_4_d1 <= 16'd640;
		image_height_4_d0 <= 16'd480; image_height_4_d1 <= 16'd480;
		image_width_5_d0 <= 16'd640; image_width_5_d1 <= 16'd640;
		image_height_5_d0 <= 16'd480; image_height_5_d1 <= 16'd480;
	end
	else
	begin
		read_req_d0    <=  read_req;
		read_req_d1    <=  read_req_d0;
		read_req_d2    <=  read_req_d1;     
		read_len_d0    <=  read_len;
		read_len_d1    <=  read_len_d0; 
		read_addr_index_d0 <= read_addr_index;
		read_addr_index_d1 <= read_addr_index_d0;
		thumbnail_mode_d0 <= thumbnail_mode;
		thumbnail_mode_d1 <= thumbnail_mode_d0;
		thumbnail_page_d0 <= thumbnail_page;
		thumbnail_page_d1 <= thumbnail_page_d0;
		image_width_0_d0 <= image_width_0; image_width_0_d1 <= image_width_0_d0;
		image_height_0_d0 <= image_height_0; image_height_0_d1 <= image_height_0_d0;
		image_width_1_d0 <= image_width_1; image_width_1_d1 <= image_width_1_d0;
		image_height_1_d0 <= image_height_1; image_height_1_d1 <= image_height_1_d0;
		image_width_2_d0 <= image_width_2; image_width_2_d1 <= image_width_2_d0;
		image_height_2_d0 <= image_height_2; image_height_2_d1 <= image_height_2_d0;
		image_width_3_d0 <= image_width_3; image_width_3_d1 <= image_width_3_d0;
		image_height_3_d0 <= image_height_3; image_height_3_d1 <= image_height_3_d0;
		image_width_4_d0 <= image_width_4; image_width_4_d1 <= image_width_4_d0;
		image_height_4_d0 <= image_height_4; image_height_4_d1 <= image_height_4_d0;
		image_width_5_d0 <= image_width_5; image_width_5_d1 <= image_width_5_d0;
		image_height_5_d0 <= image_height_5; image_height_5_d1 <= image_height_5_d0;
		
	end 
end

always @(posedge mem_clk or posedge rst)
begin
	if(rst || App_rd_en)begin
        rd_delay <= 4'd0;
    end
    else if(rd_delay < 4'd10)begin
    	rd_delay <= rd_delay + 1'b1;
    end
end
always @(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		burst_cnt <= ZERO[BURST_BITS - 1:0];
		App_rd_addr_r <= ZERO[ADDR_BITS - 1:0];
		App_rd_en_d0 <= 1'b0;
		thumbnail_mode_latch <= 1'b0;
		thumbnail_page_latch <= 1'b0;
		thumb_base_0 <= 0; thumb_base_1 <= 0;
		thumb_base_2 <= 0; thumb_base_3 <= 0;
		thumb_width_0 <= 16'd640; thumb_width_1 <= 16'd640;
		thumb_width_2 <= 16'd640; thumb_width_3 <= 16'd640;
		thumb_height_0 <= 16'd480; thumb_height_1 <= 16'd480;
		thumb_height_2 <= 16'd480; thumb_height_3 <= 16'd480;
		output_x <= 11'd0;
		output_y <= 10'd0;
		source_x_index <= 16'd0;
		x_scale_error <= 17'd0;
		full_y_scale_error <= 17'd0;
		full_row_offset <= ZERO[ADDR_BITS - 1:0];
		full_base_latch <= ZERO[ADDR_BITS - 1:0];
		full_width_latch <= 16'd640;
		full_height_latch <= 16'd480;
		thumb_width_latch <= 16'd640;
		thumb_y_error_0 <= 17'd0; thumb_y_error_1 <= 17'd0;
		thumb_y_error_2 <= 17'd0; thumb_y_error_3 <= 17'd0;
		thumb_row_offset_0 <= ZERO[ADDR_BITS - 1:0];
		thumb_row_offset_1 <= ZERO[ADDR_BITS - 1:0];
		thumb_row_offset_2 <= ZERO[ADDR_BITS - 1:0];
		thumb_row_offset_3 <= ZERO[ADDR_BITS - 1:0];
	end
	else begin
	
		if(state == S_CHECK_FIFO)
			burst_cnt <= ZERO[BURST_BITS - 1:0];
		else if(App_rd_en)
			burst_cnt <= burst_cnt + 1'b1;
		else
			burst_cnt <= burst_cnt;
		//
		if(state == S_ACK)
			begin
				thumbnail_mode_latch <= thumbnail_mode_d1;
				thumbnail_page_latch <= thumbnail_page_d1;
				thumb_base_0 <= thumbnail_page_d1 ? read_addr_4 : read_addr_0;
				thumb_base_1 <= thumbnail_page_d1 ? read_addr_5 : read_addr_1;
				thumb_base_2 <= thumbnail_page_d1 ? read_addr_0 : read_addr_2;
				thumb_base_3 <= thumbnail_page_d1 ? read_addr_0 : read_addr_3;
				thumb_width_0 <= thumbnail_page_d1 ? image_width_4_d1 : image_width_0_d1;
				thumb_width_1 <= thumbnail_page_d1 ? image_width_5_d1 : image_width_1_d1;
				thumb_width_2 <= thumbnail_page_d1 ? image_width_0_d1 : image_width_2_d1;
				thumb_width_3 <= thumbnail_page_d1 ? image_width_0_d1 : image_width_3_d1;
				thumb_height_0 <= thumbnail_page_d1 ? image_height_4_d1 : image_height_0_d1;
				thumb_height_1 <= thumbnail_page_d1 ? image_height_5_d1 : image_height_1_d1;
				thumb_height_2 <= thumbnail_page_d1 ? image_height_0_d1 : image_height_2_d1;
				thumb_height_3 <= thumbnail_page_d1 ? image_height_0_d1 : image_height_3_d1;
				output_x <= 11'd0;
				output_y <= 10'd0;
				source_x_index <= 16'd0;
				x_scale_error <= 17'd0;
				full_y_scale_error <= 17'd0;
				full_row_offset <= ZERO[ADDR_BITS - 1:0];
				thumb_width_latch <= thumbnail_page_d1 ? image_width_4_d1 : image_width_0_d1;
				case (read_addr_index_d1)
					3'd0: begin
						full_base_latch <= read_addr_0;
						full_width_latch <= image_width_0_d1;
						full_height_latch <= image_height_0_d1;
					end
					3'd1: begin
						full_base_latch <= read_addr_1;
						full_width_latch <= image_width_1_d1;
						full_height_latch <= image_height_1_d1;
					end
					3'd2: begin
						full_base_latch <= read_addr_2;
						full_width_latch <= image_width_2_d1;
						full_height_latch <= image_height_2_d1;
					end
					3'd3: begin
						full_base_latch <= read_addr_3;
						full_width_latch <= image_width_3_d1;
						full_height_latch <= image_height_3_d1;
					end
					3'd4: begin
						full_base_latch <= read_addr_4;
						full_width_latch <= image_width_4_d1;
						full_height_latch <= image_height_4_d1;
					end
					default: begin
						full_base_latch <= read_addr_5;
						full_width_latch <= image_width_5_d1;
						full_height_latch <= image_height_5_d1;
					end
				endcase
				thumb_y_error_0 <= 17'd0; thumb_y_error_1 <= 17'd0;
				thumb_y_error_2 <= 17'd0; thumb_y_error_3 <= 17'd0;
				thumb_row_offset_0 <= ZERO[ADDR_BITS - 1:0];
				thumb_row_offset_1 <= ZERO[ADDR_BITS - 1:0];
				thumb_row_offset_2 <= ZERO[ADDR_BITS - 1:0];
				thumb_row_offset_3 <= ZERO[ADDR_BITS - 1:0];
				if(thumbnail_mode_d1)
					App_rd_addr_r <= thumbnail_page_d1 ? read_addr_4 : read_addr_0;
				else if(read_addr_index_d1 == 3'd0)
					App_rd_addr_r <= read_addr_0;
				else if(read_addr_index_d1 == 3'd1)
					App_rd_addr_r <= read_addr_1;
				else if(read_addr_index_d1 == 3'd2)
					App_rd_addr_r <= read_addr_2;
				else if(read_addr_index_d1 == 3'd3)
					App_rd_addr_r <= read_addr_3;
				else if(read_addr_index_d1 == 3'd4)
					App_rd_addr_r <= read_addr_4;
				else
					App_rd_addr_r <= read_addr_5;
			end
		else if(App_rd_en)
			begin
				if(thumbnail_mode_latch) begin
					if(output_x == 11'd1279) begin
						output_x <= 11'd0;
						source_x_index <= 16'd0;
						x_scale_error <= 17'd0;
						if(output_y == 10'd719) begin
							output_y <= 10'd0;
							thumb_width_latch <= thumb_width_0;
							thumb_y_error_0 <= 17'd0; thumb_y_error_1 <= 17'd0;
							thumb_y_error_2 <= 17'd0; thumb_y_error_3 <= 17'd0;
							thumb_row_offset_0 <= ZERO[ADDR_BITS - 1:0];
							thumb_row_offset_1 <= ZERO[ADDR_BITS - 1:0];
							thumb_row_offset_2 <= ZERO[ADDR_BITS - 1:0];
							thumb_row_offset_3 <= ZERO[ADDR_BITS - 1:0];
							App_rd_addr_r <= thumb_base_0;
						end else if(output_y == 10'd359) begin
							output_y <= output_y + 1'b1;
							thumb_width_latch <= thumb_width_2;
							App_rd_addr_r <= thumb_base_2;
						end else if(output_y < 10'd359) begin
							output_y <= output_y + 1'b1;
							thumb_width_latch <= thumb_width_0;
							thumb_y_error_0 <= thumb_y_sum_0 -
								((thumb_y_step_0_q == 2) ? 17'd720 :
								 (thumb_y_step_0_q == 1) ? 17'd360 : 17'd0);
							thumb_y_error_1 <= thumb_y_sum_1 -
								((thumb_y_step_1_q == 2) ? 17'd720 :
								 (thumb_y_step_1_q == 1) ? 17'd360 : 17'd0);
							thumb_row_offset_0 <= thumb_row_offset_0 +
							    ((thumb_y_step_0_q == 2) ? (thumb_width_0 << 1) :
							     (thumb_y_step_0_q == 1) ? thumb_width_0 : 0);
							thumb_row_offset_1 <= thumb_row_offset_1 +
							    ((thumb_y_step_1_q == 2) ? (thumb_width_1 << 1) :
							     (thumb_y_step_1_q == 1) ? thumb_width_1 : 0);
							App_rd_addr_r <= thumb_base_0 + thumb_row_offset_0 +
							    ((thumb_y_step_0_q == 2) ? (thumb_width_0 << 1) :
							     (thumb_y_step_0_q == 1) ? thumb_width_0 : 0);
						end else begin
							output_y <= output_y + 1'b1;
							thumb_width_latch <= thumb_width_2;
							thumb_y_error_2 <= thumb_y_sum_2 -
							    ((thumb_y_step_2_q == 2) ? 17'd720 :
							     (thumb_y_step_2_q == 1) ? 17'd360 : 17'd0);
							thumb_y_error_3 <= thumb_y_sum_3 -
							    ((thumb_y_step_3_q == 2) ? 17'd720 :
							     (thumb_y_step_3_q == 1) ? 17'd360 : 17'd0);
							thumb_row_offset_2 <= thumb_row_offset_2 +
							    ((thumb_y_step_2_q == 2) ? (thumb_width_2 << 1) :
							     (thumb_y_step_2_q == 1) ? thumb_width_2 : 0);
							thumb_row_offset_3 <= thumb_row_offset_3 +
							    ((thumb_y_step_3_q == 2) ? (thumb_width_3 << 1) :
							     (thumb_y_step_3_q == 1) ? thumb_width_3 : 0);
							App_rd_addr_r <= thumb_base_2 + thumb_row_offset_2 +
							    ((thumb_y_step_2_q == 2) ? (thumb_width_2 << 1) :
							     (thumb_y_step_2_q == 1) ? thumb_width_2 : 0);
						end
						end else if(output_x == 11'd639) begin
						output_x <= output_x + 1'b1;
						source_x_index <= 16'd0;
						x_scale_error <= 17'd0;
						thumb_width_latch <= (output_y < 10'd360) ?
						                     thumb_width_1 : thumb_width_3;
						App_rd_addr_r <= (output_y < 10'd360) ?
						                 (thumb_base_1 + thumb_row_offset_1) :
						                 (thumb_base_3 + thumb_row_offset_3);
					end else begin
						output_x <= output_x + 1'b1;
						source_x_index <= source_x_index + thumb_x_step;
						x_scale_error <= x_error_sum -
								((thumb_x_step == 2) ? 17'd1280 :
								 (thumb_x_step == 1) ? 17'd640 : 17'd0);
						App_rd_addr_r <= App_rd_addr_r + thumb_x_step;
					end
				end else begin
					if(output_x == 11'd639) begin
						output_x <= 11'd0;
						source_x_index <= 16'd0;
						x_scale_error <= 17'd0;
						if(output_y == 10'd719) begin
							output_y <= 10'd0;
							full_y_scale_error <= 17'd0;
							full_row_offset <= ZERO[ADDR_BITS - 1:0];
							App_rd_addr_r <= full_base_latch;
						end else begin
							output_y <= output_y + 1'b1;
							if(full_y_step_q) begin
								full_y_scale_error <= full_y_error_sum - 17'd720;
								full_row_offset <= full_row_offset + full_width_latch;
								App_rd_addr_r <= full_base_latch + full_row_offset + full_width_latch;
							end else begin
								full_y_scale_error <= full_y_error_sum;
								App_rd_addr_r <= full_base_latch + full_row_offset;
							end
						end
					end else begin
						output_x <= output_x + 1'b1;
						if(full_x_step) begin
							source_x_index <= source_x_index + 1'b1;
							x_scale_error <= full_x_error_sum - 17'd640;
							App_rd_addr_r <= App_rd_addr_r + 1'b1;
						end else begin
							x_scale_error <= full_x_error_sum;
							App_rd_addr_r <= App_rd_addr_r;
						end
					end
				end
			end
		else
			App_rd_addr_r <= App_rd_addr_r;
		//
		if(App_rd_en_r && burst_cnt + App_rd_en < BURST_SIZE)
			App_rd_en_d0 <= 1'b1;
		else
			App_rd_en_d0 <= 1'b0;
	
	end		
end
always@(posedge mem_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		state <= S_IDLE;
		read_len_latch <= ZERO[ADDR_BITS - 1:0];
		
		//rd_burst_addr <= ZERO[ADDR_BITS - 1:0];
		//rd_burst_req <= 1'b0;
		App_rd_en_r <= 1'b0;
		
		read_cnt <= ZERO[ADDR_BITS - 1:0];
		fifo_aclr <= 1'b0;
		//rd_burst_len <= ZERO[BURST_BITS - 1:0];
		read_req_ack <= 1'b0;
	end
	else
		case(state)
			//idle state,waiting for read, read_req_d2 == '1' goto the 'S_ACK'
			S_IDLE:
			begin
				if(read_req_d2 == 1'b1 && Sdr_init_done)
				begin
					state <= S_ACK;
				end
				read_req_ack <= 1'b0;
			end
			//'S_ACK' state completes the read request response, the FIFO reset, the address latch, and the data length latch
			S_ACK:
			begin
				if(read_req_d2 == 1'b0)
				begin
					state <= S_CHECK_FIFO;
					fifo_aclr <= 1'b0;
					read_req_ack <= 1'b0;
				end
				else
				begin
					//read request response
					read_req_ack <= 1'b1;
					//FIFO reset
					fifo_aclr <= 1'b1;
					//select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
					/*
					if(read_addr_index_d1 == 2'd0)
						App_rd_addr <= read_addr_0;
					else if(read_addr_index_d1 == 2'd1)
						App_rd_addr <= read_addr_1;
					else if(read_addr_index_d1 == 2'd2)
						App_rd_addr <= read_addr_2;
					else if(read_addr_index_d1 == 2'd3)
						App_rd_addr <= read_addr_3;
					*/
					//latch data length
					read_len_latch <= read_len_d1;
				end
				//read data counter reset, read_cnt <= 0;
				read_cnt <= ZERO[ADDR_BITS - 1:0];
			end
			S_CHECK_FIFO:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the FIFO space is a burst read request, goto burst read state
				else if(wrusedw < (FIFO_DEPTH - BURST_SIZE) &&
				        ~App_wr_busy && ~Sdr_init_ref_vld && ~Sdr_busy)
				begin
					state <= S_READ_BURST;
					//rd_burst_len <= BURST_SIZE[BURST_BITS - 1:0];
					//rd_burst_req <= 1'b1;
					App_rd_en_r <= 1'b1;
				end
			end
			
			S_READ_BURST:
			begin
				//burst finish  
				if(rd_burst_finish == 1'b1)
				begin
					App_rd_en_r <= 1'b0;
					state <= S_READ_BURST_END;
					//read counter + burst length
					read_cnt <= read_cnt + BURST_SIZE[ADDR_BITS - 1:0];
					//the next burst read address is generated
					//rd_burst_addr <= rd_burst_addr + BURST_SIZE[ADDR_BITS - 1:0];
				end     
			end
			S_READ_BURST_END:
			begin
				//if there is a read request at this time, enter the 'S_ACK' state
				if(read_req_d2 == 1'b1)
				begin
					state <= S_ACK;
				end
				//if the read counter value is less than the frame length, continue read,
				//otherwise the read is complete
				else if(read_cnt < read_len_latch)
				begin
					state <= S_CHECK_FIFO;
				end
				else
				begin
					state <= S_END;
				end
			end
			S_END:
			begin
				state <= S_IDLE;
			end
			default:
				state <= S_IDLE;
		endcase
end
endmodule
