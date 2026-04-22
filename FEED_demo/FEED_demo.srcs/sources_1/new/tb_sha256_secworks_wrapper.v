`timescale 1ns / 1ps

module tb_sha256_secworks_wrapper;

    reg         clk;
    reg         rst_n;
    reg         start_i;
    reg [7:0]   msg_len_i;
    reg [439:0] msg_data_i;

    wire        busy_o;
    wire        done_o;
    wire [255:0] digest_o;

    localparam [255:0] SHA256_ABC   = 256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad;
    localparam [255:0] SHA256_HELLO = 256'h2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824;

    // DUT
    sha256_secworks_wrapper dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start_i   (start_i),
        .msg_len_i (msg_len_i),
        .msg_data_i(msg_data_i),
        .busy_o    (busy_o),
        .done_o    (done_o),
        .digest_o  (digest_o)
    );

    // 100MHz simulation clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task run_case;
        input integer   case_id;
        input [7:0]     plen;
        input [439:0]   pdata;
        input [255:0]   pexp;
        integer timeout;
        begin
            msg_len_i  = plen;
            msg_data_i = pdata;

            @(posedge clk);
            start_i = 1'b1;
            @(posedge clk);
            start_i = 1'b0;

            timeout = 0;
            while (!done_o && timeout < 5000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end

            if (timeout >= 5000) begin
                $display("[TB][FAIL] case %0d timeout waiting done_o", case_id);
                $finish;
            end

            if (digest_o !== pexp) begin
                $display("[TB][FAIL] case %0d digest mismatch", case_id);
                $display("          exp = %h", pexp);
                $display("          got = %h", digest_o);
                $finish;
            end

            $display("[TB][PASS] case %0d digest = %h", case_id, digest_o);
            repeat (8) @(posedge clk);
        end
    endtask

    initial begin
        rst_n     = 1'b0;
        start_i   = 1'b0;
        msg_len_i = 8'd0;
        msg_data_i= {55{8'h00}};

        // Reset phase
        repeat (12) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // case 1: "abc"
        run_case(
            1,
            8'd3,
            {8'h61, 8'h62, 8'h63, {52{8'h00}}},
            SHA256_ABC
        );

        // case 2: "hello"
        run_case(
            2,
            8'd5,
            {8'h68, 8'h65, 8'h6c, 8'h6c, 8'h6f, {50{8'h00}}},
            SHA256_HELLO
        );

        $display("[TB] ALL TESTS PASSED");
        $finish;
    end

endmodule
