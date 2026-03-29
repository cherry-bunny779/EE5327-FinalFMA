////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_sp_fma_pipelined
// Description: Testbench for the 3-stage pipelined SP FMA module
//              Tests latency, throughput, and functional correctness
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_sp_fma_pipelined;

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
    logic [31:0] a, b, c;
    logic [31:0] result;
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
        logic [31:0] expected_result;
        string       test_name;
        real         a_val, b_val, c_val;
    } expected_t;
    
    expected_t expected_queue[$];
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    sp_fma_pipelined dut (
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
    
    function real sp_to_real(input [31:0] sp_val);
        logic        sign;
        logic [7:0]  exp;
        logic [22:0] mant;
        real         result;
        
        sign = sp_val[31];
        exp  = sp_val[30:23];
        mant = sp_val[22:0];
        
        if (exp == 8'hFF) begin
            result = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            result = (mant == 0) ? 0.0 : (sign ? -1.0 : 1.0) * real'(mant) / (2.0**23) * (2.0**(-126));
        end else begin
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / (2.0**23)) * (2.0**(int'(exp) - 127));
        end
        return result;
    endfunction
    
    task automatic submit_test(
        input [31:0] test_a,
        input [31:0] test_b, 
        input [31:0] test_c,
        input [31:0] expected,
        input string name
    );
        expected_t exp_entry;
        
        a = test_a;
        b = test_b;
        c = test_c;
        valid_in = 1'b1;
        
        exp_entry.expected_result = expected;
        exp_entry.test_name = name;
        exp_entry.a_val = sp_to_real(test_a);
        exp_entry.b_val = sp_to_real(test_b);
        exp_entry.c_val = sp_to_real(test_c);
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
            result_val = sp_to_real(result);
            expected_val = sp_to_real(exp_entry.expected_result);
            
            if (exp_entry.expected_result[30:23] == 8'hFF && exp_entry.expected_result[22:0] != 0) begin
                match = nan_out;
            end else begin
                match = (result == exp_entry.expected_result);
            end
            
            if (match) begin
                pass_count++;
                $display("[PASS] %s: %.6f × %.6f + %.6f = %.6f (0x%08h)",
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val,
                         result_val, result);
            end else begin
                fail_count++;
                $display("[FAIL] %s: %.6f × %.6f + %.6f", 
                         exp_entry.test_name,
                         exp_entry.a_val, exp_entry.b_val, exp_entry.c_val);
                $display("       Expected: 0x%08h (%.6f)", 
                         exp_entry.expected_result, expected_val);
                $display("       Got:      0x%08h (%.6f)", 
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
    
    // SP Constants
    localparam [31:0] SP_ZERO     = 32'h00000000;
    localparam [31:0] SP_ONE      = 32'h3F800000;
    localparam [31:0] SP_TWO      = 32'h40000000;
    localparam [31:0] SP_THREE    = 32'h40400000;
    localparam [31:0] SP_FOUR     = 32'h40800000;
    localparam [31:0] SP_FIVE     = 32'h40A00000;
    localparam [31:0] SP_SIX      = 32'h40C00000;
    localparam [31:0] SP_SEVEN    = 32'h40E00000;
    localparam [31:0] SP_EIGHT    = 32'h41000000;
    localparam [31:0] SP_TEN      = 32'h41200000;
    localparam [31:0] SP_HALF     = 32'h3F000000;
    localparam [31:0] SP_NEG_ONE  = 32'hBF800000;
    localparam [31:0] SP_NEG_TWO  = 32'hC0000000;
    localparam [31:0] SP_INF      = 32'h7F800000;
    localparam [31:0] SP_NEG_INF  = 32'hFF800000;
    localparam [31:0] SP_NAN      = 32'h7FC00000;
    localparam [31:0] SP_1_5      = 32'h3FC00000;
    localparam [31:0] SP_NEG_SIX  = 32'hC0C00000;
    localparam [31:0] SP_NEG_FIVE = 32'hC0A00000;
    localparam [31:0] SP_100      = 32'h42C80000;
    localparam [31:0] SP_1000     = 32'h447A0000;
    
    initial begin
        $display("================================================================");
        $display("Pipelined SP FMA Testbench");
        $display("Pipeline Depth: %0d cycles", PIPELINE_DEPTH);
        $display("================================================================\n");
        
        rst = 1'b1;
        valid_in = 1'b0;
        a = 32'b0;
        b = 32'b0;
        c = 32'b0;
        
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        
        //======================================================================
        // Test Group 1: Basic FMA Operations
        //======================================================================
        $display("\n--- Test Group 1: Basic FMA Operations ---\n");
        
        submit_test(SP_ONE, SP_ONE, SP_ZERO, SP_ONE, "1×1+0=1");
        submit_test(SP_TWO, SP_THREE, SP_ONE, SP_SEVEN, "2×3+1=7");
        submit_test(SP_TWO, SP_TWO, SP_ZERO, SP_FOUR, "2×2+0=4");
        submit_test(SP_ONE, SP_ONE, SP_ONE, SP_TWO, "1×1+1=2");
        submit_test(SP_THREE, SP_THREE, SP_ONE, SP_TEN, "3×3+1=10");
        submit_test(SP_HALF, SP_FOUR, SP_ZERO, SP_TWO, "0.5×4+0=2");
        submit_test(SP_1_5, SP_TWO, SP_ZERO, SP_THREE, "1.5×2+0=3");
        submit_test(SP_TWO, SP_FOUR, SP_ZERO, SP_EIGHT, "2×4+0=8");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 2: Pipeline Throughput
        //======================================================================
        $display("\n--- Test Group 2: Pipeline Throughput ---\n");
        
        submit_test(SP_ONE, SP_ONE, SP_ZERO, SP_ONE, "Pipe[0]: 1×1+0");
        submit_test(SP_TWO, SP_ONE, SP_ZERO, SP_TWO, "Pipe[1]: 2×1+0");
        submit_test(SP_THREE, SP_ONE, SP_ZERO, SP_THREE, "Pipe[2]: 3×1+0");
        submit_test(SP_FOUR, SP_ONE, SP_ZERO, SP_FOUR, "Pipe[3]: 4×1+0");
        submit_test(SP_FIVE, SP_ONE, SP_ZERO, SP_FIVE, "Pipe[4]: 5×1+0");
        submit_test(SP_SIX, SP_ONE, SP_ZERO, SP_SIX, "Pipe[5]: 6×1+0");
        submit_test(SP_SEVEN, SP_ONE, SP_ZERO, SP_SEVEN, "Pipe[6]: 7×1+0");
        submit_test(SP_EIGHT, SP_ONE, SP_ZERO, SP_EIGHT, "Pipe[7]: 8×1+0");
        submit_test(SP_TEN, SP_TEN, SP_ZERO, SP_100, "Pipe[8]: 10×10+0");
        submit_test(SP_100, SP_TEN, SP_ZERO, SP_1000, "Pipe[9]: 100×10+0");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 3: Negative Numbers
        //======================================================================
        $display("\n--- Test Group 3: Negative Numbers ---\n");
        
        submit_test(SP_NEG_ONE, SP_ONE, SP_ZERO, SP_NEG_ONE, "(-1)×1+0=-1");
        submit_test(SP_NEG_ONE, SP_NEG_ONE, SP_ZERO, SP_ONE, "(-1)×(-1)+0=1");
        submit_test(SP_TWO, SP_NEG_ONE, SP_ZERO, SP_NEG_TWO, "2×(-1)+0=-2");
        submit_test(SP_TWO, SP_THREE, SP_NEG_ONE, SP_FIVE, "2×3+(-1)=5");
        submit_test(SP_NEG_TWO, SP_THREE, SP_ONE, SP_NEG_FIVE, "(-2)×3+1=-5");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 4: Zero Cases
        //======================================================================
        $display("\n--- Test Group 4: Zero Cases ---\n");
        
        submit_test(SP_ZERO, SP_FIVE, SP_THREE, SP_THREE, "0×5+3=3");
        submit_test(SP_FIVE, SP_ZERO, SP_THREE, SP_THREE, "5×0+3=3");
        submit_test(SP_ZERO, SP_ZERO, SP_ZERO, SP_ZERO, "0×0+0=0");
        submit_test(SP_TWO, SP_THREE, SP_ZERO, SP_SIX, "2×3+0=6");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 5: Infinity and NaN Cases
        //======================================================================
        $display("\n--- Test Group 5: Infinity and NaN Cases ---\n");
        
        submit_test(SP_INF, SP_ONE, SP_ZERO, SP_INF, "inf×1+0=inf");
        submit_test(SP_ONE, SP_INF, SP_ZERO, SP_INF, "1×inf+0=inf");
        submit_test(SP_INF, SP_ZERO, SP_ONE, SP_NAN, "inf×0+1=NaN");
        submit_test(SP_NAN, SP_ONE, SP_ZERO, SP_NAN, "NaN×1+0=NaN");
        submit_test(SP_ONE, SP_ONE, SP_NAN, SP_NAN, "1×1+NaN=NaN");
        submit_test(SP_INF, SP_ONE, SP_NEG_INF, SP_NAN, "inf×1+(-inf)=NaN");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 6: Cancellation
        //======================================================================
        $display("\n--- Test Group 6: Cancellation Cases ---\n");
        
        submit_test(SP_THREE, SP_TWO, SP_NEG_SIX, SP_ZERO, "3×2+(-6)=0");
        
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
        #100000;
        $display("\n*** TIMEOUT ***\n");
        $finish;
    end

endmodule