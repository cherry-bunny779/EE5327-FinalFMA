`timescale 1ns / 1ps

// Testbench for IEEE 754 Double-Precision Fused Multiply-Add
module tb_dp_fma;

    //==========================================================================
    // Signals
    //==========================================================================
    logic [63:0] a, b, c;
    logic [63:0] result;
    logic        overflow;
    logic        underflow;
    logic        nan_out;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    dp_fma dut (
        .a        (a),
        .b        (b),
        .c        (c),
        .result   (result),
        .overflow (overflow),
        .underflow(underflow),
        .nan_out  (nan_out)
    );

    //==========================================================================
    // Helper: convert DP bits to real for printing
    //==========================================================================
    function real dp_to_real(input [63:0] hex_val);
        logic        sign;
        logic [10:0] exp;
        logic [51:0] mant;
        real         res;

        sign = hex_val[63];
        exp  = hex_val[62:52];
        mant = hex_val[51:0];

        // Special cases: Inf / NaN
        if (exp == 11'h7FF) begin
            // Infinity if mant == 0, otherwise NaN
            res = (mant == 0)
                  ? (sign ? -1.0/0.0 : 1.0/0.0)
                  : 0.0/0.0;
        end
        // Subnormal or zero
        else if (exp == 0) begin
            if (mant == 0) begin
                res = 0.0;
            end else begin
                res = (sign ? -1.0 : 1.0)
                      * real'(mant) / (2.0**52)
                      * (2.0**(-1022));
            end
        end
        // Normalized number
        else begin
            res = (sign ? -1.0 : 1.0)
                  * (1.0 + real'(mant) / (2.0**52))
                  * (2.0**(exp - 1023));
        end

        return res;
    endfunction

    //==========================================================================
    // Test Task
    //==========================================================================
    task automatic test_fma(
        input [63:0] op_a,
        input [63:0] op_b,
        input [63:0] op_c,
        input [63:0] expected,
        input string test_name
    );
        a = op_a;
        b = op_b;
        c = op_c;

        #1;

        $display("----------------------------------------");
        $display("Test: %s", test_name);
        $display("  A      = 0x%016h (%.16f)", op_a, dp_to_real(op_a));
        $display("  B      = 0x%016h (%.16f)", op_b, dp_to_real(op_b));
        $display("  C      = 0x%016h (%.16f)", op_c, dp_to_real(op_c));
        $display("  Result = 0x%016h (%.16f)", result, dp_to_real(result));
        $display("  Expect = 0x%016h (%.16f)", expected, dp_to_real(expected));
        $display("  Flags  = overflow:%b underflow:%b nan:%b",
                 overflow, underflow, nan_out);

        if (result == expected)
            $display("  STATUS: PASS");
        else
            $display("  STATUS: FAIL");
    endtask

    //==========================================================================
    // Stimulus
    //==========================================================================
    initial begin
        $display("========================================");
        $display("DP Fused Multiply-Add Testbench");
        $display("========================================");

        a = 64'b0;
        b = 64'b0;
        c = 64'b0;
        #10;

        // Test 1: 1.0 × 1.0 + 0.0 = 1.0
        test_fma(64'h3FF0000000000000, 64'h3FF0000000000000,
                 64'h0000000000000000, 64'h3FF0000000000000,
                 "1.0 x 1.0 + 0.0 = 1.0");

        // Test 2: 2.0 × 3.0 + 0.0 = 6.0
        test_fma(64'h4000000000000000, 64'h4008000000000000,
                 64'h0000000000000000, 64'h4018000000000000,
                 "2.0 x 3.0 + 0.0 = 6.0");

        // Test 3: 2.0 × 3.0 + 1.0 = 7.0
        test_fma(64'h4000000000000000, 64'h4008000000000000,
                 64'h3FF0000000000000, 64'h401C000000000000,
                 "2.0 x 3.0 + 1.0 = 7.0");

        // Test 4: 1.0 × 1.0 + 1.0 = 2.0
        test_fma(64'h3FF0000000000000, 64'h3FF0000000000000,
                 64'h3FF0000000000000, 64'h4000000000000000,
                 "1.0 x 1.0 + 1.0 = 2.0");

        // Test 5: 2.0 × 2.0 + (-4.0) = 0.0 (exact cancellation)
        test_fma(64'h4000000000000000, 64'h4000000000000000,
                 64'hC010000000000000, 64'h0000000000000000,
                 "2.0 x 2.0 + (-4.0) = 0.0");

        // Test 6: 0.5 × 0.5 + 0.5 = 0.75
        test_fma(64'h3FE0000000000000, 64'h3FE0000000000000,
                 64'h3FE0000000000000, 64'h3FE8000000000000,
                 "0.5 x 0.5 + 0.5 = 0.75");

        // Test 7: 5.75 × 3.25 + 1.0 = 19.6875
        test_fma(64'h4017000000000000, 64'h400A000000000000,
                 64'h3FF0000000000000, 64'h4033B00000000000,
                 "5.75 x 3.25 + 1.0 = 19.6875");

        // Test 8: -2.0 × 3.0 + 10.0 = 4.0
        test_fma(64'hC000000000000000, 64'h4008000000000000,
                 64'h4024000000000000, 64'h4010000000000000,
                 "-2.0 x 3.0 + 10.0 = 4.0");

        // Test 9: 0 × Any + C = C
        test_fma(64'h0000000000000000, 64'h4000000000000000,
                 64'h3FF0000000000000, 64'h3FF0000000000000,
                 "0.0 x 2.0 + 1.0 = 1.0");

        // Test 10: A × B + 0 = A × B (duplicate of Test 2)
        test_fma(64'h4000000000000000, 64'h4008000000000000,
                 64'h0000000000000000, 64'h4018000000000000,
                 "2.0 x 3.0 + 0.0 = 6.0");

        // Test 11: 1.5 × 2.5 + 0.25 = 4.0
        test_fma(64'h3FF8000000000000, 64'h4004000000000000,
                 64'h3FD0000000000000, 64'h4010000000000000,
                 "1.5 x 2.5 + 0.25 = 4.0");

        // Test 12: Inf × finite + finite = Inf
        test_fma(64'h7FF0000000000000, 64'h4000000000000000,
                 64'h3FF0000000000000, 64'h7FF0000000000000,
                 "Inf x 2.0 + 1.0 = Inf");

        // Test 13: Inf × 0 + finite = NaN
        test_fma(64'h7FF0000000000000, 64'h0000000000000000,
                 64'h3FF0000000000000, 64'h7FF8000000000000,
                 "Inf x 0.0 + 1.0 = NaN");

        // Test 14: NaN propagation
        test_fma(64'h7FF8000000000000, 64'h4000000000000000,
                 64'h3FF0000000000000, 64'h7FF8000000000000,
                 "NaN x 2.0 + 1.0 = NaN");

        // Test 15: Inf × 1.0 + (-Inf) = NaN
        test_fma(64'h7FF0000000000000, 64'h3FF0000000000000,
                 64'hFFF0000000000000, 64'h7FF8000000000000,
                 "Inf x 1.0 + (-Inf) = NaN");

        // Test 16: Large product + small addend (2.0 × 2.0 + 0.001 ? 4.001)
        test_fma(64'h4000000000000000, 64'h4000000000000000,
                 64'h3F50624DD2F1A9FC, 64'h4010010624DD2F1B,
                 "2.0 x 2.0 + 0.001 ~= 4.001");

        $display("========================================");
        $display("Testbench Complete");
        $display("========================================");

        #100;
        $finish;
    end

endmodule

