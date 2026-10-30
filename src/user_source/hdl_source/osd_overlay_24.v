`timescale 1ns / 1ps

module osd_overlay_24 #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync,
    input  wire        de,
    input  wire [23:0] rgb_in,
    input  wire [10:0] pixel_x,
    input  wire [2:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  playback_status,
    input  wire [23:0] loading_status,
    input  wire [6:0]  guide_status,
    input  wire        store_closed,
    output wire        store_closed_active,
    input  wire [7:0]  error_code,
    input  wire [7:0]  brightness,
    input  wire [7:0]  contrast,
    output reg  [23:0] rgb_out,
    output reg         de_out,
    output reg         osd_active,
    output reg  [10:0] pixel_x_out,
    output reg         vsync_out
);

reg [11:0] line_y;
reg        de_q;
reg        vs_q;
reg        de_d1;
reg        de_d2;
reg        vs_d1;
reg        vs_d2;
reg [10:0] pixel_x_d1;
reg [10:0] pixel_x_d2;
reg [23:0] rgb_d1;
reg [23:0] rgb_d2;
wire       frame_start;
wire [11:0] osd_rgb12;
wire        osd_hit;
wire [23:0] osd_rgb24;
wire        ticker_hit;
wire [23:0] ticker_rgb;
wire        countdown_hit;
wire [23:0] countdown_rgb;
wire notice_hit;
wire [23:0] notice_rgb;
wire loading_hit;
wire [23:0] loading_rgb;
wire guide_hit;
wire [23:0] guide_rgb;

assign frame_start = !vs_q && vsync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        line_y <= 12'd0;
        de_q   <= 1'b0;
        vs_q   <= 1'b1;
    end else begin
        de_q <= de;
        vs_q <= vsync;
        if (vsync)
            line_y <= 12'd0;
        else if (de_q && !de)
            line_y <= line_y + 1'b1;
    end
end

status_osd_overlay #(
    .OSD_X (OSD_X),
    .OSD_Y (OSD_Y)
) u_status_osd_overlay (
    .clk          (clk),
    .rst_n        (rst_n),
    .frame_start  (frame_start),
    .active_index (active_index),
    .auto_enabled (auto_enabled),
    .error_code   (error_code),
    .brightness   (brightness),
    .contrast     (contrast),
    .in_de        (de),
    .in_rgb       ({rgb_in[23:20], rgb_in[15:12], rgb_in[7:4]}),
    .pixel_x      ({1'b0, pixel_x}),
    .pixel_y      (line_y),
    .out_rgb      (osd_rgb12),
    .out_de       (),
    .osd_pixel    (osd_hit)
);

supermarket_ticker u_supermarket_ticker (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
    .de(de), .pixel_x(pixel_x), .pixel_y(line_y),
    .active(ticker_hit), .rgb(ticker_rgb)
);

playback_countdown_overlay u_playback_countdown (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
    .status(playback_status), .de(de), .pixel_x(pixel_x), .pixel_y(line_y),
    .active(countdown_hit), .rgb(countdown_rgb)
);

store_closed_overlay u_store_closed_overlay (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
    .enabled(store_closed), .enabled_frame(store_closed_active),
    .de(de), .pixel_x(pixel_x), .pixel_y(line_y),
    .active(notice_hit), .rgb(notice_rgb)
);

loading_status_overlay u_loading_status_overlay (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start), .status(loading_status),
    .de(de), .pixel_x(pixel_x), .pixel_y(line_y), .active(loading_hit), .rgb(loading_rgb)
);

guide_map_overlay u_guide_map_overlay (
    .clk(clk), .rst_n(rst_n), .frame_start(frame_start),
    .status((guide_status[5] && active_index != guide_status[2:0]) ?
            4'd0 : guide_status[6:3]),
    .de(de), .pixel_x(pixel_x), .pixel_y(line_y),
    .active(guide_hit), .rgb(guide_rgb)
);

assign osd_rgb24 = notice_hit ? notice_rgb : guide_hit ? guide_rgb :
                   loading_hit ? loading_rgb : countdown_hit ? countdown_rgb :
                   ticker_hit ? ticker_rgb : osd_hit ?
                   {osd_rgb12[11:8], osd_rgb12[11:8],
                    osd_rgb12[7:4],  osd_rgb12[7:4],
                    osd_rgb12[3:0],  osd_rgb12[3:0]} : rgb_d2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rgb_out     <= 24'd0;
        de_d1       <= 1'b0;
        de_d2       <= 1'b0;
        de_out      <= 1'b0;
        osd_active  <= 1'b0;
        rgb_d1      <= 24'd0;
        rgb_d2      <= 24'd0;
        pixel_x_d1  <= 11'd0;
        pixel_x_d2  <= 11'd0;
        pixel_x_out <= 11'd0;
        vs_d1       <= 1'b0;
        vs_d2       <= 1'b0;
        vsync_out   <= 1'b0;
    end else begin
        rgb_out     <= osd_rgb24;
        de_d1       <= de;
        de_d2       <= de_d1;
        de_out      <= de_d2;
        osd_active  <= notice_hit || loading_hit || guide_hit || osd_hit ||
                       ticker_hit || countdown_hit;
        rgb_d1      <= rgb_in;
        rgb_d2      <= rgb_d1;
        pixel_x_d1  <= pixel_x;
        pixel_x_d2  <= pixel_x_d1;
        pixel_x_out <= pixel_x_d2;
        vs_d1       <= vsync;
        vs_d2       <= vs_d1;
        vsync_out   <= vs_d2;
    end
end

endmodule

// Frame-locked loading summary; successful startup hides after 120 frames.
// Failures remain visible. A missing card is only described as "not ready".
module loading_status_overlay (
    input wire clk, input wire rst_n, input wire frame_start,
    input wire [23:0] status,
    input wire de, input wire [10:0] pixel_x, input wire [11:0] pixel_y,
    output reg active, output reg [23:0] rgb
);
reg [23:0] status_frame;
reg [6:0] ready_frames;
wire [3:0] state = status_frame[23:20];
wire visible = state != 15 && !(state == 5 && ready_frames == 120);
wire panel = pixel_x >= 384 && pixel_x < 896 && pixel_y >= 80 && pixel_y < 200;
wire line1 = pixel_y >= 92 && pixel_y < 124;
wire line2 = pixel_y >= 132 && pixel_y < 164;
wire text_area = pixel_x >= 416 && pixel_x < 864 && (line1 || line2);
wire [10:0] text_x = pixel_x - 11'd416;
// Register the glyph/row address before decoding the font. Look ahead one
// pixel so the extra font stage still aligns with the original two-stage
// overlay. Text starts well inside each line, after the blanking transition.
wire [10:0] font_x_next = pixel_x - 11'd415;
// Both 32-pixel text bands sit on opposite sides of y=128. Outside these
// bands the font is masked, so no wide range comparator is needed on its
// address path. Drop the vertical 2x scale bit before subtracting origins.
wire font_second_line = pixel_y[7];
wire [3:0] font_row_index = pixel_y[4:1] - (font_second_line ? 4'd2 : 4'd14);
wire [3:0] cell_index = font_x_next[8:5];
wire [6:0] text_glyph;
wire [6:0] glyph = font_second_line && cell_index == 3 ? {4'd0, status_frame[19:17]} :
                         font_second_line && cell_index == 5 ? {4'd0, status_frame[16:14]} :
                         font_second_line && cell_index == 10 ? {4'd0, status_frame[13:11]} : text_glyph;
wire [15:0] font_row;
reg [10:0] font_address_q;
loading_status_text u_text (.state(state), .second_line(font_second_line), .cell_index(cell_index), .glyph(text_glyph));
loading_status_font u_font (.clk(clk), .address(font_address_q), .row_bits(font_row));
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) font_address_q <= 0;
    else font_address_q <= {glyph, font_row_index};
end
// Constant lookup avoids both division and a long cascade of pixel-rate adds.
function [8:0] progress_width;
    input [2:0] total;
    input [3:0] count;
    begin
        if (count == 0 || total == 0) progress_width = 0;
        else if (count >= {1'b0, total}) progress_width = 432;
        else case (total)
            2: progress_width = 216;
            3: progress_width = count == 1 ? 144 : 288;
            4: case (count)
                1: progress_width = 108; 2: progress_width = 216;
                default: progress_width = 324;
            endcase
            5: case (count)
                1: progress_width = 86; 2: progress_width = 172;
                3: progress_width = 259; default: progress_width = 345;
            endcase
            6: case (count)
                1: progress_width = 72; 2: progress_width = 144;
                3: progress_width = 216; 4: progress_width = 288;
                default: progress_width = 360;
            endcase
            default: progress_width = 0;
        endcase
    end
endfunction
wire [3:0] attempted_count = {1'b0, status_frame[19:17]} + {1'b0, status_frame[13:11]};
wire [8:0] success_width = progress_width(status_frame[16:14], {1'b0, status_frame[19:17]});
wire [8:0] attempted_width = progress_width(status_frame[16:14], attempted_count);
wire bar = pixel_x >= 416 && pixel_x < 848 && pixel_y >= 176 && pixel_y < 184;
wire border = pixel_y == 80 || pixel_y == 199 || pixel_x == 384 || pixel_x == 895;
reg hit_q, text_q, bar_q, border_q, warning_q;
reg [3:0] col_q;
reg [1:0] bar_color_q;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        status_frame <= 24'h100000; ready_frames <= 0;
        hit_q <= 0; text_q <= 0; bar_q <= 0; border_q <= 0; warning_q <= 0;
        col_q <= 0; bar_color_q <= 0; active <= 0; rgb <= 0;
    end else begin
        if (frame_start) begin
            status_frame <= status;
            if (status[23:20] != 5 || state != 5) ready_frames <= 0;
            else if (ready_frames < 120) ready_frames <= ready_frames + 1'b1;
        end
        hit_q <= de && panel && visible;
        text_q <= text_area; col_q <= text_x[4:1];
        bar_q <= bar; border_q <= border;
        warning_q <= state == 2 || state >= 6;
        bar_color_q <= text_x < success_width ? 2'd1 : text_x < attempted_width ? 2'd2 : 2'd0;
        active <= hit_q;
        if (text_q && font_row[15-col_q]) rgb <= 24'hFFF1BE;
        else if (border_q) rgb <= warning_q ? 24'hE69A48 : 24'h49BAA1;
        else if (bar_q) rgb <= bar_color_q == 1 ? 24'h49BAA1 : bar_color_q == 2 ? 24'hE06B64 : 24'h354C51;
        else rgb <= 24'h162C34;
    end
end
endmodule

// Full-screen built-in notice. Two stages parallel the other overlays, so
// the video timing and SDRAM fetch pipeline remain unchanged.
module store_closed_overlay (
    input wire clk, input wire rst_n, input wire frame_start,
    input wire enabled, output reg enabled_frame,
    input wire de, input wire [10:0] pixel_x, input wire [11:0] pixel_y,
    output reg active, output reg [23:0] rgb
);
wire title = pixel_x >= 384 && pixel_x < 896 && pixel_y >= 256 && pixel_y < 384;
wire subtitle = pixel_x >= 464 && pixel_x < 816 && pixel_y >= 432 && pixel_y < 464;
wire [10:0] title_x = pixel_x - 11'd384;
wire [11:0] title_y = pixel_y - 12'd256;
wire [10:0] subtitle_x = pixel_x - 11'd464;
wire [11:0] subtitle_y = pixel_y - 12'd432;
wire [3:0] cell_index = title ? {2'b00, title_x[8:7]} : (4'd4 + subtitle_x[8:5]);
wire [3:0] glyph_row = title ? title_y[6:3] : subtitle_y[4:1];
wire [3:0] glyph_col = title ? title_x[6:3] : subtitle_x[4:1];
wire [15:0] font_row;
reg de_q, text_q, title_q, border_q;
reg [3:0] col_q;
wire border = (((pixel_x >= 64 && pixel_x < 1216) &&
                 ((pixel_y >= 136 && pixel_y < 139) || (pixel_y >= 564 && pixel_y < 567))) ||
                ((pixel_y >= 136 && pixel_y < 567) &&
                 ((pixel_x >= 64 && pixel_x < 67) || (pixel_x >= 1213 && pixel_x < 1216))) ||
                (pixel_x >= 544 && pixel_x < 736 && pixel_y >= 410 && pixel_y < 413));
store_closed_font u_font (.clk(clk), .address({cell_index, glyph_row}), .row_bits(font_row));
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        enabled_frame <= 0;
        de_q <= 0; text_q <= 0; title_q <= 0; border_q <= 0; col_q <= 0;
        active <= 0; rgb <= 0;
    end else begin
        if (frame_start)
            enabled_frame <= enabled;
        de_q <= de;
        text_q <= title || subtitle;
        title_q <= title;
        border_q <= border;
        col_q <= glyph_col;
        active <= enabled_frame && de_q;
        if (text_q && font_row[15-col_q])
            rgb <= title_q ? 24'hFFF1BE : 24'hFFF8EE;
        else if (border_q)
            rgb <= 24'hD8AF60;
        else
            rgb <= 24'h401C24;
    end
end
endmodule

// Coordinates match the 2560x1440 PIC2 store map after its 1280x720 output
// scaling. All state is frame-latched; two pipeline stages match the OSD bus.
module guide_map_overlay (
    input wire clk, input wire rst_n, input wire frame_start,
    input wire [3:0] status,
    input wire de, input wire [10:0] pixel_x, input wire [11:0] pixel_y,
    output reg active, output reg [23:0] rgb
);
reg [3:0] status_frame;
wire enabled = status_frame[3];
wire confirmed = status_frame[2];
wire [1:0] category = status_frame[1:0];
wire top_panel = pixel_x >= 128 && pixel_x < 1152 &&
                 pixel_y >= 50 && pixel_y < 132;
wire [10:0] tab_x = pixel_x - 11'd128;
wire [1:0] tab_index = tab_x[9:8];
wire [7:0] tab_local_x = tab_x[7:0];
wire tab_selected = (tab_index == category);
wire tab_border = top_panel && (tab_local_x < 3 || tab_local_x >= 253 ||
                                pixel_y < 53 || pixel_y >= 129);
wire label_area = top_panel && tab_local_x >= 80 && tab_local_x < 208 &&
                  pixel_y >= 75 && pixel_y < 107;
wire [7:0] label_x = tab_local_x - 8'd80;
wire [11:0] label_y = pixel_y - 12'd75;
wire route_panel = confirmed && pixel_x >= 64 && pixel_x < 600 &&
                   pixel_y >= 550 && pixel_y < 606;
wire route_border = route_panel && (pixel_x < 67 || pixel_x >= 597 ||
                                   pixel_y < 553 || pixel_y >= 603);
wire route_area = route_panel && pixel_x >= 88 && pixel_x < 568 &&
                  pixel_y >= 561 && pixel_y < 593;
wire [10:0] route_x = pixel_x - 11'd88;
wire [11:0] route_y = pixel_y - 12'd561;
wire text_area = label_area || route_area;
wire [1:0] text_category = route_area ? category : tab_index;
wire [3:0] text_cell = route_area ? route_x[8:5] : label_x[7:5];
wire [3:0] glyph_row = route_area ? route_y[4:1] : label_y[4:1];
wire [3:0] glyph_col = route_area ? route_x[4:1] : label_x[4:1];
wire [5:0] glyph;
wire [15:0] font_row;
reg [9:0] font_address_q;

reg [10:0] zone_x0, zone_x1;
reg [11:0] zone_y0, zone_y1;
reg route_line;
always @(*) begin
    case (category)
        2'd0: begin
            zone_x0 = 225; zone_x1 = 448; zone_y0 = 238; zone_y1 = 513;
            route_line = ((pixel_y >= 530 && pixel_y < 534 && pixel_x >= 355 && pixel_x < 860) ||
                          (pixel_x >= 353 && pixel_x < 357 && pixel_y >= 475 && pixel_y < 534));
        end
        2'd1: begin
            zone_x0 = 480; zone_x1 = 847; zone_y0 = 238; zone_y1 = 520;
            route_line = ((pixel_y >= 530 && pixel_y < 534 && pixel_x >= 675 && pixel_x < 860) ||
                          (pixel_x >= 673 && pixel_x < 677 && pixel_y >= 470 && pixel_y < 534));
        end
        2'd2: begin
            zone_x0 = 868; zone_x1 = 1122; zone_y0 = 235; zone_y1 = 520;
            route_line = ((pixel_y >= 530 && pixel_y < 534 && pixel_x >= 850 && pixel_x < 990) ||
                          (pixel_x >= 988 && pixel_x < 992 && pixel_y >= 470 && pixel_y < 534));
        end
        default: begin
            zone_x0 = 918; zone_x1 = 1097; zone_y0 = 525; zone_y1 = 636;
            route_line = (pixel_y >= 574 && pixel_y < 578 && pixel_x >= 850 && pixel_x < 970);
        end
    endcase
end
wire zone_inside = pixel_x >= zone_x0 && pixel_x < zone_x1 &&
                   pixel_y >= zone_y0 && pixel_y < zone_y1;
wire zone_border = zone_inside &&
                   (pixel_x < zone_x0 + 4 || pixel_x >= zone_x1 - 4 ||
                    pixel_y < zone_y0 + 4 || pixel_y >= zone_y1 - 4);
wire hit_now = enabled && de &&
               (top_panel || (confirmed && (route_panel || zone_border || route_line)));
reg hit_q, hit_d1, panel_q, panel_d1, text_q, text_d1;
reg border_q, border_d1, zone_q, zone_d1, path_q, path_d1;
reg selected_q, selected_d1;
reg [3:0] col_q, col_d1;

guide_map_text u_text (
    .category(text_category), .route(route_area),
    .cell_index(text_cell), .glyph(glyph)
);
guide_map_font u_font (.clk(clk), .address(font_address_q), .row_bits(font_row));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        status_frame <= 4'd0;
        font_address_q <= 10'd0;
        hit_q <= 0; hit_d1 <= 0; panel_q <= 0; panel_d1 <= 0;
        text_q <= 0; text_d1 <= 0; border_q <= 0; border_d1 <= 0;
        zone_q <= 0; zone_d1 <= 0; path_q <= 0; path_d1 <= 0;
        selected_q <= 0; selected_d1 <= 0; col_q <= 0; col_d1 <= 0;
        active <= 0; rgb <= 0;
    end else begin
        if (frame_start) status_frame <= status;
        font_address_q <= {glyph, glyph_row};
        hit_q <= hit_now;
        panel_q <= top_panel || route_panel;
        text_q <= text_area;
        border_q <= tab_border || route_border;
        zone_q <= confirmed && zone_border;
        path_q <= confirmed && route_line;
        selected_q <= tab_selected && top_panel;
        col_q <= glyph_col;
        hit_d1 <= hit_q;
        panel_d1 <= panel_q;
        text_d1 <= text_q;
        border_d1 <= border_q;
        zone_d1 <= zone_q;
        path_d1 <= path_q;
        selected_d1 <= selected_q;
        col_d1 <= col_q;
        active <= hit_d1;
        if (text_d1 && font_row[15-col_d1])
            rgb <= 24'hFFF4D8;
        else if (zone_d1)
            rgb <= 24'hFFD04E;
        else if (path_d1)
            rgb <= 24'h43E2C0;
        else if (border_d1)
            rgb <= selected_d1 ? 24'hFFD04E : 24'h567A77;
        else if (panel_d1)
            rgb <= selected_d1 ? 24'h386451 : 24'h15322F;
        else
            rgb <= 24'd0;
    end
end
endmodule

// A request/acknowledge snapshot transfers all status bits together. The SD
// side holds the payload until the next request; only toggles cross via 2FF.
module playback_status_cdc #(parameter integer WIDTH = 8) (
    input wire src_clk, input wire src_rst_n,
    input wire [WIDTH-1:0] src_status,
    input wire dst_clk, input wire dst_rst_n,
    input wire frame_start,
    output reg [WIDTH-1:0] dst_status
);
reg request;
(* async_reg = "true" *) reg [1:0] request_sync;
reg acknowledge;
reg [WIDTH-1:0] payload;
(* async_reg = "true" *) reg [1:0] acknowledge_sync;
reg acknowledge_seen;

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
        request_sync <= 0;
        acknowledge <= 0;
        payload <= 0;
    end else begin
        request_sync <= {request_sync[0], request};
        if (request_sync[1] != acknowledge) begin
            payload <= src_status;
            acknowledge <= request_sync[1];
        end
    end
end

always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        request <= 0;
        acknowledge_sync <= 0;
        acknowledge_seen <= 0;
        dst_status <= 0;
    end else begin
        acknowledge_sync <= {acknowledge_sync[0], acknowledge};
        if (frame_start && (request == acknowledge_sync[1]))
            request <= ~request;
        if (acknowledge_sync[1] != acknowledge_seen) begin
            dst_status <= payload;
            acknowledge_seen <= acknowledge_sync[1];
        end
    end
end
endmodule

// Two-stage panel runs beside the existing overlays, keeping video latency.
// 160x40 pixels at top right, 2x-scaled 5x7 text and a gold accent line.
module playback_countdown_overlay (
    input wire clk, input wire rst_n, input wire frame_start,
    input wire [7:0] status,
    input wire de, input wire [10:0] pixel_x, input wire [11:0] pixel_y,
    output reg active, output reg [23:0] rgb
);
reg [1:0] mode_frame;
reg [3:0] tens_frame, ones_frame;
wire [10:0] text_x = pixel_x - 11'd1120;
wire [11:0] text_y = pixel_y - 12'd30;
wire [3:0] char_cell = text_x[7:4];
reg [6:0] character;
reg [4:0] glyph_q;
reg [2:0] glyph_x_q;
reg band_q, text_q, accent_q, digit_q;
reg [1:0] mode_q;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_frame <= 0;
        tens_frame <= 0;
        ones_frame <= 0;
    end else if (frame_start) begin
        mode_frame <= status[7:6];
        tens_frame <= status[5:0] / 6'd10;
        ones_frame <= status[5:0] % 6'd10;
    end
end

function [4:0] font_row;
    input [6:0] ch;
    input [2:0] row;
    reg [34:0] bits;
    begin
        case (ch)
            "0": bits = {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            "1": bits = {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "2": bits = {5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            "3": bits = {5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
            "4": bits = {5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            "5": bits = {5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
            "6": bits = {5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
            "7": bits = {5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
            "8": bits = {5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            "9": bits = {5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
            "N": bits = {5'b10001,5'b11001,5'b11001,5'b10101,5'b10011,5'b10011,5'b10001};
            "E": bits = {5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            "X": bits = {5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
            "T": bits = {5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            "S": bits = {5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            "P": bits = {5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
            "A": bits = {5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "U": bits = {5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "D": bits = {5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
            "L": bits = {5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            "C": bits = {5'b01110,5'b10001,5'b10000,5'b10000,5'b10000,5'b10001,5'b01110};
            "W": bits = {5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
            "I": bits = {5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            ".": bits = {5'b00000,5'b00000,5'b00000,5'b00000,5'b00000,5'b00100,5'b00100};
            default: bits = 35'd0;
        endcase
        case (row)
            0: font_row = bits[34:30];
            1: font_row = bits[29:25];
            2: font_row = bits[24:20];
            3: font_row = bits[19:15];
            4: font_row = bits[14:10];
            5: font_row = bits[9:5];
            default: font_row = bits[4:0];
        endcase
    end
endfunction

always @(*) begin
    character = " ";
    case (mode_frame)
        1: case (char_cell)
            0: character="N"; 1: character="E"; 2: character="X"; 3: character="T";
            5: character="0"+tens_frame; 6: character="0"+ones_frame; 7: character="S";
            default: character=" ";
        endcase
        2: case (char_cell)
            0: character="P"; 1: character="A"; 2: character="U";
            3: character="S"; 4: character="E"; 5: character="D";
            default: character=" ";
        endcase
        3: case (char_cell)
            0: character="S"; 1: character="E"; 2: character="L";
            3: character="E"; 4: character="C"; 5: character="T";
            default: character=" ";
        endcase
        default: case (char_cell)
            0: character="W"; 1: character="A"; 2: character="I"; 3: character="T";
            4,5,6: character=".";
            default: character=" ";
        endcase
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        glyph_q <= 0; glyph_x_q <= 0;
        band_q <= 0; text_q <= 0; accent_q <= 0; digit_q <= 0; mode_q <= 0;
        active <= 0; rgb <= 0;
    end else begin
        glyph_q <= font_row(character, text_y[3:1]);
        glyph_x_q <= text_x[3:1];
        band_q <= de && pixel_x >= 1104 && pixel_x < 1264 &&
                  pixel_y >= 16 && pixel_y < 56;
        text_q <= pixel_x >= 1120 && pixel_x < 1248 &&
                  pixel_y >= 30 && pixel_y < 44 && text_x[3:1] < 5;
        accent_q <= pixel_y < 18;
        digit_q <= mode_frame == 1 && (char_cell == 5 || char_cell == 6);
        mode_q <= mode_frame;
        active <= band_q;
        rgb <= accent_q ? 24'hd8ad58 :
               (text_q && glyph_q[4-glyph_x_q]) ?
               (digit_q ? 24'hffe17a : mode_q == 2 ? 24'hb8c5c9 : 24'hfff1be) :
               24'h102e2c;
    end
end
endmodule
