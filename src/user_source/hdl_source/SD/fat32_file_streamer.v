`timescale 1ns/1ps

module fat32_file_streamer #(
    parameter integer MAX_VISITED_CLUSTERS = 8192
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        file_start,
    input  wire        read_enable,
    input  wire [31:0] first_cluster,
    input  wire [31:0] file_size,
    input  wire [7:0]  sectors_per_cluster,
    input  wire [31:0] fat_start_lba,
    input  wire [31:0] data_start_lba,
    input  wire [31:0] max_cluster,
    output wire        file_busy,
    output reg         file_done,
    output reg         file_valid,
    output reg  [7:0]  file_byte,
    output reg  [31:0] file_byte_offset,
    output reg  [7:0]  fs_error,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

localparam [7:0] ERR_NONE              = 8'h00;
localparam [7:0] ERR_SECTOR            = 8'h10;
localparam [7:0] ERR_FAT_LOOP          = 8'h23;
localparam [7:0] ERR_CLUSTER_RANGE     = 8'h24;
localparam [7:0] ERR_EARLY_EOF         = 8'h25;
localparam [7:0] ERR_VISITED_EXHAUSTED = 8'h26;

localparam [3:0] ST_IDLE      = 4'd0;
localparam [3:0] ST_DATA_REQ  = 4'd1;
localparam [3:0] ST_DATA_WAIT = 4'd2;
localparam [3:0] ST_FAT_REQ   = 4'd3;
localparam [3:0] ST_FAT_WAIT  = 4'd4;
localparam [3:0] ST_FAT_PARSE = 4'd5;
localparam [3:0] ST_FINISH    = 4'd6;
localparam [3:0] ST_DATA_OFFSET = 4'd7;
localparam [3:0] ST_DATA_ADDR   = 4'd8;

localparam integer CHAIN_COUNT_WIDTH = $clog2(MAX_VISITED_CLUSTERS + 1);

reg [3:0] state;
reg [31:0] current_cluster;
reg [31:0] cluster_sector_offset;
reg [31:0] remaining_bytes;
reg [7:0] sector_in_cluster;
reg [8:0] fat_entry_offset;
reg [7:0] fat_byte0;
reg [7:0] fat_byte1;
reg [7:0] fat_byte2;
reg [7:0] fat_byte3;
reg [CHAIN_COUNT_WIDTH-1:0] chain_count;
reg final_chain_check;

wire [27:0] parsed_next_cluster;
assign parsed_next_cluster = {fat_byte3[3:0], fat_byte2, fat_byte1, fat_byte0};
assign file_busy = (state != ST_IDLE);

function [31:0] multiply_by_spc;
    input [31:0] value;
    input [7:0] spc;
    begin
        case (spc)
            8'd1:   multiply_by_spc = value;
            8'd2:   multiply_by_spc = value << 1;
            8'd4:   multiply_by_spc = value << 2;
            8'd8:   multiply_by_spc = value << 3;
            8'd16:  multiply_by_spc = value << 4;
            8'd32:  multiply_by_spc = value << 5;
            8'd64:  multiply_by_spc = value << 6;
            8'd128: multiply_by_spc = value << 7;
            default: multiply_by_spc = 32'd0;
        endcase
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state              <= ST_IDLE;
        file_done          <= 1'b0;
        file_valid         <= 1'b0;
        file_byte          <= 8'd0;
        file_byte_offset   <= 32'd0;
        fs_error           <= ERR_NONE;
        sector_req         <= 1'b0;
        sector_lba         <= 32'd0;
        current_cluster    <= 32'd0;
        cluster_sector_offset <= 32'd0;
        remaining_bytes    <= 32'd0;
        sector_in_cluster  <= 8'd0;
        fat_entry_offset   <= 9'd0;
        fat_byte0          <= 8'd0;
        fat_byte1          <= 8'd0;
        fat_byte2          <= 8'd0;
        fat_byte3          <= 8'd0;
        chain_count        <= {CHAIN_COUNT_WIDTH{1'b0}};
        final_chain_check  <= 1'b0;
    end else begin
        file_done  <= 1'b0;
        file_valid <= 1'b0;
        sector_req <= 1'b0;

        if ((state == ST_DATA_WAIT) && sector_valid && (remaining_bytes != 0)) begin
            file_valid       <= 1'b1;
            file_byte        <= sector_byte;
            file_byte_offset <= file_size - remaining_bytes;
            remaining_bytes  <= remaining_bytes - 1'b1;
        end

        if ((state == ST_FAT_WAIT) && sector_valid) begin
            if (sector_byte_index == fat_entry_offset)
                fat_byte0 <= sector_byte;
            else if (sector_byte_index == fat_entry_offset + 9'd1)
                fat_byte1 <= sector_byte;
            else if (sector_byte_index == fat_entry_offset + 9'd2)
                fat_byte2 <= sector_byte;
            else if (sector_byte_index == fat_entry_offset + 9'd3)
                fat_byte3 <= sector_byte;
        end

        case (state)
            ST_IDLE: if (file_start) begin
                fs_error          <= ERR_NONE;
                file_byte_offset  <= 32'd0;
                remaining_bytes   <= file_size;
                sector_in_cluster <= 8'd0;
                chain_count       <= {{(CHAIN_COUNT_WIDTH-1){1'b0}}, 1'b1};
                final_chain_check <= 1'b0;
                if ((file_size == 0) || (first_cluster < 2) ||
                    (first_cluster > max_cluster) || (sectors_per_cluster == 0)) begin
                    fs_error <= ERR_CLUSTER_RANGE;
                    state    <= ST_FINISH;
                end else begin
                    current_cluster <= first_cluster;
                    state <= ST_DATA_OFFSET;
                end
            end

            ST_DATA_OFFSET: begin
                cluster_sector_offset <= multiply_by_spc(
                                             current_cluster - 32'd2,
                                             sectors_per_cluster);
                state <= ST_DATA_ADDR;
            end

            ST_DATA_ADDR: begin
                sector_lba <= data_start_lba + cluster_sector_offset;
                state      <= ST_DATA_REQ;
            end

            ST_DATA_REQ: if (read_enable && !sector_busy) begin
                sector_req <= 1'b1;
                state      <= ST_DATA_WAIT;
            end

            ST_DATA_WAIT: if (sector_done) begin
                if (sector_error != ERR_NONE) begin
                    fs_error <= ERR_SECTOR;
                    state    <= ST_FINISH;
                end else if ((remaining_bytes == 0) ||
                             ((remaining_bytes == 1) && sector_valid)) begin
                    final_chain_check <= 1'b1;
                    fat_entry_offset  <= {current_cluster[6:0], 2'b00};
                    sector_lba        <= fat_start_lba + (current_cluster >> 7);
                    state             <= ST_FAT_REQ;
                end else if (sector_in_cluster + 1'b1 < sectors_per_cluster) begin
                    sector_in_cluster <= sector_in_cluster + 1'b1;
                    sector_lba        <= sector_lba + 1'b1;
                    state             <= ST_DATA_REQ;
                end else begin
                    sector_in_cluster <= 8'd0;
                    fat_entry_offset  <= {current_cluster[6:0], 2'b00};
                    sector_lba        <= fat_start_lba + (current_cluster >> 7);
                    state             <= ST_FAT_REQ;
                end
            end

            ST_FAT_REQ: if (!sector_busy) begin
                sector_req <= 1'b1;
                state      <= ST_FAT_WAIT;
            end

            ST_FAT_WAIT: if (sector_done) begin
                if (sector_error != ERR_NONE) begin
                    fs_error <= ERR_SECTOR;
                    state    <= ST_FINISH;
                end else begin
                    state <= ST_FAT_PARSE;
                end
            end

            ST_FAT_PARSE: begin
                if (final_chain_check) begin
                    final_chain_check <= 1'b0;
                    if (parsed_next_cluster >= 28'hffffff8) begin
                        state <= ST_FINISH;
                    end else begin
                        fs_error <= ERR_FAT_LOOP;
                        state    <= ST_FINISH;
                    end
                end else if (parsed_next_cluster >= 28'hffffff8) begin
                    fs_error <= ERR_EARLY_EOF;
                    state    <= ST_FINISH;
                end else if ((parsed_next_cluster < 2) ||
                             ({4'd0, parsed_next_cluster} > max_cluster)) begin
                    fs_error <= ERR_CLUSTER_RANGE;
                    state    <= ST_FINISH;
                end else if (chain_count >= MAX_VISITED_CLUSTERS) begin
                    fs_error <= ERR_VISITED_EXHAUSTED;
                    state    <= ST_FINISH;
                end else if ({4'd0, parsed_next_cluster} == current_cluster) begin
                    fs_error <= ERR_FAT_LOOP;
                    state    <= ST_FINISH;
                end else begin
                    chain_count       <= chain_count + 1'b1;
                    current_cluster   <= {4'd0, parsed_next_cluster};
                    sector_in_cluster <= 8'd0;
                    state             <= ST_DATA_OFFSET;
                end
            end

            ST_FINISH: begin
                file_done <= 1'b1;
                state     <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
