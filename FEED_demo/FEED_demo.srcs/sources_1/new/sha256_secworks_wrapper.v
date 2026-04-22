`timescale 1ns / 1ps

module sha256_secworks_wrapper (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start_i,
    input  wire [7:0]      msg_len_i,            // <= 55
    input  wire [8*55-1:0] msg_data_i,           // byte0�����λ

    output reg             busy_o,
    output reg             done_o,
    output reg [255:0]     digest_o
);

    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_BUILD     = 3'd1;
    localparam [2:0] S_WAIT_RDY1 = 3'd2;
    localparam [2:0] S_START     = 3'd3;
    localparam [2:0] S_WAIT_RDY2 = 3'd4;
    localparam [2:0] S_DONE      = 3'd5;

    reg [2:0] state;

    reg         core_init;
    reg         core_next;
    reg [511:0] core_block;
    wire        core_ready;
    wire [255:0] core_digest;
    wire         core_digest_valid;

    reg         core_mode;

    integer i;

    // mode:
    // 2'b01 = SHA-256
    // 2'b00 = SHA-224
    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            busy_o   <= 1'b0;
            done_o   <= 1'b0;
            digest_o <= 256'd0;

            core_init  <= 1'b0;
            core_next  <= 1'b0;
            core_block <= 512'd0;
            core_mode  <= 1'b1;
        end else begin
            done_o    <= 1'b0;
            core_init <= 1'b0;
            core_next <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        busy_o <= 1'b1;
                        state  <= S_BUILD;
                    end
                end

                S_BUILD: begin
                    core_block <= 512'd0;
                    core_mode  <= 1'b1; // SHA-256

                    // ������Ϣ�� block ��λ
                    for (i = 0; i < 55; i = i + 1) begin
                        if (i < msg_len_i)
                            core_block[511 - i*8 -: 8] <= msg_data_i[8*(55-i)-1 -: 8];
                        else
                            core_block[511 - i*8 -: 8] <= 8'h00;
                    end

                    // ׷�� 0x80
                    core_block[511 - msg_len_i*8 -: 8] <= 8'h80;

                    // �м� padding �������㣨��ʵ�����Ѿ������ˣ����ﲻдҲ�У�

                    // ��� 64bit д�� bit length����ˣ�
                    core_block[63:0] <= ({56'd0, msg_len_i} << 3);

                    state <= S_WAIT_RDY1;
                end

                S_WAIT_RDY1: begin
                    if (core_ready) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    core_init <= 1'b1;
                    state <= S_WAIT_RDY2;
                end

                S_WAIT_RDY2: begin
                    if (core_digest_valid) begin
                        digest_o <= core_digest;
                        state    <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

    // secworks sha256 core
    sha256_core u_sha256_core (
        .clk(clk),
        .reset_n(rst_n),

        .init(core_init),
        .next(core_next),
        .mode(core_mode),

        .block(core_block),

        .ready(core_ready),
        .digest(core_digest),
        .digest_valid(core_digest_valid)
    );

endmodule
