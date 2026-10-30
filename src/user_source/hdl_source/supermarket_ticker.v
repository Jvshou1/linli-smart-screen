`timescale 1ns / 1ps

// Two-stage overlay, parallel to status_osd_overlay: no extra video latency.
// 64 cells * 32 pixels = 2048: natural 11-bit wrapping, no divider/modulo.
module supermarket_ticker #(
    parameter integer TICKER_Y = 680,
    parameter integer SCROLL_STEP = 2
)(
    input wire clk,
    input wire rst_n,
    input wire frame_start,
    input wire de,
    input wire [10:0] pixel_x,
    input wire [11:0] pixel_y,
    output reg active,
    output reg [23:0] rgb
);

reg [10:0] scroll_phase;
wire [10:0] text_x = pixel_x + scroll_phase;
wire [11:0] text_y = pixel_y - (TICKER_Y + 4);
wire [9:0] font_address = {text_x[10:5], text_y[4:1]};
wire [15:0] font_row;
reg [3:0] glyph_x_q;
reg band_q;
reg text_q;
reg accent_q;

supermarket_ticker_font u_font (
    .clk(clk), .address(font_address), .row_bits(font_row)
);

// Advance only during vertical blanking. The same position is used for all
// lines of a frame, including when switching pictures/thumbnail pages.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        scroll_phase <= 11'd0;
    else if (frame_start)
        scroll_phase <= scroll_phase + SCROLL_STEP;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        glyph_x_q <= 4'd0;
        band_q <= 1'b0;
        text_q <= 1'b0;
        accent_q <= 1'b0;
        active <= 1'b0;
        rgb <= 24'd0;
    end else begin
        glyph_x_q <= text_x[4:1];
        band_q <= de && (pixel_x < 11'd1280) &&
                  (pixel_y >= TICKER_Y) && (pixel_y < TICKER_Y + 40);
        text_q <= (pixel_y >= TICKER_Y + 4) &&
                  (pixel_y < TICKER_Y + 36);
        accent_q <= (pixel_y < TICKER_Y + 2);
        active <= band_q;
        rgb <= accent_q ? 24'hd8ad58 :
               (text_q && font_row[15 - glyph_x_q]) ? 24'hfff1be :
               24'h102e2c;
    end
end

endmodule
