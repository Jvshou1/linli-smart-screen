module bmp_read #(
    parameter integer CLK_FREQ_HZ        = 100_000_000,
    parameter integer SD_READ_TIMEOUT_MS = 500,
    parameter [15:0]  BMP_WIDTH          = 16'd640,
    parameter [15:0]  BMP_HEIGHT         = 16'd480
)(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    output reg [2:0]            bmp_error,
    output reg                  load_error,

    input                       sd_init_done,
    output reg [3:0]            state_code,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;

localparam [2:0] ERR_NONE      = 3'd0;
localparam [2:0] ERR_HEADER    = 3'd1;
localparam [2:0] ERR_TIMEOUT   = 3'd2;
localparam [2:0] ERR_TRUNCATED = 3'd3;
localparam [31:0] TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * SD_READ_TIMEOUT_MS;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] dib_size;
reg [31:0] width;
reg [31:0] height;
reg [15:0] planes;
reg [15:0] bit_count;
reg [31:0] compression;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg [31:0] pixel_count;
reg [31:0] sd_timeout_cnt;

wire header_match;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_match;
wire [31:0] next_scan_sector_if_miss;
wire [32:0] next_scan_sector_wide;
wire [31:0] expected_pixels;
wire [31:0] expected_pixel_bytes;
wire [31:0] pixel_data_end;
wire        pixel_write_now;
wire [32:0] bmp_len_after_cycle;
wire [32:0] pixel_count_after_cycle;
wire        file_complete_now;
wire        bad_bmp_skip_valid;

