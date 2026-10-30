`timescale 1ns/1ps
`include "../user_source/hdl_source/include/global_def.v"

module tb_refresh_interval;
    localparam integer INTERVAL = `SELF_REFRESH_INTERVAL;

    initial begin
        $display("REFRESH_INTERVAL=%0d", INTERVAL);
        if (INTERVAL != 1562)
            $fatal(1, "100 MHz SDRAM must refresh every 1562 cycles");
        $finish;
    end
endmodule
