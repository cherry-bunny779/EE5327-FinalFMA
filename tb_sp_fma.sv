////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_sp_fma
// Description: Testbench for IEEE 754 Single-Precision Fused Multiply-Add
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_sp_fma;

    //==========================================================================
    // Signals
    //==========================================================================
    
    logic [31:0] a, b, c;
    logic [31:0] result;
    logic        overflow;
    logic        underflow;
    logic        nan_out;
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    sp_fma dut (
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
    
    function real sp_to_real(input [31:0] hex_val);
        logic        sign;
        logic [7:0]  exp;
        logic [22:0] mant;
        real         res;
        
        sign = hex_val[31];
        exp  = hex_val[30:23];
        mant = hex_val[22:0];
        
        if (exp == 8'hFF) begin
            res = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            res = (mant == 0) ? 0.0 : (sign ? -1.0 : 1.0) * real'(mant) / (2.0**23) * (2.0**(-126));
        end else begin
            res = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / (2.0**23)) * (2.0**(exp - 127));
        end
        return res;
    endfunction
    
    //==========================================================================
    // Test Task
    //==========================================================================
    
    task automatic test_fma(
        input [31:0] op_a,
        input [31:0] op_b,
        input [31:0] op_c,
        input [31:0] expected,
        input string test_name
    );
        a = op_a;
        b = op_b;
        c = op_c;
        
        #1;
        
        $display("----------------------------------------");
        $display("Test: %s", test_name);
        $display("  A      = 0x%08h (%.10f)", op_a, sp_to_real(op_a));
        $display("  B      = 0x%08h (%.10f)", op_b, sp_to_real(op_b));
        $display("  C      = 0x%08h (%.10f)", op_c, sp_to_real(op_c));
        $display("  Result = 0x%08h (%.10f)", result, sp_to_real(result));
        $display("  Expect = 0x%08h (%.10f)", expected, sp_to_real(expected));
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
        $display("SP Fused Multiply-Add Testbench");
        $display("========================================");
        
        a = 32'b0; b = 32'b0; c = 32'b0;
        #10;
        
        // Test 1: 1.0 × 1.0 + 0.0 = 1.0
        test_fma(32'h3F800000, 32'h3F800000, 32'h00000000, 32'h3F800000, 
                 "1.0 x 1.0 + 0.0 = 1.0");
        
        // Test 2: 2.0 × 3.0 + 0.0 = 6.0
        test_fma(32'h40000000, 32'h40400000, 32'h00000000, 32'h40C00000, 
                 "2.0 x 3.0 + 0.0 = 6.0");
        
        // Test 3: 2.0 × 3.0 + 1.0 = 7.0
        test_fma(32'h40000000, 32'h40400000, 32'h3F800000, 32'h40E00000, 
                 "2.0 x 3.0 + 1.0 = 7.0");
        
        // Test 4: 1.0 × 1.0 + 1.0 = 2.0
        test_fma(32'h3F800000, 32'h3F800000, 32'h3F800000, 32'h40000000, 
                 "1.0 x 1.0 + 1.0 = 2.0");
        
        // Test 5: 2.0 × 2.0 + (-4.0) = 0.0 (exact cancellation)
        test_fma(32'h40000000, 32'h40000000, 32'hC0800000, 32'h00000000, 
                 "2.0 x 2.0 + (-4.0) = 0.0");
        
        // Test 6: 0.5 × 0.5 + 0.5 = 0.75
        test_fma(32'h3F000000, 32'h3F000000, 32'h3F000000, 32'h3F400000, 
                 "0.5 x 0.5 + 0.5 = 0.75");
        
        // Test 7: 5.75 × 3.25 + 1.0 = 19.6875
        test_fma(32'h40B80000, 32'h40500000, 32'h3F800000, 32'h419D8000, 
                 "5.75 x 3.25 + 1.0 = 19.6875");
        
        // Test 8: -2.0 × 3.0 + 10.0 = 4.0
        test_fma(32'hC0000000, 32'h40400000, 32'h41200000, 32'h40800000, 
                 "-2.0 x 3.0 + 10.0 = 4.0");
        
        // Test 9: 0 × Any + C = C
        test_fma(32'h00000000, 32'h40000000, 32'h3F800000, 32'h3F800000, 
                 "0.0 x 2.0 + 1.0 = 1.0");
        
        // Test 10: A × B + 0 = A × B
        test_fma(32'h40000000, 32'h40400000, 32'h00000000, 32'h40C00000, 
                 "2.0 x 3.0 + 0.0 = 6.0");
        
        // Test 11: 1.5 × 2.5 + 0.25 = 4.0
        test_fma(32'h3FC00000, 32'h40200000, 32'h3E800000, 32'h40800000, 
                 "1.5 x 2.5 + 0.25 = 4.0");
        
        // Test 12: Inf × finite + finite = Inf
        test_fma(32'h7F800000, 32'h40000000, 32'h3F800000, 32'h7F800000, 
                 "Inf x 2.0 + 1.0 = Inf");
        
        // Test 13: Inf × 0 + finite = NaN
        test_fma(32'h7F800000, 32'h00000000, 32'h3F800000, 32'h7FC00000, 
                 "Inf x 0.0 + 1.0 = NaN");
        
        // Test 14: NaN propagation
        test_fma(32'h7FC00000, 32'h40000000, 32'h3F800000, 32'h7FC00000, 
                 "NaN x 2.0 + 1.0 = NaN");
        
        // Test 15: Inf + (-Inf) = NaN
        test_fma(32'h7F800000, 32'h3F800000, 32'hFF800000, 32'h7FC00000, 
                 "Inf x 1.0 + (-Inf) = NaN");
        
        // Test 16: Large product + small addend
        // 0.001 ≈ 0x3A83126F, 4.001 ≈ 0x40800831
        test_fma(32'h40000000, 32'h40000000, 32'h3A83126F, 32'h40800831, 
                 "2.0 x 2.0 + 0.001 ≈ 4.001");
        
        $display("========================================");
        $display("Testbench Complete");
        $display("========================================");
        
        #100;
        $finish;
    end

endmodule
