`timescale 1ns/1ps

module tb_frame_fifo_read_720p;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg read_req = 1'b0;
    reg thumbnail_mode = 1'b0;
    reg refresh_active = 1'b0;
    wire read_req_ack;
    wire app_rd_en;
    wire [20:0] app_rd_addr;
    integer word_count = 0;
    integer expected;

    always #5 clk = ~clk;

    frame_fifo_read #(.BURST_SIZE(8)) dut (
        .rst(rst), .mem_clk(clk), .Sdr_init_done(1'b1),
        .Sdr_init_ref_vld(refresh_active), .Sdr_busy(1'b0),
        .Sdr_rd_en(1'b0), .App_wr_busy(1'b0), .O_rd_busy(),
        .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
        .read_req(read_req), .read_req_ack(read_req_ack),
        .read_finish(),
        .read_addr_0(21'd10000), .read_addr_1(21'd400000),
        .read_addr_2(21'd800000), .read_addr_3(21'd1200000),
        .read_addr_4(21'd1600000), .read_addr_5(21'd1900000),
        .read_addr_index(3'd0), .thumbnail_mode(thumbnail_mode),
        .thumbnail_page(1'b0),
        .image_width_0(16'd640), .image_height_0(16'd480),
        .image_width_1(16'd640), .image_height_1(16'd480),
        .image_width_2(16'd640), .image_height_2(16'd480),
        .image_width_3(16'd640), .image_height_3(16'd480),
        .image_width_4(16'd640), .image_height_4(16'd480),
        .image_width_5(16'd640), .image_height_5(16'd480),
        .read_len(thumbnail_mode ? 21'd921600 : 21'd460800),
        .fifo_aclr(), .wrusedw(10'd0)
    );

    always @(posedge clk) begin
        if (rst)
            word_count = 0;
        else if (app_rd_en && word_count < 641) begin
            if (thumbnail_mode)
                expected = word_count < 640 ? 10000 + word_count : 400000;
            else
                expected = word_count < 640 ? 10000 + word_count : 10000;
            if (app_rd_addr !== expected)
                $fatal(1, "mode=%0d word=%0d addr=%0d expected=%0d",
                       thumbnail_mode, word_count, app_rd_addr, expected);
            word_count = word_count + 1;
        end
    end

    task check_mode;
        input mode;
        begin
            @(negedge clk);
            rst = 1'b1;
            read_req = 1'b0;
            thumbnail_mode = mode;
            repeat (5) @(negedge clk);
            rst = 1'b0;
            repeat (5) @(negedge clk);
            read_req = 1'b1;
            wait (read_req_ack);
            @(negedge clk);
            read_req = 1'b0;
            wait (word_count == 641);
        end
    endtask

    initial begin
        check_mode(1'b0);
        check_mode(1'b1);
        $display("FRAME FIFO READ PASS: full and thumbnail row boundaries");
        $finish;
    end

    initial begin
        wait (word_count == 8);
        @(negedge clk);
        refresh_active = 1'b1;
        repeat (18) begin
            @(negedge clk);
            if (app_rd_en)
                $fatal(1, "read burst started during refresh");
        end
        refresh_active = 1'b0;
    end

    initial begin
        #2000000;
        $fatal(1, "frame reader timeout");
    end
endmodule
