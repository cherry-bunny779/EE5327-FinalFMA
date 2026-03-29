////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_hp_fma_pipelined
// Description: Testbench for the 3-stage pipelined HP FMA module
//              Tests latency, throughput, and functional correctness
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_hp_fma_pipelined;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam CLK_PERIOD = 10;
    localparam PIPELINE_DEPTH = 3;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    
    logic        clk;
    logic        rst;
    logic        valid_in;
    logic [15:0] a, b, c;
    logic [15:0] result;
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
    
    typedef struct {
        logic [15:0] expected_result;
        string       test_name;
        real         a_val, b_val, c_val;
    } expected_t;
    
    expected_t expected_queue[$];
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    hp_fma_pipelined dut (
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
    
    function real hp_to_real(input [15:0] hp_val);
        logic        sign;
        logic [4:0]  exp;
        logic [9:0]  mant;
        real         result;
        
        sign = hp_val[15];
        exp  = hp_val[14:10];
        mant = hp_val[9:0];
        
        if (exp == 5'h1F) begin
            result = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            result = (mant == 0) ? 0.0 : (sign ? -1.0 : 1.0) * real'(mant) / 1024.0 * (2.0**(-14));
        end else begin
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / 1024.0) * (2.0**(int'(exp) - 15));
        end
        return result;
    endfunction
    
    task automatic submit_test(
        input [15:0] test_a,
        input [15:0] test_b, 
        input [15:0] test_c,
        input [15:0] expected,
        input string name
    );
        expected_t exp_entry;
        
        a = test_a;
        b = test_b;
        c = test_c;
        valid_in = 1'b1;
        
        exp_entry.expected_result = expected;
        exp_entry.test_name = name;
        exp_entry.a_val = hp_to_real(test_a);
        exp_entry.b_val = hp_to_real(test_b);
        exp_entry.c_val = hp_to_real(test_c);
        expected_queue.push_back(exp_entry);
        
        test_count++;
        @(posedge clk);
    endtask
    
    task automatic check_output();
        expected_t exp_entry;
        real result_val, expected_val;
        logic match;
        
        if (valid_out && expected_queue.size() > 0) begin
            exp_entry = expected_queue.pop_front();
            result_val = hp_to_real(result);
            expected_val = hp_to_real(exp_entry.expected_result);
            
            if (exp_entry.expected_result[14:10] == 5'h1F && exp_entry.expected_result[9:0] != 0) begin
                match = nan_out;
            end else begin
                match = (result == exp_entry.expected_result);
            end
            
            if (match) begin
                pass_count++;
                $display("[PASS] %s: %.4f × %.4f + %.4f = %.4f (0x%04h)",
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val,
                         result_val, result);
            end else begin
                fail_count++;
                $display("[FAIL] %s: %.4f × %.4f + %.4f", 
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val);
                $display("       Expected: 0x%04h (%.4f)", 
                         exp_entry.expected_result, expected_val);
                $display("       Got:      0x%04h (%.4f)", 
                         result, result_val);
            end
        end
    endtask
    
    //==========================================================================
    // Output Checker Process
    //==========================================================================
    
    always @(negedge clk) begin
        if (!rst) begin
            check_output();
        end
    end
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    // HP Constants
    localparam [15:0] HP_ZERO     = 16'h0000;
    localparam [15:0] HP_ONE      = 16'h3C00;
    localparam [15:0] HP_TWO      = 16'h4000;
    localparam [15:0] HP_THREE    = 16'h4200;
    localparam [15:0] HP_FOUR     = 16'h4400;
    localparam [15:0] HP_FIVE     = 16'h4500;
    localparam [15:0] HP_SIX      = 16'h4600;
    localparam [15:0] HP_SEVEN    = 16'h4700;
    localparam [15:0] HP_EIGHT    = 16'h4800;
    localparam [15:0] HP_TEN      = 16'h4900;
    localparam [15:0] HP_HALF     = 16'h3800;
    localparam [15:0] HP_NEG_ONE  = 16'hBC00;
    localparam [15:0] HP_NEG_TWO  = 16'hC000;
    localparam [15:0] HP_INF      = 16'h7C00;
    localparam [15:0] HP_NEG_INF  = 16'hFC00;
    localparam [15:0] HP_NAN      = 16'h7E00;
    localparam [15:0] HP_1_5      = 16'h3E00;
    localparam [15:0] HP_NEG_SIX  = 16'hC600;
    localparam [15:0] HP_NEG_FIVE = 16'hC500;
    localparam [15:0] HP_NINE     = 16'h4880;
    
    initial begin
        $display("================================================================");
        $display("Pipelined HP FMA Testbench");
        $display("Pipeline Depth: %0d cycles", PIPELINE_DEPTH);
        $display("================================================================\n");
        
        rst = 1'b1;
        valid_in = 1'b0;
        a = 16'b0;
        b = 16'b0;
        c = 16'b0;
        
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        
        //======================================================================
        // Test Group 1: Basic FMA Operations
        //======================================================================
        $display("\n--- Test Group 1: Basic FMA Operations ---\n");
        
        submit_test(HP_ONE, HP_ONE, HP_ZERO, HP_ONE, "1×1+0=1");
        submit_test(HP_TWO, HP_THREE, HP_ONE, HP_SEVEN, "2×3+1=7");
        submit_test(HP_TWO, HP_TWO, HP_ZERO, HP_FOUR, "2×2+0=4");
        submit_test(HP_ONE, HP_ONE, HP_ONE, HP_TWO, "1×1+1=2");
        submit_test(HP_THREE, HP_THREE, HP_ONE, HP_TEN, "3×3+1=10");
        submit_test(HP_HALF, HP_FOUR, HP_ZERO, HP_TWO, "0.5×4+0=2");
        submit_test(HP_1_5, HP_TWO, HP_ZERO, HP_THREE, "1.5×2+0=3");
        submit_test(HP_TWO, HP_FOUR, HP_ZERO, HP_EIGHT, "2×4+0=8");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 2: Pipeline Throughput
        //======================================================================
        $display("\n--- Test Group 2: Pipeline Throughput ---\n");
        
        submit_test(HP_ONE, HP_ONE, HP_ZERO, HP_ONE, "Pipe[0]: 1×1+0");
        submit_test(HP_TWO, HP_ONE, HP_ZERO, HP_TWO, "Pipe[1]: 2×1+0");
        submit_test(HP_THREE, HP_ONE, HP_ZERO, HP_THREE, "Pipe[2]: 3×1+0");
        submit_test(HP_FOUR, HP_ONE, HP_ZERO, HP_FOUR, "Pipe[3]: 4×1+0");
        submit_test(HP_FIVE, HP_ONE, HP_ZERO, HP_FIVE, "Pipe[4]: 5×1+0");
        submit_test(HP_SIX, HP_ONE, HP_ZERO, HP_SIX, "Pipe[5]: 6×1+0");
        submit_test(HP_SEVEN, HP_ONE, HP_ZERO, HP_SEVEN, "Pipe[6]: 7×1+0");
        submit_test(HP_EIGHT, HP_ONE, HP_ZERO, HP_EIGHT, "Pipe[7]: 8×1+0");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 3: Negative Numbers
        //======================================================================
        $display("\n--- Test Group 3: Negative Numbers ---\n");
        
        submit_test(HP_NEG_ONE, HP_ONE, HP_ZERO, HP_NEG_ONE, "(-1)×1+0=-1");
        submit_test(HP_NEG_ONE, HP_NEG_ONE, HP_ZERO, HP_ONE, "(-1)×(-1)+0=1");
        submit_test(HP_TWO, HP_NEG_ONE, HP_ZERO, HP_NEG_TWO, "2×(-1)+0=-2");
        submit_test(HP_TWO, HP_THREE, HP_NEG_ONE, HP_FIVE, "2×3+(-1)=5");
        submit_test(HP_NEG_TWO, HP_THREE, HP_ONE, HP_NEG_FIVE, "(-2)×3+1=-5");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 4: Zero Cases
        //======================================================================
        $display("\n--- Test Group 4: Zero Cases ---\n");
        
        submit_test(HP_ZERO, HP_FIVE, HP_THREE, HP_THREE, "0×5+3=3");
        submit_test(HP_FIVE, HP_ZERO, HP_THREE, HP_THREE, "5×0+3=3");
        submit_test(HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, "0×0+0=0");
        submit_test(HP_TWO, HP_THREE, HP_ZERO, HP_SIX, "2×3+0=6");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 5: Infinity and NaN Cases
        //======================================================================
        $display("\n--- Test Group 5: Infinity and NaN Cases ---\n");
        
        submit_test(HP_INF, HP_ONE, HP_ZERO, HP_INF, "inf×1+0=inf");
        submit_test(HP_ONE, HP_INF, HP_ZERO, HP_INF, "1×inf+0=inf");
        submit_test(HP_INF, HP_ZERO, HP_ONE, HP_NAN, "inf×0+1=NaN");
        submit_test(HP_NAN, HP_ONE, HP_ZERO, HP_NAN, "NaN×1+0=NaN");
        submit_test(HP_ONE, HP_ONE, HP_NAN, HP_NAN, "1×1+NaN=NaN");
        submit_test(HP_INF, HP_ONE, HP_NEG_INF, HP_NAN, "inf×1+(-inf)=NaN");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 6: Cancellation
        //======================================================================
        $display("\n--- Test Group 6: Cancellation Cases ---\n");
        
        submit_test(HP_THREE, HP_TWO, HP_NEG_SIX, HP_ZERO, "3×2+(-6)=0");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
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
    
    initial begin
        #50000;
        $display("\n*** TIMEOUT ***\n");
        $finish;
    end

endmodule