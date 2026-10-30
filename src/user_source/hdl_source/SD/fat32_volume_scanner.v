`timescale 1ns/1ps

// FAT32 volume discovery and fixed 8.3 root-directory resource lookup.
// The root directory's first cluster is scanned in full, matching PIC1.BMP
// through PIC6.BMP. Missing files are reported while valid entries are kept.
module fat32_volume_scanner (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        scan_start,
    output wire        scan_busy,
    output reg         scan_done,
    output reg  [7:0]  fs_error,
    output reg  [31:0] partition_lba,
    output reg  [7:0]  sectors_per_cluster,
    output reg  [31:0] fat_start_lba,
    output reg  [31:0] data_start_lba,
    output reg  [31:0] max_cluster,
    output reg  [5:0]  resource_valid,
    output reg  [31:0] resource0_cluster,
    output reg  [31:0] resource1_cluster,
    output reg  [31:0] resource2_cluster,
    output reg  [31:0] resource3_cluster,
    output reg  [31:0] resource4_cluster,
    output reg  [31:0] resource5_cluster,
    output reg  [31:0] resource0_size,
    output reg  [31:0] resource1_size,
    output reg  [31:0] resource2_size,
    output reg  [31:0] resource3_size,
    output reg  [31:0] resource4_size,
    output reg  [31:0] resource5_size,
    output reg         audio_resource_valid,
    output reg  [31:0] audio_resource_cluster,
    output reg  [31:0] audio_resource_size,
    output reg         config_resource_valid,
    output reg  [31:0] config_resource_cluster,
    output reg  [31:0] config_resource_size,
    output reg         sector_req,
    output reg  [31:0] sector_lba,
    input  wire        sector_busy,
    input  wire        sector_valid,
    input  wire [7:0]  sector_byte,
    input  wire [8:0]  sector_byte_index,
    input  wire        sector_done,
    input  wire [7:0]  sector_error
);

localparam [7:0] ERR_NONE             = 8'h00;
localparam [7:0] ERR_SECTOR           = 8'h10;
localparam [7:0] ERR_BOOT_SIGNATURE   = 8'h20;
localparam [7:0] ERR_UNSUPPORTED_BPB  = 8'h21;
localparam [7:0] ERR_RESOURCE_MISSING = 8'h22;

localparam [3:0] ST_IDLE        = 4'd0;
localparam [3:0] ST_LBA0_REQ    = 4'd1;
localparam [3:0] ST_LBA0_WAIT   = 4'd2;
localparam [3:0] ST_LBA0_PARSE  = 4'd3;
localparam [3:0] ST_BOOT_REQ    = 4'd4;
localparam [3:0] ST_BOOT_WAIT   = 4'd5;
localparam [3:0] ST_BOOT_PARSE  = 4'd6;
localparam [3:0] ST_LAYOUT_SUM   = 4'd7;
localparam [3:0] ST_LAYOUT_DATA  = 4'd8;
localparam [3:0] ST_LAYOUT_LIMIT = 4'd9;
localparam [3:0] ST_LAYOUT_ROOT  = 4'd10;
localparam [3:0] ST_ROOT_REQ     = 4'd11;
localparam [3:0] ST_ROOT_WAIT    = 4'd12;
localparam [3:0] ST_ROOT_NEXT    = 4'd13;
localparam [3:0] ST_FINISH       = 4'd14;

reg [3:0] state;
reg       scan_start_q;
reg [7:0] sector_buffer [0:511];
reg [31:0] total_sectors;
reg [31:0] fat_sectors;
reg [31:0] root_cluster;
reg [31:0] root_first_lba;
reg [31:0] data_sector_count;
reg [31:0] fat_span;
reg [31:0] layout_overhead;
reg [31:0] root_sector_offset;
reg [15:0] reserved_sectors;
reg [7:0] fat_count;
reg [7:0] root_sector_index;
reg root_end_seen;

reg [7:0] dir_name0;
reg [7:0] dir_name1;
reg [7:0] dir_name2;
reg [7:0] dir_name3;
reg [7:0] dir_name4;
reg [7:0] dir_name5;
reg [7:0] dir_name6;
reg [7:0] dir_name7;
reg [7:0] dir_name8;
reg [7:0] dir_name9;
reg [7:0] dir_name10;
reg       dir_match;
reg       dir_audio_match;
reg       dir_config_match;
reg [2:0] dir_resource_index;
reg [15:0] dir_cluster_high;
reg [15:0] dir_cluster_low;
reg [31:0] dir_file_size;

assign scan_busy = (state != ST_IDLE);

function [15:0] le16;
    input integer offset;
    begin
        le16 = {sector_buffer[offset+1], sector_buffer[offset]};
    end
endfunction

function [31:0] le32;
    input integer offset;
    begin
        le32 = {sector_buffer[offset+3], sector_buffer[offset+2],
                sector_buffer[offset+1], sector_buffer[offset]};
    end
endfunction

function valid_spc;
    input [7:0] value;
    begin
        valid_spc = (value != 0) && ((value & (value - 1'b1)) == 0);
    end
endfunction

// FAT32 permits only power-of-two sectors-per-cluster values.  Expressing the
// layout math as shifts avoids inferring a large combinational divider.
function [31:0] divide_by_spc;
    input [31:0] value;
    input [7:0] spc;
    begin
        case (spc)
            8'd1:   divide_by_spc = value;
            8'd2:   divide_by_spc = value >> 1;
            8'd4:   divide_by_spc = value >> 2;
            8'd8:   divide_by_spc = value >> 3;
            8'd16:  divide_by_spc = value >> 4;
            8'd32:  divide_by_spc = value >> 5;
            8'd64:  divide_by_spc = value >> 6;
            8'd128: divide_by_spc = value >> 7;
            default: divide_by_spc = 32'd0;
        endcase
    end
endfunction

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

function is_fat32_partition;
    input [7:0] partition_type;
    begin
        is_fat32_partition = (partition_type == 8'h0b) ||
                             (partition_type == 8'h0c) ||
                             (partition_type == 8'h1b) ||
                             (partition_type == 8'h1c);
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                <= ST_IDLE;
        scan_start_q         <= 1'b0;
        scan_done            <= 1'b0;
        fs_error             <= ERR_NONE;
        partition_lba        <= 32'd0;
        sectors_per_cluster  <= 8'd0;
        fat_start_lba        <= 32'd0;
        data_start_lba       <= 32'd0;
        max_cluster          <= 32'd0;
        resource_valid       <= 6'd0;
        resource0_cluster    <= 32'd0;
        resource1_cluster    <= 32'd0;
        resource2_cluster    <= 32'd0;
        resource3_cluster    <= 32'd0;
        resource4_cluster    <= 32'd0;
        resource5_cluster    <= 32'd0;
        resource0_size       <= 32'd0;
        resource1_size       <= 32'd0;
        resource2_size       <= 32'd0;
        resource3_size       <= 32'd0;
        resource4_size       <= 32'd0;
        resource5_size       <= 32'd0;
        audio_resource_valid <= 1'b0;
        audio_resource_cluster <= 32'd0;
        audio_resource_size  <= 32'd0;
        config_resource_valid <= 1'b0;
        config_resource_cluster <= 32'd0;
        config_resource_size <= 32'd0;
        sector_req           <= 1'b0;
        sector_lba           <= 32'd0;
        total_sectors        <= 32'd0;
        fat_sectors          <= 32'd0;
        root_cluster         <= 32'd0;
        root_first_lba       <= 32'd0;
        data_sector_count    <= 32'd0;
        fat_span             <= 32'd0;
        layout_overhead      <= 32'd0;
        root_sector_offset   <= 32'd0;
        reserved_sectors     <= 16'd0;
        fat_count            <= 8'd0;
        root_sector_index    <= 8'd0;
        root_end_seen        <= 1'b0;
        dir_name0            <= 8'd0;
        dir_name1            <= 8'd0;
        dir_name2            <= 8'd0;
        dir_name3            <= 8'd0;
        dir_name4            <= 8'd0;
        dir_name5            <= 8'd0;
        dir_name6            <= 8'd0;
        dir_name7            <= 8'd0;
        dir_name8            <= 8'd0;
        dir_name9            <= 8'd0;
        dir_name10           <= 8'd0;
        dir_match            <= 1'b0;
        dir_audio_match      <= 1'b0;
        dir_config_match     <= 1'b0;
        dir_resource_index   <= 3'd0;
        dir_cluster_high     <= 16'd0;
        dir_cluster_low      <= 16'd0;
        dir_file_size        <= 32'd0;
    end else begin
        scan_start_q <= scan_start;
        scan_done  <= 1'b0;
        sector_req <= 1'b0;

        if (sector_valid && (state != ST_ROOT_WAIT))
            sector_buffer[sector_byte_index] <= sector_byte;

        if (sector_valid && (state == ST_ROOT_WAIT)) begin
            case (sector_byte_index[4:0])
                5'd0: begin
                    dir_name0  <= sector_byte;
                    dir_match  <= 1'b0;
                    dir_audio_match <= 1'b0;
                    dir_config_match <= 1'b0;
                    if (sector_byte == 8'h00)
                        root_end_seen <= 1'b1;
                end
                5'd1:  dir_name1  <= sector_byte;
                5'd2:  dir_name2  <= sector_byte;
                5'd3:  dir_name3  <= sector_byte;
                5'd4:  dir_name4  <= sector_byte;
                5'd5:  dir_name5  <= sector_byte;
                5'd6:  dir_name6  <= sector_byte;
                5'd7:  dir_name7  <= sector_byte;
                5'd8:  dir_name8  <= sector_byte;
                5'd9:  dir_name9  <= sector_byte;
                5'd10: dir_name10 <= sector_byte;
                5'd11: begin
                    if ((dir_name0 != 8'h00) && (dir_name0 != 8'he5) &&
                        ((sector_byte & 8'h18) == 0) &&
                        (dir_name0 == "P") && (dir_name1 == "I") &&
                        (dir_name2 == "C") && (dir_name3 >= "1") &&
                        (dir_name3 <= "6") && (dir_name4 == " ") &&
                        (dir_name5 == " ") && (dir_name6 == " ") &&
                        (dir_name7 == " ") && (dir_name8 == "B") &&
                        (dir_name9 == "M") && (dir_name10 == "P")) begin
                        dir_match          <= 1'b1;
                        dir_resource_index <= dir_name3 - "1";
                    end else if ((dir_name0 != 8'h00) &&
                                 (dir_name0 != 8'he5) &&
                                 ((sector_byte & 8'h18) == 0) &&
                                 (dir_name0 == "A") && (dir_name1 == "U") &&
                                 (dir_name2 == "D") && (dir_name3 == "I") &&
                                 (dir_name4 == "O") && (dir_name5 == " ") &&
                                 (dir_name6 == " ") && (dir_name7 == " ") &&
                                 (dir_name8 == "P") && (dir_name9 == "C") &&
                                 (dir_name10 == "M")) begin
                        dir_audio_match <= 1'b1;
                    end else if ((dir_name0 != 8'h00) &&
                                 (dir_name0 != 8'he5) &&
                                 ((sector_byte & 8'h18) == 0) &&
                                 (dir_name0 == "C") && (dir_name1 == "O") &&
                                 (dir_name2 == "N") && (dir_name3 == "F") &&
                                 (dir_name4 == "I") && (dir_name5 == "G") &&
                                 (dir_name6 == " ") && (dir_name7 == " ") &&
                                 (dir_name8 == "T") && (dir_name9 == "X") &&
                                 (dir_name10 == "T")) begin
                        dir_config_match <= 1'b1;
                    end
                end
                5'd20: dir_cluster_high[7:0]  <= sector_byte;
                5'd21: dir_cluster_high[15:8] <= sector_byte;
                5'd26: dir_cluster_low[7:0]   <= sector_byte;
                5'd27: dir_cluster_low[15:8]  <= sector_byte;
                5'd28: dir_file_size[7:0]     <= sector_byte;
                5'd29: dir_file_size[15:8]    <= sector_byte;
                5'd30: dir_file_size[23:16]   <= sector_byte;
                5'd31: begin
                    dir_file_size[31:24] <= sector_byte;
                    if (dir_match && ({dir_cluster_high, dir_cluster_low} >= 2) &&
                        ({sector_byte, dir_file_size[23:0]} != 0)) begin
                        case (dir_resource_index)
                            3'd0: begin
                                resource0_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource0_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[0] <= 1'b1;
                            end
                            3'd1: begin
                                resource1_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource1_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[1] <= 1'b1;
                            end
                            3'd2: begin
                                resource2_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource2_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[2] <= 1'b1;
                            end
                            3'd3: begin
                                resource3_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource3_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[3] <= 1'b1;
                            end
                            3'd4: begin
                                resource4_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource4_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[4] <= 1'b1;
                            end
                            default: begin
                                resource5_cluster <= {dir_cluster_high, dir_cluster_low};
                                resource5_size    <= {sector_byte, dir_file_size[23:0]};
                                resource_valid[5] <= 1'b1;
                            end
                        endcase
                    end else if (dir_audio_match &&
                                 ({dir_cluster_high, dir_cluster_low} >= 2) &&
                                 ({sector_byte, dir_file_size[23:0]} != 0)) begin
                        audio_resource_cluster <= {dir_cluster_high,
                                                   dir_cluster_low};
                        audio_resource_size <= {sector_byte,
                                                dir_file_size[23:0]};
                        audio_resource_valid <= 1'b1;
                    end else if (dir_config_match &&
                                 ({dir_cluster_high, dir_cluster_low} >= 2) &&
                                 ({sector_byte, dir_file_size[23:0]} != 0) &&
                                 ({sector_byte, dir_file_size[23:0]} <= 512)) begin
                        config_resource_cluster <= {dir_cluster_high,
                                                    dir_cluster_low};
                        config_resource_size <= {sector_byte,
                                                 dir_file_size[23:0]};
                        config_resource_valid <= 1'b1;
                    end
                end
                default: begin end
            endcase
        end

        case (state)
            ST_IDLE: if (scan_start_q) begin
                fs_error          <= ERR_NONE;
                partition_lba     <= 32'd0;
                resource_valid    <= 6'd0;
                resource0_cluster <= 32'd0;
                resource1_cluster <= 32'd0;
                resource2_cluster <= 32'd0;
                resource3_cluster <= 32'd0;
                resource4_cluster <= 32'd0;
                resource5_cluster <= 32'd0;
                resource0_size    <= 32'd0;
                resource1_size    <= 32'd0;
                resource2_size    <= 32'd0;
                resource3_size    <= 32'd0;
                resource4_size    <= 32'd0;
                resource5_size    <= 32'd0;
                audio_resource_valid <= 1'b0;
                audio_resource_cluster <= 32'd0;
                audio_resource_size <= 32'd0;
                config_resource_valid <= 1'b0;
                config_resource_cluster <= 32'd0;
                config_resource_size <= 32'd0;
                state             <= ST_LBA0_REQ;
            end

            ST_LBA0_REQ: if (!sector_busy) begin
                sector_lba <= 32'd0;
                sector_req <= 1'b1;
                state      <= ST_LBA0_WAIT;
            end

            ST_LBA0_WAIT: if (sector_done) begin
                if (sector_error != ERR_NONE) begin
                    fs_error <= ERR_SECTOR;
                    state    <= ST_FINISH;
                end else begin
                    state <= ST_LBA0_PARSE;
                end
            end

            ST_LBA0_PARSE: begin
                if ((sector_buffer[510] != 8'h55) || (sector_buffer[511] != 8'haa)) begin
                    fs_error <= ERR_BOOT_SIGNATURE;
                    state    <= ST_FINISH;
                end else if (((sector_buffer[0] == 8'heb) ||
                              (sector_buffer[0] == 8'he9)) &&
                             (le16(11) == 16'd512) &&
                             valid_spc(sector_buffer[13]) &&
                             (le16(14) != 0) &&
                             ((sector_buffer[16] == 1) ||
                              (sector_buffer[16] == 2)) &&
                             (le16(17) == 0) && (le16(22) == 0) &&
                             (le32(32) != 0) && (le32(36) != 0) &&
                             (le32(44) >= 2)) begin
                    // Some MBR bootstrap code also starts with EB/E9.  Treat
                    // LBA0 as a superfloppy only when its BPB is FAT32-shaped.
                    partition_lba <= 32'd0;
                    state         <= ST_BOOT_PARSE;
                end else if (is_fat32_partition(sector_buffer[450])) begin
                    partition_lba <= le32(454);
                    sector_lba    <= le32(454);
                    state         <= ST_BOOT_REQ;
                end else if (is_fat32_partition(sector_buffer[466])) begin
                    partition_lba <= le32(470);
                    sector_lba    <= le32(470);
                    state         <= ST_BOOT_REQ;
                end else if (is_fat32_partition(sector_buffer[482])) begin
                    partition_lba <= le32(486);
                    sector_lba    <= le32(486);
                    state         <= ST_BOOT_REQ;
                end else if (is_fat32_partition(sector_buffer[498])) begin
                    partition_lba <= le32(502);
                    sector_lba    <= le32(502);
                    state         <= ST_BOOT_REQ;
                end else begin
                    fs_error <= ERR_UNSUPPORTED_BPB;
                    state    <= ST_FINISH;
                end
            end

            ST_BOOT_REQ: if (!sector_busy) begin
                sector_req <= 1'b1;
                state      <= ST_BOOT_WAIT;
            end

            ST_BOOT_WAIT: if (sector_done) begin
                if (sector_error != ERR_NONE) begin
                    fs_error <= ERR_SECTOR;
                    state    <= ST_FINISH;
                end else begin
                    state <= ST_BOOT_PARSE;
                end
            end

            ST_BOOT_PARSE: begin
                if ((sector_buffer[510] != 8'h55) || (sector_buffer[511] != 8'haa)) begin
                    fs_error <= ERR_BOOT_SIGNATURE;
                    state    <= ST_FINISH;
                end else if ((le16(11) != 16'd512) || !valid_spc(sector_buffer[13]) ||
                             (le16(14) == 0) ||
                             ((sector_buffer[16] != 1) && (sector_buffer[16] != 2)) ||
                             (le16(17) != 0) || (le16(22) != 0) ||
                             (le32(32) == 0) || (le32(36) == 0) ||
                             (le32(44) < 2)) begin
                    fs_error <= ERR_UNSUPPORTED_BPB;
                    state    <= ST_FINISH;
                end else begin
                    sectors_per_cluster <= sector_buffer[13];
                    reserved_sectors    <= le16(14);
                    fat_count           <= sector_buffer[16];
                    total_sectors       <= le32(32);
                    fat_sectors         <= le32(36);
                    root_cluster        <= le32(44);
                    fat_span            <= le32(36) * sector_buffer[16];
                    fat_start_lba        <= partition_lba + le16(14);
                    state                <= ST_LAYOUT_SUM;
                end
            end

            // Pipeline the FAT32 layout math. Keeping subtraction, division by
            // sectors-per-cluster and address generation in separate cycles is
            // required for reliable operation at the 100 MHz SD clock.
            ST_LAYOUT_SUM: begin
                layout_overhead <= {16'd0, reserved_sectors} + fat_span;
                state           <= ST_LAYOUT_DATA;
            end

            ST_LAYOUT_DATA: begin
                if (total_sectors <= layout_overhead) begin
                    fs_error <= ERR_UNSUPPORTED_BPB;
                    state    <= ST_FINISH;
                end else begin
                    data_start_lba    <= partition_lba + layout_overhead;
                    data_sector_count <= total_sectors - layout_overhead;
                    root_sector_offset <= multiply_by_spc(root_cluster - 2,
                                                          sectors_per_cluster);
                    state <= ST_LAYOUT_LIMIT;
                end
            end

            ST_LAYOUT_LIMIT: begin
                max_cluster <= divide_by_spc(data_sector_count,
                                             sectors_per_cluster) + 1'b1;
                state <= ST_LAYOUT_ROOT;
            end

            ST_LAYOUT_ROOT: begin
                if (root_cluster > max_cluster) begin
                    fs_error <= ERR_UNSUPPORTED_BPB;
                    state    <= ST_FINISH;
                end else begin
                    root_first_lba    <= data_start_lba + root_sector_offset;
                    sector_lba        <= data_start_lba + root_sector_offset;
                    root_sector_index <= 8'd0;
                    root_end_seen     <= 1'b0;
                    state             <= ST_ROOT_REQ;
                end
            end

            ST_ROOT_REQ: if (!sector_busy) begin
                dir_match  <= 1'b0;
                dir_audio_match <= 1'b0;
                dir_config_match <= 1'b0;
                sector_req <= 1'b1;
                state      <= ST_ROOT_WAIT;
            end

            ST_ROOT_WAIT: if (sector_done) begin
                if (sector_error != ERR_NONE) begin
                    fs_error <= ERR_SECTOR;
                    state    <= ST_FINISH;
                end else begin
                    state <= ST_ROOT_NEXT;
                end
            end

            ST_ROOT_NEXT: begin
                if (((resource_valid == 6'h3f) && audio_resource_valid &&
                     config_resource_valid) ||
                    root_end_seen ||
                    (root_sector_index + 1'b1 >= sectors_per_cluster)) begin
                    if (resource_valid == 6'd0)
                        fs_error <= ERR_RESOURCE_MISSING;
                    state <= ST_FINISH;
                end else begin
                    root_sector_index <= root_sector_index + 1'b1;
                    sector_lba        <= root_first_lba + root_sector_index + 1'b1;
                    state             <= ST_ROOT_REQ;
                end
            end

            ST_FINISH: begin
                scan_done <= 1'b1;
                state     <= ST_IDLE;
            end

            default: state <= ST_IDLE;
        endcase
    end
end

endmodule
