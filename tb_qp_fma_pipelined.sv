////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_qp_fma_pipelined
// Description: Testbench for the 3-stage pipelined QP FMA module
//              Tests latency, throughput, and functional correctness
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_qp_fma_pipelined;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam CLK_PERIOD = 10;
    localparam PIPELINE_DEPTH = 3;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    
    logic         clk;
    logic         rst;
    logic         valid_in;
    logic [127:0] a, b, c;
    logic [127:0] result;
    logic         overflow;
    logic         underflow;
    logic         nan_out;
    logic         valid_out;
    
    //==========================================================================
    // Test Infrastructure
    //==========================================================================
    
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    typedef struct {
        logic [127:0] expected_result;
        string        test_name;
    } expected_t;
    
    expected_t expected_queue[$];
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    qp_fma_pipelined dut (
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
    
    function real qp_to_real(input [127:0] qp_val);
        logic         sign;
        logic [14:0]  exp;
        logic [111:0] mant;
        real          result;
        real          mant_real;
        int           i;
        
        sign = qp_val[127];
        exp  = qp_val[126:112];
        mant = qp_val[111:0];
        
        // Approximate conversion (loses precision for display purposes)
        mant_real = 0.0;
        for (i = 0; i < 52; i++) begin  // Only use top 52 bits for real
            if (mant[111-i])
                mant_real = mant_real + (1.0 / (2.0 ** (i+1)));
        end
        
        if (exp == 15'h7FFF) begin
            result = (mant == 0) ? (sign ? -1.0/0.0 : 1.0/0.0) : 0.0/0.0;
        end else if (exp == 0) begin
            result = 0.0;  // Simplified - ignoring subnormals for display
        end else begin
            result = (sign ? -1.0 : 1.0) * (1.0 + mant_real) * (2.0 ** (int'(exp) - 16383));
        end
        return result;
    endfunction
    
    task automatic submit_test(
        input [127:0] test_a,
        input [127:0] test_b, 
        input [127:0] test_c,
        input [127:0] expected,
        input string  name
    );
        expected_t exp_entry;
        
        a = test_a;
        b = test_b;
        c = test_c;
        valid_in = 1'b1;
        
        exp_entry.expected_result = expected;
        exp_entry.test_name = name;
        expected_queue.push_back(exp_entry);
        
        test_count++;
        @(posedge clk);
    endtask
    
    task automatic check_output();
        expected_t exp_entry;
        logic match;
        
        if (valid_out && expected_queue.size() > 0) begin
            exp_entry = expected_queue.pop_front();
            
            if (exp_entry.expected_result[126:112] == 15'h7FFF && 
                exp_entry.expected_result[111:0] != 0) begin
                match = nan_out;
            end else begin
                match = (result == exp_entry.expected_result);
            end
            
            if (match) begin
                pass_count++;
                $display("[PASS] %s: result = 0x%032h (%.4f)",
                         exp_entry.test_name, result, qp_to_real(result));
            end else begin
                fail_count++;
                $display("[FAIL] %s", exp_entry.test_name);
                $display("       Expected: 0x%032h (%.4f)", 
                         exp_entry.expected_result, qp_to_real(exp_entry.expected_result));
                $display("       Got:      0x%032h (%.4f)", 
                         result, qp_to_real(result));
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
    
    // QP Constants
    localparam [127:0] QP_ZERO     = 128'h00000000000000000000000000000000;
    localparam [127:0] QP_ONE      = 128'h3FFF0000000000000000000000000000;
    localparam [127:0] QP_TWO      = 128'h40000000000000000000000000000000;
    localparam [127:0] QP_THREE    = 128'h40008000000000000000000000000000;
    localparam [127:0] QP_FOUR     = 128'h40010000000000000000000000000000;
    localparam [127:0] QP_FIVE     = 128'h40014000000000000000000000000000;
    localparam [127:0] QP_SIX      = 128'h40018000000000000000000000000000;
    localparam [127:0] QP_SEVEN    = 128'h4001C000000000000000000000000000;
    localparam [127:0] QP_EIGHT    = 128'h40020000000000000000000000000000;
    localparam [127:0] QP_TEN      = 128'h40024000000000000000000000000000;
    localparam [127:0] QP_HALF     = 128'h3FFE0000000000000000000000000000;
    localparam [127:0] QP_NEG_ONE  = 128'hBFFF0000000000000000000000000000;
    localparam [127:0] QP_NEG_TWO  = 128'hC0000000000000000000000000000000;
    localparam [127:0] QP_INF      = 128'h7FFF0000000000000000000000000000;
    localparam [127:0] QP_NEG_INF  = 128'hFFFF0000000000000000000000000000;
    localparam [127:0] QP_NAN      = 128'h7FFF8000000000000000000000000000;
    localparam [127:0] QP_NEG_SIX  = 128'hC0018000000000000000000000000000;
    localparam [127:0] QP_NEG_FIVE = 128'hC0014000000000000000000000000000;
    
    initial begin
        $display("================================================================");
        $display("Pipelined QP FMA Testbench");
        $display("Pipeline Depth: %0d cycles", PIPELINE_DEPTH);
        $display("================================================================\n");
        
        rst = 1'b1;
        valid_in = 1'b0;
        a = 128'b0;
        b = 128'b0;
        c = 128'b0;
        
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        
        //======================================================================
        // Test Group 1: Basic FMA Operations
        //======================================================================
        $display("\n--- Test Group 1: Basic FMA Operations ---\n");
        
        submit_test(QP_ONE, QP_ONE, QP_ZERO, QP_ONE, "1×1+0=1");
        submit_test(QP_TWO, QP_THREE, QP_ONE, QP_SEVEN, "2×3+1=7");
        submit_test(QP_TWO, QP_TWO, QP_ZERO, QP_FOUR, "2×2+0=4");
        submit_test(QP_ONE, QP_ONE, QP_ONE, QP_TWO, "1×1+1=2");
        submit_test(QP_THREE, QP_THREE, QP_ONE, QP_TEN, "3×3+1=10");
        submit_test(QP_HALF, QP_FOUR, QP_ZERO, QP_TWO, "0.5×4+0=2");
        submit_test(QP_TWO, QP_FOUR, QP_ZERO, QP_EIGHT, "2×4+0=8");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 2: Pipeline Throughput
        //======================================================================
        $display("\n--- Test Group 2: Pipeline Throughput ---\n");
        
        submit_test(QP_ONE, QP_ONE, QP_ZERO, QP_ONE, "Pipe[0]: 1×1+0");
        submit_test(QP_TWO, QP_ONE, QP_ZERO, QP_TWO, "Pipe[1]: 2×1+0");
        submit_test(QP_THREE, QP_ONE, QP_ZERO, QP_THREE, "Pipe[2]: 3×1+0");
        submit_test(QP_FOUR, QP_ONE, QP_ZERO, QP_FOUR, "Pipe[3]: 4×1+0");
        submit_test(QP_FIVE, QP_ONE, QP_ZERO, QP_FIVE, "Pipe[4]: 5×1+0");
        submit_test(QP_SIX, QP_ONE, QP_ZERO, QP_SIX, "Pipe[5]: 6×1+0");
        submit_test(QP_SEVEN, QP_ONE, QP_ZERO, QP_SEVEN, "Pipe[6]: 7×1+0");
        submit_test(QP_EIGHT, QP_ONE, QP_ZERO, QP_EIGHT, "Pipe[7]: 8×1+0");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 3: Negative Numbers
        //======================================================================
        $display("\n--- Test Group 3: Negative Numbers ---\n");
        
        submit_test(QP_NEG_ONE, QP_ONE, QP_ZERO, QP_NEG_ONE, "(-1)×1+0=-1");
        submit_test(QP_NEG_ONE, QP_NEG_ONE, QP_ZERO, QP_ONE, "(-1)×(-1)+0=1");
        submit_test(QP_TWO, QP_NEG_ONE, QP_ZERO, QP_NEG_TWO, "2×(-1)+0=-2");
        submit_test(QP_TWO, QP_THREE, QP_NEG_ONE, QP_FIVE, "2×3+(-1)=5");
        submit_test(QP_NEG_TWO, QP_THREE, QP_ONE, QP_NEG_FIVE, "(-2)×3+1=-5");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 4: Zero Cases
        //======================================================================
        $display("\n--- Test Group 4: Zero Cases ---\n");
        
        submit_test(QP_ZERO, QP_FIVE, QP_THREE, QP_THREE, "0×5+3=3");
        submit_test(QP_FIVE, QP_ZERO, QP_THREE, QP_THREE, "5×0+3=3");
        submit_test(QP_ZERO, QP_ZERO, QP_ZERO, QP_ZERO, "0×0+0=0");
        submit_test(QP_TWO, QP_THREE, QP_ZERO, QP_SIX, "2×3+0=6");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 5: Infinity and NaN Cases
        //======================================================================
        $display("\n--- Test Group 5: Infinity and NaN Cases ---\n");
        
        submit_test(QP_INF, QP_ONE, QP_ZERO, QP_INF, "inf×1+0=inf");
        submit_test(QP_ONE, QP_INF, QP_ZERO, QP_INF, "1×inf+0=inf");
        submit_test(QP_INF, QP_ZERO, QP_ONE, QP_NAN, "inf×0+1=NaN");
        submit_test(QP_NAN, QP_ONE, QP_ZERO, QP_NAN, "NaN×1+0=NaN");
        submit_test(QP_ONE, QP_ONE, QP_NAN, QP_NAN, "1×1+NaN=NaN");
        submit_test(QP_INF, QP_ONE, QP_NEG_INF, QP_NAN, "inf×1+(-inf)=NaN");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 6: Cancellation
        //======================================================================
        $display("\n--- Test Group 6: Cancellation Cases ---\n");
        
        submit_test(QP_THREE, QP_TWO, QP_NEG_SIX, QP_ZERO, "3×2+(-6)=0");
        
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
        #200000;
        $display("\n*** TIMEOUT ***\n");
        $finish;
    end

endmodule