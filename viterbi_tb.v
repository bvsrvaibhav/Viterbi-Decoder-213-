// Copyright 2025 Your Name
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//     http://www.apache.org/licenses/LICENSE-2.0
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns / 1ps

module powerhouse;

    reg clk;
    reg rst;
    reg [1:0] recv_sym;
    reg in_valid;

    wire [9:0] recv_sym_out;
    wire [9:0] corrected_codeword;
    wire [4:0] decoded_bits;
    wire done;

    integer i;

    // Input sequence: 11, 01, 00, 10, 11
    reg [1:0] input_sequence [0:4];

    // Instantiate the decoder
    coolie uut (
        .clk(clk),
        .rst(rst),
        .in_sym(recv_sym),
        .in_valid(in_valid),
        .recv_sym_out(recv_sym_out),
        .corrected_codeword(corrected_codeword),
        .decoded_bits(decoded_bits),
        .done(done)
    );

    // Clock generation
    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst = 1;
        in_valid = 0;
        recv_sym = 2'b00;
        
//        input_sequence[0] = 2'b11;
//        input_sequence[1] = 2'b11;
//        input_sequence[2] = 2'b00;
//        input_sequence[3] = 2'b10;
//        input_sequence[4] = 2'b10;

//??????????????????????????????????????????????????????????????????

        input_sequence[0] = 2'b10;
        input_sequence[1] = 2'b11;
        input_sequence[2] = 2'b00;
        input_sequence[3] = 2'b11;
        input_sequence[4] = 2'b00;

        // Initialize input sequence

//        input_sequence[0] = 2'b00;
//        input_sequence[1] = 2'b10;
//        input_sequence[2] = 2'b01;
//        input_sequence[3] = 2'b11;
//        input_sequence[4] = 2'b00;

//        input_sequence[0] = 2'b10;
//        input_sequence[1] = 2'b11;
//        input_sequence[2] = 2'b11;
//        input_sequence[3] = 2'b00;
//        input_sequence[4] = 2'b11;

        // Reset pulse
        #10 rst = 0;
        @(posedge clk);

        // Wait for FSM to enter LOAD state
        wait (uut.state == 3'd2);
        @(posedge clk); // Allow 1 more cycle

        // Feed input sequence
        for (i = 0; i < 5; i = i + 1) begin
            recv_sym = input_sequence[i];
            in_valid = 1;
            @(posedge clk);
            in_valid = 0;
            @(posedge clk);  // One cycle gap (optional)
        end

        // Wait for 'done' signal
        wait (done == 1);
        @(posedge clk); // Let FSM settle one more cycle

        // Display full result
        $display("---------------------------------------------------");
        $display("Input sequence      : %b", recv_sym_out);
        $display("Corrected codeword  : %b", corrected_codeword);
        $display("Decoded bitstream   : %b", decoded_bits);
        $display("---------------------------------------------------");

            $finish;
    end

endmodule
