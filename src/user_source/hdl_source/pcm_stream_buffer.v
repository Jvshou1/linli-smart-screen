`timescale 1ns/1ps

// Byte-stream to 48 kHz PCM bridge. The writer accepts complete FAT sectors
// in bursts and pauses the next sector while fewer than 256 sample slots are
// free. Extended Gray-code pointers distinguish full from empty across clocks.
module pcm_stream_buffer #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer RD_CLK_HZ = 25000000
) (
    input  wire        wr_clk,
    input  wire        wr_rst_n,
    input  wire        stream_enable,
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    output wire        fill_enable,

    input  wire        rd_clk,
    input  wire        rd_rst_n,
    input  wire [7:0]  gain,
    output reg         pcm_valid,
    output reg  [23:0] pcm_left,
    output reg  [23:0] pcm_right,
    output wire        buffer_low
);

localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
localparam [PTR_WIDTH-1:0] DEPTH_COUNT = (1 << ADDR_WIDTH);

reg [PTR_WIDTH-1:0] wr_bin;
reg [PTR_WIDTH-1:0] rd_bin;
reg [PTR_WIDTH-1:0] wr_gray;
reg [PTR_WIDTH-1:0] rd_gray;
(* async_reg = "true" *) reg [PTR_WIDTH-1:0] rd_gray_sync1;
(* async_reg = "true" *) reg [PTR_WIDTH-1:0] rd_gray_sync2;
(* async_reg = "true" *) reg [PTR_WIDTH-1:0] wr_gray_sync1;
(* async_reg = "true" *) reg [PTR_WIDTH-1:0] wr_gray_sync2;
reg [7:0] lo_byte;
reg       lo_pending;
reg [31:0] sample_acc;
reg               sample_pending;
reg               sample_has_data;
reg               stream_enable_sync1;
reg               stream_enable_sync2;
wire [15:0]        ram_dout;
wire signed [15:0] ram_sample;
wire               ram_wr_en;
wire               ram_rd_en;
wire               sample_tick;
wire signed [24:0] gain_product;

function [PTR_WIDTH-1:0] to_gray;
    input [PTR_WIDTH-1:0] value;
    begin
        to_gray = value ^ (value >> 1);
    end
endfunction

function [PTR_WIDTH-1:0] from_gray;
    input [PTR_WIDTH-1:0] value;
    reg [PTR_WIDTH-1:0] result;
    integer i;
    begin
        result[PTR_WIDTH-1] = value[PTR_WIDTH-1];
        for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
            result[i] = result[i+1] ^ value[i];
        from_gray = result;
    end
endfunction

wire [PTR_WIDTH-1:0] rd_bin_in_wr = from_gray(rd_gray_sync2);
wire [PTR_WIDTH-1:0] wr_bin_in_rd = from_gray(wr_gray_sync2);
wire [PTR_WIDTH-1:0] used_wr = wr_bin - rd_bin_in_wr;
wire [PTR_WIDTH-1:0] used_rd = wr_bin_in_rd - rd_bin;
wire [PTR_WIDTH-1:0] free_wr = DEPTH_COUNT - used_wr;

assign fill_enable = stream_enable && (free_wr >= 256);
assign buffer_low  = (used_rd < 256);
assign sample_tick = (sample_acc + SAMPLE_RATE_HZ >= RD_CLK_HZ);
assign ram_wr_en = stream_enable && byte_valid && lo_pending &&
                   (used_wr < DEPTH_COUNT);
assign ram_rd_en = stream_enable_sync2 && sample_tick && (used_rd >= 256);
assign ram_sample = ram_dout;
assign gain_product = ram_sample * $signed({1'b0, gain});

// Reuse the TD-generated dual-port RAM template already present in this
// project. Its force_ram attribute maps the 4096x16 store into BRAM instead
// of expanding it into flip-flops or distributed logic.
ram_infer_rfifo_32_32_512 #(
    .MODE        ("SDP"),
    .DATAWIDTH_A (16),
    .ADDRWIDTH_A (ADDR_WIDTH),
    .DATAWIDTH_B (16),
    .ADDRWIDTH_B (ADDR_WIDTH),
    .REGMODE_A   ("NOREG"),
    .REGMODE_B   ("NOREG")
) u_pcm_bram (
    .clka  (wr_clk),
    .rsta  (~wr_rst_n),
    .cea   (1'b1),
    .ocea  (1'b0),
    .wea   (ram_wr_en),
    .dia   ({byte_data, lo_byte}),
    .addra (wr_bin[ADDR_WIDTH-1:0]),
    .doa   (),
    .clkb  (rd_clk),
    .rstb  (~rd_rst_n),
    .ceb   (ram_rd_en),
    .oceb  (1'b1),
    .web   (1'b0),
    .dib   (16'd0),
    .addrb (rd_bin[ADDR_WIDTH-1:0]),
    .dob   (ram_dout)
);

always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_bin        <= {PTR_WIDTH{1'b0}};
        wr_gray       <= {PTR_WIDTH{1'b0}};
        rd_gray_sync1 <= {PTR_WIDTH{1'b0}};
        rd_gray_sync2 <= {PTR_WIDTH{1'b0}};
        lo_byte       <= 8'd0;
        lo_pending    <= 1'b0;
    end else begin
        rd_gray_sync1 <= rd_gray;
        rd_gray_sync2 <= rd_gray_sync1;

        if (!stream_enable) begin
            wr_bin     <= {PTR_WIDTH{1'b0}};
            wr_gray    <= {PTR_WIDTH{1'b0}};
            lo_pending <= 1'b0;
        end else if (byte_valid) begin
            if (!lo_pending) begin
                lo_byte    <= byte_data;
                lo_pending <= 1'b1;
            end else if (used_wr < DEPTH_COUNT) begin
                wr_bin     <= wr_bin + 1'b1;
                wr_gray    <= to_gray(wr_bin + 1'b1);
                lo_pending <= 1'b0;
            end
        end
    end
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_bin        <= {PTR_WIDTH{1'b0}};
        rd_gray       <= {PTR_WIDTH{1'b0}};
        wr_gray_sync1 <= {PTR_WIDTH{1'b0}};
        wr_gray_sync2 <= {PTR_WIDTH{1'b0}};
        sample_acc    <= 32'd0;
        sample_pending <= 1'b0;
        sample_has_data <= 1'b0;
        stream_enable_sync1 <= 1'b0;
        stream_enable_sync2 <= 1'b0;
        pcm_valid     <= 1'b0;
        pcm_left      <= 24'd0;
        pcm_right     <= 24'd0;
    end else begin
        wr_gray_sync1 <= wr_gray;
        wr_gray_sync2 <= wr_gray_sync1;
        stream_enable_sync1 <= stream_enable;
        stream_enable_sync2 <= stream_enable_sync1;
        pcm_valid <= 1'b0;

        if (!stream_enable_sync2) begin
            rd_bin     <= {PTR_WIDTH{1'b0}};
            rd_gray    <= {PTR_WIDTH{1'b0}};
            sample_acc <= 32'd0;
            sample_pending <= 1'b0;
            sample_has_data <= 1'b0;
            pcm_left   <= 24'd0;
            pcm_right  <= 24'd0;
        end else begin
            if (sample_pending) begin
                // 16-bit PCM is promoted to the HDMI 24-bit range while gain
                // is applied: sample * 255 is approximately sample << 8.
                pcm_left  <= sample_has_data ? gain_product[23:0] : 24'd0;
                pcm_right <= sample_has_data ? gain_product[23:0] : 24'd0;
                pcm_valid <= 1'b1;
                sample_pending <= 1'b0;
            end

            if (sample_tick) begin
                sample_acc <= sample_acc + SAMPLE_RATE_HZ - RD_CLK_HZ;
                sample_pending <= 1'b1;
                sample_has_data <= (used_rd >= 256);
                if (used_rd >= 256) begin
                    rd_bin    <= rd_bin + 1'b1;
                    rd_gray   <= to_gray(rd_bin + 1'b1);
                end
            end else begin
                sample_acc <= sample_acc + SAMPLE_RATE_HZ;
            end
        end
    end
end

endmodule

// Gain changes run independently of sample arrivals. Source changes first
// ramp to silence, then switch and ramp back up. Nine serial shift/add steps
// per stereo sample avoid adding DSP blocks to the SDRAM-heavy design.
module audio_soft_volume #(
    parameter integer CLK_HZ = 75000000,
    parameter integer FADE_MS = 500
)(
    input wire clk, input wire rst_n,
    input wire [7:0] volume, input wire muted, input wire pcm_requested,
    input wire pcm_valid, input wire [23:0] pcm_left, pcm_right,
    input wire tone_valid, input wire [23:0] tone_left, tone_right,
    output reg out_valid, output reg [23:0] out_left, out_right
);
localparam integer STEP_RAW = (CLK_HZ / 1000) * FADE_MS / 256;
localparam integer STEP_CYCLES = STEP_RAW > 0 ? STEP_RAW : 1;
localparam integer STEP_WIDTH = STEP_CYCLES > 1 ? $clog2(STEP_CYCLES) : 1;
reg [STEP_WIDTH-1:0] step_count;
reg [8:0] current_gain;
reg source_pcm;
wire [8:0] target_gain = (muted || (source_pcm != pcm_requested)) ? 9'd0 :
                        volume == 255 ? 9'd256 : {1'b0, volume};
wire sample_valid = source_pcm ? pcm_valid : tone_valid;
wire [23:0] sample_left = source_pcm ? pcm_left : tone_left;
wire [23:0] sample_right = source_pcm ? pcm_right : tone_right;
reg busy;
reg [3:0] bit_index;
reg [8:0] multiplier;
reg [32:0] left_shift, right_shift, left_sum, right_sum;
wire [32:0] left_next = left_sum + (multiplier[0] ? left_shift : 33'd0);
wire [32:0] right_next = right_sum + (multiplier[0] ? right_shift : 33'd0);
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        step_count <= 0; current_gain <= 0; source_pcm <= 0;
        busy <= 0; bit_index <= 0; multiplier <= 0;
        left_shift <= 0; right_shift <= 0; left_sum <= 0; right_sum <= 0;
        out_valid <= 0; out_left <= 0; out_right <= 0;
    end else begin
        if (current_gain == 0 && source_pcm != pcm_requested)
            source_pcm <= pcm_requested;
        if (current_gain == target_gain) begin
            step_count <= 0;
        end else if (step_count == STEP_CYCLES - 1) begin
            step_count <= 0;
            current_gain <= current_gain < target_gain ? current_gain + 1'b1 : current_gain - 1'b1;
        end else step_count <= step_count + 1'b1;

        out_valid <= 0;
        if (!busy && sample_valid) begin
            busy <= 1;
            bit_index <= 0;
            multiplier <= current_gain;
            left_shift <= {{9{sample_left[23]}}, sample_left};
            right_shift <= {{9{sample_right[23]}}, sample_right};
            left_sum <= 0; right_sum <= 0;
        end else if (busy) begin
            left_sum <= left_next; right_sum <= right_next;
            left_shift <= left_shift << 1; right_shift <= right_shift << 1;
            multiplier <= multiplier >> 1;
            bit_index <= bit_index + 1'b1;
            if (bit_index == 8) begin
                out_left <= left_next[31:8]; out_right <= right_next[31:8];
                out_valid <= 1; busy <= 0;
            end
        end
    end
end
endmodule
