`timescale 1ns/1ps

// Requested switches fade to black before the bank is committed, then fade in.
// Bank changes that happen without a request use a left-to-right reveal. The
// caller maps autoplay to requests and manual keys to direct bank changes.
module video_fade_transition #(
    parameter integer FADE_FRAMES = 16
) (
    input  wire       ctrl_clk,
    input  wire       ctrl_rst_n,
    input  wire       next_event_in,
    output wire       next_event_out,
    output wire       fade_busy,

    input  wire       pix_clk,
    input  wire       pix_rst_n,
    input  wire       player_active,
    input  wire       frame_start,
    input  wire       index_commit,
    input  wire [2:0] active_index,
    output wire [7:0] alpha_out,
    output wire       fade_active,
    output wire       wipe_active,
    output wire [4:0] ramp_out,
    output wire [1:0] transition_kind
);

generate
if (FADE_FRAMES == 0) begin : g_bypass
    assign next_event_out  = next_event_in;
    assign fade_busy       = 1'b0;
    assign alpha_out       = 8'd255;
    assign fade_active     = 1'b0;
    assign wipe_active     = 1'b0;
    assign ramp_out        = 5'd0;
    assign transition_kind = 2'd0;
end else begin : g_transition
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_OUT  = 2'd1;
    localparam [1:0] S_HOLD = 2'd2;
    localparam [1:0] S_IN   = 2'd3;
    localparam integer STEP = 256 / FADE_FRAMES;

    reg        req_toggle;
    reg        ack_seen;
    reg        commit_sync1;
    reg        commit_sync2;
    reg        busy_sync1;
    reg        busy_sync2;

    reg [1:0]  state;
    reg [4:0]  ramp;
    reg        req_sync1;
    reg        req_sync2;
    reg        req_seen;
    reg        commit_toggle;
    reg        wipe_mode;
    reg [1:0]  wipe_kind;

    wire       fade_running;
    wire [12:0] ramp_alpha;

    assign fade_running    = (state != S_IDLE);
    assign fade_active     = fade_running;
    assign fade_busy       = busy_sync2;
    assign next_event_out  = (commit_sync2 != ack_seen);
    assign wipe_active     = (state == S_IN) && wipe_mode;
    assign ramp_out        = ramp;
    assign transition_kind = wipe_kind;
    assign ramp_alpha      = ramp * STEP;
    assign alpha_out       = (state == S_IDLE) ? 8'd255 :
                             (state == S_HOLD) ? 8'd0 :
                             wipe_active       ? 8'd255 :
                             (ramp >= FADE_FRAMES) ? 8'd255 :
                             ramp_alpha[7:0];

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            state         <= S_IDLE;
            ramp          <= 5'd0;
            req_sync1     <= 1'b0;
            req_sync2     <= 1'b0;
            req_seen      <= 1'b0;
            commit_toggle <= 1'b0;
            wipe_mode     <= 1'b0;
            wipe_kind     <= 2'd0;
        end else begin
            req_sync1 <= req_toggle;
            req_sync2 <= req_sync1;

            case (state)
                S_IDLE: begin
                    ramp      <= 5'd0;
                    wipe_mode <= 1'b0;
                    if ((req_sync2 != req_seen) && player_active) begin
                        req_seen  <= req_sync2;
                        state     <= S_OUT;
                        ramp      <= FADE_FRAMES;
                        wipe_kind <= 2'd0;
                    end else if (index_commit && player_active) begin
                        state     <= S_IN;
                        ramp      <= 5'd0;
                        wipe_mode <= 1'b1;
                        wipe_kind <= active_index[1:0];
                    end
                end

                S_OUT: begin
                    if (req_sync2 != req_seen)
                        req_seen <= req_sync2;
                    if (frame_start) begin
                        if (ramp == 0) begin
                            state         <= S_HOLD;
                            commit_toggle <= ~commit_toggle;
                        end else begin
                            ramp <= ramp - 1'b1;
                        end
                    end
                end

                S_HOLD: begin
                    if (index_commit) begin
                        state     <= S_IN;
                        ramp      <= 5'd0;
                        wipe_mode <= 1'b0;
                    end
                end

                S_IN: begin
                    if (req_sync2 != req_seen)
                        req_seen <= req_sync2;
                    if (frame_start) begin
                        if (ramp >= FADE_FRAMES) begin
                            state     <= S_IDLE;
                            wipe_mode <= 1'b0;
                        end else begin
                            ramp <= ramp + 1'b1;
                        end
                    end
                end

                default: begin
                    state     <= S_IDLE;
                    ramp      <= 5'd0;
                    wipe_mode <= 1'b0;
                end
            endcase
        end
    end

    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            req_toggle  <= 1'b0;
            ack_seen    <= 1'b0;
            commit_sync1 <= 1'b0;
            commit_sync2 <= 1'b0;
            busy_sync1  <= 1'b0;
            busy_sync2  <= 1'b0;
        end else begin
            busy_sync1   <= fade_running;
            busy_sync2   <= busy_sync1;
            commit_sync1 <= commit_toggle;
            commit_sync2 <= commit_sync1;

            if (next_event_in && !busy_sync2)
                req_toggle <= ~req_toggle;
            if (commit_sync2 != ack_seen)
                ack_seen <= commit_sync2;
        end
    end
end
endgenerate

endmodule
