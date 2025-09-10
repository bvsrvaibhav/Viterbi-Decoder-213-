`timescale 1ns/1ps

module coolie (
    input clk,
    input rst,
    input [1:0] in_sym,
    input in_valid,
    output reg [9:0] recv_sym_out,
    output reg [9:0] corrected_codeword,
    output reg [4:0] decoded_bits,
    output reg done
);
    // Parameters
    parameter SEQ_LEN = 5;
    parameter NUM_STATES = 4;
    // Tie preference: 0 -> prefer input=0 on ties, 1 -> prefer input=1 on ties
    parameter TIE_PREF = 1;

    // FSM states
    localparam IDLE      = 3'd0,
               INIT      = 3'd1,
               LOAD      = 3'd2,
               COMPUTE   = 3'd3,
               TRACEBACK = 3'd4,
               DONE      = 3'd5;

    // internal regs
    reg [2:0] state;
    reg [2:0] cycle;       // load cycle index (0..SEQ_LEN-1)
    reg [2:0] pm_cycle;    // compute cycle index (0..SEQ_LEN-1)
    reg [1:0] current_state; // <-- DECLARED

    // Path metrics (wider so sums don't overflow small widths)
    reg [7:0] path_metric[0:NUM_STATES-1];
    reg [7:0] next_metric[0:NUM_STATES-1];

    // Survivor memory: store {tb_bit, prev_state[1:0]} (3 bits)
    // survivor[time_index][state]
    reg [2:0] survivor [0:SEQ_LEN-1][0:NUM_STATES-1];

    // Received symbols buffer (store 2-bit symbols)
    reg [1:0] recv_sym[0:SEQ_LEN-1];

    // temporary outputs
    reg [4:0] decoded_temp;
    reg [9:0] corrected_temp;

    // locals
    integer i;
    integer j;              // <-- DECLARED for nested loops
    reg [1:0] out0, out1;
    reg [7:0] m0, m1;      // candidate metrics
    reg [1:0] prev0, prev1;
    reg [7:0] min_metric;
    reg [1:0] tb_state;
    reg [2:0] survivor_entry;
    reg tb_bit;

    // ---------- Encoder function (K=3, G1=111, G2=101) ----------
    function [1:0] encode;
        input [1:0] state;
        input bit_in;
        reg [2:0] shift;
        begin
            shift = {bit_in, state};  // MSB newest
            encode[1] = shift[2] ^ shift[1] ^ shift[0]; // G1 = 111
            encode[0] = shift[2] ^ shift[0];            // G2 = 101
        end
    endfunction

    // ---------- Hamming distance for 2-bit symbols ----------
    function [1:0] hamming;
        input [1:0] a, b;
        begin
            hamming = (a[0]^b[0]) + (a[1]^b[1]);
        end
    endfunction

    // -------------------- Main FSM --------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // reset everything
            state <= IDLE;
            cycle <= 0;
            pm_cycle <= 0;
            decoded_bits <= 0;
            corrected_codeword <= 0;
            recv_sym_out <= 0;
            done <= 0;
            decoded_temp <= 0;
            corrected_temp <= 0;
            // zero path metrics (will be reinitialized in INIT)
            for (i = 0; i < NUM_STATES; i = i + 1)
                path_metric[i] <= 0;
            // clear survivor memory (optional)
            for (i = 0; i < SEQ_LEN; i = i + 1)
                for (j = 0; j < NUM_STATES; j = j + 1)
                    survivor[i][j] <= 3'b000;
        end else begin
            case (state)
                // ---------------- IDLE ----------------
                IDLE: begin
                    cycle <= 0;
                    pm_cycle <= 0;
                    decoded_bits <= 0;
                    corrected_codeword <= 0;
                    recv_sym_out <= 0;
                    done <= 0;
                    $display("State: IDLE");
                    state <= INIT;
                end

                // ---------------- INIT ----------------
                INIT: begin
                    // initialize path metrics: assume encoder started in state 00
                    for (i = 0; i < NUM_STATES; i = i + 1)
                        path_metric[i] <= (i == 0) ? 8'd0 : 8'd255; // large init for others
                    decoded_temp <= 0;
                    corrected_temp <= 0;
                    $display("INIT: Path metrics initialized");
                    state <= LOAD;
                end

                // ---------------- LOAD ----------------
                LOAD: begin
                    if (in_valid) begin
                        recv_sym[cycle] <= in_sym;
                        // pack recv symbols for display (left-shift)
                        recv_sym_out <= {recv_sym_out[7:0], in_sym};
                        $display("LOAD: cycle=%0d, in_sym=%b", cycle, in_sym);
                        cycle <= cycle + 1;
                        if (cycle == SEQ_LEN - 1) begin
                            // all symbols loaded -> start COMPUTE
                            pm_cycle <= 0;
                            state <= COMPUTE;
                        end
                    end
                end
                // ---------------- COMPUTE ----------------
                COMPUTE: begin
                    $display("------------ COMPUTE: pm_cycle=%0d ------------", pm_cycle);
                    // init next metrics to large
                    for (i = 0; i < NUM_STATES; i = i + 1)
                        next_metric[i] = 8'd255;
                    // compute for each current state i
                    for (i = 0; i < NUM_STATES; i = i + 1) begin
                        // explicit mapping of previous states that branch into state i:
                       // In COMPUTE
case(i)
    2'b00: begin prev0=2'b00; prev1=2'b11; end  // states that can lead to 00
    2'b01: begin prev0=2'b11; prev1=2'b01; end  // states that can lead to 01
    2'b10: begin prev0=2'b10; prev1=2'b01; end  // states that can lead to 10
    2'b11: begin prev0=2'b11; prev1=2'b00; end  // states that can lead to 11
endcase


                        // branch outputs for the two candidate incoming branches
                        out0 = encode(prev0, 1'b0); // branch with input=0
                        out1 = encode(prev1, 1'b1); // branch with input=1

                        // candidate metrics (add previous path metric + local hamming)
                        m0 = path_metric[prev0] + hamming(out0, recv_sym[pm_cycle]);
                        m1 = path_metric[prev1] + hamming(out1, recv_sym[pm_cycle]);

                        $display("State %b:", i[1:0]);
                        $display("  prev0=%b, in=0, encoded=%b, Hamming=%0d, Metric=%0d",
                                 prev0, out0, hamming(out0, recv_sym[pm_cycle]), m0);
                        $display("  prev1=%b, in=1, encoded=%b, Hamming=%0d, Metric=%0d",
                                 prev1, out1, hamming(out1, recv_sym[pm_cycle]), m1);

                        // selection with tie-break:
                        if (m0 < m1) begin
                            next_metric[i] = m0;
                            // store as {tb_bit, prev_state}
                            survivor[pm_cycle][i] = {1'b0, prev0};
                            $display("  Selected: input=0, path_metric=%0d", m0);
                        end
                        else if (m1 < m0) begin
                            next_metric[i] = m1;
                            survivor[pm_cycle][i] = {1'b1, prev1};
                            $display("  Selected: input=1, path_metric=%0d", m1);
                        end
                        else begin
                            // tie: first try local encoded-match preference (lower hamming)
                            if (hamming(out0, recv_sym[pm_cycle]) < hamming(out1, recv_sym[pm_cycle])) begin
                                next_metric[i] = m0;
                                survivor[pm_cycle][i] = {1'b0, prev0};
                                $display("  Tie -> chose input=0 (local match), path_metric=%0d", m0);
                            end
                            else if (hamming(out1, recv_sym[pm_cycle]) < hamming(out0, recv_sym[pm_cycle])) begin
                                next_metric[i] = m1;
                                survivor[pm_cycle][i] = {1'b1, prev1};
                                $display("  Tie -> chose input=1 (local match), path_metric=%0d", m1);
                            end
                            else begin
                                // final deterministic bias: use TIE_PREF parameter
                                if (TIE_PREF == 1) begin
                                    next_metric[i] = m1;
                                    survivor[pm_cycle][i] = {1'b1, prev1};
                                    $display("  Tie -> chose input=1 (TIE_PREF), path_metric=%0d", m1);
                                end else begin
                                    next_metric[i] = m0;
                                    survivor[pm_cycle][i] = {1'b0, prev0};
                                    $display("  Tie -> chose input=0 (TIE_PREF), path_metric=%0d", m0);
                                end
                            end
                        end
                    end // for i

                    // commit path metrics
                    for (i = 0; i < NUM_STATES; i = i + 1) begin
                        path_metric[i] <= next_metric[i];
                        $display("  -> Path Metric [%b] = %0d", i[1:0], next_metric[i]);
                    end

                    // advance or go to traceback
                    if (pm_cycle == SEQ_LEN - 1) begin
                        state <= TRACEBACK;
                    end else begin
                        pm_cycle <= pm_cycle + 1;
                    end
                end // COMPUTE

                // ---------------- TRACEBACK ----------------
                TRACEBACK: begin
                    // pick final state with minimum metric
                    min_metric = path_metric[0];
                    current_state = 2'b00;
                    for (i = 1; i < NUM_STATES; i = i + 1) begin
                        if (path_metric[i] < min_metric) begin
                            min_metric = path_metric[i];
                            current_state = i[1:0];
                        end
                    end

                    $display("------------ TRACEBACK ------------");
                    $display("Starting at state: %b (metric=%0d)", current_state, min_metric);
                    // traceback from last symbol down to first
                    for (i = SEQ_LEN - 1; i >= 0; i = i - 1) begin
                        // unpack survivor_entry where survivor = {tb_bit, prev_state[1:0]}
                        survivor_entry = survivor[i][current_state];
                        tb_bit = survivor_entry[2];        // MSB = tb_bit
                        tb_state = survivor_entry[1:0];    // LSBs = prev_state

                        // use tb_state (prev state) to reconstruct encoded output
                        decoded_temp[SEQ_LEN - 1 - i] = tb_bit;
                        corrected_temp[(SEQ_LEN - 1 - i)*2 +: 2] = encode(tb_state, tb_bit);

                        $display("Step %0d: current_state=%b, tb_bit=%b, tb_state=%b -> encoded=%b",
                                 i, current_state, tb_bit, tb_state, encode(tb_state, tb_bit));

                        // move to previous state for next traceback step
                        current_state = tb_state;
                    end

                    state <= DONE;
                end

                // ---------------- DONE ----------------
                DONE: begin
                    decoded_bits <= decoded_temp;
                    corrected_codeword <= corrected_temp;
                    done <= 1;
                    $display("------------ DONE ------------");
                    $display("Decoded Bitstream  : %b", decoded_temp);
                    $display("Corrected Codeword : %b", corrected_temp);
                    $display("Input sequence     : %b", recv_sym_out);
                    // go back to IDLE if you want to reuse
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
