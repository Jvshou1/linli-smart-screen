module thumbnail_layout #(
    parameter integer DISPLAY_WIDTH  = 1280,
    parameter integer DISPLAY_HEIGHT = 720,
    parameter integer THUMB_WIDTH    = 640,
    parameter integer THUMB_HEIGHT   = 360
)(
    input  wire        in_de,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [2:0]  focus_index,
    input  wire [5:0]  image_complete,
    output reg         thumb_de,
    output reg  [2:0]  source_index,
    output reg  [9:0]  source_x,
    output reg  [9:0]  source_y,
    output reg         focus_border
);

reg [11:0] local_x;
reg [11:0] local_y;
reg [2:0]  quadrant_index;

always @(*) begin
    thumb_de     = 1'b0;
    source_index = 3'd0;
    source_x     = 10'd0;
    source_y     = 10'd0;
    focus_border = 1'b0;
    local_x      = 12'd0;
    local_y      = 12'd0;
    quadrant_index = 3'd0;

    // The four previews fill the complete 1280x720 active area as a 2x2 grid.
    if (in_de && (pixel_x < DISPLAY_WIDTH) &&
        (pixel_y < DISPLAY_HEIGHT) &&
        (pixel_x < (2 * THUMB_WIDTH)) &&
        (pixel_y < (2 * THUMB_HEIGHT))) begin
        // The active image is a fixed 2x2 grid. Keep this logic made only of
        // comparisons and subtractors; the actual source-pixel scaling is
        // performed by frame_fifo_read, so the source coordinate outputs are
        // diagnostic only.
        quadrant_index = (pixel_y >= 12'd360) ? 3'd2 : 3'd0;
        if (pixel_x >= 12'd640)
            quadrant_index = quadrant_index + 3'd1;
        source_index = quadrant_index;
        if (focus_index >= 3'd4)
            source_index = quadrant_index + 3'd4;

        local_x = (pixel_x >= 12'd640) ? (pixel_x - 12'd640) : pixel_x;
        local_y = (pixel_y >= 12'd360) ? (pixel_y - 12'd360) : pixel_y;

        if ((source_index < 3'd6) && image_complete[source_index]) begin
            thumb_de = 1'b1;
            source_x = local_x[9:0];
            source_y = local_y[9:0];
            focus_border = (source_index == focus_index) &&
                           ((local_x < 12'd2) || (local_y < 12'd2) ||
                            (local_x >= 12'd638) || (local_y >= 12'd358));
        end
    end
end

endmodule
