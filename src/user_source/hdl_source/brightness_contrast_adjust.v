`timescale 1ns / 1ps

// Combinational pixel adjustment: no additional delay to DE/HS/VS.
module brightness_contrast_adjust (
    input  wire [23:0] rgb_in,
    input  wire [7:0]  brightness,
    input  wire [7:0]  contrast,
    output wire [23:0] rgb_out
);

function [7:0] adjust_channel;
    input [7:0] pixel;
    input [7:0] bright;
    input [7:0] ctr;
    reg [16:0] bright_sum;
    reg [16:0] bright_pixel_ext;
    reg [7:0] bright_pixel;
    reg signed [8:0] centered;
    reg signed [17:0] result;
    begin
        // The four UI brightness values are fixed binary fractions.  Keep the
        // exact 255 bypass and implement the other values with shifts/adds so
        // this path does not infer a MULT18 at the 75 MHz pixel clock.
        case (bright)
            // Keep the fixed-point radix in bit 8 for the unity-gain case.
            // The previous value left pixel in bits [7:0], then bright_pixel
            // selected [15:8], turning every default pixel into black.
            8'd255: bright_pixel_ext = ({9'd0, pixel} << 8);
            8'd192: bright_pixel_ext = ({9'd0, pixel} << 7) +
                                       ({9'd0, pixel} << 6) +
                                       {9'd0, pixel};
            8'd128: bright_pixel_ext = ({9'd0, pixel} << 7) +
                                       {9'd0, pixel};
            default: bright_pixel_ext = ({9'd0, pixel} << 6) +
                                         {9'd0, pixel};
        endcase
        bright_pixel = bright_pixel_ext[15:8];
        centered = $signed({1'b0, bright_pixel}) - 9'sd128;
        // Contrast values are also fixed points.  Arithmetic shifts preserve
        // the sign for pixels below the midpoint.
        case (ctr)
            8'd128: result = centered + 18'sd128;
            8'd160: result = centered + (centered >>> 2) + 18'sd128;
            8'd192: result = centered + (centered >>> 1) + 18'sd128;
            default: result = (centered <<< 1) - (centered >>> 7) + 18'sd128;
        endcase
        if (result < 18'sd0)
            adjust_channel = 8'd0;
        else if (result > 18'sd255)
            adjust_channel = 8'd255;
        else
            adjust_channel = result[7:0];
    end
endfunction

assign rgb_out = {
    adjust_channel(rgb_in[23:16], brightness, contrast),
    adjust_channel(rgb_in[15:8], brightness, contrast),
    adjust_channel(rgb_in[7:0], brightness, contrast)
};

endmodule
