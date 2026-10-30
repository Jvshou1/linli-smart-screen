`timescale 1ns/1ps

// KEY3 is active low. A short press advances the five-step volume setting;
// holding for at least one second advances the slideshow period on release.
// Period levels: 0=2s, 1=5s, 2=10s, 3=per-image dwell (power-on default).
module param_menu_controller #(
    parameter integer CLKS_PER_MS = 100_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_HOLD_MS = 1000
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key1_n,
    input  wire       key3_n,
    input  wire       config_valid,
    input  wire [2:0] config_volume_level,
    output reg  [7:0] volume_gain,
    output reg  [1:0] period_level
);

localparam [31:0] DEBOUNCE_CYCLES = DEBOUNCE_MS * CLKS_PER_MS;
localparam [31:0] LONG_HOLD_CYCLES = LONG_HOLD_MS * CLKS_PER_MS;

(* async_reg = "true" *) reg [1:0] key_sync;
(* async_reg = "true" *) reg [1:0] key1_sync;
reg        key_stable;
reg        key1_stable;
reg [31:0] debounce_count;
reg [31:0] key1_debounce_count;
reg        combo_seen;
reg [31:0] hold_count;
reg        press_active;
reg [2:0]  volume_level;
reg        config_seen;

wire [2:0] next_volume_level = (volume_level == 3'd4) ?
                               3'd0 : volume_level + 3'd1;
wire [1:0] next_period_level = (period_level == 2'd3) ?
                               2'd0 : period_level + 2'd1;

function [7:0] volume_lut;
    input [2:0] level;
    begin
        case (level)
            3'd0:    volume_lut = 8'd0;
            3'd1:    volume_lut = 8'd64;
            3'd2:    volume_lut = 8'd128;
            3'd3:    volume_lut = 8'd192;
            default: volume_lut = 8'd255;
        endcase
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_sync       <= 2'b11;
        key1_sync      <= 2'b11;
        key_stable     <= 1'b1;
        key1_stable    <= 1'b1;
        debounce_count <= 32'd0;
        key1_debounce_count <= 32'd0;
    end else begin
        key_sync <= {key_sync[0], key3_n};
        key1_sync <= {key1_sync[0], key1_n};

        if (key_sync[1] == key_stable) begin
            debounce_count <= 32'd0;
        end else if (debounce_count >= DEBOUNCE_CYCLES - 1'b1) begin
            key_stable     <= key_sync[1];
            debounce_count <= 32'd0;
        end else begin
            debounce_count <= debounce_count + 1'b1;
        end
        if (key1_sync[1] == key1_stable) begin
            key1_debounce_count <= 32'd0;
        end else if (key1_debounce_count >= DEBOUNCE_CYCLES - 1'b1) begin
            key1_stable <= key1_sync[1];
            key1_debounce_count <= 32'd0;
        end else begin
            key1_debounce_count <= key1_debounce_count + 1'b1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        volume_level <= 3'd1;
        volume_gain  <= 8'd64;
        period_level <= 2'd3;
        hold_count   <= 32'd0;
        press_active <= 1'b0;
        config_seen  <= 1'b0;
        combo_seen   <= 1'b0;
    end else if (config_valid && !config_seen) begin
        config_seen  <= 1'b1;
        volume_level <= (config_volume_level <= 3'd4) ? config_volume_level : 3'd1;
        volume_gain  <= volume_lut((config_volume_level <= 3'd4) ?
                                   config_volume_level : 3'd1);
    end else if (!press_active) begin
        hold_count <= 32'd0;
        if (!key_stable && !key1_stable)
            combo_seen <= 1'b1;
        else if (key_stable && key1_stable)
            combo_seen <= 1'b0;
        if (!key_stable)
            press_active <= 1'b1;
    end else if (!key_stable) begin
        if (!key1_stable)
            combo_seen <= 1'b1;
        if (hold_count < LONG_HOLD_CYCLES)
            hold_count <= hold_count + 1'b1;
    end else begin
        press_active <= 1'b0;
        hold_count   <= 32'd0;

        if (combo_seen || !key1_stable) begin
            // The KEY1+KEY3 gesture owns this entire KEY3 press.
        end else if (hold_count >= LONG_HOLD_CYCLES) begin
            period_level <= next_period_level;
        end else begin
            volume_level <= next_volume_level;
            volume_gain  <= volume_lut(next_volume_level);
        end
    end
end

endmodule
