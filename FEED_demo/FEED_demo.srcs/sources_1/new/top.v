`timescale 1ns / 1ps

module top (
    input  wire clk_p,
    input  wire clk_n,
    input  wire uart_rxd,
    output wire uart_txd
);

    // Internal logic clock after divide-by-2 from the 200MHz input clock.
    localparam integer SYS_CLK_FREQ = 100_000_000;

    // ================= Clock =================
    wire clk_ibuf;
    wire clk;
    wire rst_n;

    reg [7:0] rst_cnt = 8'd0;
    reg       rst_n_reg = 1'b0;

    assign rst_n = rst_n_reg;

    IBUFDS u_ibufds_clk (
        .I (clk_p),
        .IB(clk_n),
        .O (clk_ibuf)
    );

    BUFGCE_DIV #(
        .BUFGCE_DIVIDE(2),
        .SIM_DEVICE("ULTRASCALE")
    ) u_bufgce_div (
        .I  (clk_ibuf),
        .CE (1'b1),
        .CLR(1'b0),
        .O  (clk)
    );

    // Keep reset asserted for a short time after configuration.
    always @(posedge clk) begin
        if (!rst_n_reg) begin
            rst_cnt <= rst_cnt + 8'd1;
            if (rst_cnt == 8'hFF) begin
                rst_n_reg <= 1'b1;
            end
        end
    end

    // ================= UART =================
    wire [7:0] rx_data;
    wire       rx_done;

    reg  [7:0] tx_data;
    reg        tx_start;
    wire       tx_busy;

    uart_rx #(
        .CLK_FREQ (SYS_CLK_FREQ),
        .BAUD_RATE(115200)
    ) u_uart_rx (
        .clk    (clk),
        .rst_n  (rst_n),
        .rx     (uart_rxd),
        .data_o (rx_data),
        .done_o (rx_done)
    );

    uart_tx #(
        .CLK_FREQ (SYS_CLK_FREQ),
        .BAUD_RATE(115200)
    ) u_uart_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .start_i (tx_start),
        .data_i  (tx_data),
        .tx      (uart_txd),
        .busy_o  (tx_busy)
    );

    // ================= SHA =================
    reg         sha_start;
    reg [7:0]   sha_len;
    reg [439:0] sha_data;

    wire         sha_done;
    wire [255:0] sha_digest;

    sha256_secworks_wrapper u_sha (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_i    (sha_start),
        .msg_len_i  (sha_len),
        .msg_data_i (sha_data),
        .busy_o     (),
        .done_o     (sha_done),
        .digest_o   (sha_digest)
    );

    // ================= FSM =================
    localparam S_IDLE  = 3'd0;
    localparam S_LEN_H = 3'd1;
    localparam S_LEN_L = 3'd2;
    localparam S_RECV  = 3'd3;
    localparam S_SHA   = 3'd4;
    localparam S_SEND  = 3'd5;

    reg [2:0] state = S_IDLE;

    reg [15:0] frame_len;
    reg [15:0] recv_cnt;
    reg [5:0]  send_cnt;
    reg        send_wait_busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            tx_start       <= 1'b0;
            tx_data        <= 8'h00;
            sha_start      <= 1'b0;
            sha_len        <= 8'd0;
            sha_data       <= {55{8'h00}};
            frame_len      <= 16'd0;
            recv_cnt       <= 16'd0;
            send_cnt       <= 6'd0;
            send_wait_busy <= 1'b0;
        end else begin
            tx_start  <= 1'b0;
            sha_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (rx_done) begin
                        frame_len[15:8] <= rx_data;
                        state <= S_LEN_L;
                    end
                end

                S_LEN_L: begin
                    if (rx_done) begin
                        frame_len[7:0] <= rx_data;
                        recv_cnt <= 16'd0;
                        sha_data <= {55{8'h00}};
                        state <= S_RECV;
                    end
                end

                S_RECV: begin
                    if (rx_done) begin
                        // Fill message bytes from MSB side: byte0 at [439:432]
                        if (recv_cnt < 16'd55)
                            sha_data[439 - recv_cnt*8 -: 8] <= rx_data;

                        recv_cnt <= recv_cnt + 16'd1;

                        if (recv_cnt + 16'd1 >= frame_len) begin
                            sha_len   <= (frame_len[7:0] > 8'd55) ? 8'd55 : frame_len[7:0];
                            sha_start <= 1'b1;
                            state <= S_SHA;
                        end
                    end
                end

                S_SHA: begin
                    if (sha_done) begin
                        send_cnt       <= 6'd0;
                        send_wait_busy <= 1'b0;
                        state          <= S_SEND;
                    end
                end

                S_SEND: begin
                    if (!send_wait_busy) begin
                        if (!tx_busy) begin
                            tx_data        <= sha_digest[255 - send_cnt*8 -: 8];
                            tx_start       <= 1'b1;
                            send_wait_busy <= 1'b1;
                        end
                    end else begin
                        // Wait until uart_tx leaves IDLE (busy_o goes high),
                        // then advance to the next digest byte.
                        if (tx_busy) begin
                            send_wait_busy <= 1'b0;
                            if (send_cnt == 6'd31) begin
                                state <= S_IDLE;
                            end
                            send_cnt <= send_cnt + 6'd1;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
