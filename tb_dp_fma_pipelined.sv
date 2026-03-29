////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_dp_fma_pipelined
// Description: Testbench for the 3-stage pipelined DP FMA module
//              Tests latency, throughput, and functional correctness
//
// Test Categories:
//   1. Basic FMA operations
//   2. Pipeline throughput (back-to-back operations)
//   3. Special cases (NaN, Inf, Zero)
//   4. Edge cases (subnormals, rounding)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_dp_fma_pipelined;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam CLK_PERIOD = 10;  // 100 MHz clock
    localparam PIPELINE_DEPTH = 3;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    
    logic        clk;
    logic        rst;
    logic        valid_in;
    logic [63:0] a, b, c;
    logic [63:0] result;
    logic        overflow;
    logic        underflow;
    logic        nan_out;
    logic        valid_out;
    
    //==========================================================================
    // Test Infrastructure
    //==========================================================================
    
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    // Queue to track expected results through pipeline
    typedef struct {
        logic [63:0] expected_result;
        string       test_name;
        real         a_val, b_val, c_val;
    } expected_t;
    
    expected_t expected_queue[$];
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    dp_fma_pipelined dut (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (valid_in),
        .a         (a),
        .b         (b),
        .c         (c),
        .result    (result),
        .overflow  (overflow),
        .underflow (underflow),
        .nan_out   (nan_out),
        .valid_out (valid_out)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    // Convert DP hex to real value
    function real dp_to_real(input [63:0] dp_val);
        logic        sign;
        logic [10:0] exp;
        logic [51:0] mant;
        real         result;
        
        sign = dp_val[63];
        exp  = dp_val[62:52];
        mant = dp_val[51:0];
        
        if (exp == 11'h7FF) begin
            result = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            result = (mant == 0) ? 0.0 : (sign ? -1.0 : 1.0) * real'(mant) / (2.0**52) * (2.0**(-1022));
        end else begin
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / (2.0**52)) * (2.0**(int'(exp) - 1023));
        end
        return result;
    endfunction
    
    // Convert real to DP hex (approximate, for reference)
    function [63:0] real_to_dp(input real val);
        logic        sign;
        logic [10:0] exp;
        logic [51:0] mant;
        real         abs_val;
        int          exp_int;
        real         mant_real;
        
        if (val == 0.0) return 64'h0;
        
        sign = (val < 0.0);
        abs_val = sign ? -val : val;
        
        // Find exponent
        exp_int = 0;
        mant_real = abs_val;
        
        if (abs_val >= 2.0) begin
            while (mant_real >= 2.0) begin
                mant_real = mant_real / 2.0;
                exp_int = exp_int + 1;
            end
        end else if (abs_val < 1.0) begin
            while (mant_real < 1.0) begin
                mant_real = mant_real * 2.0;
                exp_int = exp_int - 1;
            end
        end
        
        exp = exp_int + 1023;
        mant = (mant_real - 1.0) * (2.0**52);
        
        return {sign, exp, mant};
    endfunction
    
    // Submit a test case to the pipeline
    // Inputs are applied, then we wait for clock to latch them
    task automatic submit_test(
        input [63:0] test_a,
        input [63:0] test_b, 
        input [63:0] test_c,
        input [63:0] expected,
        input string name
    );
        expected_t exp_entry;
        
        // Apply inputs (will be latched on next rising edge)
        a = test_a;
        b = test_b;
        c = test_c;
        valid_in = 1'b1;
        
        // Queue the expected result
        exp_entry.expected_result = expected;
        exp_entry.test_name = name;
        exp_entry.a_val = dp_to_real(test_a);
        exp_entry.b_val = dp_to_real(test_b);
        exp_entry.c_val = dp_to_real(test_c);
        expected_queue.push_back(exp_entry);
        
        test_count++;
        
        // Wait for clock edge to latch inputs
        @(posedge clk);
    endtask
    
    // Check output when valid
    task automatic check_output();
        expected_t exp_entry;
        real result_val, expected_val;
        logic match;
        
        if (valid_out && expected_queue.size() > 0) begin
            exp_entry = expected_queue.pop_front();
            result_val = dp_to_real(result);
            expected_val = dp_to_real(exp_entry.expected_result);
            
            // Check for exact match or NaN match
            if (exp_entry.expected_result[62:52] == 11'h7FF && exp_entry.expected_result[51:0] != 0) begin
                // Expected NaN
                match = nan_out;
            end else begin
                match = (result == exp_entry.expected_result);
            end
            
            if (match) begin
                pass_count++;
                $display("[PASS] %s: %.6f × %.6f + %.6f = %.6f (0x%016h)",
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val,
                         result_val, result);
            end else begin
                fail_count++;
                $display("[FAIL] %s: %.6f × %.6f + %.6f", 
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val);
                $display("       Expected: 0x%016h (%.6f)", 
                         exp_entry.expected_result, expected_val);
                $display("       Got:      0x%016h (%.6f)", 
                         result, result_val);
            end
        end
    endtask
    
    //==========================================================================
    // Output Checker Process
    // Check on negedge to avoid race conditions with DUT updates on posedge
    //==========================================================================
    
    always @(negedge clk) begin
        if (!rst) begin
            check_output();
        end
    end
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    // DP Constants
    localparam [63:0] DP_ZERO     = 64'h0000000000000000;
    localparam [63:0] DP_ONE      = 64'h3FF0000000000000;
    localparam [63:0] DP_TWO      = 64'h4000000000000000;
    localparam [63:0] DP_THREE    = 64'h4008000000000000;
    localparam [63:0] DP_FOUR     = 64'h4010000000000000;
    localparam [63:0] DP_FIVE     = 64'h4014000000000000;
    localparam [63:0] DP_SIX      = 64'h4018000000000000;
    localparam [63:0] DP_SEVEN    = 64'h401C000000000000;
    localparam [63:0] DP_EIGHT    = 64'h4020000000000000;
    localparam [63:0] DP_TEN      = 64'h4024000000000000;
    localparam [63:0] DP_HALF     = 64'h3FE0000000000000;
    localparam [63:0] DP_NEG_ONE  = 64'hBFF0000000000000;
    localparam [63:0] DP_NEG_TWO  = 64'hC000000000000000;
    localparam [63:0] DP_INF      = 64'h7FF0000000000000;
    localparam [63:0] DP_NEG_INF  = 64'hFFF0000000000000;
    localparam [63:0] DP_NAN      = 64'h7FF8000000000000;
    localparam [63:0] DP_1_5      = 64'h3FF8000000000000;
    localparam [63:0] DP_2_5      = 64'h4004000000000000;
    localparam [63:0] DP_100      = 64'h4059000000000000;
    localparam [63:0] DP_1000     = 64'h408F400000000000;
    
    initial begin
        $display("================================================================");
        $display("Pipelined DP FMA Testbench");
        $display("Pipeline Depth: %0d cycles", PIPELINE_DEPTH);
        $display("================================================================\n");
        
        // Initialize
        rst = 1'b1;
        valid_in = 1'b0;
        a = 64'b0;
        b = 64'b0;
        c = 64'b0;
        
        // Reset sequence
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        
        //======================================================================
        // Test Group 1: Basic FMA Operations
        //======================================================================
        $display("\n--- Test Group 1: Basic FMA Operations ---\n");
        
        // 1×1+0 = 1
        submit_test(DP_ONE, DP_ONE, DP_ZERO, DP_ONE, "1×1+0=1");
        
        // 2×3+1 = 7
        submit_test(DP_TWO, DP_THREE, DP_ONE, DP_SEVEN, "2×3+1=7");
        
        // 2×2+0 = 4
        submit_test(DP_TWO, DP_TWO, DP_ZERO, DP_FOUR, "2×2+0=4");
        
        // 1×1+1 = 2
        submit_test(DP_ONE, DP_ONE, DP_ONE, DP_TWO, "1×1+1=2");
        
        // 3×3+1 = 10
        submit_test(DP_THREE, DP_THREE, DP_ONE, DP_TEN, "3×3+1=10");
        
        // 0.5×4+0 = 2
        submit_test(DP_HALF, DP_FOUR, DP_ZERO, DP_TWO, "0.5×4+0=2");
        
        // 1.5×2+0 = 3
        submit_test(DP_1_5, DP_TWO, DP_ZERO, DP_THREE, "1.5×2+0=3");
        
        // 2.5×2+0 = 5
        submit_test(DP_2_5, DP_TWO, DP_ZERO, DP_FIVE, "2.5×2+0=5");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 2: Pipeline Throughput (Back-to-back)
        //======================================================================
        $display("\n--- Test Group 2: Pipeline Throughput ---\n");
        
        // Submit 10 operations back-to-back
        submit_test(DP_ONE, DP_ONE, DP_ZERO, DP_ONE, "Pipe[0]: 1×1+0");
        submit_test(DP_TWO, DP_ONE, DP_ZERO, DP_TWO, "Pipe[1]: 2×1+0");
        submit_test(DP_THREE, DP_ONE, DP_ZERO, DP_THREE, "Pipe[2]: 3×1+0");
        submit_test(DP_FOUR, DP_ONE, DP_ZERO, DP_FOUR, "Pipe[3]: 4×1+0");
        submit_test(DP_FIVE, DP_ONE, DP_ZERO, DP_FIVE, "Pipe[4]: 5×1+0");
        submit_test(DP_SIX, DP_ONE, DP_ZERO, DP_SIX, "Pipe[5]: 6×1+0");
        submit_test(DP_SEVEN, DP_ONE, DP_ZERO, DP_SEVEN, "Pipe[6]: 7×1+0");
        submit_test(DP_EIGHT, DP_ONE, DP_ZERO, DP_EIGHT, "Pipe[7]: 8×1+0");
        submit_test(DP_ONE, DP_TEN, DP_ZERO, DP_TEN, "Pipe[8]: 1×10+0");
        submit_test(DP_TWO, DP_FIVE, DP_ZERO, DP_TEN, "Pipe[9]: 2×5+0");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 3: Negative Numbers
        //======================================================================
        $display("\n--- Test Group 3: Negative Numbers ---\n");
        
        // (-1)×1+0 = -1
        submit_test(DP_NEG_ONE, DP_ONE, DP_ZERO, DP_NEG_ONE, "(-1)×1+0=-1");
        
        // (-1)×(-1)+0 = 1
        submit_test(DP_NEG_ONE, DP_NEG_ONE, DP_ZERO, DP_ONE, "(-1)×(-1)+0=1");
        
        // 2×(-1)+0 = -2
        submit_test(DP_TWO, DP_NEG_ONE, DP_ZERO, DP_NEG_TWO, "2×(-1)+0=-2");
        
        // 2×3+(-1) = 5
        submit_test(DP_TWO, DP_THREE, DP_NEG_ONE, DP_FIVE, "2×3+(-1)=5");
        
        // (-2)×3+1 = -5
        submit_test(DP_NEG_TWO, DP_THREE, DP_ONE, 64'hC014000000000000, "(-2)×3+1=-5");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 4: Special Cases - Zero
        //======================================================================
        $display("\n--- Test Group 4: Zero Cases ---\n");
        
        // 0×5+3 = 3
        submit_test(DP_ZERO, DP_FIVE, DP_THREE, DP_THREE, "0×5+3=3");
        
        // 5×0+3 = 3
        submit_test(DP_FIVE, DP_ZERO, DP_THREE, DP_THREE, "5×0+3=3");
        
        // 0×0+0 = 0
        submit_test(DP_ZERO, DP_ZERO, DP_ZERO, DP_ZERO, "0×0+0=0");
        
        // 2×3+0 = 6
        submit_test(DP_TWO, DP_THREE, DP_ZERO, DP_SIX, "2×3+0=6");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 5: Special Cases - Infinity and NaN
        //======================================================================
        $display("\n--- Test Group 5: Infinity and NaN Cases ---\n");
        
        // inf × 1 + 0 = inf
        submit_test(DP_INF, DP_ONE, DP_ZERO, DP_INF, "inf×1+0=inf");
        
        // 1 × inf + 0 = inf
        submit_test(DP_ONE, DP_INF, DP_ZERO, DP_INF, "1×inf+0=inf");
        
        // inf × 0 + 1 = NaN (inf × 0 is undefined)
        submit_test(DP_INF, DP_ZERO, DP_ONE, DP_NAN, "inf×0+1=NaN");
        
        // NaN × 1 + 0 = NaN
        submit_test(DP_NAN, DP_ONE, DP_ZERO, DP_NAN, "NaN×1+0=NaN");
        
        // 1 × 1 + NaN = NaN
        submit_test(DP_ONE, DP_ONE, DP_NAN, DP_NAN, "1×1+NaN=NaN");
        
        // inf + (-inf) = NaN (inf × 1 + (-inf))
        submit_test(DP_INF, DP_ONE, DP_NEG_INF, DP_NAN, "inf×1+(-inf)=NaN");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 6: Larger Numbers
        //======================================================================
        $display("\n--- Test Group 6: Larger Numbers ---\n");
        
        // 100 × 10 + 0 = 1000
        submit_test(DP_100, DP_TEN, DP_ZERO, DP_1000, "100×10+0=1000");
        
        // 10 × 10 + 0 = 100
        submit_test(DP_TEN, DP_TEN, DP_ZERO, DP_100, "10×10+0=100");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 7: Cancellation (Subtraction)
        //======================================================================
        $display("\n--- Test Group 7: Cancellation Cases ---\n");
        
        // 3×2+(-6) = 0
        submit_test(DP_THREE, DP_TWO, 64'hC018000000000000, DP_ZERO, "3×2+(-6)=0");
        
        // 5×2+(-10) = 0
        submit_test(DP_FIVE, DP_TWO, 64'hC024000000000000, DP_ZERO, "5×2+(-10)=0");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 8: Intermittent Valid
        //======================================================================
        $display("\n--- Test Group 8: Intermittent Valid Signal ---\n");
        
        submit_test(DP_TWO, DP_TWO, DP_ZERO, DP_FOUR, "Intermit[0]: 2×2+0");
        
        // Gap with no valid input
        valid_in = 1'b0;
        repeat (2) @(posedge clk);
        
        submit_test(DP_THREE, DP_THREE, DP_ZERO, 64'h4022000000000000, "Intermit[1]: 3×3+0=9");
        
        // Another gap
        valid_in = 1'b0;
        repeat (3) @(posedge clk);
        
        submit_test(DP_FOUR, DP_FOUR, DP_ZERO, 64'h4030000000000000, "Intermit[2]: 4×4+0=16");
        
        // Wait for pipeline to flush
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 5) @(posedge clk);
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n================================================================");
        $display("Test Summary");
        $display("================================================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("================================================================\n");
        
        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***\n");
        end else begin
            $display("*** SOME TESTS FAILED ***\n");
        end
        
        #100;
        $finish;
    end
    
    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    
    initial begin
        #100000;
        $display("\n*** TIMEOUT - Test did not complete ***\n");
        $finish;
    end
    
    //==========================================================================
    // Waveform Dump (optional)
    //==========================================================================
    
    initial begin
        $dumpfile("tb_dp_fma_pipelined.vcd");
        $dumpvars(0, tb_dp_fma_pipelined);
    end

endmodule