module promax_audio_waveform #(
    parameter integer WAVE_X       = 64,
    parameter integer WAVE_Y       = 400,
    parameter integer WAVE_WIDTH   = 512,
    parameter integer WAVE_HEIGHT  = 64,
    parameter integer DECIMATE     = 12,
    parameter integer SAMPLE_COUNT = 32
)(
    input                       clk,
    input                       rst_n,
    input                       vsync,
    input                       de,
    input      [23:0]           rgb_in,
    input      [10:0]           pixel_x,
    input                       enable,
    input                       pcm_tap_valid,
    input signed [15:0]         pcm_tap_left,
    output reg [23:0]           rgb_out,
    output reg                  waveform_active
);

localparam integer CENTER_Y       = WAVE_Y + (WAVE_HEIGHT / 2);
localparam integer SAMPLE_SPACING = WAVE_WIDTH / SAMPLE_COUNT;
localparam integer PEAK_X_START   = WAVE_X + WAVE_WIDTH + 8;
localparam integer PEAK_X_END     = WAVE_X + WAVE_WIDTH + 16;

reg signed [7:0] sample_bank0 [0:SAMPLE_COUNT-1];
reg signed [7:0] sample_bank1 [0:SAMPLE_COUNT-1];
reg [7:0]        peak_bank0;
reg [7:0]        peak_bank1;
reg [7:0]        display_peak;
reg              write_bank;
reg              display_bank;
reg              display_valid;
reg [5:0]        capture_count;
reg [7:0]        decimate_count;

reg [11:0] line_y;
reg        de_q;
reg        vs_q;

integer          sample_index;
reg signed [7:0] selected_sample;
integer          sample_value;
integer          sample_y;
integer          peak_height;
reg              axis_window;
reg              rail_window;
reg              peak_window;
reg [11:0]       line_y_q;
reg [11:0]       sample_y_q;
reg [23:0]       rgb_q;
reg              peak_q;
reg              axis_q;
reg              rail_q;
reg              wave_q;
reg              display_valid_q;
reg              enabled_q;
reg              wave_pixel;
reg              axis_pixel;
reg              rail_pixel;
reg              peak_pixel;
reg [23:0]       rgb_comb;
reg              waveform_active_comb;

wire frame_start;
wire [7:0] sample_abs;

