`timescale 1ns/1ps

// Adapts the FAT32 sector interface to the legacy sd_card_top read interface.
module sd_sector_adapter #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer READ_TIMEOUT_MS = 500
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sector_req,
    input  wire [31:0] sector_lba,
    output wire        sector_busy,
    output wire        sector_valid,
    output wire [7:0]  sector_byte,
    output wire [8:0]  sector_byte_index,
    output reg         sector_done,
    output reg  [7:0]  sector_error,

    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire        sd_sec_read_data_valid,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_end
);

localparam [7:0] ERR_NONE    = 8'h00;
localparam [7:0] ERR_TIMEOUT = 8'h10;
localparam integer TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * READ_TIMEOUT_MS;

reg       busy_reg;
reg       timed_out;
reg [8:0] byte_cnt;
reg [31:0] timeout_cnt;

assign sector_busy       = busy_reg;
assign sector_valid      = busy_reg && !timed_out && sd_sec_read_data_valid;
assign sector_byte       = sd_sec_read_data;
assign sector_byte_index = byte_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sd_sec_read      <= 1'b0;
        sd_sec_read_addr <= 32'd0;
        sector_done      <= 1'b0;
        sector_error     <= ERR_NONE;
        busy_reg         <= 1'b0;
        timed_out        <= 1'b0;
        byte_cnt         <= 9'd0;
        timeout_cnt      <= 32'd0;
    end else begin
        sector_done <= 1'b0;

        if (!busy_reg) begin
            sd_sec_read <= 1'b0;
            byte_cnt    <= 9'd0;
            timeout_cnt <= 32'd0;
            timed_out   <= 1'b0;
            if (sector_req) begin
                sd_sec_read_addr <= sector_lba;
                sd_sec_read      <= 1'b1;
                sector_error     <= ERR_NONE;
                busy_reg         <= 1'b1;
            end
        end else if (timed_out) begin
            // Let the legacy controller return to idle before accepting another request.
            if (sd_sec_read_end) begin
                busy_reg  <= 1'b0;
                timed_out <= 1'b0;
            end
        end else if (sd_sec_read_end) begin
            sd_sec_read  <= 1'b0;
            sector_done  <= 1'b1;
            sector_error <= ERR_NONE;
            busy_reg     <= 1'b0;
            byte_cnt     <= 9'd0;
            timeout_cnt  <= 32'd0;
        end else if (timeout_cnt >= TIMEOUT_CYCLES - 1) begin
            sd_sec_read  <= 1'b0;
            sector_done  <= 1'b1;
            sector_error <= ERR_TIMEOUT;
            timed_out    <= 1'b1;
        end else begin
            timeout_cnt <= timeout_cnt + 32'd1;
            if (sd_sec_read_data_valid)
                byte_cnt <= byte_cnt + 9'd1;
        end
    end
end

endmodule
