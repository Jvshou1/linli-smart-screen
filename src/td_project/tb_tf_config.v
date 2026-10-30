`timescale 1ns/1ps

module tb_tf_config;
    reg clk = 0, rst = 1, start = 0, valid = 0, done = 0;
    reg [7:0] byte_in = 0;
    wire [5:0] d0, d1, d2, d3, d4, d5;
    wire [2:0] volume;
    wire autoplay;
    wire autoplay_present;
    reg config_valid = 0, key3 = 1;
    wire [7:0] gain;
    wire [1:0] period;
    integer i;
    reg [8*10-1:0] final_line = "AUTOPLAY=0";
    reg [8*7-1:0] crlf_line = "PIC6=01";

    always #5 clk = ~clk;
    tf_config_parser dut (
        .clk(clk), .rst(rst), .start(start), .valid(valid), .done(done),
        .byte_in(byte_in), .dwell0(d0), .dwell1(d1), .dwell2(d2),
        .dwell3(d3), .dwell4(d4), .dwell5(d5),
        .volume_level(volume), .autoplay(autoplay),
        .autoplay_present(autoplay_present)
    );
    param_menu_controller #(.CLKS_PER_MS(1)) menu (
        .clk(clk), .rst_n(!rst), .key1_n(1'b1), .key3_n(key3),
        .config_valid(config_valid), .config_volume_level(volume),
        .volume_gain(gain), .period_level(period)
    );

    task send_byte;
        input [7:0] value;
        begin
            @(negedge clk);
            byte_in = value;
            valid = 1;
            @(negedge clk);
            valid = 0;
        end
    endtask

    task send_line;
        input [8*16-1:0] data;
        input integer len;
        integer j;
        begin
            for (j = len - 1; j >= 0; j = j - 1)
                send_byte(data[j*8 +: 8]);
            send_byte(8'h0a);
        end
    endtask

    task restart;
        begin
            @(negedge clk);
            start = 1;
            @(negedge clk);
            start = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        restart;
        send_line("PIC1=30", 7);
        send_line("PIC2=00", 7);
        send_line("PIC3=31", 7);
        send_line("PIC4=ab", 7);
        send_line("VOLUME=4", 8);
        send_line("AUTOPLAY=1", 10);
        send_line("UNKNOWN=9", 9);
        if (d0 != 30 || d1 != 10 || d2 != 15 || d3 != 8 ||
            d4 != 10 || d5 != 10 || volume != 4 || !autoplay || !autoplay_present)
            $fatal(1, "valid and invalid config lines were not isolated");
        config_valid = 1;
        repeat (3) @(negedge clk);
        if (gain != 255 || period != 3)
            $fatal(1, "configured volume was not applied");
        key3 = 0;
        repeat (30) @(negedge clk);
        key3 = 1;
        repeat (30) @(negedge clk);
        if (gain != 0)
            $fatal(1, "KEY3 did not advance from configured volume");

        restart;
        config_valid = 0;
        if (autoplay_present)
            $fatal(1, "AUTOPLAY presence leaked across config reads");
        for (i = 6; i >= 0; i = i - 1)
            send_byte(crlf_line[i*8 +: 8]);
        send_byte(8'h0d);
        send_byte(8'h0a);
        // A final line without LF must still be accepted at EOF.
        for (i = 9; i >= 0; i = i - 1)
            send_byte(final_line[i*8 +: 8]);
        @(negedge clk);
        done = 1;
        @(negedge clk);
        done = 0;
        if (d0 != 5 || d5 != 1 || volume != 1 || autoplay || !autoplay_present)
            $fatal(1, "defaults, CRLF, or EOF failed d0=%0d d5=%0d volume=%0d auto=%0d",
                   d0, d5, volume, autoplay);
        restart;
        send_line("PIC1=06", 7);
        if (d0 != 6 || autoplay_present)
            $fatal(1, "omitted AUTOPLAY did not preserve its absent state");
        $display("TF CONFIG PASS: defaults, values, invalid lines, CRLF, EOF, volume");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "TF config timeout");
    end
endmodule
