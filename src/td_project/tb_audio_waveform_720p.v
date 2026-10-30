`timescale 1ns/1ps

module tb_audio_waveform_720p;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg vsync = 1'b0;
    reg de = 1'b0;
    reg [10:0] pixel_x = 11'd0;
    reg pcm_valid = 1'b0;
    wire [23:0] rgb_out;
    wire active;
    integer row;

    always #5 clk = ~clk;

    promax_audio_waveform #(
        .WAVE_X(64), .WAVE_Y(400), .WAVE_WIDTH(512),
        .WAVE_HEIGHT(64), .DECIMATE(1), .SAMPLE_COUNT(32)
    ) dut (
        .clk(clk), .rst_n(rst_n), .vsync(vsync), .de(de),
        .rgb_in(24'h202020), .pixel_x(pixel_x), .enable(1'b1),
        .pcm_tap_valid(pcm_valid), .pcm_tap_left(16'sh4000),
        .rgb_out(rgb_out), .waveform_active(active)
    );

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk); vsync = 1'b1;
        @(negedge clk); vsync = 1'b0;
        for (row = 0; row < 32; row = row + 1) begin
            @(negedge clk); pcm_valid = 1'b1;
        end
        @(negedge clk); pcm_valid = 1'b0;
        @(negedge clk); vsync = 1'b1;
        @(negedge clk); vsync = 1'b0;
        repeat (3) @(negedge clk);
        if (!dut.display_valid)
            $fatal(1, "captured waveform did not commit at frame start");

        for (row = 0; row < 416; row = row + 1) begin
            @(negedge clk); de = 1'b1;
            @(negedge clk); de = 1'b0;
        end
        @(negedge clk);
        if (dut.line_y !== 416)
            $fatal(1, "wrong active-line counter: %0d", dut.line_y);
        pixel_x = 11'd68;
        de = 1'b1;
        repeat (4) @(negedge clk);
        if (!active || rgb_out !== 24'h34eac4)
            $fatal(1, "waveform pixel missing: active=%0d rgb=%h", active, rgb_out);
        $display("AUDIO WAVEFORM PASS: active line and PCM bar visible");
        $finish;
    end
endmodule
