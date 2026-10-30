
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3,           // 短按音量，长按轮播周期
    input [3:0]                 image_adjust_sw, // SW1-2: B 00/01/11/10=255/192/128/64; SW3-4: C 00/01/11/10=128/160/192/255

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [20:0] FRAME_PIXELS = 21'd307200;   // 640*480
parameter [20:0] BUF0_ADDR    = 21'd0;
parameter [20:0] BUF1_ADDR    = 21'd307200;
parameter [20:0] BUF2_ADDR    = 21'd614400;
parameter [20:0] BUF3_ADDR    = 21'd921600;
parameter [20:0] BUF4_ADDR    = 21'd1228800;
parameter [20:0] BUF5_ADDR    = 21'd1536000;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;
wire sys_pll_lock;
wire video_pll_lock;

wire core_pll_ready_n;
wire audio_pll_ready_n;
wire ref_rst_n;
wire sd_rst_n;
wire mem_rst_n;
wire video_rst_n;
wire hdmi5x_rst_n;
wire audio_rst_n;
wire sdram_init_done_sd;
wire sd_powerup_release_n;

reg [22:0] sd_powerup_count;
reg        sd_powerup_ready;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] thumbnail_source_rgb;
wire [23:0] transition_rgb;
wire [23:0] adjusted_rgb;
wire [23:0] pre_osd_data;
wire [23:0] osd_rgb_data;
wire [23:0] vout_data;
reg  [23:0] compositor_rgb_q;
reg  [23:0] compositor_fallback_q;
reg  [10:0] compositor_x_q;
reg         compositor_de_q;
reg         compositor_vs_q;
reg         compositor_display_valid_q;
reg  [23:0] transition_source_rgb_q;
reg  [23:0] transition_fallback_rgb_q;
reg  [10:0] transition_x_q;
reg         transition_de_q;
reg         transition_vs_q;
reg         transition_display_valid_q;
reg         transition_fade_active_q;
reg  [7:0]  transition_fade_alpha_q;
reg         transition_wipe_active_q;
reg  [10:0] transition_wipe_boundary_q;
reg         video_axis_de_q;
reg         video_axis_vs_q;
reg         video_axis_de_d;
reg         video_axis_vs_d;
wire        display_valid;
wire        auto_play_enabled;
wire        auto_play_enabled_video;
wire [7:0]  playback_status_sd;
wire [6:0]  guide_status_sd;
wire [6:0]  guide_status_video;
wire [23:0] loading_status_sd, loading_status_video;
wire        store_closed_sd;
wire        store_closed_video;
wire        store_closed_frame;
wire [7:0]  playback_status_video;
wire        thumbnail_mode;
wire        thumbnail_mode_video;
wire [2:0]  thumbnail_focus_index;
(* async_reg = "true" *) reg [2:0] thumbnail_focus_meta_video;
(* async_reg = "true" *) reg [2:0] thumbnail_focus_sync_video;
reg [2:0]   active_thumbnail_focus_index;
wire [5:0]  image_complete_status;
wire [15:0] image_width_0;
wire [15:0] image_height_0;
wire [15:0] image_width_1;
wire [15:0] image_height_1;
wire [15:0] image_width_2;
wire [15:0] image_height_2;
wire [15:0] image_width_3;
wire [15:0] image_height_3;
wire [15:0] image_width_4;
wire [15:0] image_height_4;
wire [15:0] image_width_5;
wire [15:0] image_height_5;
wire [15:0] write_image_width;
wire [15:0] write_image_height;
wire [20:0] write_image_pixels;
wire [7:0]  osd_error_video;
wire        osd_de;
wire        osd_active;
wire [10:0] osd_pixel_x;
wire        osd_vsync;
wire        waveform_active;
wire [31:0] storage_debug_status;
wire [23:0] storage_diagnostic;
wire        sdram_ready_video;
wire        transition_request;
wire [2:0]  transition_target;
wire        transition_commit;
wire        transition_busy;
wire [7:0]  fade_alpha;
wire        fade_active;
wire        wipe_active;
wire [4:0]  wipe_ramp;
wire [1:0]  transition_kind;
wire        frame_start_video;
(* async_reg = "true" *) reg [3:0] adjust_sw_meta;
(* async_reg = "true" *) reg [3:0] adjust_sw_sync;
reg [3:0]  adjust_sw_frame;
reg [7:0]  brightness_video;
reg [7:0]  contrast_video;
wire        index_commit_video;
wire [10:0] wipe_boundary;
wire [15:0] fade_r_product;
wire [15:0] fade_g_product;
wire [15:0] fade_b_product;
reg         display_valid_video_meta;
reg         display_valid_video;
(* async_reg = "true" *) reg [5:0] image_complete_video_meta;
(* async_reg = "true" *) reg [5:0] image_complete_video_sync;
reg [5:0]   active_image_complete;
reg         active_thumbnail_mode;
(* async_reg = "true" *) reg [31:0] storage_debug_meta;
(* async_reg = "true" *) reg [31:0] storage_debug_video;
(* async_reg = "true" *) reg [23:0] storage_diagnostic_meta;
(* async_reg = "true" *) reg [23:0] storage_diagnostic_clk;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;
wire [6:0]  seg_data_rst;
wire [6:0]  seg_data_sys_pll;
wire [6:0]  seg_data_video_pll;
wire [6:0]  seg_data_hdmi_lock;
wire [6:0]  seg_data_audio_pll;
wire [6:0]  seg_data_diag_0;
wire [6:0]  seg_data_diag_1;
wire [6:0]  seg_data_diag_2;
wire [6:0]  seg_data_diag_3;
wire [6:0]  seg_data_diag_4;
wire [6:0]  seg_data_diag_5;
wire [6:0]  seg_data_0_mux;
wire [6:0]  seg_data_1_mux;
wire [6:0]  seg_data_2_mux;
wire [6:0]  seg_data_3_mux;
wire [6:0]  seg_data_4_mux;
wire [6:0]  seg_data_5_mux;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire        video_read_valid;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [2:0]  write_buf_idx;
wire [2:0]  disp_buf_idx;
reg  [2:0]  disp_idx_sync1_video;
reg  [2:0]  disp_idx_sync2_video;
reg  [2:0]  active_disp_buf_idx;
reg  [2:0]  active_disp_buf_idx_d;
reg         video_read_req_d;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

