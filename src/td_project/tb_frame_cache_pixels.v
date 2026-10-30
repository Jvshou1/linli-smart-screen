`timescale 1ns/1ps
// Exercise the real frame FIFOs and pixel-valid path with a memory-port model.
module tb_frame_cache_pixels;
    reg mem_clk = 0, pix_clk = 0, rst = 1;
    always #5 mem_clk = ~mem_clk;
    always #6.667 pix_clk = ~pix_clk;
    reg req = 0, de = 0, thumbnail_mode = 0;
    wire ack, pop, valid, out_de;
    wire [31:0] data;
    wire [23:0] pixel;
    wire rd;
    wire [20:0] addr;
    reg write_req=0, write_en=0;
    reg [31:0] write_data=0;
    wire write_ack, write_finish, wr;
    wire [20:0] wr_addr;
    wire [31:0] wr_data;
    integer wx, wy, a;
    wire ready, refresh, busy, returned;
    wire [31:0] returned_data;
    sdram memory_controller(.Clk(mem_clk), .Clk_sft(~mem_clk), .Rst(rst),
        .Sdr_init_done(ready), .Sdr_init_ref_vld(refresh), .Sdr_busy(busy),
        .App_wr_en(wr), .App_wr_addr(wr_addr), .App_wr_dm(4'd0), .App_wr_din(wr_data),
        .App_rd_en(rd), .App_rd_addr(addr), .Sdr_rd_en(returned), .Sdr_rd_dout(returned_data));
    sdram_pin_memory memory_model(.clk(memory_controller.SDRAM_CLK),
        .cmd({memory_controller.SDR_RAS,memory_controller.SDR_CAS,memory_controller.SDR_WE}),
        .bank(memory_controller.SDR_BA), .addr(memory_controller.SDR_ADDR),
        .dq(memory_controller.SDR_DQ));
    integer i, count = 0, row, x, expected, n;
    frame_read_write dut (
        .rst(rst), .mem_clk(mem_clk), .Sdr_init_done(ready),
        .Sdr_init_ref_vld(refresh), .Sdr_busy(busy),
        .App_rd_en(rd), .App_rd_addr(addr),
        .Sdr_rd_en(returned), .Sdr_rd_dout(returned_data),
        .read_clk(pix_clk), .read_req(req), .read_req_ack(ack),
        .read_addr_0(21'd0), .read_addr_1(21'd307200),
        .read_addr_2(21'd614400), .read_addr_3(21'd921600),
        .read_addr_4(21'd1228800), .read_addr_5(21'd1536000),
        .read_addr_index(3'd0),
        .thumbnail_mode(thumbnail_mode), .thumbnail_page(1'b0),
        .image_width_0(16'd640), .image_height_0(16'd480),
        .image_width_1(16'd640), .image_height_1(16'd480),
        .image_width_2(16'd640), .image_height_2(16'd480),
        .image_width_3(16'd640), .image_height_3(16'd480),
        .image_width_4(16'd640), .image_height_4(16'd480),
        .image_width_5(16'd640), .image_height_5(16'd480),
        .read_len(thumbnail_mode ? 21'd921600 : 21'd460800),
        .read_en(pop), .read_valid(valid), .read_data(data),
        .App_wr_en(wr), .App_wr_addr(wr_addr), .App_wr_din(wr_data),
        .write_clk(mem_clk), .write_req(write_req), .write_en(write_en),
        .write_req_ack(write_ack), .write_finish(write_finish),
        .write_len(21'd307200), .write_valid_pixels(21'd307200),
        .write_width(16'd640), .write_height(16'd480),
        .write_addr_index(3'd0), .write_data(write_data),
        .write_addr_0(21'd0), .write_addr_1(21'd307200),
        .write_addr_2(21'd614400), .write_addr_3(21'd921600),
        .write_addr_4(21'd1228800), .write_addr_5(21'd1536000)
    );
    video_delay video (
        .video_clk(pix_clk), .rst(rst), .thumbnail_mode(thumbnail_mode),
        .read_en(pop), .read_valid(valid), .read_data(data[31:8]),
        .hs(1'b0), .vs(1'b0), .de(de), .de_r(out_de), .vout_data(pixel)
    );
    always @(posedge pix_clk) begin
        #1;
        if (out_de) begin
            row = count / 1280;
            x = count % 1280;
            expected = thumbnail_mode ?
                (x >= 640 ? 307200 : 0) + (row * 480 / 360) * 640 + x % 640 + 1 :
                (row * 480 / 720) * 640 + x / 2 + 1;
            if (pixel !== expected)
                $fatal(1, "mode=%b pixel %0d got %h expected %h", thumbnail_mode, count, pixel, expected);
            count = count + 1;
        end
    end
    task check_mode;
        input mode;
        begin
            rst = 1; req = 0; count = 0; thumbnail_mode = mode;
            repeat (5) @(negedge pix_clk);
            rst = 0; req = 1;
            wait (ack);
            @(negedge pix_clk); req = 0;
            if(!mode) begin
                write_req=1;
                wait(write_ack);
                @(negedge mem_clk); write_req=0;
                repeat(16) @(negedge mem_clk);
                for(wy=479;wy>=0;wy=wy-1) for(wx=0;wx<640;wx=wx+1) begin
                    write_en=1; write_data=(wy*640+wx+1)<<8;
                    @(negedge mem_clk); write_en=0;
                    repeat(7) @(negedge mem_clk);
                end
                wait(write_finish);
                repeat(100) @(negedge mem_clk);
                for(a=0;a<307200;a=a+1) begin
                    wx=((a>>10)<<10)|(((a>>2)&3)<<8)|((a>>4&63)<<2)|(a&3);
                    if(memory_model.memory[wx] !== (a+1)<<8)
                        $fatal(1,"write mismatch app=%h pin=%h got=%h",a,wx,memory_model.memory[wx]);
                end
                $display("FRAME WRITE PASS: 307200 pixels, vertical flip, refresh");
                req=1; wait(ack); @(negedge pix_clk); req=0;
            end
            repeat (1000) @(negedge pix_clk);
            for (n = 0; n < 4; n = n + 1) begin
                de = 1;
                repeat (1280) @(negedge pix_clk);
                de = 0;
                repeat (370) @(negedge pix_clk);
            end
            if (count != 5120) $fatal(1, "wrong output count %0d", count);
        end
    endtask
    initial begin
        check_mode(0);
        check_mode(1);
        $display("FRAME CACHE PIXELS PASS: real FIFOs, full-screen and thumbnails, row boundaries");
        $finish;
    end
    initial begin #35000000; $fatal(1, "timeout"); end
endmodule

// Functional BL4/CAS3 pin model. No board timing or retention is modeled.
module sdram_pin_memory(input clk, input [2:0] cmd,
    input [1:0] bank, input [10:0] addr, inout [31:0] dq);
    reg [31:0] memory[0:2097151];
    reg [10:0] rows[0:3];
    reg drive=0;
    reg [31:0] q;
    reg [7:0] pending=0;
    integer pending_addr[0:7];
    integer k, wb=0, wc=0, wleft=0, base;
    assign dq=drive ? q : 32'bz;
    // Application address layout is {row, col[7:2], bank, col[1:0]}.
    initial for(k=0;k<2097152;k=k+1) begin
        base=(((k>>10)<<10)|((k&252)<<2)|(((k>>8)&3)<<2)|(k&3));
        memory[k]=base<307200 ? 32'hdeadbeef : (base+1)<<8;
    end
    always @(posedge clk) begin
        drive<=0;
        if(wleft>0) begin
            memory[{rows[wb],10'b0}+wb*256+wc]=dq;
            wc=wc+1; wleft=wleft-1;
        end
        if(pending[0]) begin q<=memory[pending_addr[0]]; drive<=1; end
        pending=pending>>1;
        for(k=0;k<7;k=k+1) pending_addr[k]=pending_addr[k+1];
        case(cmd)
            3'b011: rows[bank]=addr;
            3'b100: begin
                wb=bank; wc=addr[7:0];
                memory[{rows[wb],10'b0}+wb*256+wc]=dq;
                wc=wc+1; wleft=3;
            end
            3'b101: begin
                base={rows[bank],10'b0}+bank*256+addr[7:0];
                for(k=0;k<4;k=k+1) begin pending[k+2]=1; pending_addr[k+2]=base+k; end
            end
        endcase
    end
endmodule