assign ready = (state == ST_IDLE);
assign expected_pixels = {16'd0, BMP_WIDTH} * {16'd0, BMP_HEIGHT};
assign expected_pixel_bytes = expected_pixels * 32'd3;
assign pixel_data_end = pixel_offset + expected_pixel_bytes;
assign header_match = (header_0 == "B") &&
                      (header_1 == "M") &&
                      (dib_size >= 32'd40) &&
                      (width  == {16'd0, BMP_WIDTH}) &&
                      (height == {16'd0, BMP_HEIGHT}) &&
                      (planes == 16'd1) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0) &&
                      (pixel_offset >= 32'd54) &&
                      (file_len >= expected_pixel_bytes) &&
                      (pixel_offset <= (file_len - expected_pixel_bytes));
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  pixel_data_end);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 :
                           ((file_len >> 9) + ((file_len[8:0] != 9'd0) ? 32'd1 : 32'd0));
assign next_scan_sector_wide = {1'b0, scan_sector} + {1'b0, file_sector_count};
assign next_scan_sector_if_match = next_scan_sector_wide[31:0];
assign next_scan_sector_if_miss  = scan_sector + 32'd1;
assign pixel_write_now = bmp_data_valid && (bmp_byte_idx == 2'd2);
assign bmp_len_after_cycle = {1'b0, bmp_len_cnt} +
                             ((sd_sec_read_data_valid) ? 33'd1 : 33'd0);
assign pixel_count_after_cycle = {1'b0, pixel_count} +
                                 ((pixel_write_now) ? 33'd1 : 33'd0);
assign file_complete_now = (bmp_len_after_cycle >= {1'b0, file_len});
assign bad_bmp_skip_valid = (header_0 == "B") && (header_1 == "M") &&
                            (file_len >= 32'd54) &&
                            (scan_sector <= scan_max_sector) &&
                            (file_sector_count <= (scan_max_sector - scan_sector));

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        dib_size     <= 32'd0;
        width        <= 32'd0;
        height       <= 32'd0;
        planes       <= 16'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_size[7:0] <= sd_sec_read_data;
            10'd15: dib_size[15:8] <= sd_sec_read_data;
            10'd16: dib_size[23:16] <= sd_sec_read_data;
            10'd17: dib_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        pixel_count <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (pixel_write_now)
            pixel_count <= pixel_count + 32'd1;
    end else begin
        pixel_count <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_byte_idx <= 2'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid)
            bmp_byte_idx <= (bmp_byte_idx == 2'd2) ? 2'd0 : (bmp_byte_idx + 2'd1);
    end else begin
        bmp_byte_idx <= 2'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (bmp_data_valid) begin
            case (bmp_byte_idx)
                2'd0: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[7:0]  <= sd_sec_read_data;
                end
                2'd1: begin
                    bmp_data_wr_en <= 1'b0;
                    bmp_data[15:8] <= sd_sec_read_data;
                end
                2'd2: begin
                    bmp_data_wr_en  <= 1'b1;
                    bmp_data[23:16] <= sd_sec_read_data;
                end
                default: begin
                    bmp_data_wr_en <= 1'b0;
                end
            endcase
        end else begin
            bmp_data_wr_en <= 1'b0;
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error         <= ERR_NONE;
        load_error        <= 1'b0;
        sd_timeout_cnt    <= 32'd0;
    end else if (!sd_init_done) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        bmp_error         <= ERR_NONE;
        load_error        <= 1'b0;
        sd_timeout_cnt    <= 32'd0;
    end else begin
        scan_found_valid <= 1'b0;
        load_error       <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
                sd_timeout_cnt <= 32'd0;

                if (scan_start) begin
                    bmp_error         <= ERR_NONE;
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    bmp_error           <= ERR_NONE;
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_data_valid || sd_sec_read_end)
                    sd_timeout_cnt <= 32'd0;
                else if (sd_timeout_cnt < TIMEOUT_CYCLES)
                    sd_timeout_cnt <= sd_timeout_cnt + 32'd1;

                if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                    sd_sec_read  <= 1'b0;
                    scan_done    <= 1'b1;
                    bmp_error    <= ERR_TIMEOUT;
                    state        <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;

                    if (header_match) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;

                        if ((scan_found_total + 3'd1 >= scan_target_count) ||
                            (next_scan_sector_wide > {1'b0, scan_max_sector})) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_match;
                            scan_sector      <= next_scan_sector_if_match;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            if (bad_bmp_skip_valid) begin
                                sd_sec_read_addr <= next_scan_sector_if_match;
                                scan_sector      <= next_scan_sector_if_match;
                            end else begin
                                sd_sec_read_addr <= next_scan_sector_if_miss;
                                scan_sector      <= next_scan_sector_if_miss;
                            end
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_data_valid || sd_sec_read_end)
                    sd_timeout_cnt <= 32'd0;
                else if (sd_timeout_cnt < TIMEOUT_CYCLES)
                    sd_timeout_cnt <= sd_timeout_cnt + 32'd1;

                if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                    sd_sec_read <= 1'b0;
                    bmp_error   <= ERR_TIMEOUT;
                    load_error  <= 1'b1;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (header_match) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        bmp_error  <= ERR_HEADER;
                        load_error <= 1'b1;
                        state      <= ST_IDLE;
                    end
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (sd_timeout_cnt < TIMEOUT_CYCLES)
                    sd_timeout_cnt <= sd_timeout_cnt + 32'd1;

                if (write_req_ack) begin
                    write_req <= 1'b0;
                    sd_timeout_cnt <= 32'd0;
                    state     <= ST_LOAD_DATA;
                end else if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                    write_req  <= 1'b0;
                    bmp_error  <= ERR_TIMEOUT;
                    load_error <= 1'b1;
                    state      <= ST_IDLE;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_data_valid || sd_sec_read_end)
                    sd_timeout_cnt <= 32'd0;
                else if (sd_timeout_cnt < TIMEOUT_CYCLES)
                    sd_timeout_cnt <= sd_timeout_cnt + 32'd1;

                if (sd_timeout_cnt >= TIMEOUT_CYCLES) begin
                    sd_sec_read <= 1'b0;
                    bmp_error   <= ERR_TIMEOUT;
                    load_error  <= 1'b1;
                    state       <= ST_IDLE;
                end else if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (file_complete_now) begin
                        if (pixel_count_after_cycle != {1'b0, expected_pixels}) begin
                            bmp_error  <= ERR_TRUNCATED;
                            load_error <= 1'b1;
                        end else begin
                            bmp_error <= ERR_NONE;
                        end
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
