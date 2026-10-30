`timescale 1ns/1ps

// Three complete rasters exercise activation/deactivation in mid-frame: only
// the following frame may change. Every active pixel and timing output is checked.
module tb_store_closed;
    reg clk = 0, rst_n = 0, vsync = 0, de = 0, closed = 0;
    reg [10:0] pixel_x = 0;
    wire [23:0] rgb_out;
    wire de_out, vsync_out, active_frame;
    wire [10:0] x_out;
    reg de_pipe [0:2], vs_pipe [0:2];
    integer x_pipe [0:2], y_pipe [0:2], f_pipe [0:2];
    integer x, y = 0, frame = 0, k;
    integer title_pixels [0:3];
    integer subtitle_pixels = 0, covered = 0, restored = 0;
    always #5 clk = ~clk;
    osd_overlay_24 dut (
        .clk(clk), .rst_n(rst_n), .vsync(vsync), .de(de), .rgb_in(24'h123456),
        .pixel_x(pixel_x), .active_index(3'd0), .auto_enabled(1'b1),
        .playback_status(8'h45), .loading_status(closed ? 24'h100000 : 24'hf00000),
        .guide_status(7'd0), .store_closed(closed), .store_closed_active(active_frame),
        .error_code(8'd0), .brightness(8'hff), .contrast(8'h80),
        .rgb_out(rgb_out), .de_out(de_out), .osd_active(), .pixel_x_out(x_out), .vsync_out(vsync_out)
    );
    always @(posedge clk) begin
        for (k = 2; k > 0; k = k - 1) begin
            de_pipe[k] = de_pipe[k-1]; vs_pipe[k] = vs_pipe[k-1];
            x_pipe[k] = x_pipe[k-1]; y_pipe[k] = y_pipe[k-1]; f_pipe[k] = f_pipe[k-1];
        end
        de_pipe[0] = de; vs_pipe[0] = vsync;
        x_pipe[0] = pixel_x; y_pipe[0] = y; f_pipe[0] = frame;
        #1;
        if (rst_n) begin
            if (de_out !== de_pipe[2] || vsync_out !== vs_pipe[2] || x_out !== x_pipe[2])
                $fatal(1, "Notice changed video latency");
            if (de_out && f_pipe[2] == 1) begin
                covered = covered + 1;
                if (rgb_out !== 24'h401C24 && rgb_out !== 24'hD8AF60 &&
                    rgb_out !== 24'hFFF1BE && rgb_out !== 24'hFFF8EE)
                    $fatal(1, "Old image/OSD leaked into notice x=%d y=%d rgb=%h", x_pipe[2], y_pipe[2], rgb_out);
                if (y_pipe[2] == 136 && x_pipe[2] >= 64 && x_pipe[2] < 1216 && rgb_out !== 24'hD8AF60)
                    $fatal(1, "Gold border coordinate mismatch");
                if (rgb_out == 24'hFFF1BE) begin
                    if (x_pipe[2] < 384 || x_pipe[2] >= 896 || y_pipe[2] < 256 || y_pipe[2] >= 384)
                        $fatal(1, "Title glyph outside centered title area");
                    title_pixels[(x_pipe[2]-384)/128] = title_pixels[(x_pipe[2]-384)/128] + 1;
                end
                if (rgb_out == 24'hFFF8EE) subtitle_pixels = subtitle_pixels + 1;
            end
            if (de_out && f_pipe[2] != 1 && y_pipe[2] >= 200 && y_pipe[2] < 600) begin
                if (rgb_out !== 24'h123456) $fatal(1, "Notice tore or did not clear at frame boundary");
                restored = restored + 1;
            end
        end
    end
    initial begin
        for (k = 0; k < 4; k = k + 1) title_pixels[k] = 0;
        repeat (5) @(negedge clk);
        rst_n = 1;
        for (frame = 0; frame < 3; frame = frame + 1) begin
            vsync = 1;
            repeat (8) @(negedge clk);
            vsync = 0;
            for (y = 0; y < 720; y = y + 1) begin
                for (x = 0; x < 1280; x = x + 1) begin
                    de = 1; pixel_x = x;
                    if (y == 360 && x == 640) closed = (frame == 0);
                    @(negedge clk);
                end
                de = 0; pixel_x = 0;
                repeat (6) @(negedge clk);
            end
        end
        repeat (5) @(negedge clk);
        for (k = 0; k < 4; k = k + 1)
            if (title_pixels[k] < 1000) $fatal(1, "Missing Chinese title character %d", k);
        if (covered != 1280*720 || restored != 1280*400*2 || subtitle_pixels < 500)
            $fatal(1, "Incomplete notice raster coverage");
        $display("NOTICE OSD PASS: centered Chinese title/subtitle, full-frame coverage, border, frame-locked entry/exit and unchanged video latency");
        $finish;
    end
    initial begin #40000000; $fatal(1, "Notice raster test timeout"); end
endmodule

module tb_loading_video;
    reg clk = 0, rst_n = 0, vsync = 0, de = 0;
    reg [10:0] x = 0;
    reg [23:0] status = {4'd4, 3'd2, 3'd6, 3'd1, 3'd3, 8'd0};
    wire [23:0] rgb;
    wire de_out, vs_out;
    wire [10:0] x_out;
    reg dp [0:2], vp [0:2];
    integer xp [0:2], yp [0:2], fp [0:2];
    integer col, row = 0, f = 0, k, glyphs = 0, checked = 0;
    reg [23:0] expected;
    // Independent, direct font lookup checks the speculative RTL fetch at
    // every character/row boundary, including the first pixel of each cell.
    wire ref_line2 = row >= 132 && row < 164;
    wire [10:0] ref_text_x = x - 11'd416;
    wire [11:0] ref_text_y = ref_line2 ? row - 132 : row - 92;
    wire [3:0] ref_cell = ref_text_x[8:5];
    wire [6:0] ref_text_glyph;
    wire [6:0] ref_glyph = ref_line2 && ref_cell == 3 ? (f == 0 ? 7'd2 : 7'd6) :
                          ref_line2 && ref_cell == 5 ? 7'd6 :
                          ref_line2 && ref_cell == 10 ? (f == 0 ? 7'd1 : 7'd0) : ref_text_glyph;
    wire [15:0] ref_font_row;
    reg [3:0] ref_col_q;
    reg ref_text_q, ref_pixel_d2, ref_pixel_d3;
    loading_status_text ref_text (.state(f == 0 ? 4'd4 : 4'd5), .second_line(ref_line2),
        .cell_index(ref_cell), .glyph(ref_text_glyph));
    loading_status_font ref_font (.clk(clk), .address({ref_glyph, ref_text_y[4:1]}), .row_bits(ref_font_row));
    always @(posedge clk) begin
        ref_col_q <= ref_text_x[4:1];
        ref_text_q <= x >= 416 && x < 864 && ((row >= 92 && row < 124) || ref_line2);
        ref_pixel_d2 <= ref_text_q && ref_font_row[15-ref_col_q];
        ref_pixel_d3 <= ref_pixel_d2;
    end
    always #5 clk = ~clk;
    osd_overlay_24 dut (.clk(clk), .rst_n(rst_n), .vsync(vsync), .de(de), .pixel_x(x),
        .rgb_in(24'h123456), .active_index(3'd0), .auto_enabled(1'b1),
        .playback_status(8'h45), .loading_status(status), .guide_status(7'd0),
        .store_closed(1'b0), .store_closed_active(),
        .error_code(8'd0), .brightness(8'hff), .contrast(8'h80),
        .rgb_out(rgb), .de_out(de_out), .vsync_out(vs_out), .pixel_x_out(x_out), .osd_active());
    always @(posedge clk) begin
        for (k = 2; k > 0; k = k - 1) begin
            dp[k] = dp[k-1]; vp[k] = vp[k-1];
            xp[k] = xp[k-1]; yp[k] = yp[k-1]; fp[k] = fp[k-1];
        end
        dp[0] = de; vp[0] = vsync; xp[0] = x; yp[0] = row; fp[0] = f;
        #1;
        if (rst_n) begin
            if (de_out !== dp[2] || vs_out !== vp[2] || x_out !== xp[2]) $fatal(1, "Loading panel changed three-stage video alignment");
            if (de_out && yp[2] >= 64 && yp[2] < 220) begin
                checked = checked + 1;
                if (xp[2] < 384 || xp[2] >= 896 || yp[2] < 80 || yp[2] >= 200) begin
                    if (rgb !== 24'h123456) $fatal(1, "Loading panel escaped bounds or image delayed incorrectly");
                end else begin
                    if (rgb !== 24'h162c34 && rgb !== 24'h49baa1 && rgb !== 24'he06b64 && rgb !== 24'h354c51 && rgb !== 24'hfff1be)
                        $fatal(1, "Loading RGB leaked, missing or misaligned at %d,%d", xp[2], yp[2]);
                    if (rgb == 24'hfff1be) glyphs = glyphs + 1;
                    if (xp[2] >= 416 && xp[2] < 864 &&
                        ((yp[2] >= 92 && yp[2] < 124) || (yp[2] >= 132 && yp[2] < 164))) begin
                        expected = ref_pixel_d3 ? 24'hfff1be : 24'h162c34;
                        if (rgb !== expected) $fatal(1, "Loading glyph alignment at %d,%d frame=%d got=%h expected=%h", xp[2], yp[2], fp[2], rgb, expected);
                    end
                    if (yp[2] >= 176 && yp[2] < 184 && xp[2] >= 416 && xp[2] < 848) begin
                        expected = fp[2] == 1 || xp[2] < 560 ? 24'h49baa1 : xp[2] < 632 ? 24'he06b64 : 24'h354c51;
                        if (rgb !== expected) $fatal(1, "Progress edge misalignment or mid-frame tear at %d,%d frame=%d rgb=%h expected=%h status=%h line=%d", xp[2], yp[2], fp[2], rgb, expected, dut.u_loading_status_overlay.status_frame, dut.line_y);
                    end
                end
            end
        end
    end
    initial begin
        repeat (5) @(negedge clk); rst_n = 1;
        // Establish inactive VSYNC after reset before the first frame edge.
        repeat (2) @(negedge clk);
        for (f = 0; f < 2; f = f + 1) begin
            vsync = 1; repeat (8) @(negedge clk); vsync = 0;
            for (row = 0; row < 220; row = row + 1) begin
                for (col = 0; col < 1280; col = col + 1) begin
                    x = col; de = 1;
                    if (row == 140 && col == 0) status = f == 0 ? {4'd5, 3'd6, 3'd6, 3'd0, 3'd6, 8'd0} : 24'h700000;
                    @(negedge clk);
                end
                de = 0; x = 0; repeat (6) @(negedge clk);
            end
        end
        repeat (5) @(negedge clk);
        if (glyphs < 400 || checked != 1280*156*2) $fatal(1, "Loading panel raster incomplete");
        $display("LOADING VIDEO PASS: continuous raster, Chinese text, exact progress edges, mid-frame isolation, image passthrough and three-stage video alignment");
        $finish;
    end
    initial begin #10000000; $fatal(1, "Loading raster timeout"); end
endmodule

module tb_loading_status;
    reg clk = 0, src_clk = 0, rst_n = 0, frame_start = 0, de = 0;
    reg [10:0] x = 0;
    reg [11:0] y = 0;
    reg [23:0] status = {4'd4, 3'd1, 3'd6, 3'd0, 3'd2, 8'd0};
    reg [23:0] src_status = 24'h123456;
    wire [23:0] transferred;
    wire active;
    wire [23:0] rgb;
    integer row, col, n, glyph_pixels = 0, changed_pixels = 0, snapshots = 0;
    integer total, good, failed, green_width, used_width;
    reg [23:0] digit1 [0:1023];
    always #5 clk = ~clk;
    always #7 src_clk = ~src_clk;
    always #37 src_status = src_status == 24'h123456 ? 24'habcdef : 24'h123456;
    loading_status_overlay dut (.clk(clk), .rst_n(rst_n), .frame_start(frame_start),
        .status(status), .de(de), .pixel_x(x), .pixel_y(y), .active(active), .rgb(rgb));
    playback_status_cdc #(.WIDTH(24)) cdc (.src_clk(src_clk), .src_rst_n(rst_n), .src_status(src_status),
        .dst_clk(clk), .dst_rst_n(rst_n), .frame_start(frame_start), .dst_status(transferred));
    always @(negedge clk) if (rst_n && transferred != 0) begin
        if (transferred !== 24'h123456 && transferred !== 24'habcdef) $fatal(1, "Torn 24-bit loading snapshot");
        snapshots = snapshots + 1;
    end
    task frame;
        begin
            @(negedge clk); frame_start = 1; de = 0;
            @(negedge clk); frame_start = 0;
            repeat (5) @(negedge clk);
        end
    endtask
    task pixel;
        input integer px, py;
        begin
            @(negedge clk); x = px; y = py; de = 1;
            repeat (3) @(negedge clk);
        end
    endtask
    task color_is;
        input integer px, py;
        input [23:0] expected;
        begin
            pixel(px, py);
            if (!active || rgb !== expected) $fatal(1, "Loading panel at %d,%d got=%h active=%b expected=%h", px, py, rgb, active, expected);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk); rst_n = 1; frame;
        color_is(384, 100, 24'h49baa1);
        color_is(440, 180, 24'h49baa1);
        color_is(500, 180, 24'h354c51);
        for (row = 92; row < 124; row = row + 1)
            for (col = 416; col < 608; col = col + 1) begin
                pixel(col, row);
                if (rgb == 24'hfff1be) glyph_pixels = glyph_pixels + 1;
            end
        if (glyph_pixels < 200) $fatal(1, "Loading Chinese title missing");
        for (row = 0; row < 32; row = row + 1)
            for (col = 0; col < 32; col = col + 1) begin
                pixel(512+col, 132+row); digit1[row*32+col] = rgb;
            end
        status = {4'd9, 3'd2, 3'd6, 3'd1, 3'd4, 8'd0};
        color_is(500, 180, 24'h354c51); // Mid-frame status must not tear.
        frame;
        color_is(384, 100, 24'he69a48);
        color_is(500, 180, 24'h49baa1);
        color_is(580, 180, 24'he06b64);
        color_is(700, 180, 24'h354c51);
        for (row = 0; row < 32; row = row + 1)
            for (col = 0; col < 32; col = col + 1) begin
                pixel(512+col, 132+row);
                if (rgb != digit1[row*32+col]) changed_pixels = changed_pixels + 1;
            end
        if (changed_pixels < 20) $fatal(1, "Loading count digit did not update");
        repeat (125) frame;
        color_is(580, 180, 24'he06b64); // Warnings never auto-hide.
        // Every supported resource count, including rounding at five files.
        for (total = 1; total <= 6; total = total + 1)
            for (good = 0; good <= total; good = good + 1) begin
                failed = good < total ? 1 : 0;
                status = {4'd4, good[2:0], total[2:0], failed[2:0], 3'd1, 8'd0}; frame;
                green_width = 432 * good / total;
                used_width = 432 * (good + failed) / total;
                if (good > 0) color_is(416+green_width-1, 180, 24'h49baa1);
                if (failed > 0) color_is(416+used_width-1, 180, 24'he06b64);
                if (used_width < 432) color_is(416+used_width, 180, 24'h354c51);
            end
        status = {4'd5, 3'd6, 3'd6, 3'd0, 3'd6, 8'd0}; frame;
        color_is(847, 180, 24'h49baa1);
        repeat (119) frame;
        color_is(400, 90, 24'h162c34);
        frame; pixel(400, 90);
        if (active) $fatal(1, "Successful load did not hide after 120 frames");
        status = 24'h600000; frame;
        color_is(400, 90, 24'h162c34);
        status = 24'hf00000; frame; pixel(400, 90);
        if (active) $fatal(1, "Disabled loading panel remained visible");
        if (snapshots < 100) $fatal(1, "No asynchronous status snapshots observed");
        $display("LOADING OSD PASS: Chinese text/digits, exact progress colors, frame latch, warning persistence, 120-frame auto-hide and atomic 24-bit CDC");
        $finish;
    end
    initial begin #1000000; $fatal(1, "Loading panel timeout"); end
endmodule

module tb_osd_overlay_24;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg vsync = 1'b0;
    reg de = 1'b0;
    reg [10:0] pixel_x = 11'd0;
    wire [23:0] rgb_out;
    wire osd_active;
    integer row;
    integer col;
    integer backdrop_count = 0;
    integer glyph_count = 0;

    always #5 clk = ~clk;

    osd_overlay_24 #(.OSD_X(64), .OSD_Y(48)) dut (
        .clk(clk), .rst_n(rst_n), .vsync(vsync), .de(de),
        .rgb_in(24'h808080), .pixel_x(pixel_x),
        .active_index(3'd0), .auto_enabled(1'b1),
        .playback_status(8'h45), .loading_status(24'hf00000),
        .guide_status(7'd0),
        .store_closed(1'b0), .store_closed_active(),
        .error_code(8'd0), .brightness(8'hff), .contrast(8'h80),
        .rgb_out(rgb_out), .de_out(), .osd_active(osd_active),
        .pixel_x_out(), .vsync_out()
    );

    always @(posedge clk) begin
        if (osd_active && rgb_out == 24'h111111)
            backdrop_count = backdrop_count + 1;
        if (osd_active && rgb_out == 24'hffff00)
            glyph_count = glyph_count + 1;
    end

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        vsync = 1'b1;
        repeat (10) @(negedge clk);
        vsync = 1'b0;
        for (row = 0; row < 80; row = row + 1) begin
            for (col = 0; col < 110; col = col + 1) begin
                @(negedge clk);
                de = 1'b1;
                pixel_x = col;
            end
            @(negedge clk);
            de = 1'b0;
            pixel_x = 11'd0;
            repeat (4) @(negedge clk);
        end
        if (backdrop_count == 0 || glyph_count == 0)
            $fatal(1, "OSD missing: backdrop=%0d glyph=%0d", backdrop_count, glyph_count);
        $display("OSD PASS: backdrop=%0d glyph=%0d", backdrop_count, glyph_count);
        $finish;
    end
endmodule

// Full 720p raster regression: the ticker must not change video latency,
// overwrite the audio-waveform area, tear between lines, or glitch on wrap.
module tb_supermarket_ticker;
    reg clk = 0;
    reg rst_n = 0;
    reg vsync = 0;
    reg de = 0;
    reg [10:0] pixel_x = 0;
    reg [23:0] rgb_in = 0;
    wire [23:0] rgb_out;
    wire de_out, vsync_out, osd_active;
    wire [10:0] pixel_x_out;
    integer drive_y = 0;
    integer frame_id = 0;
    integer row, col, pulse;
    integer k;
    integer glyphs = 0;
    integer comparisons = 0;
    integer waveform_pixels = 0;
    reg de_pipe [0:2];
    reg vs_pipe [0:2];
    integer x_pipe [0:2];
    integer y_pipe [0:2];
    integer frame_pipe [0:2];
    reg [23:0] rgb_pipe [0:2];
    reg [23:0] first_strip [0:40959];

    always #5 clk = ~clk;
    osd_overlay_24 #(.OSD_X(64), .OSD_Y(48)) dut (
        .clk(clk), .rst_n(rst_n), .vsync(vsync), .de(de),
        .rgb_in(rgb_in), .pixel_x(pixel_x),
        .active_index(3'd2), .auto_enabled(1'b1),
        .playback_status(8'h4f), .loading_status(24'hf00000),
        .guide_status(7'd0),
        .store_closed(1'b0), .store_closed_active(),
        .error_code(8'd0), .brightness(8'hff), .contrast(8'h80),
        .rgb_out(rgb_out), .de_out(de_out), .osd_active(osd_active),
        .pixel_x_out(pixel_x_out), .vsync_out(vsync_out)
    );

    always @(posedge clk) begin
        for (k = 2; k > 0; k = k - 1) begin
            de_pipe[k] = de_pipe[k-1];
            vs_pipe[k] = vs_pipe[k-1];
            x_pipe[k] = x_pipe[k-1];
            y_pipe[k] = y_pipe[k-1];
            frame_pipe[k] = frame_pipe[k-1];
            rgb_pipe[k] = rgb_pipe[k-1];
        end
        de_pipe[0] = de;
        vs_pipe[0] = vsync;
        x_pipe[0] = pixel_x;
        y_pipe[0] = drive_y;
        frame_pipe[0] = frame_id;
        rgb_pipe[0] = rgb_in;
        #1;
        if (rst_n && de_pipe[2] !== 1'bx) begin
            if (de_out !== de_pipe[2] || vsync_out !== vs_pipe[2] ||
                pixel_x_out !== x_pipe[2])
                $fatal(1, "Video/coordinate latency changed");
            if (!de_out && osd_active)
                $fatal(1, "Overlay leaked into blanking");
            if (de_out && y_pipe[2] >= 100 && y_pipe[2] < 680) begin
                if (rgb_out !== rgb_pipe[2] || osd_active)
                    $fatal(1, "Picture/waveform area overwritten at %0d,%0d", x_pipe[2], y_pipe[2]);
                waveform_pixels = waveform_pixels + 1;
            end
            if (de_out && y_pipe[2] >= 680) begin
                if (!osd_active)
                    $fatal(1, "Ticker missing at %0d,%0d", x_pipe[2], y_pipe[2]);
                if (y_pipe[2] < 682 && rgb_out !== 24'hd8ad58)
                    $fatal(1, "Ticker top accent misaligned");
                if (y_pipe[2] >= 684 && y_pipe[2] < 716) begin
                    if (rgb_out !== 24'hfff1be && rgb_out !== 24'h102e2c)
                        $fatal(1, "Invalid text/background pixel");
                    if (rgb_out == 24'hfff1be) glyphs = glyphs + 1;
                    if (frame_pipe[2] == 0)
                        first_strip[(y_pipe[2]-684)*1280+x_pipe[2]] = rgb_out;
                    else if (frame_pipe[2] == 1 && x_pipe[2] < 1278) begin
                        if (rgb_out !== first_strip[(y_pipe[2]-684)*1280+x_pipe[2]+2])
                            $fatal(1, "Scroll direction/step or frame coherence failure");
                        comparisons = comparisons + 1;
                    end else if (frame_pipe[2] == 2) begin
                        if (rgb_out !== first_strip[(y_pipe[2]-684)*1280+x_pipe[2]])
                            $fatal(1, "Ticker did not wrap seamlessly");
                        comparisons = comparisons + 1;
                    end
                end else if (y_pipe[2] >= 682 && rgb_out !== 24'h102e2c)
                    $fatal(1, "Glyph leaked outside text band");
            end
        end
    end

    task frame_pulse;
        begin
            @(negedge clk); vsync = 1;
            repeat (6) @(negedge clk);
            vsync = 0;
            repeat (4) @(negedge clk);
        end
    endtask

    task draw_frame;
        begin
            frame_pulse;
            for (row = 0; row < 720; row = row + 1) begin
                for (col = 0; col < 1280; col = col + 1) begin
                    @(negedge clk);
                    de = 1; pixel_x = col; drive_y = row;
                    rgb_in = {col[7:0], row[7:0], 8'h5a};
                end
                @(negedge clk); de = 0; pixel_x = 0;
                repeat (4) @(negedge clk);
            end
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        draw_frame;
        frame_id = 1;
        draw_frame;
        for (pulse = 0; pulse < 1022; pulse = pulse + 1) frame_pulse;
        frame_id = 2;
        draw_frame;
        repeat (5) @(negedge clk);
        if (glyphs < 1000 || comparisons != 81856 || waveform_pixels != 2227200)
            $fatal(1, "Incomplete coverage: glyphs=%0d compare=%0d passthrough=%0d", glyphs, comparisons, waveform_pixels);
        $display("TICKER PASS: Chinese glyphs=%0d, scroll/wrap checks=%0d, passthrough pixels=%0d", glyphs, comparisons, waveform_pixels);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "Ticker test timed out");
    end
endmodule

module tb_playback_countdown;
    reg clk = 0;
    reg src_clk = 0;
    reg rst_n = 0;
    reg frame_start = 0;
    reg de = 0;
    reg [10:0] x = 0;
    reg [11:0] y = 0;
    reg [7:0] status = 8'h4f;
    wire active;
    wire [23:0] rgb;
    wire [7:0] transferred_status;
    always #5 clk = ~clk;
    always #7 src_clk = ~src_clk;
    playback_countdown_overlay panel (
        .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .status(status),
        .de(de), .pixel_x(x), .pixel_y(y), .active(active), .rgb(rgb)
    );
    playback_status_cdc bridge (
        .src_clk(src_clk), .src_rst_n(rst_n), .src_status(status),
        .dst_clk(clk), .dst_rst_n(rst_n), .frame_start(frame_start),
        .dst_status(transferred_status)
    );
    task pulse_frame;
        begin
            @(negedge clk); frame_start = 1;
            @(negedge clk); frame_start = 0;
            repeat (15) @(negedge clk);
            if (transferred_status !== status)
                $fatal(1, "Atomic CDC snapshot failed");
        end
    endtask
    task probe;
        input integer px, py;
        input expected_active;
        input [23:0] expected_rgb;
        begin
            x = px; y = py; de = 1;
            repeat (2) @(negedge clk);
            if (active !== expected_active ||
                (expected_active && rgb !== expected_rgb))
                $fatal(1, "Panel pixel failed at %d,%d: active=%b rgb=%h expected=%h",
                       px, py, active, rgb, expected_rgb);
        end
    endtask
    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        pulse_frame;
        probe(1104,16,1,24'hd8ad58);
        probe(1104,18,1,24'h102e2c);
        probe(1103,30,0,0);
        probe(1264,30,0,0);
        probe(1120,56,0,0);
        probe(1202,30,1,24'h102e2c); // NEXT 15S: tens=1, row0 col1 blank
        probe(1216,30,1,24'hffe17a); // ones=5, top-left filled
        status = 8'h45;
        probe(1202,30,1,24'h102e2c); // unchanged before frame boundary
        pulse_frame;
        probe(1202,30,1,24'hffe17a); // NEXT 05S: tens=0, row0 col1 filled
        status = 8'h4e;
        pulse_frame;
        probe(1216,30,1,24'h102e2c); // NEXT 14S: ones=4, top-left blank
        status = 8'h80;
        pulse_frame;
        probe(1120,30,1,24'hb8c5c9); // PAUSED
        status = 8'hc0;
        pulse_frame;
        probe(1122,30,1,24'hfff1be); // SELECT
        status = 0;
        pulse_frame;
        probe(1120,30,1,24'hfff1be); // WAIT...
        de = 0;
        repeat (2) @(negedge clk);
        if (active) $fatal(1, "Panel leaked into blanking");
        $display("COUNTDOWN OSD PASS: decimal glyphs, states, frame latch, clipping, latency and asynchronous snapshots");
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "Countdown panel test timed out");
    end
endmodule