// Board diagnostics: first digit d, then SD input, memory history, current
// memory traffic, current pixel traffic, and selected picture (1..6).
// SD nibble: request / pixels / nonzero pixels / at least one completed image.
// Memory history: write / nonzero write / read request / read return.
// Memory window: initialized / read request / read return / nonzero return.
// Pixel window: pop / valid / nonzero FIFO data / nonzero raw video.
// Current windows are published every 2^25 clocks, so a later stall is visible.
reg [3:0] image_sd_seen, image_mem_seen;
reg [2:0] image_mem_window;
reg [3:0] image_mem_snapshot, image_pixel_window, image_pixel_snapshot;
reg [24:0] image_mem_timer, image_pixel_timer;
(* async_reg = "true" *) reg [11:0] image_diag_meta, image_diag_sync;
(* async_reg = "true" *) reg [4:0] image_pixel_meta, image_pixel_sync;
reg [2:0] image_index_meta, image_index_sync;
wire [23:0] image_diagnostic_clk = {1'b0, image_index_sync,
    image_pixel_sync[3:0], image_diag_sync[3:0],
    image_diag_sync[7:4], image_diag_sync[11:8], 4'hd};
wire [23:0] board_diagnostic = image_pixel_sync[4] ?
    image_diagnostic_clk : storage_diagnostic_clk;

always @(posedge sd_card_clk or negedge sd_rst_n) begin
    if (!sd_rst_n) image_sd_seen <= 0;
    else begin
        if (sd_card_write_req) image_sd_seen[3] <= 1;
        if (sd_card_write_en) image_sd_seen[2] <= 1;
        if (sd_card_write_en && |sd_card_write_data[31:8]) image_sd_seen[1] <= 1;
        if (|image_complete_status) image_sd_seen[0] <= 1;
    end
end
always @(posedge ext_mem_clk or negedge mem_rst_n) begin
    if (!mem_rst_n) begin
        image_mem_seen <= 0; image_mem_window <= 0;
        image_mem_snapshot <= 0; image_mem_timer <= 0;
    end else begin
        if (App_wr_en) image_mem_seen[3] <= 1;
        if (App_wr_en && |App_wr_din[31:8]) image_mem_seen[2] <= 1;
        if (App_rd_en) image_mem_seen[1] <= 1;
        if (Sdr_rd_en) image_mem_seen[0] <= 1;
        image_mem_timer <= image_mem_timer + 1'b1;
        if (&image_mem_timer) begin
            image_mem_snapshot <= {Sdr_init_done, image_mem_window};
            image_mem_window <= {App_rd_en, Sdr_rd_en,
                Sdr_rd_en && |Sdr_rd_dout[31:8]};
        end else begin
            if (App_rd_en) image_mem_window[2] <= 1;
            if (Sdr_rd_en) image_mem_window[1] <= 1;
            if (Sdr_rd_en && |Sdr_rd_dout[31:8]) image_mem_window[0] <= 1;
        end
    end
end
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        image_pixel_timer <= 0; image_pixel_window <= 0; image_pixel_snapshot <= 0;
    end else begin
        image_pixel_timer <= image_pixel_timer + 1'b1;
        if (&image_pixel_timer) begin
            image_pixel_snapshot <= image_pixel_window;
            image_pixel_window <= {video_read_en, video_read_valid,
                video_read_valid && |video_read_data[31:8], de && |vout_data_raw};
        end else begin
            if (video_read_en) image_pixel_window[3] <= 1;
            if (video_read_valid) image_pixel_window[2] <= 1;
            if (video_read_valid && |video_read_data[31:8]) image_pixel_window[1] <= 1;
            if (de && |vout_data_raw) image_pixel_window[0] <= 1;
        end
    end
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        image_diag_meta <= 0; image_diag_sync <= 0;
        image_pixel_meta <= 0; image_pixel_sync <= 0;
        image_index_meta <= 0; image_index_sync <= 0;
    end else begin
        image_diag_meta <= {image_sd_seen, image_mem_seen, image_mem_snapshot};
        image_diag_sync <= image_diag_meta;
        image_pixel_meta <= {display_valid_video, image_pixel_snapshot};
        image_pixel_sync <= image_pixel_meta;
        image_index_meta <= active_disp_buf_idx + 3'd1;
        image_index_sync <= image_index_meta;
    end
end

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        tone_audio_valid;
wire [23:0] tone_audio_left_data;
wire [23:0] tone_audio_right_data;
wire        audio_pcm_byte_valid;
wire [7:0]  audio_pcm_byte;
wire        audio_stream_active;
wire        audio_stream_active_video;
wire        audio_fill_enable;
wire        pcm_audio_valid;
wire [23:0] pcm_audio_left_data;
wire [23:0] pcm_audio_right_data;
wire        pcm_buffer_low;
wire [7:0]  volume_gain_ctrl;
wire        config_volume_valid_sd;
wire [2:0]  config_volume_level_sd;
(* async_reg = "true" *) reg config_volume_valid_meta, config_volume_valid_sync;
(* async_reg = "true" *) reg [2:0] config_volume_level_meta, config_volume_level_sync;
(* async_reg = "true" *) reg [7:0] volume_gain_video_meta;
(* async_reg = "true" *) reg [7:0] volume_gain_video_sync;
reg  [7:0]  volume_gain_video_prev;
reg  [7:0]  volume_gain_video;
wire [1:0]  auto_period_level_ctrl;
(* async_reg = "true" *) reg [1:0] auto_period_level_meta;
(* async_reg = "true" *) reg [1:0] auto_period_level_sync;
reg  [1:0]  auto_period_level_prev;
reg  [1:0]  auto_period_level_sd;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;
wire        hdmi_video_locked;

reg  [10:0] fallback_x;
reg  [9:0]  fallback_y;
reg  [23:0] fallback_rgb;
wire        thumbnail_de;
wire [2:0]  thumbnail_source_index;
wire [9:0]  thumbnail_source_x;
wire [9:0]  thumbnail_source_y;
wire        thumbnail_focus_border;

// Video, TF-card and SDRAM must not depend on the optional audio PLL. Otherwise
// an audio lock failure holds the entire board in reset and removes HDMI output.
assign core_pll_ready_n  = rst_n & sys_pll_lock & video_pll_lock;
assign audio_pll_ready_n = rst_n & audio_pll_lock;
assign sd_powerup_release_n = core_pll_ready_n & sd_powerup_ready;

// Give the TF card supply and socket contacts time to settle after power-up.
// This also makes FPGA reconfiguration reliable while the card stays powered.
always @(posedge clk or negedge core_pll_ready_n) begin
    if (!core_pll_ready_n) begin
        sd_powerup_count <= 23'd0;
        sd_powerup_ready <= 1'b0;
    end else if (!sd_powerup_ready) begin
        if (sd_powerup_count >= 23'd4_999_999)
            sd_powerup_ready <= 1'b1;
        else
            sd_powerup_count <= sd_powerup_count + 1'b1;
    end
end

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (~rst_n),
    .locked     (sys_pll_lock)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (~rst_n),
    .locked     (video_pll_lock)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (~rst_n),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// Asynchronous assertion and synchronous release in each active clock domain.
reset_sync u_ref_reset (
    .clk        (clk),
    .ext_rst_n  (core_pll_ready_n),
    .rst_n_sync (ref_rst_n)
);

reset_sync u_sd_reset (
    .clk        (sd_card_clk),
    .ext_rst_n  (sd_powerup_release_n),
    .rst_n_sync (sd_rst_n)
);

reset_sync u_mem_reset (
    .clk        (ext_mem_clk),
    .ext_rst_n  (core_pll_ready_n),
    .rst_n_sync (mem_rst_n)
);

reset_sync u_video_reset (
    .clk        (video_clk),
    .ext_rst_n  (core_pll_ready_n),
    .rst_n_sync (video_rst_n)
);

reset_sync u_hdmi5x_reset (
    .clk        (hdmi_5x_clk),
    .ext_rst_n  (core_pll_ready_n),
    .rst_n_sync (hdmi5x_rst_n)
);

reset_sync u_audio_reset (
    .clk        (audio_mclk),
    .ext_rst_n  (audio_pll_ready_n),
    .rst_n_sync (audio_rst_n)
);

// The TF scanner may start only after SDRAM initialization is visible in the
// SD-card clock domain.
sync_2ff u_sdram_init_sync (
    .clk      (sd_card_clk),
    .rst_n    (sd_rst_n),
    .async_in (Sdr_init_done),
    .sync_out (sdram_init_done_sd)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or negedge mem_rst_n) begin
    if (!mem_rst_n)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF FAT32 scan and six-bank preload =====================
param_menu_controller #(
    .CLKS_PER_MS (50_000),
    .DEBOUNCE_MS (20),
    .LONG_HOLD_MS(1000)
) u_param_menu_controller (
    .clk          (clk),
    .rst_n        (rst_n),
    .key1_n       (key1),
    .key3_n       (key3),
    .volume_gain  (volume_gain_ctrl),
    .period_level (auto_period_level_ctrl),
    .config_valid(config_volume_valid_sync),
    .config_volume_level(config_volume_level_sync)
);

always @(posedge clk or negedge ref_rst_n) begin
    if (!ref_rst_n) begin
        config_volume_valid_meta <= 1'b0;
        config_volume_valid_sync <= 1'b0;
        config_volume_level_meta <= 3'd1;
        config_volume_level_sync <= 3'd1;
    end else begin
        config_volume_valid_meta <= config_volume_valid_sd;
        config_volume_valid_sync <= config_volume_valid_meta;
        config_volume_level_meta <= config_volume_level_sd;
        config_volume_level_sync <= config_volume_level_meta;
    end
end

// Keep KEY3 timing logic off the already heavily loaded SD-card clock tree.
// Commit the two-bit setting only after two synchronized samples agree.
always @(posedge sd_card_clk or negedge sd_rst_n) begin
    if (!sd_rst_n) begin
        auto_period_level_meta <= 2'd3;
        auto_period_level_sync <= 2'd3;
        auto_period_level_prev <= 2'd3;
        auto_period_level_sd   <= 2'd3;
    end else begin
        auto_period_level_meta <= auto_period_level_ctrl;
        auto_period_level_sync <= auto_period_level_meta;
        auto_period_level_prev <= auto_period_level_sync;
        if (auto_period_level_sync == auto_period_level_prev)
            auto_period_level_sd <= auto_period_level_prev;
    end
end

sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .BMP_WIDTH          (16'd640),
    .BMP_HEIGHT         (16'd480),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd6)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (~sd_rst_n),
    .start_enable      (sdram_init_done_sd),
    .key_next          (key1),
    .key_auto          (key2),
    .key_menu          (key3),
    .image_adjust_sw   (image_adjust_sw),
    .auto_period_level (auto_period_level_sd),
    .config_volume_valid(config_volume_valid_sd),
    .config_volume_level(config_volume_level_sd),
    .state_code        (state_code),
    .display_valid     (display_valid),
    .debug_status      (storage_debug_status),
    .storage_diagnostic(storage_diagnostic),
    .auto_play_enabled (auto_play_enabled),
    .playback_status (playback_status_sd),
    .guide_status    (guide_status_sd),
    .loading_status (loading_status_sd),
    .store_closed (store_closed_sd),
    .thumbnail_mode    (thumbnail_mode),
    .thumbnail_focus_index(thumbnail_focus_index),
    .image_complete_status(image_complete_status),
    .image_width_0     (image_width_0),
    .image_height_0    (image_height_0),
    .image_width_1     (image_width_1),
    .image_height_1    (image_height_1),
    .image_width_2     (image_width_2),
    .image_height_2    (image_height_2),
    .image_width_3     (image_width_3),
    .image_height_3    (image_height_3),
    .image_width_4     (image_width_4),
    .image_height_4    (image_height_4),
    .image_width_5     (image_width_5),
    .image_height_5    (image_height_5),
    .write_image_width (write_image_width),
    .write_image_height(write_image_height),
    .write_image_pixels(write_image_pixels),
    .transition_request(transition_request),
    .transition_target (transition_target),
    .transition_commit (transition_commit),
    .transition_busy   (transition_busy),
    .audio_fill_enable (audio_fill_enable),
    .audio_pcm_valid   (audio_pcm_byte_valid),
    .audio_pcm_byte    (audio_pcm_byte),
    .audio_stream_active(audio_stream_active),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

// Keep board-level clock/reset status visible even if the image pipeline is
// not running. The five status digits should all read 1 in normal operation.
seg_decoder seg_decoder_rst(
    .bin_data          ({3'd0, rst_n}),
    .seg_data          (seg_data_rst)
);

seg_decoder seg_decoder_sys_pll(
    .bin_data          ({3'd0, sys_pll_lock}),
    .seg_data          (seg_data_sys_pll)
);

seg_decoder seg_decoder_video_pll(
    .bin_data          ({3'd0, video_pll_lock}),
    .seg_data          (seg_data_video_pll)
);

seg_decoder seg_decoder_hdmi_lock(
    .bin_data          ({3'd0, hdmi_video_locked}),
    .seg_data          (seg_data_hdmi_lock)
);

seg_decoder seg_decoder_audio_pll(
    .bin_data          ({3'd0, audio_pll_lock}),
    .seg_data          (seg_data_audio_pll)
);

// When no image is valid, show the SD controller state, last R1 response,
// and scanner/file error code as six hexadecimal digits. This makes a
// persistent yellow screen actionable without changing the video output.
seg_decoder seg_decoder_diag_0(.bin_data(board_diagnostic[3:0]),
                               .seg_data(seg_data_diag_0));
seg_decoder seg_decoder_diag_1(.bin_data(board_diagnostic[7:4]),
                               .seg_data(seg_data_diag_1));
seg_decoder seg_decoder_diag_2(.bin_data(board_diagnostic[11:8]),
                               .seg_data(seg_data_diag_2));
seg_decoder seg_decoder_diag_3(.bin_data(board_diagnostic[15:12]),
                               .seg_data(seg_data_diag_3));
seg_decoder seg_decoder_diag_4(.bin_data(board_diagnostic[19:16]),
                               .seg_data(seg_data_diag_4));
seg_decoder seg_decoder_diag_5(.bin_data(board_diagnostic[23:20]),
                               .seg_data(seg_data_diag_5));

assign seg_data_0_mux = seg_data_diag_0;
assign seg_data_1_mux = seg_data_diag_1;
assign seg_data_2_mux = seg_data_diag_2;
assign seg_data_3_mux = seg_data_diag_3;
assign seg_data_4_mux = seg_data_diag_4;
assign seg_data_5_mux = seg_data_diag_5;

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,seg_data_0_mux}),
    .seg_data_1        ({1'b1,seg_data_1_mux}),
    .seg_data_2        ({1'b1,seg_data_2_mux}),
    .seg_data_3        ({1'b1,seg_data_3_mux}),
    .seg_data_4        ({1'b1,seg_data_4_mux}),
    .seg_data_5        ({1'b1,seg_data_5_mux})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (~video_rst_n),
    .thumbnail_mode    (active_thumbnail_mode),
    .read_en           (video_read_en),
	.read_valid        (video_read_valid),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// Synchronize the requested bank into the pixel clock domain and commit it
// only when the timing generator starts a new frame. The memory-side reader
// sees this stable value before it acknowledges that frame's read request.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        disp_idx_sync1_video <= 3'd0;
        disp_idx_sync2_video <= 3'd0;
        active_disp_buf_idx  <= 3'd0;
        video_read_req_d     <= 1'b0;
    end else begin
        disp_idx_sync1_video <= disp_buf_idx;
        disp_idx_sync2_video <= disp_idx_sync1_video;
        video_read_req_d     <= video_read_req;
        if (video_read_req && !video_read_req_d)
            active_disp_buf_idx <= disp_idx_sync2_video;
    end
end

assign frame_start_video = video_read_req && !video_read_req_d;
assign index_commit_video = (active_disp_buf_idx != active_disp_buf_idx_d);

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n)
        active_disp_buf_idx_d <= 3'd0;
    else
        active_disp_buf_idx_d <= active_disp_buf_idx;
end

video_fade_transition #(
    .FADE_FRAMES (16)
) u_video_fade_transition (
    .ctrl_clk        (sd_card_clk),
    .ctrl_rst_n      (sd_rst_n),
    .next_event_in   (transition_request),
    .next_event_out  (transition_commit),
    .fade_busy       (transition_busy),
    .pix_clk         (video_clk),
    .pix_rst_n       (video_rst_n),
    .player_active   (display_valid_video),
    .frame_start     (frame_start_video),
    .index_commit    (index_commit_video),
    .active_index    (active_disp_buf_idx),
    .alpha_out       (fade_alpha),
    .fade_active     (fade_active),
    .wipe_active     (wipe_active),
    .ramp_out        (wipe_ramp),
    .transition_kind (transition_kind)
);

// The storage state changes slowly. Two video-clock samples keep the fallback
// diagnostic stable while it crosses from the SD clock domain.
sync_2ff u_sdram_ready_video_sync (
    .clk      (video_clk),
    .rst_n    (video_rst_n),
    .async_in (Sdr_init_done),
    .sync_out (sdram_ready_video)
);

sync_2ff u_auto_play_video_sync (
    .clk      (video_clk),
    .rst_n    (video_rst_n),
    .async_in (auto_play_enabled),
    .sync_out (auto_play_enabled_video)
);

playback_status_cdc u_playback_status_cdc (
    .src_clk(sd_card_clk), .src_rst_n(sd_rst_n),
    .src_status(playback_status_sd),
    .dst_clk(video_clk), .dst_rst_n(video_rst_n),
    .frame_start(frame_start_video), .dst_status(playback_status_video)
);

playback_status_cdc #(.WIDTH(24)) u_loading_status_cdc (
    .src_clk(sd_card_clk), .src_rst_n(sd_rst_n), .src_status(loading_status_sd),
    .dst_clk(video_clk), .dst_rst_n(video_rst_n),
    .frame_start(frame_start_video), .dst_status(loading_status_video)
);

playback_status_cdc #(.WIDTH(7)) u_guide_status_cdc (
    .src_clk(sd_card_clk), .src_rst_n(sd_rst_n), .src_status(guide_status_sd),
    .dst_clk(video_clk), .dst_rst_n(video_rst_n),
    .frame_start(frame_start_video), .dst_status(guide_status_video)
);

sync_2ff u_thumbnail_mode_video_sync (
    .clk      (video_clk),
    .rst_n    (video_rst_n),
    .async_in (thumbnail_mode),
    .sync_out (thumbnail_mode_video)
);

// Focus is generated in the SD-card clock domain.  Synchronize it and latch
// it with the mode at a frame boundary so the border never moves mid-frame.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        thumbnail_focus_meta_video <= 3'd0;
        thumbnail_focus_sync_video <= 3'd0;
        active_thumbnail_focus_index <= 3'd0;
    end else begin
        thumbnail_focus_meta_video <= thumbnail_focus_index;
        thumbnail_focus_sync_video <= thumbnail_focus_meta_video;
        if (frame_start_video)
            active_thumbnail_focus_index <= thumbnail_focus_sync_video;
    end
end

always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        display_valid_video_meta <= 1'b0;
        display_valid_video      <= 1'b0;
        image_complete_video_meta <= 6'd0;
        image_complete_video_sync <= 6'd0;
        storage_debug_meta       <= 32'd0;
        storage_debug_video      <= 32'd0;
    end else begin
        display_valid_video_meta <= display_valid;
        display_valid_video      <= display_valid_video_meta;
        image_complete_video_meta <= image_complete_status;
        image_complete_video_sync <= image_complete_video_meta;
        storage_debug_meta       <= storage_debug_status;
        storage_debug_video      <= storage_debug_meta;
    end
end

// The diagnostic bus is generated in sd_card_clk and consumed by the board
// clock domain used by the seven-segment scanner.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        storage_diagnostic_meta <= 24'd0;
        storage_diagnostic_clk  <= 24'd0;
    end else begin
        storage_diagnostic_meta <= storage_diagnostic;
        storage_diagnostic_clk  <= storage_diagnostic_meta;
    end
end

// Apply mode and availability changes only at a frame boundary. The same
// latched mode drives the memory reader and pixel compositor for that frame.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        active_thumbnail_mode  <= 1'b0;
        active_image_complete  <= 6'd0;
    end else if (frame_start_video) begin
        active_thumbnail_mode <= thumbnail_mode_video;
        active_image_complete <= image_complete_video_sync;
    end
end

// Count active pixels for the color-bar fallback. The solid diagnostic colors
// below identify which storage stage prevents the first image from appearing.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        fallback_x <= 11'd0;
        fallback_y <= 10'd0;
    end else if (frame_start_video) begin
        fallback_x <= 11'd0;
        fallback_y <= 10'd0;
    end else if (!de) begin
        fallback_x <= 11'd0;
    end else if (fallback_x == 11'd1279) begin
        fallback_x <= 11'd0;
        if (fallback_y == 10'd719)
            fallback_y <= 10'd0;
        else
            fallback_y <= fallback_y + 10'd1;
    end else begin
        fallback_x <= fallback_x + 11'd1;
    end
end

always @(*) begin
    if (!sdram_ready_video)
        fallback_rgb = 24'hFF0000; // red: SDRAM initialization did not finish
    else if (!storage_debug_video[1])
        fallback_rgb = 24'hFFFF00; // yellow: SD-card initialization did not finish
    else if (storage_debug_video[31:24] == 8'h22)
        fallback_rgb = 24'h0000FF; // blue: one or more required PIC*.BMP files are missing
    else if (storage_debug_video[31:24] != 8'd0)
        fallback_rgb = 24'hFF00FF; // magenta: FAT32 volume scan failed
    else if ((storage_debug_video[23:16] != 8'd0) ||
             (storage_debug_video[11:9] != 3'd0) ||
             storage_debug_video[6])
        fallback_rgb = 24'hFF8000; // orange: file stream or BMP load failed
    else if (storage_debug_video[3] ||
             (storage_debug_video[2] && !storage_debug_video[4]))
        fallback_rgb = 24'h00FFFF; // cyan: FAT32 root-directory scan is active
    else if (storage_debug_video[4] &&
             (storage_debug_video[15:12] == 4'd0))
        fallback_rgb = 24'h0000FF; // blue: no PIC1.BMP..PIC6.BMP was found
    else if (storage_debug_video[5] ||
             (storage_debug_video[8:7] != 2'd0))
        fallback_rgb = 24'h00FF00; // green: BMP is being loaded into SDRAM
    else if (fallback_x < 10'd80)
        fallback_rgb = 24'hFFFFFF;
    else if (fallback_x < 10'd160)
        fallback_rgb = 24'hFFFF00;
    else if (fallback_x < 10'd240)
        fallback_rgb = 24'h00FFFF;
    else if (fallback_x < 10'd320)
        fallback_rgb = 24'h00FF00;
    else if (fallback_x < 10'd400)
        fallback_rgb = 24'hFF00FF;
    else if (fallback_x < 10'd480)
        fallback_rgb = 24'hFF0000;
    else if (fallback_x < 10'd560)
        fallback_rgb = 24'h0000FF;
    else
        fallback_rgb = 24'h000000;
end

thumbnail_layout u_thumbnail_layout (
    .in_de         (de),
    .pixel_x       ({1'd0, fallback_x}),
    .pixel_y       ({2'd0, fallback_y}),
    .focus_index   (active_thumbnail_focus_index),
    .image_complete(active_image_complete),
    .thumb_de      (thumbnail_de),
    .source_index  (thumbnail_source_index),
    .source_x      (thumbnail_source_x),
    .source_y      (thumbnail_source_y),
    .focus_border  (thumbnail_focus_border)
);

assign thumbnail_source_rgb = !active_thumbnail_mode ? vout_data_raw :
                              thumbnail_focus_border ? 24'hFFFF00 :
                              thumbnail_de ? vout_data_raw : 24'h000000;

// Autoplay uses alpha mode: old frame -> black -> new frame. Direct key bank
// changes reveal the new frame from left to right. OSD is added afterwards so
// status text remains readable throughout either transition.
assign fade_r_product = transition_source_rgb_q[23:16] * transition_fade_alpha_q;
assign fade_g_product = transition_source_rgb_q[15:8]  * transition_fade_alpha_q;
assign fade_b_product = transition_source_rgb_q[7:0]   * transition_fade_alpha_q;
assign wipe_boundary  = (wipe_ramp >= 5'd16) ? 11'd1280 :
                        (wipe_ramp * 11'd80);
assign transition_rgb = transition_wipe_active_q ?
                        (({1'b0, transition_x_q} < transition_wipe_boundary_q) ?
                         transition_source_rgb_q : 24'h000000) :
                        transition_fade_active_q ?
                        {fade_r_product[15:8], fade_g_product[15:8],
                         fade_b_product[15:8]} : transition_source_rgb_q;

// Split thumbnail selection from transition mixing. Carry matching timing,
// coordinates and validity through both stages with the pixel data.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        transition_source_rgb_q    <= 24'd0;
        transition_fallback_rgb_q  <= 24'd0;
        transition_x_q             <= 11'd0;
        transition_de_q            <= 1'b0;
        transition_vs_q            <= 1'b0;
        transition_display_valid_q <= 1'b0;
        transition_fade_active_q   <= 1'b0;
        transition_fade_alpha_q    <= 8'd0;
        transition_wipe_active_q   <= 1'b0;
        transition_wipe_boundary_q <= 11'd0;
        compositor_rgb_q          <= 24'd0;
        compositor_fallback_q     <= 24'd0;
        compositor_x_q             <= 11'd0;
        compositor_de_q           <= 1'b0;
        compositor_vs_q           <= 1'b0;
        compositor_display_valid_q <= 1'b0;
        video_axis_de_q           <= 1'b0;
        video_axis_vs_q           <= 1'b0;
        video_axis_de_d           <= 1'b0;
        video_axis_vs_d           <= 1'b0;
    end else begin
        transition_source_rgb_q    <= thumbnail_source_rgb;
        transition_fallback_rgb_q  <= fallback_rgb;
        transition_x_q             <= fallback_x;
        transition_de_q            <= de;
        transition_vs_q            <= vs;
        transition_display_valid_q <= display_valid_video;
        transition_fade_active_q   <= fade_active;
        transition_fade_alpha_q    <= fade_alpha;
        transition_wipe_active_q   <= wipe_active;
        transition_wipe_boundary_q <= wipe_boundary;
        compositor_rgb_q           <= transition_rgb;
        compositor_fallback_q      <= transition_fallback_rgb_q;
        compositor_x_q             <= transition_x_q;
        compositor_de_q            <= transition_de_q;
        compositor_vs_q            <= transition_vs_q;
        compositor_display_valid_q <= transition_display_valid_q;
        video_axis_de_d            <= osd_de;
        video_axis_de_q            <= video_axis_de_d;
        video_axis_vs_d            <= compositor_vs_q;
        video_axis_vs_q            <= video_axis_vs_d;
    end
end

// Both controls are static board switches. Sample them in the pixel domain
// and apply their two-bit settings together at the next frame boundary.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        adjust_sw_meta <= 4'd0;
        adjust_sw_sync <= 4'd0;
        adjust_sw_frame <= 4'd0;
    end else begin
        adjust_sw_meta <= image_adjust_sw;
        adjust_sw_sync <= adjust_sw_meta;
        if (frame_start_video)
            adjust_sw_frame <= adjust_sw_sync;
    end
end

always @(*) begin
    case (adjust_sw_frame[1:0])
        2'b00: brightness_video = 8'd255;
        2'b01: brightness_video = 8'd192;
        2'b10: brightness_video = 8'd64;
        default: brightness_video = 8'd128;
    endcase
    case (adjust_sw_frame[3:2])
        2'b00: contrast_video = 8'd128;
        2'b01: contrast_video = 8'd160;
        2'b10: contrast_video = 8'd255;
        default: contrast_video = 8'd192;
    endcase
end

brightness_contrast_adjust u_brightness_contrast_adjust (
    .rgb_in     (compositor_rgb_q),
    .brightness (brightness_video),
    .contrast   (contrast_video),
    .rgb_out    (adjusted_rgb)
);

assign pre_osd_data = compositor_display_valid_q ? adjusted_rgb :
                                                   compositor_fallback_q;
assign osd_error_video = (storage_debug_video[31:24] != 8'd0) ?
                         storage_debug_video[31:24] :
                         (storage_debug_video[23:16] != 8'd0) ?
                         storage_debug_video[23:16] :
                         (storage_debug_video[11:9] != 3'd0) ?
                         {5'd0, storage_debug_video[11:9]} : 8'd0;

sync_2ff u_store_closed_sync (
    .clk(video_clk), .rst_n(video_rst_n),
    .async_in(store_closed_sd), .sync_out(store_closed_video)
);

osd_overlay_24 #(
    .OSD_X (64),
    .OSD_Y (48)
) u_osd_overlay_24 (
    .clk          (video_clk),
    .rst_n        (video_rst_n),
    .vsync        (compositor_vs_q),
    .de           (compositor_de_q),
    .rgb_in       (pre_osd_data),
    .pixel_x      (compositor_x_q),
    .active_index (active_disp_buf_idx),
    .auto_enabled (auto_play_enabled_video),
    .playback_status (playback_status_video),
    .loading_status (loading_status_video),
    .guide_status   (guide_status_video),
    .store_closed (store_closed_video),
    .store_closed_active (store_closed_frame),
    .error_code   (osd_error_video),
    .brightness   (brightness_video),
    .contrast     (contrast_video),
    .rgb_out      (osd_rgb_data),
    .de_out       (osd_de),
    .osd_active   (osd_active),
    .pixel_x_out  (osd_pixel_x),
    .vsync_out    (osd_vsync)
);

// The PCM buffer already emits 48 kHz sample-valid pulses in the pixel-clock
// domain. Overlay its signed high 16 bits after the status OSD.
promax_audio_waveform #(
    .WAVE_X       (64),
    .WAVE_Y       (608),
    .WAVE_WIDTH   (512),
    .WAVE_HEIGHT  (64),
    .DECIMATE     (12),
    .SAMPLE_COUNT (32)
) u_promax_audio_waveform (
    .clk             (video_clk),
    .rst_n           (video_rst_n),
    .vsync           (osd_vsync),
    .de              (osd_de),
    .rgb_in          (osd_rgb_data),
    .pixel_x         (osd_pixel_x),
    .enable          (audio_stream_active_video && !store_closed_frame),
    .pcm_tap_valid   (pcm_audio_valid),
    .pcm_tap_left    (pcm_audio_left_data[23:8]),
    .rgb_out         (vout_data),
    .waveform_active (waveform_active)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (BUF2_ADDR),
    .read_addr_3       (BUF3_ADDR),
    .read_addr_4       (BUF4_ADDR),
    .read_addr_5       (BUF5_ADDR),
    .read_addr_index   (active_disp_buf_idx),
    .thumbnail_mode    (active_thumbnail_mode),
    .thumbnail_page    (active_thumbnail_focus_index[2]),
    .image_width_0     (image_width_0),
    .image_height_0    (image_height_0),
    .image_width_1     (image_width_1),
    .image_height_1    (image_height_1),
    .image_width_2     (image_width_2),
    .image_height_2    (image_height_2),
    .image_width_3     (image_width_3),
    .image_height_3    (image_height_3),
    .image_width_4     (image_width_4),
    .image_height_4    (image_height_4),
    .image_width_5     (image_width_5),
    .image_height_5    (image_height_5),
    // Full screen duplicates each FIFO pixel in the video clock domain;
    // thumbnails still consume one word per output pixel.
    .read_len          (active_thumbnail_mode ? 21'd921600 : 21'd460800),
    .read_en           (video_read_en),
	.read_valid        (video_read_valid),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (BUF2_ADDR),
    .write_addr_3      (BUF3_ADDR),
    .write_addr_4      (BUF4_ADDR),
    .write_addr_5      (BUF5_ADDR),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_width       (write_image_width),
    .write_height      (write_image_height),
    .write_valid_pixels(write_image_pixels),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (~mem_rst_n),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== Audio: TF-card PCM with test-tone fallback =====================
sync_2ff u_audio_stream_video_sync (
    .clk      (video_clk),
    .rst_n    (video_rst_n),
    .async_in (audio_stream_active),
    .sync_out (audio_stream_active_video)
);

// The setting changes only when KEY3 is released. Require two matching
// synchronized samples before committing the multi-bit value to audio logic.
always @(posedge video_clk or negedge video_rst_n) begin
    if (!video_rst_n) begin
        volume_gain_video_meta <= 8'd64;
        volume_gain_video_sync <= 8'd64;
        volume_gain_video_prev <= 8'd64;
        volume_gain_video      <= 8'd64;
    end else begin
        volume_gain_video_meta <= volume_gain_ctrl;
        volume_gain_video_sync <= volume_gain_video_meta;
        volume_gain_video_prev <= volume_gain_video_sync;
        if (volume_gain_video_sync == volume_gain_video_prev)
            volume_gain_video <= volume_gain_video_prev;
    end
end

pcm_stream_buffer #(
    .ADDR_WIDTH     (12),
    .SAMPLE_RATE_HZ (48000),
    .RD_CLK_HZ      (75000000)
) u_pcm_stream_buffer (
    .wr_clk        (sd_card_clk),
    .wr_rst_n      (sd_rst_n),
    .stream_enable (audio_stream_active),
    .byte_valid    (audio_pcm_byte_valid),
    .byte_data     (audio_pcm_byte),
    .fill_enable   (audio_fill_enable),
    .rd_clk        (video_clk),
    .rd_rst_n      (video_rst_n),
    // Picture transitions must not mute the independent music stream.
    // KEY3 volume is applied after the PCM/test-tone selection below.
    .gain          (8'd255),
    .pcm_valid     (pcm_audio_valid),
    .pcm_left      (pcm_audio_left_data),
    .pcm_right     (pcm_audio_right_data),
    .buffer_low    (pcm_buffer_low)
);

hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (~audio_rst_n),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (~video_rst_n),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (tone_audio_valid),
    .O_audio_left_data  (tone_audio_left_data),
    .O_audio_right_data (tone_audio_right_data)
);

audio_soft_volume u_audio_soft_volume (
    .clk(video_clk), .rst_n(video_rst_n),
    .volume(volume_gain_video), .muted(store_closed_frame),
    .pcm_requested(audio_stream_active_video),
    .pcm_valid(pcm_audio_valid), .pcm_left(pcm_audio_left_data), .pcm_right(pcm_audio_right_data),
    .tone_valid(tone_audio_valid), .tone_left(tone_audio_left_data), .tone_right(tone_audio_right_data),
    .out_valid(audio_valid), .out_left(audio_left_data), .out_right(audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (~video_rst_n),
    .I_vs          (video_axis_vs_q),
    .I_de          (video_axis_de_q),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (~video_rst_n),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 1650       ),
    .HSA                    ( 40         ),
    .HFP                    ( 110        ),
    .HBP                    ( 220        ),
    .HACTIVE                ( 1280       ),
    .VTOTAL                 ( 750        ),
    .VSA                    ( 5          ),
    .VFP                    ( 5          ),
    .VBP                    ( 20         ),
    .VACTIVE                ( 720        ),
    .VIDEO_VIC              ( 69         ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 125        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (~video_rst_n),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    // Start HDMI audio packets only after the video stream has locked. This
    // keeps audio startup from interfering with initial video acquisition.
    .I_audio_valid      (audio_valid & hdmi_video_locked),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid & hdmi_video_locked),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (hdmi_video_locked),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (~video_rst_n),
    .I_serial_rst       (~hdmi5x_rst_n),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
