`timescale 1ns/1ps

module tb_fat32_config_lookup;
    reg clk = 0, rst_n = 0, sector_valid = 0;
    reg [7:0] sector_byte = 0;
    reg [8:0] sector_byte_index = 0;
    wire config_valid;
    wire [31:0] config_cluster, config_size;
    integer i;
    reg [15:0] entry_size;

    always #5 clk = ~clk;
    fat32_volume_scanner dut (
        .clk(clk), .rst_n(rst_n), .scan_start(1'b0),
        .config_resource_valid(config_valid),
        .config_resource_cluster(config_cluster),
        .config_resource_size(config_size),
        .sector_busy(1'b0), .sector_valid(sector_valid),
        .sector_byte(sector_byte), .sector_byte_index(sector_byte_index),
        .sector_done(1'b0), .sector_error(8'd0)
    );

    function [7:0] entry_byte;
        input integer offset;
        input [15:0] size;
        begin
            case (offset)
                0: entry_byte = "C"; 1: entry_byte = "O";
                2: entry_byte = "N"; 3: entry_byte = "F";
                4: entry_byte = "I"; 5: entry_byte = "G";
                6,7: entry_byte = " ";
                8: entry_byte = "T"; 9: entry_byte = "X";
                10: entry_byte = "T";
                11: entry_byte = 8'h20;
                26: entry_byte = 8'd2;
                28: entry_byte = size[7:0];
                29: entry_byte = size[15:8];
                default: entry_byte = 8'd0;
            endcase
        end
    endfunction

    task send_entry;
        input [15:0] size;
        begin
            @(negedge clk);
            dut.state = 4'd12; // ST_ROOT_WAIT, bypass BPB setup in this lookup test.
            for (i = 0; i < 32; i = i + 1) begin
                sector_byte_index = i;
                sector_byte = entry_byte(i, size);
                sector_valid = 1;
                @(negedge clk);
            end
            sector_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        send_entry(16'd60);
        if (!config_valid || config_cluster != 2 || config_size != 60)
            $fatal(1, "CONFIG.TXT root entry was not found");
        @(negedge clk);
        rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        send_entry(16'd513);
        if (config_valid)
            $fatal(1, "oversize config must be ignored");
        $display("FAT32 CONFIG LOOKUP PASS: root entry and 512-byte size limit");
        $finish;
    end
endmodule
