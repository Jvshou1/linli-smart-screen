`timescale 1ns / 1ps

// Asynchronous assertion, synchronous de-assertion reset synchronizer.
module reset_sync(
    input  wire clk,
    input  wire ext_rst_n,
    output wire rst_n_sync
);
    (* async_reg = "true" *) reg s1;
    (* async_reg = "true" *) reg s2;

    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) begin
            s1 <= 1'b0;
            s2 <= 1'b0;
        end else begin
            s1 <= 1'b1;
            s2 <= s1;
        end
    end

    assign rst_n_sync = s2;
endmodule

// Two-flop synchronizer for a slow-changing single-bit CDC status signal.
module sync_2ff #(
    parameter RESET_VAL = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire async_in,
    output wire sync_out
);
    (* async_reg = "true" *) reg s1;
    (* async_reg = "true" *) reg s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= RESET_VAL;
            s2 <= RESET_VAL;
        end else begin
            s1 <= async_in;
            s2 <= s1;
        end
    end

    assign sync_out = s2;
endmodule
