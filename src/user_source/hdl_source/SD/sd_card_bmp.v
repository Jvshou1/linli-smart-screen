
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [15:0]  BMP_WIDTH          = 16'd640,
    parameter [15:0]  BMP_HEIGHT         = 16'd480,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd6,
    parameter integer SD_READ_TIMEOUT_MS = 500,
    parameter [1:0]   MAX_RETRIES        = 2'd1,
    parameter integer LONG_PRESS_MS     = 1000,
    parameter integer NOTICE_HOLD_MS    = 2000,
    parameter integer IDLE_RESUME_SECONDS = 30,
    parameter integer IMAGE0_DWELL_SECONDS = 5,
    parameter integer IMAGE1_DWELL_SECONDS = 10,
    parameter integer IMAGE2_DWELL_SECONDS = 15,
    parameter integer IMAGE3_DWELL_SECONDS = 8,
    parameter integer IMAGE4_DWELL_SECONDS = 10,
    parameter integer IMAGE5_DWELL_SECONDS = 10
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       key_menu,
    input      [3:0]            image_adjust_sw,
    input      [1:0]            auto_period_level,
    input                       start_enable,
    output reg                  config_volume_valid,
    output wire [2:0]           config_volume_level,
    output reg [3:0]            state_code,     // 复用端口：内容改为当前图片编号
    output reg                  display_valid,
    output wire [31:0]          debug_status,
    output wire [23:0]          storage_diagnostic,
    output wire                 auto_play_enabled,
    output wire [7:0]           playback_status,
    output wire [6:0]           guide_status,
    output reg [23:0]           loading_status,
    output reg                  store_closed,
    output reg                  thumbnail_mode,
    output reg [2:0]            thumbnail_focus_index,
    output wire [5:0]           image_complete_status,
    output reg [15:0]           image_width_0,
    output reg [15:0]           image_height_0,
    output reg [15:0]           image_width_1,
    output reg [15:0]           image_height_1,
    output reg [15:0]           image_width_2,
    output reg [15:0]           image_height_2,
    output reg [15:0]           image_width_3,
    output reg [15:0]           image_height_3,
    output reg [15:0]           image_width_4,
    output reg [15:0]           image_height_4,
    output reg [15:0]           image_width_5,
    output reg [15:0]           image_height_5,
    output wire [15:0]          write_image_width,
    output wire [15:0]          write_image_height,
    output wire [20:0]          write_image_pixels,

    output reg                  transition_request,
    output reg [2:0]            transition_target,
    input                       transition_commit,
    input                       transition_busy,

    input                       audio_fill_enable,
    output wire                 audio_pcm_valid,
    output wire [7:0]           audio_pcm_byte,
    output wire                 audio_stream_active,

    input                       write_finish_toggle,
    output reg [2:0]            write_buf_idx,
    output reg [2:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_next_release;
wire key_auto_press;
wire key_auto_release;
wire key_next_stable;
wire key_menu_stable;
wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             sd_init_done;
wire [4:0]       sd_controller_state;
wire [7:0]       sd_last_r1;
wire             bmp_ready;
wire             scan_done;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
reg  [2:0]       bmp_error;
reg              load_error;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_cluster;
reg [31:0]       load_file_size;
reg              scan_kicked;
reg              scan_complete;
reg              auto_play_en;
reg              config_autoplay_allowed;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [2:0]        img_idx;
reg [2:0]        load_idx;
reg [5:0]        image_complete;
reg [5:0]        preload_attempted;
reg              preload_done;
reg              next_req_pending;
reg              load_busy;
reg              preload_prepare;
reg              bmp_active_seen;
reg              write_finish_seen;
reg              load_error_seen;
reg [1:0]        retry_count;
reg [2:0]        last_bmp_error;
// === 新增：KEY2 长按检测相关寄存器 ===
wire             key_auto_stable;      // KEY2消抖后的稳定状态（1=松开，0=按下），由消抖模块驱动
reg [31:0]       long_press_cnt;       // 长按计数器
reg              long_press_marked;    // 长按已触发标记（防止按住不放重复触发）
reg              guide_active;
reg              guide_confirmed;
reg [1:0]        guide_category;
reg [2:0]        guide_return_idx;
reg              guide_return_auto;
reg [31:0]       chord_press_cnt;
reg              chord_press_marked;
wire             thumbnail_confirm_event;
reg [31:0]       notice_hold_count;
reg              notice_hold_marked;
reg              key_pair_seen;
reg              prev_pair_seen;
reg [31:0]       prev_pair_count;
reg              prev_pair_marked;
wire             prev_request_event;
wire notice_toggle_event = !key_next_stable && key_auto_stable &&
                           key_menu_stable && !key_pair_seen &&
                           !prev_pair_seen && !notice_hold_marked &&
                           (notice_hold_count >= (CLK_FREQ_HZ / 1000) * NOTICE_HOLD_MS - 1);
wire key_next_short_event = key_next_release && key_auto_stable &&
                            key_menu_stable && !notice_hold_marked &&
                            !key_pair_seen && !prev_pair_seen && !store_closed;
assign prev_request_event = !key_next_stable && !key_menu_stable &&
                            key_auto_stable && !prev_pair_marked &&
                            !store_closed && !thumbnail_mode && !guide_active &&
                            preload_done && display_valid &&
                            (resource_count(image_complete) > 3'd1) &&
                            !transition_busy &&
                            (prev_pair_count >= (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1);

// Independent of SD-card readiness: the built-in notice is always available.
// Consume the entire key gesture, including either release order of a chord.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        store_closed <= 1'b0;
        notice_hold_count <= 0;
        notice_hold_marked <= 1'b0;
        key_pair_seen <= 1'b0;
        prev_pair_seen <= 1'b0;
        prev_pair_count <= 32'd0;
        prev_pair_marked <= 1'b0;
    end else begin
        if (!key_next_stable && !key_auto_stable)
            key_pair_seen <= 1'b1;
        else if (key_next_stable && key_auto_stable &&
                 !key_next_release && !key_auto_release)
            key_pair_seen <= 1'b0;
        if (!key_next_stable && !key_menu_stable)
            prev_pair_seen <= 1'b1;
        else if (key_next_stable && key_menu_stable && !key_next_release)
            prev_pair_seen <= 1'b0;
        if (key_next_stable && key_menu_stable) begin
            prev_pair_count <= 32'd0;
            prev_pair_marked <= 1'b0;
        end else if (!key_next_stable && !key_menu_stable && key_auto_stable &&
                     !key_pair_seen && !prev_pair_marked &&
                     !store_closed && !thumbnail_mode && !guide_active &&
                     preload_done && display_valid &&
                     (resource_count(image_complete) > 3'd1)) begin
            if (!prev_request_event)
                if (prev_pair_count < (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)
                    prev_pair_count <= prev_pair_count + 1'b1;
        end else
            prev_pair_count <= 32'd0;
        if (prev_request_event)
            prev_pair_marked <= 1'b1;
        if (key_next_press)
            notice_hold_marked <= 1'b0;
        if (key_next_stable || !key_auto_stable || !key_menu_stable ||
            key_pair_seen || prev_pair_seen)
            notice_hold_count <= 0;
        else if (!notice_hold_marked && !notice_toggle_event)
            notice_hold_count <= notice_hold_count + 1'b1;
        if (notice_toggle_event) begin
            store_closed <= ~store_closed;
            notice_hold_marked <= 1'b1;
        end
    end
end

// bmp_ready 先表示“源文件读取/送 FIFO 完成”；真正切显示要等 write_finish_toggle 同步后
reg              source_done_seen;

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

wire auto_tick;
reg [31:0] auto_play_cycles;
reg [5:0] auto_play_seconds;
reg [5:0] playback_seconds_left;
reg [31:0] playback_second_count;
reg [1:0] auto_period_level_prev;
wire auto_period_changed = (auto_period_level != auto_period_level_prev);
wire [2:0] next_loaded_from_current;
wire [2:0] prev_loaded_from_current;
wire       preload_done_comb;
wire       load_complete_now;
wire       long_press_trigger;

// Inactivity is separate from image dwell: automatic picture changes must not
// postpone recovery, and a held button must never count as unattended use.
localparam integer IDLE_TICK_WIDTH = (CLK_FREQ_HZ > 1) ? $clog2(CLK_FREQ_HZ) : 1;
localparam integer IDLE_SECONDS_WIDTH = (IDLE_RESUME_SECONDS > 0) ?
                                        $clog2(IDLE_RESUME_SECONDS + 1) : 1;
(* async_reg = "true" *) reg [6:0] user_controls_meta;
(* async_reg = "true" *) reg [6:0] user_controls_sync;
reg [6:0] user_controls_prev;
reg [IDLE_TICK_WIDTH-1:0] idle_second_count;
reg [IDLE_SECONDS_WIDTH-1:0] idle_seconds;
wire user_activity = (user_controls_sync[2:0] != 3'b111) ||
                     (user_controls_sync != user_controls_prev) ||
                     !key_next_stable || !key_auto_stable ||
                     key_next_press || key_auto_press || key_auto_release ||
                     auto_period_changed;
wire idle_armed = config_autoplay_allowed && !store_closed &&
                  !notice_toggle_event && !guide_active &&
                  (IDLE_RESUME_SECONDS > 0) && sd_init_done &&
                  scan_complete && preload_done && display_valid &&
                  (resource_count(image_complete) > 3'd1) &&
                  (thumbnail_mode || !auto_play_en);
wire idle_expired = (idle_seconds >= IDLE_RESUME_SECONDS) ||
                    ((idle_seconds == IDLE_RESUME_SECONDS - 1) &&
                     (idle_second_count == CLK_FREQ_HZ - 1));
wire idle_resume_event = idle_armed && !user_activity && idle_expired &&
                         !transition_busy && !transition_commit &&
                         !transition_request;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        user_controls_meta <= 7'b0000111;
        user_controls_sync <= 7'b0000111;
        user_controls_prev <= 7'b0000111;
        idle_second_count <= 0;
        idle_seconds <= 0;
    end else begin
        user_controls_meta <= {image_adjust_sw, key_menu, key_auto, key_next};
        user_controls_sync <= user_controls_meta;
        user_controls_prev <= user_controls_sync;
        if (!idle_armed || user_activity) begin
            idle_second_count <= 0;
            idle_seconds <= 0;
        end else if (idle_seconds < IDLE_RESUME_SECONDS) begin
            if (idle_second_count == CLK_FREQ_HZ - 1) begin
                idle_second_count <= 0;
                idle_seconds <= idle_seconds + 1'b1;
            end else begin
                idle_second_count <= idle_second_count + 1'b1;
            end
        end
    end
end

// FAT32 volume scanner results.
wire             scanner_busy;
wire             scanner_done;
wire [7:0]       scanner_error;
wire [7:0]       scanner_spc;
wire [31:0]      scanner_fat_start;
wire [31:0]      scanner_data_start;
wire [31:0]      scanner_max_cluster;
wire [5:0]       scanner_resource_valid;
wire [2:0]       layout_buf_idx = scanner_resource_valid[0] ? 3'd1 : 3'd0;
wire             layout_ready = scanner_resource_valid[1] &&
                                image_complete[layout_buf_idx];
wire [31:0]      scanner_cluster0;
wire [31:0]      scanner_cluster1;
wire [31:0]      scanner_cluster2;
wire [31:0]      scanner_cluster3;
wire [31:0]      scanner_cluster4;
wire [31:0]      scanner_cluster5;
wire [31:0]      scanner_size0;
wire [31:0]      scanner_size1;
wire [31:0]      scanner_size2;
wire [31:0]      scanner_size3;
wire [31:0]      scanner_size4;
wire [31:0]      scanner_size5;
wire             scanner_audio_valid;
wire [31:0]      scanner_audio_cluster;
wire [31:0]      scanner_audio_size;
wire             scanner_config_valid;
wire [31:0]      scanner_config_cluster;
wire [31:0]      scanner_config_size;

// Shared sector interface and fixed-priority phase arbitration.
wire             scanner_sector_req;
wire [31:0]      scanner_sector_lba;
wire             streamer_sector_req;
wire [31:0]      streamer_sector_lba;
wire             arb_sector_req;
wire [31:0]      arb_sector_lba;
wire             arb_sector_busy;
wire             arb_sector_valid;
wire [7:0]       arb_sector_byte;
wire [8:0]       arb_sector_byte_index;
wire             arb_sector_done;
wire [7:0]       arb_sector_error;

// FAT-chain file streamer.
reg              bmp_file_start_pulse;
reg              audio_file_start_pulse;
reg              config_file_start_pulse;
reg              config_mode;
reg              config_done;
reg              config_applied;
reg              config_apply_pending;
wire             parsed_autoplay_present;
wire [5:0]       config_dwell0, config_dwell1, config_dwell2;
wire [5:0]       config_dwell3, config_dwell4, config_dwell5;
wire [2:0]       parsed_volume_level;
wire             parsed_autoplay;
wire             file_start_pulse;
wire             file_busy;
wire             file_done;
wire             file_valid;
wire [7:0]       file_byte;
wire [31:0]      file_byte_offset;
wire [7:0]       file_error;
reg              audio_mode;

// Compact diagnostic for the board seven-segment display:
// controller state, last SD R1 response, and scanner/file error.
assign storage_diagnostic = {3'd0, sd_controller_state, sd_last_r1,
                             (scanner_error != 0 ? scanner_error : file_error)};

// BMP byte-stream decoder.
localparam [1:0] RD_IDLE       = 2'd0;
localparam [1:0] RD_WRITE_WAIT = 2'd1;
localparam [1:0] RD_STREAM     = 2'd2;
localparam [1:0] RD_FILL       = 2'd3;
reg [1:0]        reader_state;
reg              write_req_reg;
reg              bmp_data_wr_en_reg;
reg [23:0]       bmp_data_reg;
reg [31:0]       reader_timeout;
reg [7:0]        magic0;
reg [7:0]        magic1;
reg [31:0]       header_file_size;
reg [31:0]       pixel_offset;
reg [31:0]       dib_header_size;
reg [31:0]       bmp_width_read;
reg [31:0]       bmp_height_read;
reg [15:0]       bmp_planes;
reg [15:0]       bmp_bpp;
reg [31:0]       bmp_compression;
reg [1:0]        pixel_byte_phase;
reg              pixel_data_active;
reg [7:0]        pixel_b;
reg [7:0]        pixel_g;
reg [31:0]       pixel_count;
reg [31:0]       source_x_count;
reg [31:0]       source_row_count;
reg [31:0]       x_scale_accum;
reg [31:0]       y_scale_accum;
reg [1:0]        row_padding_remaining;
reg              parser_error;

// Retry the complete card initialization sequence after a transient socket,
// power-up, or FPGA-reconfiguration failure instead of remaining on yellow.
localparam integer SD_INIT_RETRY_CYCLES = CLK_FREQ_HZ * 2;
localparam integer SD_RESET_HOLD_CYCLES = CLK_FREQ_HZ / 1000;
reg [31:0]       sd_init_retry_count;
reg              sd_init_retry_reset;
wire             sd_controller_rst;

wire [31:0] expected_pixels;
reg  [15:0] stored_width;
reg  [15:0] stored_height;
reg  [31:0] stored_pixels;
reg  [31:0] source_row_bytes;
reg  [31:0] source_row_stride;
reg  [31:0] source_pixel_bytes;
reg  [32:0] pixel_end_wide;
wire        bmp_header_valid;
wire        select_source_x;
wire        select_source_row;

// === 修复：加载看门狗，避免 load_busy 卡死导致按键无响应 ===
reg  [31:0] load_watchdog;
localparam integer LOAD_TIMEOUT_MS = 15000;  // Allow multi-megabyte source BMP files.
wire [31:0] LOAD_TIMEOUT_CYCLES = (CLK_FREQ_HZ / 1000) * LOAD_TIMEOUT_MS;

assign write_req  = write_req_reg;
assign write_en   = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};
assign bmp_data_wr_en = bmp_data_wr_en_reg;
assign bmp_data       = bmp_data_reg;
assign bmp_ready      = (reader_state == RD_IDLE) && !file_busy;
assign scan_done      = scan_complete;
assign auto_play_enabled = auto_play_en;
assign image_complete_status = image_complete;
assign write_image_width = stored_width;
assign write_image_height = stored_height;
assign write_image_pixels = stored_pixels[20:0];
assign file_start_pulse = bmp_file_start_pulse | audio_file_start_pulse |
                          config_file_start_pulse;
assign config_volume_level = parsed_volume_level;
assign audio_pcm_valid = audio_mode && file_valid;
assign audio_pcm_byte = file_byte;
assign audio_stream_active = audio_mode;

tf_config_parser #(
    .DWELL0(IMAGE0_DWELL_SECONDS), .DWELL1(IMAGE1_DWELL_SECONDS),
    .DWELL2(IMAGE2_DWELL_SECONDS), .DWELL3(IMAGE3_DWELL_SECONDS),
    .DWELL4(IMAGE4_DWELL_SECONDS), .DWELL5(IMAGE5_DWELL_SECONDS)
) u_tf_config_parser (
    .clk(clk), .rst(rst), .start(config_file_start_pulse),
    .valid(config_mode && file_valid), .done(config_mode && file_done),
    .byte_in(file_byte),
    .dwell0(config_dwell0), .dwell1(config_dwell1),
    .dwell2(config_dwell2), .dwell3(config_dwell3),
    .dwell4(config_dwell4), .dwell5(config_dwell5),
    .volume_level(parsed_volume_level), .autoplay(parsed_autoplay),
    .autoplay_present(parsed_autoplay_present)
);

// Display-only telemetry. Never stalls or gates image/audio file streaming.
reg init_wait_expired;
reg [7:0] audio_error_code;
reg [3:0] loading_state;
wire [2:0] loaded_count = resource_count(image_complete);
wire [2:0] failed_count = resource_count(preload_attempted & ~image_complete);
always @(*) begin
    if (!sd_init_done) loading_state = init_wait_expired ? 4'd2 : 4'd1;
    else if (!start_enable) loading_state = 4'd0;
    else if (!scan_complete) loading_state = 4'd3;
    else if (scanner_error != 0 && scanner_error != 8'h22) loading_state = 4'd7;
    else if (img_found_count == 0) loading_state = 4'd6;
    else if (!preload_done) loading_state = 4'd4;
    else if (loaded_count == 0) loading_state = 4'd8;
    else if (failed_count != 0) loading_state = 4'd9;
    else if (!scanner_audio_valid) loading_state = 4'd10;
    else if (audio_error_code != 0) loading_state = 4'd11;
    else loading_state = 4'd5;
end
always @(posedge clk or posedge rst) begin
    if (rst) begin
        init_wait_expired <= 0;
        audio_error_code <= 0;
        loading_status <= 24'h100000;
    end else begin
        if (sd_init_done) init_wait_expired <= 0;
        else if (sd_init_retry_count >= SD_INIT_RETRY_CYCLES - 1)
            init_wait_expired <= 1;
        if (!sd_init_done) audio_error_code <= 0;
        else if (audio_mode && file_done && file_error != 0)
            audio_error_code <= file_error;
        else if (audio_mode && file_valid) audio_error_code <= 0;
        loading_status <= {loading_state, loaded_count, img_found_count,
                           failed_count, (load_idx + 3'd1),
                           (audio_error_code != 0 ? audio_error_code : scanner_error)};
    end
end
assign sd_controller_rst = rst | sd_init_retry_reset;
assign debug_status   = {
    scanner_error,
    file_error,
    {1'b0, resource_count(scanner_resource_valid)},
    last_bmp_error,
    reader_state,
    load_error,
    load_busy,
    scan_complete,
    scanner_busy,
    scan_kicked,
    sd_init_done,
    start_enable
};

assign expected_pixels     = {16'd0, BMP_WIDTH} * {16'd0, BMP_HEIGHT};
assign select_source_x = ((x_scale_accum + {16'd0, stored_width}) >=
                          bmp_width_read);
assign select_source_row = ((y_scale_accum + {16'd0, stored_height}) >=
                            bmp_height_read);
assign bmp_header_valid = (magic0 == "B") && (magic1 == "M") &&
                          (dib_header_size >= 32'd40) &&
                          (bmp_width_read != 32'd0) &&
                          (bmp_width_read[31:16] == 16'd0) &&
                          (bmp_width_read <= 32'd4096) &&
                          (bmp_height_read != 32'd0) &&
                          !bmp_height_read[31] &&
                          (bmp_height_read[30:16] == 15'd0) &&
                          (bmp_height_read <= 32'd4096) &&
                          (bmp_planes == 16'd1) && (bmp_bpp == 16'd24) &&
                          (bmp_compression == 32'd0) &&
                          (pixel_offset >= 32'd54) && !pixel_end_wide[32] &&
                          (pixel_end_wide[31:0] <= load_file_size) &&
                          ((header_file_size == 0) ||
                           (pixel_end_wide[31:0] <= header_file_size));

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sd_init_retry_count <= 32'd0;
        sd_init_retry_reset <= 1'b0;
    end else if (sd_init_done) begin
        sd_init_retry_count <= 32'd0;
        sd_init_retry_reset <= 1'b0;
    end else if (sd_init_retry_reset) begin
        if (sd_init_retry_count >= SD_RESET_HOLD_CYCLES - 1) begin
            sd_init_retry_count <= 32'd0;
            sd_init_retry_reset <= 1'b0;
        end else begin
            sd_init_retry_count <= sd_init_retry_count + 1'b1;
        end
    end else if (sd_init_retry_count >= SD_INIT_RETRY_CYCLES - 1) begin
        sd_init_retry_count <= 32'd0;
        sd_init_retry_reset <= 1'b1;
    end else begin
        sd_init_retry_count <= sd_init_retry_count + 1'b1;
    end
end

assign arb_sector_req = scan_complete ? streamer_sector_req : scanner_sector_req;
assign arb_sector_lba = scan_complete ? streamer_sector_lba : scanner_sector_lba;
// KEY3 selects 2/5/10 seconds or per-image dwell (level 3, the default).
// Per-image timing follows the displayed cache bank, never the selection cursor.
// Configured seconds use the existing one-second counter; no run-time
// 100 MHz multiplier is needed in the loaded-file path.
always @(*) begin
    case (auto_period_level)
        2'd0: begin
            auto_play_cycles = (CLK_FREQ_HZ / 1000) * 32'd2000;
            auto_play_seconds = 6'd2;
        end
        2'd1: begin
            auto_play_cycles = (CLK_FREQ_HZ / 1000) * 32'd5000;
            auto_play_seconds = 6'd5;
        end
        2'd2: begin
            auto_play_cycles = (CLK_FREQ_HZ / 1000) * 32'd10000;
            auto_play_seconds = 6'd10;
        end
        default: begin
            auto_play_cycles = 32'd0;
            case (disp_buf_idx)
                3'd0: begin
                    auto_play_seconds = config_applied ? config_dwell0 : IMAGE0_DWELL_SECONDS;
                end
                3'd1: begin
                    auto_play_seconds = config_applied ? config_dwell1 : IMAGE1_DWELL_SECONDS;
                end
                3'd2: begin
                    auto_play_seconds = config_applied ? config_dwell2 : IMAGE2_DWELL_SECONDS;
                end
                3'd3: begin
                    auto_play_seconds = config_applied ? config_dwell3 : IMAGE3_DWELL_SECONDS;
                end
                3'd4: begin
                    auto_play_seconds = config_applied ? config_dwell4 : IMAGE4_DWELL_SECONDS;
                end
                default: begin
                    auto_play_seconds = config_applied ? config_dwell5 : IMAGE5_DWELL_SECONDS;
                end
            endcase
        end
    endcase
end
// Restart a full dwell when KEY3 changes the timing mode; shortening an
// interval must not immediately advance the picture on the same clock.
always @(posedge clk or posedge rst) begin
    if (rst)
        auto_period_level_prev <= 2'd3;
    else
        auto_period_level_prev <= auto_period_level;
end
assign auto_tick = !auto_period_changed &&
                   ((auto_period_level == 2'd3) ?
                    (auto_cnt != 0 && playback_seconds_left == 6'd1 &&
                     playback_second_count >= CLK_FREQ_HZ - 2) :
                    (auto_cnt >= (auto_play_cycles - 1'b1)));

// Observe the existing timer, including all its reset paths (manual selection,
// timing-mode changes, pause and transitions). No wide division is needed.
// The display trails the timer by one SD clock, invisible at frame cadence.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        playback_seconds_left <= 6'd0;
        playback_second_count <= 32'd0;
    end else if ((auto_cnt == 0) || auto_period_changed || !display_valid) begin
        playback_seconds_left <= auto_play_seconds;
        playback_second_count <= 32'd0;
    end else if (playback_second_count >= CLK_FREQ_HZ - 1) begin
        playback_second_count <= 32'd0;
        if (playback_seconds_left != 0)
            playback_seconds_left <= playback_seconds_left - 1'b1;
    end else begin
        playback_second_count <= playback_second_count + 1'b1;
    end
end

// Atomic status packet: WAIT=0, NEXT=1, PAUSED=2, SELECT=3; seconds in [5:0].
assign playback_status = {(!preload_done || !display_valid) ? 2'd0 :
                          guide_active ? 2'd3 :
                          (resource_count(image_complete) < 2) ? 2'd0 :
                          thumbnail_mode ? 2'd3 :
                          auto_play_en ? 2'd1 : 2'd2,
                          playback_seconds_left};
assign guide_status = {guide_active, guide_confirmed,
                       guide_category, layout_buf_idx};
assign next_loaded_from_current = next_loaded_index(img_idx, image_complete);
assign prev_loaded_from_current = prev_loaded_index(img_idx, image_complete);
assign preload_done_comb = all_preloads_attempted(img_found_count,
                                                   preload_attempted);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
assign load_complete_now = load_busy && !load_error &&
                           (source_done_seen || (bmp_active_seen && bmp_ready)) &&
                           (write_finish_seen || write_finish_pulse);
assign long_press_trigger = (key_auto_stable == 1'b0) &&
                            (key_next_stable == 1'b1) &&
                            key_menu_stable && !key_pair_seen &&
                            !prev_pair_seen && !store_closed &&
                            (long_press_cnt >= ((CLK_FREQ_HZ / 1000) *
                                               LONG_PRESS_MS - 1)) &&
                            !long_press_marked;

// In thumbnail mode a short KEY2 press confirms on release. Wait for release
// so the KEY1+KEY2 long-press chord cannot also confirm an image. Consume the
// release while still in thumbnail mode so it cannot toggle autoplay.
assign thumbnail_confirm_event = !store_closed && !key_pair_seen &&
                                 !prev_pair_seen && key_menu_stable &&
                                 thumbnail_mode && key_auto_release &&
                                 key_next_stable && !long_press_marked &&
                                 !chord_press_marked &&
                                 image_complete[thumbnail_focus_index] &&
                                 !transition_busy;

// Holding both keys toggles the thumbnail/full-screen mode without consuming
// either key's normal short-press action.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        thumbnail_mode    <= 1'b0;
        chord_press_cnt   <= 32'd0;
        chord_press_marked <= 1'b0;
    end else if (store_closed || notice_toggle_event || idle_resume_event ||
                 thumbnail_confirm_event || guide_active) begin
        thumbnail_mode <= 1'b0;
        chord_press_cnt <= 32'd0;
    end else if (!key_next_stable && !key_auto_stable && key_menu_stable &&
                 !prev_pair_seen) begin
        if (chord_press_cnt < ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)) begin
            chord_press_cnt <= chord_press_cnt + 32'd1;
        end else if (!chord_press_marked) begin
            thumbnail_mode     <= ~thumbnail_mode;
            chord_press_marked <= 1'b1;
        end
    end else if (key_next_stable && key_auto_stable) begin
        chord_press_cnt    <= 32'd0;
        chord_press_marked <= 1'b0;
    end
end

// Register the preload summary before it fans out to navigation and the
// 32-bit autoplay counter. The one-cycle latency is immaterial after preload.
always @(posedge clk or posedge rst) begin
    if (rst)
        preload_done <= 1'b0;
    else if (!sd_init_done || !scan_complete)
        preload_done <= 1'b0;
    else
        preload_done <= preload_done_comb;
end

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse      (key_next_press),
    .release_pulse    (key_next_release),
    .button_stable_out(key_next_stable)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_auto (
    .clk              (clk),
    .rst              (rst),
    .button_in        (key_auto),
    .press_pulse      (key_auto_press),
    .release_pulse    (key_auto_release),
    .button_stable_out(key_auto_stable)   // 新增：连接消抖后的稳定状态
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (20)
) u_key_menu (
    .clk              (clk),
    .rst              (rst),
    .button_in        (key_menu),
    .press_pulse      (),
    .release_pulse    (),
    .button_stable_out(key_menu_stable)
);

function [2:0] next_loaded_index;
    input [2:0] cur;
    input [5:0] complete;
    integer step;
    reg found;
    reg [3:0] sum;
    reg [2:0] candidate;
    begin
        next_loaded_index = cur;
        found = 1'b0;
        for (step = 1; step <= 6; step = step + 1) begin
            sum = {1'b0, cur} + step;
            candidate = (sum >= 4'd6) ? sum - 4'd6 : sum;
            if (!found && complete[candidate]) begin
                next_loaded_index = candidate;
                found = 1'b1;
            end
        end
    end
endfunction

function [2:0] prev_loaded_index;
    input [2:0] cur;
    input [5:0] complete;
    integer step;
    reg found;
    reg [2:0] candidate;
    begin
        prev_loaded_index = cur;
        found = 1'b0;
        for (step = 1; step <= 6; step = step + 1) begin
            candidate = (cur >= step) ? cur - step : cur + 6 - step;
            if (!found && complete[candidate]) begin
                prev_loaded_index = candidate;
                found = 1'b1;
            end
        end
    end
endfunction

function [2:0] resource_count;
    input [5:0] valid_mask;
    begin
        resource_count = valid_mask[0] + valid_mask[1]
                       + valid_mask[2] + valid_mask[3]
                       + valid_mask[4] + valid_mask[5];
    end
endfunction

function [2:0] resource_index_for_slot;
    input [2:0] slot;
    input [5:0] valid_mask;
    integer i;
    integer seen;
    begin
        resource_index_for_slot = 3'd0;
        seen = 0;
        for (i = 0; i < 6; i = i + 1) begin
            if (valid_mask[i]) begin
                if (seen == slot)
                    resource_index_for_slot = i[2:0];
                seen = seen + 1;
            end
        end
    end
endfunction

function [31:0] cluster_lut;
    input [2:0] idx;
    reg [2:0] resource_idx;
    begin
        resource_idx = resource_index_for_slot(idx, scanner_resource_valid);
        case (resource_idx)
            3'd0: cluster_lut = scanner_cluster0;
            3'd1: cluster_lut = scanner_cluster1;
            3'd2: cluster_lut = scanner_cluster2;
            3'd3: cluster_lut = scanner_cluster3;
            3'd4: cluster_lut = scanner_cluster4;
            default: cluster_lut = scanner_cluster5;
        endcase
    end
endfunction

function [31:0] size_lut;
    input [2:0] idx;
    reg [2:0] resource_idx;
    begin
        resource_idx = resource_index_for_slot(idx, scanner_resource_valid);
        case (resource_idx)
            3'd0: size_lut = scanner_size0;
            3'd1: size_lut = scanner_size1;
            3'd2: size_lut = scanner_size2;
            3'd3: size_lut = scanner_size3;
            3'd4: size_lut = scanner_size4;
            default: size_lut = scanner_size5;
        endcase
    end
endfunction

function [2:0] first_unattempted_slot;
    input [2:0] count;
    input [5:0] attempted;
    integer i;
    reg found;
    begin
        first_unattempted_slot = 3'd0;
        found = 1'b0;
        for (i = 0; i < 6; i = i + 1) begin
            if (!found && (i < count) && !attempted[i]) begin
                first_unattempted_slot = i[2:0];
                found = 1'b1;
            end
        end
    end
endfunction

function all_preloads_attempted;
    input [2:0] count;
    input [5:0] attempted;
    begin
        case (count)
            3'd0: all_preloads_attempted = 1'b1;
            3'd1: all_preloads_attempted = attempted[0];
            3'd2: all_preloads_attempted = &attempted[1:0];
            3'd3: all_preloads_attempted = &attempted[2:0];
            3'd4: all_preloads_attempted = &attempted[3:0];
            3'd5: all_preloads_attempted = &attempted[4:0];
            default: all_preloads_attempted = &attempted;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_cluster          <= 32'd0;
        load_file_size        <= 32'd0;
        scan_kicked           <= 1'b0;
        scan_complete         <= 1'b0;
        auto_play_en          <= 1'b0;
        config_autoplay_allowed <= 1'b1;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 3'd0;
        load_idx              <= 3'd0;
        image_complete        <= 6'd0;
        image_width_0         <= BMP_WIDTH;
        image_height_0        <= BMP_HEIGHT;
        image_width_1         <= BMP_WIDTH;
        image_height_1        <= BMP_HEIGHT;
        image_width_2         <= BMP_WIDTH;
        image_height_2        <= BMP_HEIGHT;
        image_width_3         <= BMP_WIDTH;
        image_height_3        <= BMP_HEIGHT;
        image_width_4         <= BMP_WIDTH;
        image_height_4        <= BMP_HEIGHT;
        image_width_5         <= BMP_WIDTH;
        image_height_5        <= BMP_HEIGHT;
        preload_attempted     <= 6'd0;
        write_buf_idx         <= 3'd0;
        disp_buf_idx          <= 3'd0;
        thumbnail_focus_index <= 3'd0;
        next_req_pending      <= 1'b0;
        load_busy             <= 1'b0;
        preload_prepare       <= 1'b0;
        bmp_active_seen       <= 1'b0;
        write_finish_seen     <= 1'b0;
        load_error_seen       <= 1'b0;
        retry_count           <= 2'd0;
        last_bmp_error        <= 3'd0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
        long_press_cnt        <= 32'd0;
        long_press_marked     <= 1'b0;
        guide_active          <= 1'b0;
        guide_confirmed       <= 1'b0;
        guide_category        <= 2'd0;
        guide_return_idx      <= 3'd0;
        guide_return_auto     <= 1'b0;
        transition_request    <= 1'b0;
        transition_target     <= 3'd0;
        audio_file_start_pulse <= 1'b0;
        audio_mode            <= 1'b0;
        config_file_start_pulse <= 1'b0;
        config_mode           <= 1'b0;
        config_done           <= 1'b0;
        config_applied        <= 1'b0;
        config_apply_pending  <= 1'b0;
        config_volume_valid   <= 1'b0;
        load_watchdog         <= 32'd0;
        state_code            <= 4'd1;
    end else begin
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;
        transition_request <= 1'b0;
        audio_file_start_pulse <= 1'b0;
        config_file_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            scan_complete         <= 1'b0;
            auto_play_en          <= 1'b0;
            config_autoplay_allowed <= 1'b1;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 3'd0;
            load_idx              <= 3'd0;
            image_complete        <= 6'd0;
            image_width_0         <= BMP_WIDTH;
            image_height_0        <= BMP_HEIGHT;
            image_width_1         <= BMP_WIDTH;
            image_height_1        <= BMP_HEIGHT;
            image_width_2         <= BMP_WIDTH;
            image_height_2        <= BMP_HEIGHT;
            image_width_3         <= BMP_WIDTH;
            image_height_3        <= BMP_HEIGHT;
            image_width_4         <= BMP_WIDTH;
            image_height_4        <= BMP_HEIGHT;
            image_width_5         <= BMP_WIDTH;
            image_height_5        <= BMP_HEIGHT;
            preload_attempted     <= 6'd0;
            write_buf_idx         <= 3'd0;
            disp_buf_idx          <= 3'd0;
            next_req_pending      <= 1'b0;
            load_busy             <= 1'b0;
            preload_prepare       <= 1'b0;
            bmp_active_seen       <= 1'b0;
            write_finish_seen     <= 1'b0;
            load_error_seen       <= 1'b0;
            retry_count           <= 2'd0;
            last_bmp_error        <= 3'd0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
            long_press_cnt        <= 32'd0;
            long_press_marked     <= 1'b0;
            guide_active          <= 1'b0;
            guide_confirmed       <= 1'b0;
            guide_category        <= 2'd0;
            guide_return_idx      <= 3'd0;
            guide_return_auto     <= 1'b0;
            transition_target     <= 3'd0;
            audio_mode            <= 1'b0;
            config_mode           <= 1'b0;
            config_done           <= 1'b0;
            config_applied        <= 1'b0;
            config_apply_pending  <= 1'b0;
            config_volume_valid   <= 1'b0;
            load_watchdog         <= 32'd0;
        end else begin
            // FAT32 scan results stay latched in the scanner; expose them as a
            // compact list so missing PIC numbers do not break navigation.
            if (scanner_done) begin
                scan_complete   <= 1'b1;
                img_found_count <= resource_count(scanner_resource_valid);
                config_done     <= !scanner_config_valid;
                if (scanner_config_valid) begin
                    load_cluster           <= scanner_config_cluster;
                    load_file_size         <= scanner_config_size;
                    config_file_start_pulse <= 1'b1;
                    config_mode            <= 1'b1;
                end
                if (scanner_resource_valid == 6'd0)
                    last_bmp_error <= 3'd4;
            end

            if (config_mode && file_done) begin
                config_mode <= 1'b0;
                if (file_error == 8'd0)
                    config_apply_pending <= 1'b1;
                else
                    config_done <= 1'b1;
            end
            if (config_apply_pending) begin
                config_apply_pending <= 1'b0;
                config_done <= 1'b1;
                config_applied <= 1'b1;
                config_volume_valid <= 1'b1;
                if (parsed_autoplay_present) begin
                    config_autoplay_allowed <= parsed_autoplay;
                    auto_play_en <= parsed_autoplay;
                end
            end

            if (!load_error)
                load_error_seen <= 1'b0;
            if (bmp_error != 3'd0)
                last_bmp_error <= bmp_error;

            // ready 只有在解码器确实进入过忙态后，才可解释为“源数据完成”。
            if (load_busy && !bmp_ready)
                bmp_active_seen <= 1'b1;
            if (load_busy && bmp_active_seen && bmp_ready && !load_error)
                source_done_seen <= 1'b1;
            if (load_busy && write_finish_pulse)
                write_finish_seen <= 1'b1;

            // Each resource is written once to its permanent bank. The first
            // completed image becomes visible while remaining banks preload.
            if (load_complete_now) begin
                load_busy             <= 1'b0;
                bmp_active_seen       <= 1'b0;
                write_finish_seen     <= 1'b0;
                source_done_seen      <= 1'b0;
                retry_count           <= 2'd0;
                last_bmp_error        <= 3'd0;
                load_watchdog         <= 32'd0;
                image_complete[load_idx]    <= 1'b1;
                preload_attempted[load_idx] <= 1'b1;
                case (load_idx)
                    3'd0: begin
                        image_width_0  <= stored_width;
                        image_height_0 <= stored_height;
                    end
                    3'd1: begin
                        image_width_1  <= stored_width;
                        image_height_1 <= stored_height;
                    end
                    3'd2: begin
                        image_width_2  <= stored_width;
                        image_height_2 <= stored_height;
                    end
                    3'd3: begin
                        image_width_3  <= stored_width;
                        image_height_3 <= stored_height;
                    end
                    3'd4: begin
                        image_width_4  <= stored_width;
                        image_height_4 <= stored_height;
                    end
                    default: begin
                        image_width_5  <= stored_width;
                        image_height_5 <= stored_height;
                    end
                endcase
                if (!display_valid) begin
                    disp_buf_idx  <= load_idx;
                    img_idx       <= load_idx;
                    display_valid <= 1'b1;
                end
            end

            if (!load_busy)
                load_watchdog <= 32'd0;
            else if (load_watchdog < LOAD_TIMEOUT_CYCLES)
                load_watchdog <= load_watchdog + 32'd1;

            // Retry a failed preload, then leave that bank unavailable and
            // continue with the remaining resources.
            if (load_busy && load_error && !load_error_seen) begin
                load_error_seen   <= 1'b1;
                bmp_active_seen   <= 1'b0;
                write_finish_seen <= 1'b0;
                source_done_seen  <= 1'b0;
                load_watchdog     <= 32'd0;

                if (retry_count < MAX_RETRIES) begin
                    retry_count     <= retry_count + 2'd1;
                    load_start_pulse <= 1'b1;
                end else begin
                    load_busy                   <= 1'b0;
                    retry_count                 <= 2'd0;
                    preload_attempted[load_idx] <= 1'b1;
                end
            end else begin
                // 系统级看门狗覆盖解码器之外的故障，例如 SDRAM 帧完成信号丢失。
                if (load_busy && (load_watchdog >= LOAD_TIMEOUT_CYCLES) &&
                    !load_complete_now) begin
                    load_busy           <= 1'b0;
                    bmp_active_seen     <= 1'b0;
                    write_finish_seen   <= 1'b0;
                    source_done_seen    <= 1'b0;
                    retry_count         <= 2'd0;
                    load_watchdog       <= 32'd0;
                    last_bmp_error      <= 3'd2;
                    preload_attempted[load_idx] <= 1'b1;
                end

                // Start FAT32 discovery only after both SD and SDRAM are ready.
                if (!scan_kicked && start_enable && sd_init_done) begin
                    scan_start_pulse      <= 1'b1;
                    scan_kicked           <= 1'b1;
                    scan_complete         <= 1'b0;
                    auto_play_en          <= 1'b0;
                    config_autoplay_allowed <= 1'b1;
                    auto_cnt              <= 32'd0;
                    img_found_count       <= 3'd0;
                    img_idx               <= 3'd0;
                    load_idx              <= 3'd0;
                    image_complete        <= 6'd0;
                    image_width_0         <= BMP_WIDTH;
                    image_height_0        <= BMP_HEIGHT;
                    image_width_1         <= BMP_WIDTH;
                    image_height_1        <= BMP_HEIGHT;
                    image_width_2         <= BMP_WIDTH;
                    image_height_2        <= BMP_HEIGHT;
                    image_width_3         <= BMP_WIDTH;
                    image_height_3        <= BMP_HEIGHT;
                    image_width_4         <= BMP_WIDTH;
                    image_height_4        <= BMP_HEIGHT;
                    image_width_5         <= BMP_WIDTH;
                    image_height_5        <= BMP_HEIGHT;
                    preload_attempted     <= 6'd0;
                    write_buf_idx         <= 3'd0;
                    disp_buf_idx          <= 3'd0;
                    thumbnail_focus_index <= 3'd0;
                    next_req_pending      <= 1'b0;
                    display_valid         <= 1'b0;
                    load_busy             <= 1'b0;
                    preload_prepare       <= 1'b0;
                    bmp_active_seen       <= 1'b0;
                    write_finish_seen     <= 1'b0;
                    source_done_seen      <= 1'b0;
                    retry_count           <= 2'd0;
                    last_bmp_error        <= 3'd0;
                    long_press_cnt        <= 32'd0;
                    long_press_marked     <= 1'b0;
                    guide_active          <= 1'b0;
                    guide_confirmed       <= 1'b0;
                    guide_category        <= 2'd0;
                    guide_return_idx      <= 3'd0;
                    guide_return_auto     <= 1'b0;
                    audio_mode            <= 1'b0;
                    config_mode           <= 1'b0;
                    config_done           <= 1'b0;
                    config_applied        <= 1'b0;
                    config_apply_pending  <= 1'b0;
                    config_volume_valid   <= 1'b0;
                end else begin
                    if (transition_commit) begin
                        img_idx      <= transition_target;
                        disp_buf_idx <= transition_target;
                        auto_cnt     <= 32'd0;
                    end

                    // Navigation changes only the displayed bank. It is
                    // enabled once all resources have either loaded or failed.
                    // In thumbnail mode KEY1 advances focus with wraparound;
                    // KEY2 confirms on release and never moves the focus.
                    if (guide_active) begin
                        if (key_next_short_event && key_auto_stable) begin
                            guide_category <= guide_category + 2'd1;
                            guide_confirmed <= 1'b0;
                        end
                    end else if (thumbnail_mode) begin
                        if (key_next_short_event && key_auto_stable &&
                            !chord_press_marked && (img_found_count != 3'd0))
                            thumbnail_focus_index <= (thumbnail_focus_index + 1'b1 >= img_found_count) ?
                                                     3'd0 : thumbnail_focus_index + 1'b1;
                    end else if (key_next_short_event && key_auto_stable && preload_done &&
                                 display_valid &&
                                 (resource_count(image_complete) > 3'd1))
                        next_req_pending <= 1'b1;

                    if (!store_closed && !key_pair_seen && !prev_pair_seen &&
                        key_menu_stable && key_auto_release &&
                        key_next_stable && !long_press_marked && !chord_press_marked &&
                        preload_done) begin
                        if (guide_active && layout_ready && !transition_busy) begin
                            guide_confirmed <= 1'b1;
                            img_idx <= layout_buf_idx;
                            disp_buf_idx <= layout_buf_idx;
                            auto_cnt <= 32'd0;
                        end else if (!guide_active && !thumbnail_mode &&
                                     (resource_count(image_complete) > 3'd1)) begin
                            auto_play_en <= ~auto_play_en;
                            auto_cnt <= 32'd0;
                        end
                    end

                    if (key_auto_stable == 1'b0) begin
                        if (long_press_cnt < ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS - 1)) begin
                            long_press_cnt <= long_press_cnt + 32'd1;
                        end else if (!long_press_marked) begin
                            long_press_marked <= 1'b1;
                            if (long_press_trigger && !thumbnail_mode &&
                                preload_done && display_valid && layout_ready &&
                                !transition_busy && !transition_commit) begin
                                if (guide_active) begin
                                    guide_active <= 1'b0;
                                    guide_confirmed <= 1'b0;
                                    img_idx <= guide_return_idx;
                                    disp_buf_idx <= guide_return_idx;
                                    auto_play_en <= guide_return_auto;
                                end else begin
                                    guide_active <= 1'b1;
                                    guide_confirmed <= 1'b0;
                                    guide_category <= 2'd0;
                                    guide_return_idx <= disp_buf_idx;
                                    guide_return_auto <= auto_play_en;
                                    auto_play_en <= 1'b0;
                                end
                                next_req_pending <= 1'b0;
                                transition_request <= 1'b0;
                                auto_cnt <= 32'd0;
                            end
                        end
                    end else begin
                        long_press_cnt    <= 32'd0;
                        long_press_marked <= 1'b0;
                    end

                    if (!store_closed && !notice_toggle_event && !guide_active &&
                        key_auto_stable &&
                        preload_done && auto_play_en && !thumbnail_mode && display_valid &&
                        !transition_busy && !transition_commit && !auto_period_changed &&
                        (resource_count(image_complete) > 3'd1)) begin
                        if (auto_tick)
                            auto_cnt <= 32'd0;
                        else
                            auto_cnt <= auto_cnt + 32'd1;
                    end else begin
                        auto_cnt <= 32'd0;
                    end

                    // Preload every discovered image exactly once into the
                    // bank with the same compact resource index.
                    if (config_done && preload_prepare && bmp_ready && !load_busy &&
                        !audio_mode && !preload_done_comb) begin
                        load_cluster   <= cluster_lut(load_idx);
                        load_file_size <= size_lut(load_idx);
                        write_buf_idx  <= load_idx;
                        load_start_pulse <= 1'b1;
                        load_busy         <= 1'b1;
                        preload_prepare   <= 1'b0;
                        bmp_active_seen   <= 1'b0;
                        write_finish_seen <= 1'b0;
                        source_done_seen  <= 1'b0;
                        retry_count       <= 2'd0;
                    end else if (config_done && bmp_ready && !load_busy &&
                                 !audio_mode && !preload_done_comb && !preload_prepare &&
                                 (img_found_count != 3'd0)) begin
                        load_idx <= first_unattempted_slot(img_found_count,
                                                          preload_attempted);
                        preload_prepare <= 1'b1;
                    end

                    // After image preload, reuse the FAT-chain reader for the
                    // optional raw 48 kHz mono AUDIO.PCM stream. The reader
                    // loops at EOF and pauses only between complete sectors.
                    // Use the current completion mask for reader ownership:
                    // preload_done is registered and lags the final BMP by a
                    // cycle. Never let a pending BMP share an audio launch.
                    if (preload_done && preload_done_comb && scanner_audio_valid &&
                        !audio_mode && !preload_prepare && !load_start_pulse &&
                        bmp_ready && !load_busy) begin
                        load_cluster           <= scanner_audio_cluster;
                        load_file_size         <= scanner_audio_size;
                        audio_mode             <= 1'b1;
                        audio_file_start_pulse <= 1'b1;
                    end else if (audio_mode && file_done) begin
                        if (file_error == 8'd0)
                            audio_file_start_pulse <= 1'b1;
                        else
                            audio_mode <= 1'b0;
                    end

                    if (prev_request_event) begin
                        transition_target  <= prev_loaded_from_current;
                        transition_request <= 1'b1;
                        auto_cnt           <= 32'd0;
                    end else if (thumbnail_confirm_event) begin
                        transition_target  <= thumbnail_focus_index;
                        // A fade waits for a displayed-bank change. Confirming
                        // the current bank exits thumbnails without that fade.
                        transition_request <= (thumbnail_focus_index != disp_buf_idx);
                        auto_cnt            <= 32'd0;
                    end else if (!store_closed && !notice_toggle_event && !guide_active &&
                        (next_req_pending || key_next_short_event) && !thumbnail_mode && preload_done &&
                        display_valid && !transition_busy) begin
                        img_idx          <= next_loaded_from_current;
                        disp_buf_idx     <= next_loaded_from_current;
                        next_req_pending <= 1'b0;
                        auto_cnt         <= 32'd0;
                    end else if (!store_closed && !notice_toggle_event && !guide_active &&
                                 key_auto_stable &&
                                 preload_done && display_valid && auto_play_en && !thumbnail_mode &&
                                 !transition_busy &&
                                 auto_tick && !key_auto_release &&
                                 (resource_count(image_complete) > 3'd1)) begin
                        transition_target  <= next_loaded_from_current;
                        transition_request <= 1'b1;
                        auto_cnt           <= 32'd0;
                    end

                    // Keep the displayed image and timing/volume settings.
                    // Resume with a full dwell, never a stale queued key or
                    // an immediate transition from the thumbnail cursor.
                    if (idle_resume_event) begin
                        auto_play_en       <= 1'b1;
                        auto_cnt           <= 32'd0;
                        next_req_pending   <= 1'b0;
                        transition_request <= 1'b0;
                    end
                end
            end
        end

        // Override navigation only; image preload and PCM streaming keep running.
        // An already accepted transition may finish underneath the notice.
        if (store_closed || notice_toggle_event) begin
            auto_cnt <= 0;
            next_req_pending <= 1'b0;
            transition_request <= 1'b0;
            auto_play_en <= notice_toggle_event && store_closed &&
                            config_autoplay_allowed;
            if (guide_active) begin
                guide_active <= 1'b0;
                guide_confirmed <= 1'b0;
                img_idx <= guide_return_idx;
                disp_buf_idx <= guide_return_idx;
            end
        end

        // 正常显示图片编号 1~6；错误锁存为 9/A/B（头错误/超时/截断）。
        if (last_bmp_error != 3'd0)
            state_code <= {1'b1, last_bmp_error};
        else
            state_code <= {1'b0, img_idx} + 4'd1;
    end
end

// Hold the SDRAM write request until its cross-clock-domain acknowledge, then
// start streaming the selected FAT file and decode its BMP byte stream.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        reader_state          <= RD_IDLE;
        write_req_reg         <= 1'b0;
        bmp_file_start_pulse  <= 1'b0;
        bmp_data_wr_en_reg    <= 1'b0;
        bmp_data_reg          <= 24'd0;
        reader_timeout        <= 32'd0;
        magic0                <= 8'd0;
        magic1                <= 8'd0;
        header_file_size      <= 32'd0;
        pixel_offset          <= 32'd54;
        dib_header_size       <= 32'd0;
        bmp_width_read        <= 32'd0;
        bmp_height_read       <= 32'd0;
        bmp_planes            <= 16'd0;
        bmp_bpp               <= 16'd0;
        bmp_compression       <= 32'd0;
        stored_width          <= 16'd0;
        stored_height         <= 16'd0;
        stored_pixels         <= 32'd0;
        source_row_bytes      <= 32'd0;
        source_row_stride     <= 32'd0;
        source_pixel_bytes    <= 32'd0;
        pixel_end_wide        <= 33'd0;
        pixel_byte_phase      <= 2'd0;
        pixel_data_active     <= 1'b0;
        pixel_b               <= 8'd0;
        pixel_g               <= 8'd0;
        pixel_count           <= 32'd0;
        source_x_count        <= 32'd0;
        source_row_count      <= 32'd0;
        x_scale_accum         <= 32'd0;
        y_scale_accum         <= 32'd0;
        row_padding_remaining <= 2'd0;
        parser_error          <= 1'b0;
        bmp_error             <= 3'd0;
        load_error            <= 1'b0;
    end else begin
        bmp_file_start_pulse <= 1'b0;
        bmp_data_wr_en_reg <= 1'b0;
        load_error         <= 1'b0;

        case (reader_state)
            RD_IDLE: begin
                write_req_reg  <= 1'b0;
                reader_timeout <= 32'd0;
                if (load_start_pulse) begin
                    write_req_reg    <= 1'b1;
                    magic0           <= 8'd0;
                    magic1           <= 8'd0;
                    header_file_size <= 32'd0;
                    pixel_offset     <= 32'd54;
                    dib_header_size  <= 32'd0;
                    bmp_width_read   <= 32'd0;
                    bmp_height_read  <= 32'd0;
                    bmp_planes       <= 16'd0;
                    bmp_bpp          <= 16'd0;
                    bmp_compression  <= 32'd0;
                    stored_width     <= 16'd0;
                    stored_height    <= 16'd0;
                    stored_pixels    <= 32'd0;
                    source_row_bytes <= 32'd0;
                    source_row_stride <= 32'd0;
                    source_pixel_bytes <= 32'd0;
                    pixel_end_wide   <= 33'd0;
                    pixel_byte_phase <= 2'd0;
                    pixel_data_active <= 1'b0;
                    pixel_count      <= 32'd0;
                    source_x_count     <= 32'd0;
                    source_row_count   <= 32'd0;
                    x_scale_accum       <= 32'd0;
                    y_scale_accum       <= 32'd0;
                    row_padding_remaining <= 2'd0;
                    parser_error     <= 1'b0;
                    bmp_error        <= 3'd0;
                    reader_state     <= RD_WRITE_WAIT;
                end
            end

            RD_WRITE_WAIT: begin
                if (write_req_ack) begin
                    write_req_reg    <= 1'b0;
                    bmp_file_start_pulse <= 1'b1;
                    reader_timeout   <= 32'd0;
                    reader_state     <= RD_STREAM;
                end else if (reader_timeout >= LOAD_TIMEOUT_CYCLES - 1) begin
                    write_req_reg <= 1'b0;
                    bmp_error     <= 3'd2;
                    load_error    <= 1'b1;
                    reader_state  <= RD_IDLE;
                end else begin
                    reader_timeout <= reader_timeout + 32'd1;
                end
            end

            RD_STREAM: begin
                if (file_valid) begin
                    case (file_byte_offset)
                        32'd0:  magic0 <= file_byte;
                        32'd1:  magic1 <= file_byte;
                        32'd2:  header_file_size[7:0]   <= file_byte;
                        32'd3:  header_file_size[15:8]  <= file_byte;
                        32'd4:  header_file_size[23:16] <= file_byte;
                        32'd5:  header_file_size[31:24] <= file_byte;
                        32'd10: pixel_offset[7:0]       <= file_byte;
                        32'd11: pixel_offset[15:8]      <= file_byte;
                        32'd12: pixel_offset[23:16]     <= file_byte;
                        32'd13: pixel_offset[31:24]     <= file_byte;
                        32'd14: dib_header_size[7:0]    <= file_byte;
                        32'd15: dib_header_size[15:8]   <= file_byte;
                        32'd16: dib_header_size[23:16]  <= file_byte;
                        32'd17: dib_header_size[31:24]  <= file_byte;
                        32'd18: bmp_width_read[7:0]     <= file_byte;
                        32'd19: bmp_width_read[15:8]    <= file_byte;
                        32'd20: bmp_width_read[23:16]   <= file_byte;
                        32'd21: bmp_width_read[31:24]   <= file_byte;
                        32'd22: bmp_height_read[7:0]    <= file_byte;
                        32'd23: bmp_height_read[15:8]   <= file_byte;
                        32'd24: bmp_height_read[23:16]  <= file_byte;
                        32'd25: bmp_height_read[31:24]  <= file_byte;
                        32'd26: bmp_planes[7:0]         <= file_byte;
                        32'd27: bmp_planes[15:8]        <= file_byte;
                        32'd28: bmp_bpp[7:0]            <= file_byte;
                        32'd29: bmp_bpp[15:8]           <= file_byte;
                        32'd30: bmp_compression[7:0]    <= file_byte;
                        32'd31: bmp_compression[15:8]   <= file_byte;
                        32'd32: bmp_compression[23:16]  <= file_byte;
                        32'd33: bmp_compression[31:24]  <= file_byte;
                        default: begin end
                    endcase

                    // Pipeline the BMP size calculations across header bytes.
                    // The source format limits below make the sliced multiply
                    // exact for every accepted image (maximum 4096x4096).
                    if (file_byte_offset == 32'd26) begin
                        stored_width <= (bmp_width_read > {16'd0, BMP_WIDTH}) ?
                                        BMP_WIDTH : bmp_width_read[15:0];
                        stored_height <= (bmp_height_read > {16'd0, BMP_HEIGHT}) ?
                                         BMP_HEIGHT : bmp_height_read[15:0];
                        source_row_bytes <= (bmp_width_read << 1) + bmp_width_read;
                    end
                    if (file_byte_offset == 32'd27) begin
                        stored_pixels <= stored_width * stored_height;
                        source_row_stride <= (source_row_bytes + 32'd3) &
                                             32'hfffffffc;
                    end
                    if (file_byte_offset == 32'd28)
                        source_pixel_bytes <= source_row_stride[13:0] *
                                              bmp_height_read[12:0];
                    if (file_byte_offset == 32'd29)
                        pixel_end_wide <= {1'b0, pixel_offset} +
                                          {1'b0, source_pixel_bytes};

                    if ((file_byte_offset == 32'd53) && !bmp_header_valid)
                        parser_error <= 1'b1;

                    // Arm one byte before the pixel array so the three-byte
                    // phase counter is driven only by a registered enable.
                    if (!pixel_data_active && !parser_error &&
                        ((file_byte_offset + 32'd1) == pixel_offset))
                        pixel_data_active <= 1'b1;

                    if (pixel_data_active && !parser_error &&
                        (row_padding_remaining != 0)) begin
                        row_padding_remaining <= row_padding_remaining - 1'b1;
                    end else if (pixel_data_active && !parser_error) begin
                        case (pixel_byte_phase)
                            2'd0: begin
                                pixel_b          <= file_byte;
                                pixel_byte_phase <= 2'd1;
                            end
                            2'd1: begin
                                pixel_g          <= file_byte;
                                pixel_byte_phase <= 2'd2;
                            end
                            default: begin
                                if (select_source_row && select_source_x) begin
                                    bmp_data_reg       <= {file_byte, pixel_g, pixel_b};
                                    bmp_data_wr_en_reg <= 1'b1;
                                    pixel_count        <= pixel_count + 1'b1;
                                end
                                pixel_byte_phase   <= 2'd0;

                                if (select_source_x)
                                    x_scale_accum <= x_scale_accum +
                                                     {16'd0, stored_width} -
                                                     bmp_width_read;
                                else
                                    x_scale_accum <= x_scale_accum +
                                                     {16'd0, stored_width};

                                if (source_x_count == (bmp_width_read - 1'b1)) begin
                                    source_x_count <= 32'd0;
                                    x_scale_accum  <= 32'd0;
                                    source_row_count <= source_row_count + 1'b1;
                                    row_padding_remaining <=
                                        (32'd4 - (source_row_bytes & 32'd3)) & 32'd3;
                                    if (select_source_row)
                                        y_scale_accum <= y_scale_accum +
                                                         {16'd0, stored_height} -
                                                         bmp_height_read;
                                    else
                                        y_scale_accum <= y_scale_accum +
                                                         {16'd0, stored_height};
                                    if (source_row_count == (bmp_height_read - 1'b1))
                                        pixel_data_active <= 1'b0;
                                end else begin
                                    source_x_count <= source_x_count + 1'b1;
                                end
                            end
                        endcase
                    end
                end

                if (file_done) begin
                    if ((file_error != 0) || parser_error ||
                        (source_row_count != bmp_height_read) ||
                        (pixel_count != stored_pixels) ||
                        (pixel_byte_phase != 0)) begin
                        reader_state <= RD_IDLE;
                        load_error <= 1'b1;
                        if (parser_error)
                            bmp_error <= 3'd1;
                        else if (file_error == 8'h10)
                            bmp_error <= 3'd2;
                        else
                            bmp_error <= 3'd3;
                    end else begin
                        bmp_error <= 3'd0;
                        reader_state <= RD_FILL;
                    end
                end
            end

            RD_FILL: begin
                // Keep the established 640x480 transfer length. The valid
                // compact image is followed by unused zero words.
                if (pixel_count < expected_pixels) begin
                    bmp_data_reg       <= 24'd0;
                    bmp_data_wr_en_reg <= 1'b1;
                    pixel_count        <= pixel_count + 1'b1;
                end else begin
                    reader_state <= RD_IDLE;
                end
            end

            default: reader_state <= RD_IDLE;
        endcase
    end
end

fat32_volume_scanner u_fat32_volume_scanner (
    .clk                 (clk),
    .rst_n               (~rst),
    .scan_start          (scan_start_pulse),
    .scan_busy           (scanner_busy),
    .scan_done           (scanner_done),
    .fs_error            (scanner_error),
    .partition_lba       (),
    .sectors_per_cluster (scanner_spc),
    .fat_start_lba       (scanner_fat_start),
    .data_start_lba      (scanner_data_start),
    .max_cluster         (scanner_max_cluster),
    .resource_valid      (scanner_resource_valid),
    .resource0_cluster   (scanner_cluster0),
    .resource1_cluster   (scanner_cluster1),
    .resource2_cluster   (scanner_cluster2),
    .resource3_cluster   (scanner_cluster3),
    .resource4_cluster   (scanner_cluster4),
    .resource5_cluster   (scanner_cluster5),
    .resource0_size      (scanner_size0),
    .resource1_size      (scanner_size1),
    .resource2_size      (scanner_size2),
    .resource3_size      (scanner_size3),
    .resource4_size      (scanner_size4),
    .resource5_size      (scanner_size5),
    .audio_resource_valid(scanner_audio_valid),
    .audio_resource_cluster(scanner_audio_cluster),
    .audio_resource_size (scanner_audio_size),
    .config_resource_valid(scanner_config_valid),
    .config_resource_cluster(scanner_config_cluster),
    .config_resource_size(scanner_config_size),
    .sector_req          (scanner_sector_req),
    .sector_lba          (scanner_sector_lba),
    .sector_busy         (arb_sector_busy),
    .sector_valid        (scan_complete ? 1'b0 : arb_sector_valid),
    .sector_byte         (arb_sector_byte),
    .sector_byte_index   (arb_sector_byte_index),
    .sector_done         (scan_complete ? 1'b0 : arb_sector_done),
    .sector_error        (arb_sector_error)
);

fat32_file_streamer u_fat32_file_streamer (
    .clk                 (clk),
    .rst_n               (~rst),
    .file_start          (file_start_pulse),
    .read_enable         (!audio_mode || audio_fill_enable),
    .first_cluster       (load_cluster),
    .file_size           (load_file_size),
    .sectors_per_cluster (scanner_spc),
    .fat_start_lba       (scanner_fat_start),
    .data_start_lba      (scanner_data_start),
    .max_cluster         (scanner_max_cluster),
    .file_busy           (file_busy),
    .file_done           (file_done),
    .file_valid          (file_valid),
    .file_byte           (file_byte),
    .file_byte_offset    (file_byte_offset),
    .fs_error            (file_error),
    .sector_req          (streamer_sector_req),
    .sector_lba          (streamer_sector_lba),
    .sector_busy         (arb_sector_busy),
    .sector_valid        (scan_complete ? arb_sector_valid : 1'b0),
    .sector_byte         (arb_sector_byte),
    .sector_byte_index   (arb_sector_byte_index),
    .sector_done         (scan_complete ? arb_sector_done : 1'b0),
    .sector_error        (arb_sector_error)
);

sd_sector_adapter #(
    .CLK_FREQ_HZ    (CLK_FREQ_HZ),
    .READ_TIMEOUT_MS(SD_READ_TIMEOUT_MS)
) u_sd_sector_adapter (
    .clk                    (clk),
    .rst_n                  (~rst),
    .sector_req             (arb_sector_req),
    .sector_lba             (arb_sector_lba),
    .sector_busy            (arb_sector_busy),
    .sector_valid           (arb_sector_valid),
    .sector_byte            (arb_sector_byte),
    .sector_byte_index      (arb_sector_byte_index),
    .sector_done            (arb_sector_done),
    .sector_error           (arb_sector_error),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_end        (sd_sec_read_end)
);

sd_card_top #(
    .SPI_LOW_SPEED_DIV (498),
    .SPI_HIGH_SPEED_DIV(2)
) sd_card_top_m0(
    .clk                    (clk),
    .rst                    (sd_controller_rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .controller_state       (sd_controller_state),
    .last_r1                (sd_last_r1),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

// CONFIG.TXT: ASCII PIC1=05..PIC6=30, VOLUME=0..4, AUTOPLAY=0..1.
// Unknown or malformed lines are ignored; every file read starts from defaults.
module tf_config_parser #(
    parameter integer DWELL0 = 5, DWELL1 = 10, DWELL2 = 15,
    parameter integer DWELL3 = 8, DWELL4 = 10, DWELL5 = 10
)(
    input wire clk, input wire rst, input wire start,
    input wire valid, input wire done, input wire [7:0] byte_in,
    output reg [5:0] dwell0, dwell1, dwell2, dwell3, dwell4, dwell5,
    output reg [2:0] volume_level,
    output reg autoplay, output reg autoplay_present
);
reg [3:0] line_len;
reg pic_match, volume_match, autoplay_match;
reg [2:0] pic_index, volume_value;
reg [3:0] pic_tens, pic_ones;
reg autoplay_value;
wire line_end = (valid && byte_in == 8'h0a) || done;
wire [5:0] pic_seconds = ({2'd0, pic_tens} << 3) +
                         ({2'd0, pic_tens} << 1) + {2'd0, pic_ones};

always @(posedge clk or posedge rst) begin
    if (rst || start) begin
        dwell0 <= DWELL0; dwell1 <= DWELL1; dwell2 <= DWELL2;
        dwell3 <= DWELL3; dwell4 <= DWELL4; dwell5 <= DWELL5;
        volume_level <= 3'd1;
        autoplay <= 1'b0;
        autoplay_present <= 1'b0;
        line_len <= 4'd0;
        pic_match <= 1'b1;
        volume_match <= 1'b1;
        autoplay_match <= 1'b1;
        pic_index <= 3'd0;
        pic_tens <= 4'd0;
        pic_ones <= 4'd0;
        volume_value <= 3'd1;
        autoplay_value <= 1'b0;
    end else if (line_end) begin
        if (line_len == 4'd7 && pic_match && pic_tens <= 3 &&
            pic_seconds >= 1 && pic_seconds <= 30) begin
            case (pic_index)
                3'd0: dwell0 <= pic_seconds;
                3'd1: dwell1 <= pic_seconds;
                3'd2: dwell2 <= pic_seconds;
                3'd3: dwell3 <= pic_seconds;
                3'd4: dwell4 <= pic_seconds;
                3'd5: dwell5 <= pic_seconds;
                default: begin end
            endcase
        end
        if (line_len == 4'd8 && volume_match)
            volume_level <= volume_value;
        if (line_len == 4'd10 && autoplay_match) begin
            autoplay <= autoplay_value;
            autoplay_present <= 1'b1;
        end
        line_len <= 4'd0;
        pic_match <= 1'b1;
        volume_match <= 1'b1;
        autoplay_match <= 1'b1;
    end else if (valid && byte_in != 8'h0d) begin
        if (line_len != 4'd15)
            line_len <= line_len + 1'b1;
        else begin
            pic_match <= 1'b0;
            volume_match <= 1'b0;
            autoplay_match <= 1'b0;
        end
        case (line_len)
            4'd0: begin
                if (byte_in != "P") pic_match <= 1'b0;
                if (byte_in != "V") volume_match <= 1'b0;
                if (byte_in != "A") autoplay_match <= 1'b0;
            end
            4'd1: begin
                if (byte_in != "I") pic_match <= 1'b0;
                if (byte_in != "O") volume_match <= 1'b0;
                if (byte_in != "U") autoplay_match <= 1'b0;
            end
            4'd2: begin
                if (byte_in != "C") pic_match <= 1'b0;
                if (byte_in != "L") volume_match <= 1'b0;
                if (byte_in != "T") autoplay_match <= 1'b0;
            end
            4'd3: begin
                if (byte_in < "1" || byte_in > "6") pic_match <= 1'b0;
                else pic_index <= byte_in - "1";
                if (byte_in != "U") volume_match <= 1'b0;
                if (byte_in != "O") autoplay_match <= 1'b0;
            end
            4'd4: begin
                if (byte_in != "=") pic_match <= 1'b0;
                if (byte_in != "M") volume_match <= 1'b0;
                if (byte_in != "P") autoplay_match <= 1'b0;
            end
            4'd5: begin
                if (byte_in < "0" || byte_in > "9") pic_match <= 1'b0;
                else pic_tens <= byte_in - "0";
                if (byte_in != "E") volume_match <= 1'b0;
                if (byte_in != "L") autoplay_match <= 1'b0;
            end
            4'd6: begin
                if (byte_in < "0" || byte_in > "9") pic_match <= 1'b0;
                else pic_ones <= byte_in - "0";
                if (byte_in != "=") volume_match <= 1'b0;
                if (byte_in != "A") autoplay_match <= 1'b0;
            end
            4'd7: begin
                if (byte_in < "0" || byte_in > "4") volume_match <= 1'b0;
                else volume_value <= byte_in - "0";
                if (byte_in != "Y") autoplay_match <= 1'b0;
            end
            4'd8: if (byte_in != "=") autoplay_match <= 1'b0;
            4'd9: begin
                if (byte_in != "0" && byte_in != "1") autoplay_match <= 1'b0;
                else autoplay_value <= (byte_in == "1");
            end
            default: begin end
        endcase
    end
end
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    // === 新增：释放沿脉冲输出（用于“短按”判定，与长按区分）===
    output reg  release_pulse,
    // === 新增：消抖后的稳定状态输出（用于长按检测）===
    output reg  button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0      <= 1'b1;
        button_sync1      <= 1'b1;
        button_stable     <= 1'b1;
        button_stable_out <= 1'b1;
        cnt               <= 32'd0;
        press_pulse       <= 1'b0;
        release_pulse     <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;
        release_pulse <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                if (!button_stable && button_sync1)
                    release_pulse <= 1'b1;
                button_stable     <= button_sync1;
                button_stable_out <= button_sync1;   // 新增：同步输出稳定状态
                cnt               <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