assign frame_start = !vs_q && vsync;
assign sample_abs = pcm_tap_left[15] ?
                    (~pcm_tap_left[15:8] + 1'b1) : pcm_tap_left[15:8];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        line_y          <= 12'd0;
        de_q            <= 1'b0;
        vs_q            <= 1'b0;
        write_bank      <= 1'b0;
        display_bank    <= 1'b1;
        display_valid   <= 1'b0;
        capture_count   <= 6'd0;
        decimate_count  <= 8'd0;
        peak_bank0      <= 8'd0;
        peak_bank1      <= 8'd0;
        display_peak    <= 8'd0;
    end else begin
        de_q <= de;
        vs_q <= vsync;

        if (vsync)
            line_y <= 12'd0;
        else if (de_q && !de)
            line_y <= line_y + 1'b1;

        if (!enable) begin
            write_bank     <= 1'b0;
            display_bank   <= 1'b1;
            display_valid  <= 1'b0;
            capture_count  <= 6'd0;
            decimate_count <= 8'd0;
            peak_bank0     <= 8'd0;
            peak_bank1     <= 8'd0;
            display_peak   <= 8'd0;
        end else if (frame_start) begin
            if (capture_count == SAMPLE_COUNT) begin
                display_bank  <= write_bank;
                display_valid <= 1'b1;
                display_peak  <= write_bank ? peak_bank1 : peak_bank0;
                write_bank    <= ~write_bank;
            end

            capture_count  <= 6'd0;
            decimate_count <= 8'd0;
            if (write_bank)
                peak_bank0 <= 8'd0;
            else
                peak_bank1 <= 8'd0;
        end else if (pcm_tap_valid && capture_count < SAMPLE_COUNT) begin
            if (decimate_count == 0) begin
                if (write_bank)
                    sample_bank1[capture_count] <= pcm_tap_left[15:8];
                else
                    sample_bank0[capture_count] <= pcm_tap_left[15:8];

                capture_count  <= capture_count + 1'b1;
                decimate_count <= DECIMATE - 1;
                if (write_bank) begin
                    if (sample_abs > peak_bank1)
                        peak_bank1 <= sample_abs;
                end else begin
                    if (sample_abs > peak_bank0)
                        peak_bank0 <= sample_abs;
                end
            end else begin
                decimate_count <= decimate_count - 1'b1;
            end
        end
    end
end

always @(*) begin
    sample_index    = 0;
    selected_sample = 8'sd0;
    sample_value    = 0;
    sample_y        = CENTER_Y;
    peak_height     = display_peak >> 2;
    axis_window     = 1'b0;
    rail_window     = 1'b0;
    peak_window     = 1'b0;

    if (enable && de &&
        (pixel_x >= WAVE_X) && (pixel_x < WAVE_X + WAVE_WIDTH) &&
        (line_y >= WAVE_Y) && (line_y < WAVE_Y + WAVE_HEIGHT)) begin
        axis_window  = (line_y == CENTER_Y) && (pixel_x[3:0] < 4);
        rail_window  = ((line_y == WAVE_Y) ||
                        (line_y == WAVE_Y + WAVE_HEIGHT - 1));
        sample_index = (pixel_x - WAVE_X) / SAMPLE_SPACING;
        if (display_valid && sample_index < SAMPLE_COUNT)
            selected_sample = display_bank ? sample_bank1[sample_index] :
                                             sample_bank0[sample_index];
        sample_value = $signed(selected_sample);
        sample_y     = CENTER_Y - (sample_value / 4);
    end

    if (enable && de && display_valid &&
        (pixel_x >= PEAK_X_START) && (pixel_x < PEAK_X_END) &&
        (line_y >= WAVE_Y + WAVE_HEIGHT - peak_height) &&
        (line_y < WAVE_Y + WAVE_HEIGHT))
        peak_window = 1'b1;
end

always @(*) begin
    wave_pixel = enabled_q && wave_q &&
                 (line_y_q >= ((sample_y_q < CENTER_Y) ? sample_y_q : CENTER_Y)) &&
                 (line_y_q <= ((sample_y_q > CENTER_Y) ? sample_y_q : CENTER_Y));
    axis_pixel = enabled_q && axis_q;
    rail_pixel = enabled_q && rail_q;
    peak_pixel = enabled_q && display_valid_q && peak_q;
    waveform_active_comb = wave_pixel || axis_pixel || rail_pixel || peak_pixel;
    rgb_comb = wave_pixel ? 24'h34eac4 :
               peak_pixel ? 24'hffbc58 :
               axis_pixel ? 24'h416668 :
               rail_pixel ? 24'h28474b : rgb_q;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        line_y_q        <= 12'd0;
        sample_y_q      <= CENTER_Y;
        rgb_q           <= 24'd0;
        peak_q          <= 1'b0;
        axis_q          <= 1'b0;
        rail_q          <= 1'b0;
        wave_q          <= 1'b0;
        display_valid_q <= 1'b0;
        enabled_q       <= 1'b0;
        rgb_out         <= 24'd0;
        waveform_active <= 1'b0;
    end else begin
        line_y_q        <= line_y;
        sample_y_q      <= sample_y;
        rgb_q           <= rgb_in;
        peak_q          <= peak_window;
        axis_q          <= axis_window;
        rail_q          <= rail_window;
        wave_q          <= enable && de && display_valid &&
                           (pixel_x[3:0] >= 4) &&
                           (pixel_x[3:0] < 10) &&
                           (pixel_x >= WAVE_X) &&
                           (pixel_x < WAVE_X + WAVE_WIDTH) &&
                           (line_y >= WAVE_Y) &&
                           (line_y < WAVE_Y + WAVE_HEIGHT) &&
                           (sample_index < SAMPLE_COUNT);
        display_valid_q <= display_valid;
        enabled_q       <= enable;

        rgb_out         <= rgb_comb;
        waveform_active <= waveform_active_comb;
    end
end

endmodule
