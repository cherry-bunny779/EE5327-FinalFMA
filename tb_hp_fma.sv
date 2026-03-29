////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_hp_fma
// Description: Testbench for IEEE 754 Half-Precision Fused Multiply-Add
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_hp_fma;

    //==========================================================================
    // Signals
    //==========================================================================
    
    logic [15:0] a, b, c;
    logic [15:0] result;
    logic        overflow;
    logic        underflow;
    logic        nan_out;
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    hp_fma dut (
        .a         (a),
        .b         (b),
        .c         (c),
        .result    (result),
        .overflow  (overflow),
        .underflow (underflow),
        .nan_out   (nan_out)
    );
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    function real hp_to_real(input [15:0] hex_val);
        logic        sign;
        logic [4:0]  exp;
        logic [9:0]  mant;
        real         res;
        
        sign = hex_val[15];
        exp  = hex_val[14:10];
        mant = hex_val[9:0];
        
        if (exp == 5'h1F) begin
            res = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            res = (mant == 0) ? 0.0 : (sign ? -1.0 : 1.0) * real'(mant) / 1024.0 * (2.0**(-14));
        end else begin
            res = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / 1024.0) * (2.0**(exp - 15));
        end
        return res;
    endfunction
    
    //==========================================================================
    // Test Task
    //==========================================================================
    
    task automatic test_fma(
        input [15:0] op_a,
        input [15:0] op_b,
        input [15:0] op_c,
        input [15:0] expected,
        input string test_name
    );
        a = op_a;
        b = op_b;
        c = op_c;
        
        #1;
        
        $display("----------------------------------------");
        $display("Test: %s", test_name);
        $display("  A      = 0x%04h (%.6f)", op_a, hp_to_real(op_a));
        $display("  B      = 0x%04h (%.6f)", op_b, hp_to_real(op_b));
        $display("  C      = 0x%04h (%.6f)", op_c, hp_to_real(op_c));
        $display("  Result = 0x%04h (%.6f)", result, hp_to_real(result));
        $display("  Expect = 0x%04h (%.6f)", expected, hp_to_real(expected));
        $display("  Flags  = overflow:%b underflow:%b nan:%b", overflow, underflow, nan_out);
        
        if (result == expected)
            $display("  STATUS: PASS");
        else
            $display("  STATUS: FAIL");
    endtask
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    initial begin
        $display("========================================");
        $display("HP Fused Multiply-Add Testbench");
        $display("========================================");
        
        a = 16'b0; b = 16'b0; c = 16'b0;
        #10;
        
        // Test 1: 1.0 × 1.0 + 0.0 = 1.0
        test_fma(16'h3C00, 16'h3C00, 16'h0000, 16'h3C00, "1.0 x 1.0 + 0.0 = 1.0");
        
        // Test 2: 2.0 × 3.0 + 0.0 = 6.0
        test_fma(16'h4000, 16'h4200, 16'h0000, 16'h4600, "2.0 x 3.0 + 0.0 = 6.0");
        
        // Test 3: 2.0 × 3.0 + 1.0 = 7.0
        test_fma(16'h4000, 16'h4200, 16'h3C00, 16'h4700, "2.0 x 3.0 + 1.0 = 7.0");
        
        // Test 4: 1.0 × 1.0 + 1.0 = 2.0
        test_fma(16'h3C00, 16'h3C00, 16'h3C00, 16'h4000, "1.0 x 1.0 + 1.0 = 2.0");
        
        // Test 5: 2.0 × 2.0 + (-4.0) = 0.0 (exact cancellation)
        test_fma(16'h4000, 16'h4000, 16'hC400, 16'h0000, "2.0 x 2.0 + (-4.0) = 0.0");
        
        // Test 6: 0.5 × 0.5 + 0.5 = 0.75
        test_fma(16'h3800, 16'h3800, 16'h3800, 16'h3A00, "0.5 x 0.5 + 0.5 = 0.75");
        
        // Test 7: 1.5 × 2.0 + 1.0 = 4.0
        test_fma(16'h3E00, 16'h4000, 16'h3C00, 16'h4400, "1.5 x 2.0 + 1.0 = 4.0");
        
        // Test 8: -2.0 × 3.0 + 10.0 = 4.0
        test_fma(16'hC000, 16'h4200, 16'h4900, 16'h4400, "-2.0 x 3.0 + 10.0 = 4.0");
        
        // Test 9: 0 × Any + C = C
        test_fma(16'h0000, 16'h4000, 16'h3C00, 16'h3C00, "0.0 x 2.0 + 1.0 = 1.0");
        
        // Test 10: A × B + 0 = A × B
        test_fma(16'h4000, 16'h4200, 16'h0000, 16'h4600, "2.0 x 3.0 + 0.0 = 6.0");
        
        // Test 11: Inf × finite + finite = Inf
        test_fma(16'h7C00, 16'h4000, 16'h3C00, 16'h7C00, "Inf x 2.0 + 1.0 = Inf");
        
        // Test 12: Inf × 0 + finite = NaN
        test_fma(16'h7C00, 16'h0000, 16'h3C00, 16'h7E00, "Inf x 0.0 + 1.0 = NaN");
        
        // Test 13: NaN propagation
        test_fma(16'h7E00, 16'h4000, 16'h3C00, 16'h7E00, "NaN x 2.0 + 1.0 = NaN");
        
        // Test 14: Inf + (-Inf) = NaN
        test_fma(16'h7C00, 16'h3C00, 16'hFC00, 16'h7E00, "Inf x 1.0 + (-Inf) = NaN");
        
        $display("========================================");
        $display("Testbench Complete");
        $display("========================================");
        
        #100;
        $finish;
    end

endmodule
