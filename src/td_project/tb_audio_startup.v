`timescale 1ns/1ps

// Exercise control at the image/audio ownership boundary without a physical
// card. The real scanner, streamer and SPI controller are elaborated below.
module tb_audio_startup;
    reg clk = 0;
    reg rst = 1;
    reg key1 = 1;
    reg key2 = 1;
    reg key3 = 1;
    reg [3:0] image_adjust_sw = 0;
    reg [1:0] period_level = 3;
    reg transition_busy = 0;
    reg transition_commit = 0;
    wire [1:0] menu_period;
    wire [7:0] menu_volume;
    integer failures = 0;
    integer bmp_starts = 0;
    integer audio_starts = 0;
    integer prev_requests = 0;
    reg prev_tracking = 0;
    reg [2:0] prev_target_seen = 0;
    always #5 clk = ~clk;

    sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut (
        .clk(clk), .rst(rst), .key_next(key1), .key_auto(key2),
        .key_menu(key3), .image_adjust_sw(image_adjust_sw),
        .auto_period_level(period_level),
        .start_enable(1'b0), .transition_commit(transition_commit),
        .transition_busy(transition_busy), .audio_fill_enable(1'b1),
        .write_finish_toggle(1'b0), .write_req_ack(1'b0),
        .SD_MISO(1'b1)
    );

    param_menu_controller #(.CLKS_PER_MS(1)) menu (
        .clk(clk), .rst_n(!rst), .key1_n(key1), .key3_n(key3),
        .volume_gain(menu_volume), .period_level(menu_period)
    );

    task menu_press;
        input integer cycles;
        begin
            key3 = 0;
            repeat (cycles) @(negedge clk);
            key3 = 1;
            repeat (40) @(negedge clk);
        end
    endtask

    // Check the actual request boundary, rather than just the dwell lookup.
    task check_dwell;
        input [2:0] index;
        input integer cycles;
        integer elapsed;
        integer expected_seconds;
        begin
            dut.img_idx = index;
            dut.disp_buf_idx = index;
            dut.auto_cnt = 0;
            dut.auto_play_en = 1;
            for (elapsed = 1; elapsed < cycles; elapsed = elapsed + 1) begin
                @(negedge clk);
                expected_seconds = (cycles / 1000) - ((elapsed - 1) / 1000);
                if (dut.playback_status !== (8'h40 | expected_seconds))
                    $fatal(1, "Countdown mismatch: image=%d elapsed=%d status=%h expected=%d",
                           index, elapsed, dut.playback_status, expected_seconds);
                if (dut.transition_request)
                    $fatal(1, "Early auto request: image=%d count=%d expected=%d",
                           index, dut.auto_cnt, cycles);
            end
            @(negedge clk);
            if (!dut.transition_request || dut.auto_cnt != 0 ||
                dut.transition_target != ((index == 5) ? 0 : index + 1))
                $fatal(1, "Dwell boundary failed: image=%d cycles=%d target=%d request=%b",
                       index, cycles, dut.transition_target, dut.transition_request);
            dut.auto_play_en = 0;
            @(negedge clk);
        end
    endtask

    task idle_session;
        input thumbnails;
        input autoplay;
        begin
            dut.thumbnail_mode = thumbnails;
            dut.auto_play_en = autoplay;
            dut.auto_cnt = 0;
            dut.idle_seconds = 0;
            dut.idle_second_count = 0;
            dut.next_req_pending = 0;
        end
    endtask

    task check_idle_boundary;
        integer elapsed;
        reg old_thumbnails;
        reg old_autoplay;
        reg [2:0] old_bank;
        begin
            old_thumbnails = dut.thumbnail_mode;
            old_autoplay = dut.auto_play_en;
            old_bank = dut.disp_buf_idx;
            for (elapsed = 1; elapsed < 30000; elapsed = elapsed + 1) begin
                @(negedge clk);
                if (dut.thumbnail_mode != old_thumbnails ||
                    dut.auto_play_en != old_autoplay || dut.transition_request)
                    $fatal(1, "Early idle recovery/transition at %d cycles time=%t mode=%b auto=%b req=%b guide=%b",
                           elapsed, $time, dut.thumbnail_mode, dut.auto_play_en,
                           dut.transition_request, dut.guide_active);
            end
            @(negedge clk);
            if (dut.thumbnail_mode || !dut.auto_play_en || dut.auto_cnt != 0 ||
                dut.transition_request || dut.disp_buf_idx != old_bank ||
                dut.next_req_pending)
                $fatal(1, "Idle recovery did not preserve bank and restart full dwell");
            repeat (2) @(negedge clk);
            if (dut.playback_status != 8'h4f)
                $fatal(1, "Idle recovery did not restore NEXT 15S: %h", dut.playback_status);
        end
    endtask

    always @(negedge clk) if (!rst) begin
        if (dut.load_start_pulse) bmp_starts = bmp_starts + 1;
        if (dut.audio_file_start_pulse) audio_starts = audio_starts + 1;
        if (prev_tracking && dut.transition_request) begin
            prev_requests = prev_requests + 1;
            prev_target_seen = dut.transition_target;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        if (menu_period != 3 || menu_volume != 64)
            $fatal(1, "Power-on timing mode is not per-image");
        force dut.sd_init_done = 1;
        force dut.scanner_done = 0;
        force dut.scanner_audio_valid = 1;
        force dut.scanner_audio_cluster = 32'd100;
        force dut.scanner_audio_size = 32'd96000;
        force dut.scanner_resource_valid = 6'b000011;
        force dut.bmp_ready = 1;
        // Card data is not modeled in this control test; prevent the real
        // streamer reporting an invalid-volume EOF from the injected start.
        force dut.file_done = 0;
        dut.scan_kicked = 1;
        dut.scan_complete = 1;
        dut.img_found_count = 2;
        // Just after the last preload completes, its registered summary is
        // still low for one cycle. It must not start another BMP load.
        dut.preload_attempted = 6'b000011;
        dut.image_complete = 6'b000011;
        dut.load_busy = 0;
        dut.preload_prepare = 0;
        dut.preload_done = 0;
        repeat (6) @(negedge clk);
        if (bmp_starts != 0 || audio_starts != 1) begin
            $display("FAIL ownership: BMP starts=%0d audio starts=%0d", bmp_starts, audio_starts);
            failures = failures + 1;
        end

        // A successful EOF restarts only PCM and retains reader ownership.
        force dut.file_error = 0;
        force dut.file_done = 1;
        @(negedge clk);
        force dut.file_done = 0;
        repeat (2) @(negedge clk);
        if (bmp_starts != 0 || audio_starts != 2 || !dut.audio_mode) begin
            $display("FAIL audio loop: BMP starts=%0d audio starts=%0d active=%b",
                     bmp_starts, audio_starts, dut.audio_mode);
            failures = failures + 1;
        end

        // Confirming the image already on screen must exit thumbnails without
        // requesting a fade whose bank-change acknowledgement can never occur.
        dut.thumbnail_mode = 1;
        dut.thumbnail_focus_index = 0;
        dut.disp_buf_idx = 0;
        force dut.key_auto_release = 1;
        @(negedge clk);
        release dut.key_auto_release;
        if (dut.thumbnail_mode || dut.transition_request) begin
            $display("FAIL same-image confirm: thumbnail=%b transition=%b",
                     dut.thumbnail_mode, dut.transition_request);
            failures = failures + 1;
        end
        @(negedge clk);
        dut.thumbnail_mode = 1;
        dut.thumbnail_focus_index = 1;
        // KEY2 press must no longer move focus or confirm immediately.
        force dut.key_auto_press = 1;
        @(negedge clk);
        release dut.key_auto_press;
        if (!dut.thumbnail_mode || dut.thumbnail_focus_index != 1)
            $fatal(1, "KEY2 press moved focus or confirmed before release");
        // Releasing a long press or the mode-switch chord must not confirm.
        dut.long_press_marked = 1;
        force dut.key_auto_release = 1;
        @(negedge clk);
        if (!dut.thumbnail_mode) $fatal(1, "Long KEY2 press confirmed");
        dut.chord_press_marked = 1;
        @(negedge clk);
        if (!dut.thumbnail_mode) $fatal(1, "Chord release confirmed");
        release dut.key_auto_release;
        @(negedge clk);
        // A normal short release selects the focused bank without autoplay.
        dut.auto_play_en = 0;
        force dut.key_auto_release = 1;
        @(negedge clk);
        release dut.key_auto_release;
        if (dut.thumbnail_mode || !dut.transition_request || dut.transition_target != 1) begin
            $display("FAIL different-image confirm: thumbnail=%b transition=%b target=%0d",
                     dut.thumbnail_mode, dut.transition_request, dut.transition_target);
            failures = failures + 1;
        end
        repeat (3) @(negedge clk);
        if (dut.auto_play_en) $fatal(1, "Confirm release toggled autoplay");
        // KEY1 remains the forward selector, including wraparound.
        dut.thumbnail_mode = 1;
        force dut.key_next_short_event = 1;
        @(negedge clk);
        release dut.key_next_short_event;
        if (dut.thumbnail_focus_index != 0)
            $fatal(1, "KEY1 focus wrap failed");

        // Real button signals through the synchronizers and 20-cycle debounce.
        // A full-screen -> thumbnail chord must survive either release order.
        dut.thumbnail_mode = 0;
        dut.display_valid = 1;
        dut.auto_play_en = 0;
        dut.disp_buf_idx = 0;
        dut.img_idx = 0;
        key1 = 0; key2 = 0;
        repeat (1060) @(negedge clk);
        if (!dut.thumbnail_mode) $fatal(1, "Real chord did not enter thumbnails");
        key1 = 1;
        repeat (40) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (!dut.thumbnail_mode || dut.auto_play_en)
            $fatal(1, "Real chord release confirmed or toggled autoplay");

        dut.thumbnail_focus_index = 0;
        key2 = 0;
        repeat (40) @(negedge clk);
        if (!dut.thumbnail_mode || dut.thumbnail_focus_index != 0)
            $fatal(1, "Real KEY2 press moved focus");
        key2 = 1;
        repeat (40) @(negedge clk);
        if (dut.thumbnail_mode || dut.auto_play_en)
            $fatal(1, "Real KEY2 release failed same-image confirm");

        dut.thumbnail_mode = 1;
        key2 = 0;
        repeat (1060) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (!dut.thumbnail_mode)
            $fatal(1, "Real long KEY2 release unexpectedly confirmed");

        key1 = 0;
        repeat (40) @(negedge clk);
        if (dut.thumbnail_focus_index != 0)
            $fatal(1, "KEY1 advanced before short-release discrimination");
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.thumbnail_focus_index != 1)
            $fatal(1, "Real KEY1 did not advance focus");
        dut.transition_target = 0;
        key2 = 0;
        repeat (40) @(negedge clk);
        key2 = 1;
        repeat (25) @(negedge clk);
        @(negedge clk);
        if (dut.thumbnail_mode || dut.transition_target != 1 || dut.auto_play_en)
            $fatal(1, "Real different-image confirm failed: mode=%b target=%d auto=%b long=%b chord=%b focus=%d complete=%b busy=%b",
                   dut.thumbnail_mode, dut.transition_target, dut.auto_play_en,
                   dut.long_press_marked, dut.chord_press_marked,
                   dut.thumbnail_focus_index, dut.image_complete, dut.transition_busy);
        if (failures) $fatal(1, "audio startup regressions: %0d", failures);

        // KEY3 short presses retain volume control; long releases cycle
        // independent -> 2s -> 5s -> 10s -> independent, with no 30s mode.
        menu_press(40);
        if (menu_period != 3 || menu_volume != 128)
            $fatal(1, "KEY3 short press changed the timing mode");
        menu_press(1060);
        if (menu_period != 0 || menu_volume != 128) $fatal(1, "Expected global 2s");
        menu_press(1060);
        if (menu_period != 1) $fatal(1, "Expected global 5s");
        menu_press(1060);
        if (menu_period != 2) $fatal(1, "Expected global 10s");
        menu_press(1060);
        if (menu_period != 3) $fatal(1, "Expected per-image wraparound");

        // KEY1+KEY3 is a one-shot previous-image gesture, regardless of
        // which button is released first. It must consume both single keys.
        dut.image_complete = 6'b100101;
        dut.img_idx = 0;
        dut.disp_buf_idx = 0;
        dut.auto_play_en = 0;
        dut.thumbnail_mode = 0;
        prev_requests = 0;
        prev_tracking = 1;
        key1 = 0;
        repeat (30) @(negedge clk);
        key3 = 0;
        repeat (1060) @(negedge clk);
        if (prev_requests != 1 || prev_target_seen != 5 || dut.store_closed ||
            dut.guide_active || dut.thumbnail_mode)
            $fatal(1, "Previous chord failed: count=%0d target=%0d", prev_requests, prev_target_seen);
        repeat (1200) @(negedge clk);
        if (prev_requests != 1 || dut.store_closed)
            $fatal(1, "Holding previous chord repeated or opened notice");
        key1 = 1;
        repeat (40) @(negedge clk);
        key3 = 1;
        repeat (40) @(negedge clk);
        if (prev_requests != 1 || menu_period != 3 || menu_volume != 128 ||
            dut.auto_play_en || dut.next_req_pending)
            $fatal(1, "Previous chord leaked a single-key action");
        dut.img_idx = 5;
        dut.disp_buf_idx = 5;
        key3 = 0;
        repeat (30) @(negedge clk);
        key1 = 0;
        repeat (1060) @(negedge clk);
        if (prev_requests != 2 || prev_target_seen != 2)
            $fatal(1, "Reverse previous chord failed: count=%0d target=%0d", prev_requests, prev_target_seen);
        key3 = 1;
        repeat (40) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        prev_tracking = 0;
        if (prev_requests != 2 || menu_period != 3 || menu_volume != 128 ||
            dut.store_closed || dut.guide_active || dut.auto_play_en)
            $fatal(1, "Reverse release leaked a single-key action");
        key1 = 0; key3 = 0;
        repeat (100) @(negedge clk);
        key1 = 1; key3 = 1;
        repeat (40) @(negedge clk);
        if (prev_requests != 2 || menu_period != 3 || menu_volume != 128 ||
            dut.store_closed || dut.next_req_pending)
            $fatal(1, "Aborted previous chord leaked a single-key action");

        dut.thumbnail_mode = 0;
        dut.img_found_count = 6;
        dut.preload_attempted = 6'b111111;
        dut.image_complete = 6'b111111;
        dut.next_req_pending = 0;
        repeat (3) @(negedge clk);
        check_dwell(0, 5000);
        check_dwell(1, 10000);
        check_dwell(2, 15000);
        check_dwell(3, 8000);
        check_dwell(4, 10000);
        check_dwell(5, 10000);
        period_level = 0;
        repeat (2) @(negedge clk);
        check_dwell(2, 2000);
        period_level = 1;
        repeat (2) @(negedge clk);
        check_dwell(2, 5000);
        period_level = 2;
        repeat (2) @(negedge clk);
        check_dwell(2, 10000);

        // A shorter mode must clear elapsed time instead of firing at once.
        dut.auto_play_en = 1;
        dut.auto_cnt = 9000;
        period_level = 0;
        @(negedge clk);
        if (dut.auto_cnt != 0 || dut.transition_request)
            $fatal(1, "Changing timing mode caused an immediate advance");
        if (dut.playback_status != 8'h42)
            $fatal(1, "Countdown did not restart at new interval");
        transition_busy = 1;
        repeat (25) @(negedge clk);
        if (dut.auto_cnt != 0 || dut.transition_request)
            $fatal(1, "Timer ran during transition");
        transition_commit = 1;
        @(negedge clk);
        transition_busy = 0;
        @(negedge clk);
        if (dut.auto_cnt != 0) $fatal(1, "Commit did not reset dwell");
        transition_commit = 0;
        dut.auto_play_en = 0;
        repeat (3) @(negedge clk);
        if (dut.playback_status != 8'h82) $fatal(1, "Missing paused status");
        dut.thumbnail_mode = 1;
        @(negedge clk);
        if (dut.playback_status[7:6] != 3) $fatal(1, "Missing selection status");
        dut.display_valid = 0;
        @(negedge clk);
        if (dut.playback_status[7:6] != 0) $fatal(1, "Missing waiting status");
        // Paused full-screen and thumbnails both recover after exactly 30s.
        // Keep the displayed bank, not the different thumbnail cursor.
        dut.display_valid = 1;
        period_level = 3;
        repeat (4) @(negedge clk);
        dut.disp_buf_idx = 2;
        dut.img_idx = 2;
        dut.thumbnail_focus_index = 4;
        idle_session(0, 0);
        check_idle_boundary;
        check_dwell(2, 15000);
        idle_session(1, 1);
        dut.auto_cnt = 14999;
        check_idle_boundary;
        idle_session(1, 0);
        check_idle_boundary;

        // A KEY3 hold beyond the timeout is continuous activity. Its release
        // also changes the timing mode; use the normal controller path.
        idle_session(0, 0);
        repeat (20000) @(negedge clk);
        key3 = 0;
        repeat (31000) @(negedge clk);
        if (dut.auto_play_en || dut.idle_seconds != 0)
            $fatal(1, "Held KEY3 was treated as unattended use");
        key3 = 1;
        while (dut.user_activity) @(negedge clk);
        check_idle_boundary;

        // KEY1 now owns the emergency gesture. A long hold toggles once,
        // consumes its release, and remains closed well beyond idle recovery.
        idle_session(0, 0);
        dut.img_idx = 2;
        dut.disp_buf_idx = 2;
        key1 = 0;
        repeat (31000) @(negedge clk);
        if (!dut.store_closed || dut.auto_play_en || dut.idle_seconds != 0 ||
            dut.disp_buf_idx != 2 || dut.thumbnail_mode || dut.transition_request)
            $fatal(1, "Long KEY1 did not latch a single closed notice");
        key1 = 1;
        repeat (31000) @(negedge clk);
        if (!dut.store_closed || dut.auto_play_en || dut.idle_seconds != 0 || dut.disp_buf_idx != 2)
            $fatal(1, "Closed notice expired or its release changed the bank");
        key2 = 0;
        repeat (40) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (!dut.store_closed || dut.auto_play_en || dut.transition_request)
            $fatal(1, "KEY2 bypassed the closed-notice lock");
        // Even holding the thumbnail chord beyond the notice threshold cannot
        // exit the notice, nor can retaining KEY1 after releasing KEY2.
        key1 = 0; key2 = 0;
        repeat (3060) @(negedge clk);
        key2 = 1;
        repeat (3060) @(negedge clk);
        if (!dut.store_closed || dut.thumbnail_mode)
            $fatal(1, "Chord was mistaken for an emergency gesture");
        key1 = 1;
        repeat (40) @(negedge clk);
        key1 = 0;
        repeat (2060) @(negedge clk);
        if (dut.store_closed || !dut.auto_play_en || dut.thumbnail_mode ||
            dut.disp_buf_idx != 2 || dut.auto_cnt > 100 || dut.transition_request)
            $fatal(1, "Second long KEY1 did not resume current image with full dwell");
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.disp_buf_idx != 2) $fatal(1, "Exit release also skipped a picture");
        idle_session(0, 0);
        // KEY2 long hold enters guide once; KEY1 selects, KEY2 confirms.
        key2 = 0;
        repeat (31000) @(negedge clk);
        if (!dut.guide_active || dut.guide_confirmed || dut.guide_category != 0 ||
            dut.auto_play_en || dut.idle_seconds != 0 || dut.guide_return_idx != 2)
            $fatal(1, "KEY2 hold failed to enter guide or paused state");
        key2 = 1;
        repeat (40) @(negedge clk);
        key1 = 0;
        repeat (40) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.guide_category != 1 || dut.disp_buf_idx != 2)
            $fatal(1, "KEY1 failed to cycle guide category");
        key2 = 0;
        repeat (40) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (!dut.guide_confirmed || dut.disp_buf_idx != 1 ||
            dut.auto_play_en || dut.guide_status != 7'b1101001)
            $fatal(1, "KEY2 guide confirmation failed");
        key1 = 0;
        repeat (40) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.guide_category != 2 || dut.guide_confirmed || dut.disp_buf_idx != 1)
            $fatal(1, "Changing category did not clear old highlight");
        key2 = 0;
        repeat (40) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (!dut.guide_confirmed || dut.guide_category != 2)
            $fatal(1, "Guide category reconfirmation failed");
        repeat (31000) @(negedge clk);
        if (!dut.guide_active || dut.auto_play_en || dut.idle_seconds != 0)
            $fatal(1, "Guide was treated as unattended use");
        key2 = 0;
        repeat (1060) @(negedge clk);
        key2 = 1;
        repeat (40) @(negedge clk);
        if (dut.guide_active || dut.disp_buf_idx != 2 || dut.auto_play_en)
            $fatal(1, "Guide exit failed to restore prior picture and playback");
        force dut.scanner_resource_valid = 6'b000001;
        key2 = 0;
        repeat (1060) @(negedge clk);
        if (dut.guide_active)
            $fatal(1, "Guide entered without PIC2.BMP");
        key2 = 1;
        repeat (40) @(negedge clk);
        force dut.scanner_resource_valid = 6'b000011;
        while (dut.user_activity) @(negedge clk);
        idle_session(0, 0);
        check_idle_boundary;

        // Every adjustment switch rearms the timeout even if the new switch
        // position is nonzero. A fixed position must not inhibit recovery.
        idle_session(0, 0);
        repeat (20000) @(negedge clk);
        image_adjust_sw = 4'b1010;
        repeat (3) @(negedge clk);
        while (dut.user_activity) @(negedge clk);
        check_idle_boundary;

        // Expiry waits for an in-flight transition and its commit, then
        // restarts using the committed bank. Stale selection requests clear.
        idle_session(1, 0);
        transition_busy = 1;
        repeat (31000) @(negedge clk);
        if (!dut.thumbnail_mode || dut.auto_play_en || dut.idle_seconds != 30)
            $fatal(1, "Idle expiry interrupted an active transition");
        transition_commit = 1;
        dut.transition_target = 2;
        transition_busy = 0;
        @(negedge clk);
        if (!dut.thumbnail_mode || dut.auto_play_en)
            $fatal(1, "Recovery collided with transition commit");
        transition_commit = 0;
        dut.next_req_pending = 1;
        @(negedge clk);
        if (dut.thumbnail_mode || !dut.auto_play_en || dut.auto_cnt != 0 ||
            dut.next_req_pending || dut.transition_request)
            $fatal(1, "Delayed recovery did not clear pending navigation");

        idle_session(0, 0);
        dut.display_valid = 0;
        repeat (31000) @(negedge clk);
        if (dut.auto_play_en || dut.idle_seconds != 0)
            $fatal(1, "Recovery ran before images were ready");
        dut.display_valid = 1;
        dut.img_found_count = 1;
        dut.image_complete = 6'b000001;
        dut.preload_attempted = 6'b000001;
        repeat (31000) @(negedge clk);
        if (dut.auto_play_en || dut.idle_seconds != 0)
            $fatal(1, "Recovery ran with fewer than two usable images");
        // An accepted transition still commits while the foreground notice
        // owns the screen; the PCM reader retains its existing ownership.
        dut.img_found_count = 6;
        dut.image_complete = 6'b111111;
        dut.preload_attempted = 6'b111111;
        dut.config_autoplay_allowed = 0;
        idle_session(0, 0);
        repeat (31000) @(negedge clk);
        if (dut.auto_play_en || dut.idle_seconds != 0)
            $fatal(1, "AUTOPLAY=0 did not disable idle recovery");
        key1 = 0;
        repeat (2060) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        key1 = 0;
        repeat (2060) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.store_closed || dut.auto_play_en)
            $fatal(1, "AUTOPLAY=0 was bypassed on emergency notice exit");
        dut.config_autoplay_allowed = 1;
        dut.img_idx = 2;
        dut.disp_buf_idx = 2;
        transition_busy = 1;
        key1 = 0;
        repeat (2060) @(negedge clk);
        if (!dut.store_closed || dut.transition_request || !dut.audio_mode)
            $fatal(1, "Notice interrupted PCM ownership or transition control");
        key1 = 1;
        repeat (40) @(negedge clk);
        dut.transition_target = 5;
        transition_commit = 1;
        @(negedge clk);
        transition_commit = 0;
        transition_busy = 0;
        if (!dut.store_closed || dut.disp_buf_idx != 5 || dut.auto_play_en)
            $fatal(1, "In-flight transition commit was discarded in notice mode");
        key1 = 0;
        repeat (2060) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.store_closed || dut.disp_buf_idx != 5 || !dut.auto_play_en || !dut.audio_mode)
            $fatal(1, "Notice exit did not retain committed image and audio ownership");
        // The emergency control must still work with SD initialization absent.
        force dut.sd_init_done = 0;
        key1 = 0;
        repeat (2060) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (!dut.store_closed) $fatal(1, "Notice depended on SD readiness");
        repeat (31000) @(negedge clk);
        if (!dut.store_closed) $fatal(1, "SD-unready notice expired");
        key1 = 0;
        repeat (2060) @(negedge clk);
        key1 = 1;
        repeat (40) @(negedge clk);
        if (dut.store_closed) $fatal(1, "Could not exit SD-unready notice");
        $display("CONTROL PASS: audio/buttons, dwell/countdown, idle recovery, KEY1 emergency hold/release/chord isolation, latched notice and SD-independent control");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "Button regression timed out");
    end
endmodule

module tb_loading_telemetry;
    reg clk = 0, rst = 1, enabled = 0;
    wire [23:0] status;
    always #5 clk = ~clk;
    sd_card_bmp #(.CLK_FREQ_HZ(1000)) dut (
        .clk(clk), .rst(rst), .key_next(1'b1), .key_auto(1'b1), .key_menu(1'b1),
        .image_adjust_sw(4'd0), .auto_period_level(2'd3), .start_enable(enabled),
        .transition_commit(1'b0), .transition_busy(1'b0), .audio_fill_enable(1'b1),
        .write_finish_toggle(1'b0), .write_req_ack(1'b0), .SD_MISO(1'b1), .loading_status(status)
    );
    task state_is;
        input [3:0] expected;
        begin
            repeat (3) @(negedge clk);
            if (status[23:20] !== expected) $fatal(1, "Loading state got=%d expected=%d packet=%h", status[23:20], expected, status);
        end
    endtask
    initial begin
        repeat (5) @(negedge clk); rst = 0;
        force dut.sd_init_done = 0;
        state_is(1);
        repeat (2010) @(negedge clk); state_is(2);
        repeat (2050) @(negedge clk); state_is(2);
        force dut.sd_init_done = 1; state_is(0);
        enabled = 1;
        force dut.scan_complete = 0; state_is(3);
        force dut.scan_complete = 1;
        force dut.scanner_error = 8'h20; state_is(7);
        force dut.scanner_error = 8'h22;
        force dut.img_found_count = 0; state_is(6);
        force dut.img_found_count = 6;
        force dut.preload_done = 0;
        force dut.image_complete = 6'b001011;
        force dut.preload_attempted = 6'b001111;
        state_is(4);
        if (status[19:17] != 3 || status[16:14] != 6 || status[13:11] != 1)
            $fatal(1, "Loading success/total/failure counters wrong: %h", status);
        force dut.preload_done = 1; state_is(9);
        force dut.image_complete = 0; state_is(8);
        force dut.image_complete = 6'b111111;
        force dut.preload_attempted = 6'b111111;
        force dut.scanner_audio_valid = 0; state_is(10);
        force dut.scanner_audio_valid = 1;
        force dut.file_valid = 0;
        force dut.audio_mode = 1;
        force dut.file_done = 1;
        force dut.file_error = 8'h11; state_is(11);
        force dut.file_done = 0;
        force dut.file_error = 0;
        state_is(11);
        force dut.file_valid = 1; state_is(5);
        if (status[19:17] != 6 || status[13:11] != 0) $fatal(1, "Ready counters wrong");
        $display("LOADING TELEMETRY PASS: initialization timeout latch, scan errors, absent/failed/partial images, counts and audio-only error attribution");
        $finish;
    end
    initial begin #100000; $fatal(1, "Loading telemetry timeout"); end
endmodule
