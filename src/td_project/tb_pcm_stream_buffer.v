`timescale 1ns/1ps
module tb_pcm_stream_buffer;
    reg wr_clk = 0;
    reg rd_clk = 0;
    reg rst_n = 0;
    reg enabled = 0;
    reg byte_valid = 0;
    reg [7:0] byte_data = 0;
    wire pcm_valid;
    wire [23:0] pcm_left, pcm_right;
    integer n;
    integer received = 0;
    integer cycles = 0;
    integer last_cycle = 0;
    integer failures = 0;
    reg signed [15:0] sample_value;
    reg signed [24:0] expected;
    always #5 wr_clk = ~wr_clk;
    always #6.666667 rd_clk = ~rd_clk;

    pcm_stream_buffer #(.RD_CLK_HZ(75000000)) dut (
        .wr_clk(wr_clk), .wr_rst_n(rst_n), .stream_enable(enabled),
        .byte_valid(byte_valid), .byte_data(byte_data), .fill_enable(),
        .rd_clk(rd_clk), .rd_rst_n(rst_n), .gain(8'd255),
        .pcm_valid(pcm_valid), .pcm_left(pcm_left), .pcm_right(pcm_right),
        .buffer_low()
    );

    always @(negedge rd_clk) begin
        cycles = cycles + 1;
        if (pcm_valid) begin
            sample_value = (received % 2) ? -16'sh2345 : 16'sh1234;
            expected = sample_value * 25'sd255;
            if (pcm_left !== expected[23:0] || pcm_right !== expected[23:0]) begin
                $display("FAIL PCM sample %0d: got=%h expected=%h", received,
                         pcm_left, expected[23:0]);
                failures = failures + 1;
            end
            if (received && (cycles-last_cycle != 1562) && (cycles-last_cycle != 1563)) begin
                $display("FAIL PCM cadence: %0d cycles", cycles-last_cycle);
                failures = failures + 1;
            end
            last_cycle = cycles;
            received = received + 1;
            if (received == 96) begin
                if (failures) $fatal(1, "PCM failures: %0d", failures);
                $display("PCM PLAYBACK PASS: signed stereo samples, 48 kHz at 75 MHz");
                $finish;
            end
        end
    end

    initial begin
        repeat (5) @(negedge wr_clk);
        rst_n = 1;
        enabled = 1;
        // Supply alternating positive and negative little-endian mono samples.
        for (n = 0; n < 512; n = n + 1) begin
            sample_value = (n % 2) ? -16'sh2345 : 16'sh1234;
            @(negedge wr_clk);
            byte_valid = 1;
            byte_data = sample_value[7:0];
            @(negedge wr_clk);
            byte_data = sample_value[15:8];
        end
        @(negedge wr_clk);
        byte_valid = 0;
        #3000000;
        $fatal(1, "PCM timeout: received=%0d", received);
    end
endmodule

module tb_audio_soft_volume;
    reg clk = 0, rst_n = 0, muted = 0, pcm_requested = 0;
    reg [7:0] volume = 255;
    reg pcm_valid = 0, tone_valid = 0;
    reg [23:0] pcm_left = 0, pcm_right = 0, tone_left = 0, tone_right = 0;
    wire out_valid;
    wire [23:0] out_left, out_right;
    integer n, previous_gain = 0, timeout, gain_used;
    reg signed [23:0] left_signed, right_signed;
    reg signed [63:0] expected_left, expected_right;
    always #5 clk = ~clk;
    audio_soft_volume #(.CLK_HZ(256000), .FADE_MS(16)) dut (
        .clk(clk), .rst_n(rst_n), .volume(volume), .muted(muted), .pcm_requested(pcm_requested),
        .pcm_valid(pcm_valid), .pcm_left(pcm_left), .pcm_right(pcm_right),
        .tone_valid(tone_valid), .tone_left(tone_left), .tone_right(tone_right),
        .out_valid(out_valid), .out_left(out_left), .out_right(out_right)
    );
    always @(negedge clk) if (rst_n) begin
        if (dut.current_gain > 256 || $signed({1'b0, dut.current_gain}) - previous_gain > 1 ||
            previous_gain - $signed({1'b0, dut.current_gain}) > 1)
            $fatal(1, "Gain jumped or overflowed");
        previous_gain = dut.current_gain;
    end
    task check_sample;
        input [23:0] left_value, right_value;
        begin
            @(negedge clk);
            pcm_left = left_value; tone_left = left_value;
            pcm_right = right_value; tone_right = right_value;
            pcm_valid = 1; tone_valid = 1;
            gain_used = dut.current_gain;
            left_signed = left_value; right_signed = right_value;
            expected_left = left_signed; expected_left = (expected_left * gain_used) >>> 8;
            expected_right = right_signed; expected_right = (expected_right * gain_used) >>> 8;
            @(negedge clk); pcm_valid = 0; tone_valid = 0;
            for (timeout = 0; timeout < 9; timeout = timeout + 1) begin
                if (out_valid) $fatal(1, "Early or duplicated output sample");
                @(negedge clk);
            end
            if (!out_valid || out_left !== expected_left[23:0] || out_right !== expected_right[23:0])
                $fatal(1, "Soft volume arithmetic/valid mismatch gain=%d got=%h/%h expected=%h/%h", gain_used, out_left, out_right, expected_left[23:0], expected_right[23:0]);
            @(negedge clk);
            if (out_valid) $fatal(1, "Output valid is not a one-cycle pulse");
        end
    endtask
    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        // Exercise every part of the fade using opposite-polarity stereo.
        for (n = 0; n < 400; n = n + 1) check_sample(n[0] ? 24'h800000 : 24'h7fffff, n[0] ? 24'h123457 : 24'hfedcba);
        if (dut.current_gain != 256) $fatal(1, "Startup did not reach unity");
        check_sample(24'h800000, 24'h7fffff);
        volume = 64; repeat (3100) @(negedge clk);
        if (dut.current_gain != 64) $fatal(1, "Volume ramp target");
        check_sample(24'hffffff, 24'h123457);
        muted = 1; repeat (1100) @(negedge clk);
        if (dut.current_gain != 0) $fatal(1, "Notice did not fade out");
        check_sample(24'h800000, 24'h7fffff);
        muted = 0; repeat (200) @(negedge clk);
        muted = 1; repeat (220) @(negedge clk);
        if (dut.current_gain != 0) $fatal(1, "Mid-fade reversal failed");
        muted = 0; volume = 255; repeat (4200) @(negedge clk);
        // No PCM samples at all: source switching must not deadlock.
        pcm_requested = 1; repeat (4300) @(negedge clk);
        if (!dut.source_pcm || dut.current_gain > 12) $fatal(1, "Source did not switch at silence");
        repeat (4300) @(negedge clk);
        if (dut.current_gain != 256) $fatal(1, "PCM did not fade in");
        check_sample(24'h7fffff, 24'h800000);
        pcm_requested = 0; repeat (8500) @(negedge clk);
        if (dut.source_pcm || dut.current_gain != 256) $fatal(1, "Fallback recovery stalled without PCM");
        volume = 0; repeat (4200) @(negedge clk);
        check_sample(24'h7fffff, 24'h800000);
        $display("SOFT AUDIO PASS: signed stereo, exact unity/mute, gradual volume, notice reversal, sample alignment and source switching without samples");
        $finish;
    end
    initial begin #1000000; $fatal(1, "Soft audio timeout"); end
endmodule
