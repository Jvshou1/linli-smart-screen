`timescale 1ns/1ps

module tb_video_delay_720p;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg thumbnail_mode = 1'b0;
    reg de = 1'b0;
    reg valid = 1'b0;
    reg [23:0] data = 24'd0;
    wire read_en;
    wire de_out;
    wire [23:0] pixel_out;
    integer source_pixel = 0;
    integer output_pixel = 0;
    integer expected;
    integer n;

    always #5 clk = ~clk;

    video_delay dut (
        .video_clk(clk), .rst(rst), .thumbnail_mode(thumbnail_mode),
        .read_en(read_en), .read_valid(valid), .read_data(data),
        .hs(1'b0), .vs(1'b0), .de(de),
        .hs_r(), .vs_r(), .de_r(de_out), .vout_data(pixel_out)
    );

    always @(posedge clk) begin
        valid <= read_en;
        if (read_en) begin
            source_pixel <= source_pixel + 1;
            data <= source_pixel + 1;
        end
        #1;
        if (de_out) begin
            expected = thumbnail_mode ? output_pixel + 1 : output_pixel / 2 + 1;
            if (pixel_out !== expected)
                $fatal(1, "mode=%0d pixel=%0d got=%0d expected=%0d",
                       thumbnail_mode, output_pixel, pixel_out, expected);
            output_pixel = output_pixel + 1;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        for (n = 0; n < 8; n = n + 1) begin
            @(negedge clk);
            de = 1'b1;
        end
        @(negedge clk);
        de = 1'b0;
        repeat (24) @(negedge clk);
        if (output_pixel != 8 || source_pixel != 4)
            $fatal(1, "full screen counts: output=%0d source=%0d", output_pixel, source_pixel);
        thumbnail_mode = 1'b1;
        output_pixel = 0;
        source_pixel = 0;
        for (n = 0; n < 8; n = n + 1) begin
            @(negedge clk);
            de = 1'b1;
        end
        @(negedge clk);
        de = 1'b0;
        repeat (24) @(negedge clk);
        if (output_pixel != 8 || source_pixel != 8)
            $fatal(1, "thumbnail counts: output=%0d source=%0d", output_pixel, source_pixel);
        $display("VIDEO DELAY PASS: full-screen duplication and thumbnail cadence");
        $finish;
    end
endmodule
