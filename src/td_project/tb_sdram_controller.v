`timescale 1ns/1ps
// Test the vendor controller and refresh arbitration with an SDRAM pin model.
module tb_sdram_controller;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg wr=0, rd=0;
    reg [20:0] addr=0;
    reg [31:0] din=0;
    wire ready, refresh, busy, valid;
    wire [31:0] dout;
    integer i, commands=0, returned=0;
    reg [31:0] memory [0:2097151];
    reg [10:0] rows[0:3];
    integer wb=0, wc=0, wleft=0, rb=0, rc=0, rleft=0, latency=0;
    reg drive=0;
    reg [31:0] q;
    reg [7:0] pending=0;
    integer pending_addr[0:7];
    integer k;
    assign dut.SDR_DQ = drive ? q : 32'bz;
    sdram dut(.Clk(clk), .Clk_sft(~clk), .Rst(rst),
        .Sdr_init_done(ready), .Sdr_init_ref_vld(refresh), .Sdr_busy(busy),
        .App_wr_en(wr), .App_wr_addr(addr), .App_wr_dm(4'd0), .App_wr_din(din),
        .App_rd_en(rd), .App_rd_addr(addr), .Sdr_rd_en(valid), .Sdr_rd_dout(dout));
    always @(posedge dut.SDRAM_CLK) begin
        drive <= 0;
        if(wleft>0) begin
            memory[{rows[wb],2'b00,8'b0}+wb*256+wc] = dut.SDR_DQ;
            wc=wc+1; wleft=wleft-1;
        end
        if(pending[0]) begin
            q <= memory[pending_addr[0]];
            drive <= 1;
        end
        pending=pending>>1;
        for(k=0;k<7;k=k+1) pending_addr[k]=pending_addr[k+1];
        case({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE})
            3'b011: rows[dut.SDR_BA]=dut.SDR_ADDR;
            3'b100: begin
                wb=dut.SDR_BA; wc=dut.SDR_ADDR[7:0];
                memory[{rows[wb],2'b00,8'b0}+wb*256+wc]=dut.SDR_DQ;
                wc=wc+1; wleft=3;
            end
            3'b101: begin
                rb=dut.SDR_BA; rc=dut.SDR_ADDR[7:0];
                for(k=0;k<4;k=k+1) begin
                    pending[k+2]=1;
                    pending_addr[k+2]={rows[rb],2'b00,8'b0}+rb*256+rc+k;
                end
            end
        endcase
        if ({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE} != 3'b111 && commands<35) begin
            $display("CMD t=%0t cmd=%b bank=%d addr=%h busy=%b", $time,
                {dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE},dut.SDR_BA,dut.SDR_ADDR,busy);
            commands=commands+1;
        end
    end
    always @(posedge clk) if(valid) begin
        if(returned<16) $display("DATA %d %h",returned,dout);
        if(dout !== 32'h12340000+returned) $fatal(1,"data mismatch at %d got %h",returned,dout);
        returned=returned+1;
    end
    initial begin
        repeat(10) @(negedge clk); rst=0;
        wait(ready);
        repeat(100) @(negedge clk);
        for(i=0;i<256;i=i+1) begin
            wr=1; addr=i; din=32'h12340000+i;
            @(negedge clk);
        end
        wr=0;
        repeat(100) @(negedge clk);
        for(i=0;i<256;i=i+1) begin rd=1; addr=i; @(negedge clk); end
        rd=0;
        repeat(5000) @(negedge clk);
        $display("CONTROLLER returned=%0d guard=%0d busy=%b ref=%b",returned,dut.u_refresh_guard.state,busy,refresh);
        if(returned!=256 || refresh) $fatal(1,"controller stalled");
        $finish;
    end
    initial begin #3000000; $fatal(1,"timeout"); end
endmodule
