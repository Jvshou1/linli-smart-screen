`timescale 1ns / 1ps

module status_osd_overlay #(
    parameter integer OSD_X = 8,
    parameter integer OSD_Y = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_start,
    input  wire [2:0]  active_index,
    input  wire        auto_enabled,
    input  wire [7:0]  error_code,
    input  wire [7:0]  brightness,
    input  wire [7:0]  contrast,
    input  wire        in_de,
    input  wire [11:0] in_rgb,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    output reg  [11:0] out_rgb,
    output reg         out_de,
    output reg         osd_pixel
);

localparam [11:0] OSD_X_START = OSD_X;
localparam [11:0] OSD_X_END   = OSD_X + 32;
localparam [11:0] OSD_Y0      = OSD_Y;
localparam [11:0] OSD_Y1      = OSD_Y + 12;
localparam [11:0] OSD_Y2      = OSD_Y + 24;

reg [2:0] index_q;
reg       auto_q;
reg [7:0] error_q;

reg [3:0] char_value;
reg [2:0] char_row;
reg [2:0] glyph_x;
reg [4:0] local_x;
reg       glyph_enable;
reg       glyph_is_error;
reg [11:0] in_rgb_q;
reg        in_de_q;
reg [3:0] char_value_q;
reg [2:0] char_row_q;
reg [2:0] glyph_x_q;
reg       glyph_enable_q;
reg       glyph_is_error_q;
reg       osd_backdrop_q;
reg [11:0] out_rgb_q;
reg        osd_pixel_q;
reg        out_de_q;
wire x_in_osd = (pixel_x >= OSD_X_START) && (pixel_x < OSD_X_END);
wire y_in_band0 = (pixel_y >= OSD_Y0) && (pixel_y < OSD_Y0 + 12'd7);
wire y_in_band1 = (pixel_y >= OSD_Y1) && (pixel_y < OSD_Y1 + 12'd7);
wire y_in_band2 = (pixel_y >= OSD_Y2) && (pixel_y < OSD_Y2 + 12'd7);
wire osd_backdrop = in_de &&
                    (pixel_x >= OSD_X_START - 12'd4) &&
                    (pixel_x < OSD_X_END + 12'd4) &&
                    (pixel_y >= OSD_Y0 - 12'd4) &&
                    (pixel_y < OSD_Y2 + 12'd11);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        index_q <= 3'd0;
        auto_q  <= 1'b0;
        error_q <= 8'd0;
    end else if (frame_start) begin
        index_q <= active_index;
        auto_q  <= auto_enabled;
        error_q <= error_code;
    end
end

function [4:0] font_row;
    input [3:0] value;
    input [2:0] row;
    begin
        case (value)
            4'h0: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b10001;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b11111;
            endcase
            4'h1: case (row)
                0: font_row=5'b00100; 1: font_row=5'b01100;
                2: font_row=5'b00100; 3: font_row=5'b00100;
                4: font_row=5'b00100; 5: font_row=5'b00100;
                default: font_row=5'b11111;
            endcase
            4'h2: case (row)
                0: font_row=5'b11111; 1: font_row=5'b00001;
                2: font_row=5'b00001; 3: font_row=5'b11111;
                4: font_row=5'b10000; 5: font_row=5'b10000;
                default: font_row=5'b11111;
            endcase
            4'h3: case (row)
                0: font_row=5'b11111; 1: font_row=5'b00001;
                2: font_row=5'b00001; 3: font_row=5'b11111;
                4: font_row=5'b00001; 5: font_row=5'b00001;
                default: font_row=5'b11111;
            endcase
            4'h4: case (row)
                0: font_row=5'b10001; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b11111;
                4: font_row=5'b00001; 5: font_row=5'b00001;
                default: font_row=5'b00001;
            endcase
            4'h5: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10000;
                2: font_row=5'b10000; 3: font_row=5'b11111;
                4: font_row=5'b00001; 5: font_row=5'b00001;
                default: font_row=5'b11111;
            endcase
            4'h6: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10000;
                2: font_row=5'b10000; 3: font_row=5'b11111;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b11111;
            endcase
            4'h7: case (row)
                0: font_row=5'b11111; 1: font_row=5'b00001;
                2: font_row=5'b00010; 3: font_row=5'b00100;
                4: font_row=5'b01000; 5: font_row=5'b01000;
                default: font_row=5'b01000;
            endcase
            4'h8: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b11111;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b11111;
            endcase
            4'h9: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b11111;
                4: font_row=5'b00001; 5: font_row=5'b00001;
                default: font_row=5'b11111;
            endcase
            4'ha: case (row)
                0: font_row=5'b01110; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b11111;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b10001;
            endcase
            4'hb: case (row)
                0: font_row=5'b11110; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b11110;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b11110;
            endcase
            4'hc: case (row)
                0: font_row=5'b01111; 1: font_row=5'b10000;
                2: font_row=5'b10000; 3: font_row=5'b10000;
                4: font_row=5'b10000; 5: font_row=5'b10000;
                default: font_row=5'b01111;
            endcase
            4'hd: case (row)
                0: font_row=5'b11110; 1: font_row=5'b10001;
                2: font_row=5'b10001; 3: font_row=5'b10001;
                4: font_row=5'b10001; 5: font_row=5'b10001;
                default: font_row=5'b11110;
            endcase
            4'he: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10000;
                2: font_row=5'b10000; 3: font_row=5'b11110;
                4: font_row=5'b10000; 5: font_row=5'b10000;
                default: font_row=5'b11111;
            endcase
            4'hf: case (row)
                0: font_row=5'b11111; 1: font_row=5'b10000;
                2: font_row=5'b10000; 3: font_row=5'b11110;
                4: font_row=5'b10000; 5: font_row=5'b10000;
                default: font_row=5'b10000;
            endcase
            default: font_row=5'b00000;
        endcase
    end
endfunction

wire [4:0] glyph_row_q = font_row(char_value_q, char_row_q);

always @(*) begin
    char_value = 4'h0;
    char_row  = 3'd0;
    glyph_x   = 3'd0;
    local_x   = 5'd0;
    glyph_enable = 1'b0;
    glyph_is_error = 1'b0;

    if (x_in_osd && y_in_band0) begin
        local_x  = pixel_x - OSD_X_START;
        glyph_x  = local_x[2:0];
        char_row = pixel_y - OSD_Y0;
        case (local_x[4:3])
            2'd0: char_value = {1'b0, index_q} + 4'd1;
            2'd1: char_value = auto_q ? 4'ha : 4'he;
            2'd2: char_value = error_q[7:4];
            default: char_value = error_q[3:0];
        endcase
        glyph_enable = (glyph_x < 3'd5) && (char_row < 3'd7);
        glyph_is_error = (local_x[4:3] >= 2'd2) && (error_q != 8'd0);
    end else if (x_in_osd && y_in_band1) begin
        local_x  = pixel_x - OSD_X_START;
        glyph_x  = local_x[2:0];
        char_row = pixel_y - OSD_Y1;
        case (local_x[4:3])
            2'd0: char_value = 4'hb;
            2'd1: char_value = brightness[7:4];
            default: char_value = brightness[3:0];
        endcase
        glyph_enable = (glyph_x < 3'd5) && (char_row < 3'd7) &&
                       (local_x[4:3] != 2'd3);
    end else if (x_in_osd && y_in_band2) begin
        local_x  = pixel_x - OSD_X_START;
        glyph_x  = local_x[2:0];
        char_row = pixel_y - OSD_Y2;
        case (local_x[4:3])
            2'd0: char_value = 4'hc;
            2'd1: char_value = contrast[7:4];
            default: char_value = contrast[3:0];
        endcase
        glyph_enable = (glyph_x < 3'd5) && (char_row < 3'd7) &&
                       (local_x[4:3] != 2'd3);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_rgb_q    <= 12'd0;
        in_de_q     <= 1'b0;
        char_value_q <= 4'd0;
        char_row_q <= 3'd0;
        glyph_x_q <= 3'd0;
        glyph_enable_q <= 1'b0;
        glyph_is_error_q <= 1'b0;
        osd_backdrop_q <= 1'b0;
        out_rgb_q <= 12'd0;
        osd_pixel_q <= 1'b0;
        out_de_q <= 1'b0;
    end else begin
        in_rgb_q    <= in_rgb;
        in_de_q     <= in_de;
        char_value_q <= char_value;
        char_row_q <= char_row;
        glyph_x_q <= glyph_x;
        glyph_enable_q <= glyph_enable;
        glyph_is_error_q <= glyph_is_error;
        osd_backdrop_q <= osd_backdrop;
        osd_pixel_q <= (glyph_enable_q && in_de_q &&
                        glyph_row_q[4 - glyph_x_q]) || osd_backdrop_q;
        out_rgb_q <= (glyph_enable_q && in_de_q &&
                      glyph_row_q[4 - glyph_x_q]) ?
                     (glyph_is_error_q ? 12'hf44 : 12'hff0) :
                     osd_backdrop_q ? 12'h111 : in_rgb_q;
        out_de_q <= in_de_q;
    end
end

always @(*) begin
    out_rgb = out_rgb_q;
    out_de = out_de_q;
    osd_pixel = osd_pixel_q;
end

endmodule
