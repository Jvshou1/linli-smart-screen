`timescale 1ns/1ps

module tb_sdram_refresh_guard;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg init_done = 1'b0;
    reg access = 1'b0;
    reg ref_active = 1'b0;
    reg controller_busy = 1'b0;
    wire request;
    wire blocked;
    integer pulses = 0;
    integer quiet = 0;
    integer i;
    reg previous_request = 1'b0;

    always #5 clk = ~clk;
    sdram_refresh_guard #(.INTERVAL(32)) dut (
        .clk(clk), .rst(rst), .init_done(init_done),
        .app_access(access), .controller_ref_active(ref_active),
        .controller_busy(controller_busy),
        .refresh_request(request), .block_access(blocked)
    );

    always @(posedge clk) begin
        if (access) quiet = 0;
        else quiet = quiet + 1;
        #1;
        if (request) begin
            if (previous_request || !blocked || quiet < 16)
                $fatal(1, "refresh must be a single pulse after drain, quiet=%0d", quiet);
            pulses = pulses + 1;
        end
        previous_request = request;
    end

    task complete_refresh;
        begin
            wait(request);
            repeat (5) @(negedge clk);
            if (!blocked) $fatal(1, "unblocked before controller accepted refresh");
            ref_active = 1'b1;
            repeat (20) begin
                @(negedge clk);
                if (!blocked || request) $fatal(1, "refresh overlap or repeated request");
            end
            ref_active = 1'b0;
            repeat (2) @(negedge clk);
            if (blocked) $fatal(1, "did not release application after refresh");
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);
        rst = 1'b0;
        repeat(4) @(negedge clk);
        if (!blocked || request) $fatal(1, "initialization guard failed");
        init_done = 1'b1;
        access = 1'b1;
        // Model an already-running burst: pending refresh must let it drain.
        repeat(256) @(negedge clk);
        if (!blocked || pulses != 0) $fatal(1, "active burst interrupted");
        access = 1'b0;
        controller_busy = 1'b1;
        repeat (40) @(negedge clk);
        if (pulses != 0) $fatal(1, "refresh issued before controller drained");
        controller_busy = 1'b0;
        complete_refresh;
        complete_refresh;
        if (pulses != 2) $fatal(1, "incorrect refresh count %0d", pulses);
        $display("REFRESH GUARD PASS: drain, single request, delayed ack, completion, repeat");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "refresh guard timeout");
    end
endmodule
