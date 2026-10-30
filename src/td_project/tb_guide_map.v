`timescale 1ns/1ps

module tb_guide_map;
    reg clk = 0, rst_n = 0, frame_start = 0, de = 1;
    reg [3:0] status = 0;
    reg [10:0] x = 0;
    reg [11:0] y = 0;
    wire active;
    wire [23:0] rgb;
    integer px, py, text_pixels;

    always #5 clk = ~clk;
    guide_map_overlay dut (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .status(status), .de(de), .pixel_x(x), .pixel_y(y),
        .active(active), .rgb(rgb)
    );

    task frame;
        input [3:0] value;
        begin
            @(negedge clk);
            status = value;
            frame_start = 1;
            @(negedge clk);
            frame_start = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    task check_pixel;
        input [10:0] check_x;
        input [11:0] check_y;
        input check_active;
        input [23:0] check_rgb;
        begin
            @(negedge clk);
            x = check_x;
            y = check_y;
            repeat (4) @(negedge clk);
            if (active !== check_active ||
                (check_active && rgb !== check_rgb))
                $fatal(1, "Guide pixel mismatch x=%0d y=%0d active=%b rgb=%h expected=%b/%h",
                       check_x, check_y, active, rgb, check_active, check_rgb);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        frame(4'b1100); // Fresh, confirmed.
        check_pixel(225, 300, 1, 24'hFFD04E);
        check_pixel(500, 531, 1, 24'h43E2C0);
        check_pixel(300, 300, 0, 24'd0);
        check_pixel(130, 55, 1, 24'hFFD04E);

        text_pixels = 0;
        for (py = 75; py < 107; py = py + 1)
            for (px = 208; px < 304; px = px + 1) begin
                @(negedge clk);
                x = px;
                y = py;
                repeat (3) @(negedge clk);
                if (active && rgb == 24'hFFF4D8)
                    text_pixels = text_pixels + 1;
            end
        if (text_pixels == 0)
            $fatal(1, "Chinese guide label did not render");

        frame(4'b1111); // Checkout, confirmed.
        check_pixel(918, 550, 1, 24'hFFD04E);
        check_pixel(225, 300, 0, 24'd0);
        frame(4'b1010); // Daily goods, selecting only.
        check_pixel(868, 300, 0, 24'd0);
        check_pixel(384, 60, 1, 24'h567A77);
        frame(4'b0000);
        check_pixel(130, 55, 0, 24'd0);
        $display("GUIDE MAP PASS: zones, route, Chinese labels, selection and disabled state");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Guide map timeout");
    end
endmodule
