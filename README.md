# Viterbi Decoder (Hard Decision, Verilog)

This repository contains a Verilog implementation of a hard-decision Viterbi decoder for a convolutional code. The design demonstrates how the classical blocks of a Viterbi decoder can be realized in RTL: the Branch Metric Unit (BMU), the Path Metric Unit (PMU) with Add-Compare-Select Unit (ACSU), and the Traceback Unit (TBU). Together, these blocks allow the decoder to recover the most likely transmitted bitstream from noisy received symbols.

The convolutional code used is a rate 1/2 code with constraint length 3. Two generator polynomials are applied: G1 = 111 (octal 7) and G2 = 101 (octal 5). At the transmitter, each input bit is expanded into two encoded bits. At the receiver, the Viterbi decoder compares the received 2-bit symbols against all possible encoder outputs and selects the path that minimizes the accumulated error.

# Branch Metric Unit (BMU)

This block measures how closely the received symbol matches the expected encoded output for each possible transition.

In this project, the BMU is implemented using Hamming distance between the received 2-bit symbol and the possible encoder outputs.

# Path Metric Unit / Add-Compare-Select (PMU/ACSU)

The path metrics are updated by adding the branch metric to the accumulated metric from the previous state.

The ACSU compares candidate paths leading into the same state and selects the survivor path with the smallest accumulated metric.

Tie-breaking is handled deterministically using the TIE_PREF parameter, ensuring consistent results.

# Traceback Unit (TBU)

Once all received symbols are processed, the traceback unit works backward through survivor memory.

At each step, it recovers the most likely input bit and reconstructs the corrected codeword.

This ensures that the final decoded bitstream corresponds to the maximum-likelihood path.

The decoder operates as a finite state machine. It begins in IDLE, initializes path metrics in INIT, loads symbols during LOAD, computes metrics and survivors in COMPUTE, and finally reconstructs the sequence in TRACEBACK before asserting results in the DONE state.

The testbench (powerhouse.v) provides stimulus to the decoder. It defines a sequence of received symbols, feeds them into the FSM, and prints the decoded bitstream, corrected codeword, and received sequence. The testbench is easily customizable for trying different input patterns or simulating noise conditions.

In summary, this project ties together the BMU, PMU/ACSU, and TBU blocks into a functional Viterbi decoder, demonstrating maximum-likelihood sequence estimation in hardware. It serves as both a learning tool and a reference implementation for digital communication system design.
