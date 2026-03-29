////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_qp_fma_toplv_pipelined
// Description: Testbench for the top-level pipelined multiple-precision FMA
//              Tests all precision modes: QP, DP, SP, HP
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_qp_fma_toplv_pipelined;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam CLK_PERIOD = 10;
    localparam PIPELINE_DEPTH = 4;  // 1 input reg + 3 FMA pipeline stages
    
    // Precision modes
    localparam [1:0] MODE_QP = 2'b00;
    localparam [1:0] MODE_DP = 2'b01;
    localparam [1:0] MODE_SP = 2'b10;
    localparam [1:0] MODE_HP = 2'b11;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    
    logic         clk;
    logic         rst;
    logic         valid_in;
    logic [127:0] A, B, C;
    logic [1:0]   precision;
    
    logic [127:0] toplv_result;
    logic [7:0]   overflow_flags;
    logic [7:0]   underflow_flags;
    logic [7:0]   nan_flags;
    logic         valid_out;
    
    //==========================================================================
    // Test Infrastructure
    //==========================================================================
    
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;
    
    typedef struct {
        logic [127:0] expected_result;
        logic [1:0]   precision_mode;
        string        test_name;
    } expected_t;
    
    expected_t expected_queue[$];
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    qp_fma_toplv_pipelined dut (
        .clk            ( clk             ),
        .rst            ( rst             ),
        .valid_in       ( valid_in        ),
        .A              ( A               ),
        .B              ( B               ),
        .C              ( C               ),
        .precision      ( precision       ),
        .toplv_result   ( toplv_result    ),
        .overflow_flags ( overflow_flags  ),
        .underflow_flags( underflow_flags ),
        .nan_flags      ( nan_flags       ),
        .valid_out      ( valid_out       )
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // Floating-Point Constants
    //==========================================================================
    
    // HP Constants (16-bit)
    localparam [15:0] HP_ZERO    = 16'h0000;
    localparam [15:0] HP_ONE     = 16'h3C00;
    localparam [15:0] HP_TWO     = 16'h4000;
    localparam [15:0] HP_THREE   = 16'h4200;
    localparam [15:0] HP_FOUR    = 16'h4400;
    localparam [15:0] HP_SEVEN   = 16'h4700;
    localparam [15:0] HP_NEG_ONE = 16'hBC00;
    
    // SP Constants (32-bit)
    localparam [31:0] SP_ZERO    = 32'h00000000;
    localparam [31:0] SP_ONE     = 32'h3F800000;
    localparam [31:0] SP_TWO     = 32'h40000000;
    localparam [31:0] SP_THREE   = 32'h40400000;
    localparam [31:0] SP_FOUR    = 32'h40800000;
    localparam [31:0] SP_SEVEN   = 32'h40E00000;
    localparam [31:0] SP_NEG_ONE = 32'hBF800000;
    
    // DP Constants (64-bit)
    localparam [63:0] DP_ZERO    = 64'h0000000000000000;
    localparam [63:0] DP_ONE     = 64'h3FF0000000000000;
    localparam [63:0] DP_TWO     = 64'h4000000000000000;
    localparam [63:0] DP_THREE   = 64'h4008000000000000;
    localparam [63:0] DP_FOUR    = 64'h4010000000000000;
    localparam [63:0] DP_SEVEN   = 64'h401C000000000000;
    localparam [63:0] DP_NEG_ONE = 64'hBFF0000000000000;
    
    // QP Constants (128-bit)
    localparam [127:0] QP_ZERO    = 128'h00000000000000000000000000000000;
    localparam [127:0] QP_ONE     = 128'h3FFF0000000000000000000000000000;
    localparam [127:0] QP_TWO     = 128'h40000000000000000000000000000000;
    localparam [127:0] QP_THREE   = 128'h40008000000000000000000000000000;
    localparam [127:0] QP_FOUR    = 128'h40010000000000000000000000000000;
    localparam [127:0] QP_SEVEN   = 128'h4001C000000000000000000000000000;
    localparam [127:0] QP_NEG_ONE = 128'hBFFF0000000000000000000000000000;
    
    //==========================================================================
    // Helper Tasks
    //==========================================================================
    
    task automatic submit_test(
        input [127:0] test_a,
        input [127:0] test_b,
        input [127:0] test_c,
        input [1:0]   test_precision,
        input [127:0] expected,
        input string  name
    );
        expected_t exp_entry;
        
        A = test_a;
        B = test_b;
        C = test_c;
        precision = test_precision;
        valid_in = 1'b1;
        
        exp_entry.expected_result = expected;
        exp_entry.precision_mode = test_precision;
        exp_entry.test_name = name;
        expected_queue.push_back(exp_entry);
        
        test_count++;
        @(posedge clk);
    endtask
    
    task automatic check_output();
        expected_t exp_entry;
        logic match;
        string mode_str;
        
        if (valid_out && expected_queue.size() > 0) begin
            exp_entry = expected_queue.pop_front();
            match = (toplv_result == exp_entry.expected_result);
            
            case (exp_entry.precision_mode)
                MODE_QP: mode_str = "QP";
                MODE_DP: mode_str = "DP";
                MODE_SP: mode_str = "SP";
                MODE_HP: mode_str = "HP";
                default: mode_str = "??";
            endcase
            
            if (match) begin
                pass_count++;
                $display("[PASS] [%s] %s", mode_str, exp_entry.test_name);
                $display("       Result: 0x%032h", toplv_result);
            end else begin
                fail_count++;
                $display("[FAIL] [%s] %s", mode_str, exp_entry.test_name);
                $display("       Expected: 0x%032h", exp_entry.expected_result);
                $display("       Got:      0x%032h", toplv_result);
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
    
    initial begin
        $display("================================================================");
        $display("Top-Level Pipelined Multiple-Precision FMA Testbench");
        $display("Pipeline Depth: %0d cycles", PIPELINE_DEPTH);
        $display("================================================================\n");
        
        // Initialize
        rst = 1'b1;
        valid_in = 1'b0;
        A = 128'b0;
        B = 128'b0;
        C = 128'b0;
        precision = MODE_QP;
        
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);
        
        //======================================================================
        // Test Group 1: QP Mode Tests
        //======================================================================
        $display("\n--- Test Group 1: QP Mode (128-bit) ---\n");
        
        // 1×1+0 = 1
        submit_test(
            QP_ONE, QP_ONE, QP_ZERO,
            MODE_QP,
            QP_ONE,
            "QP: 1×1+0=1"
        );
        
        // 2×3+1 = 7
        submit_test(
            QP_TWO, QP_THREE, QP_ONE,
            MODE_QP,
            QP_SEVEN,
            "QP: 2×3+1=7"
        );
        
        // 2×2+0 = 4
        submit_test(
            QP_TWO, QP_TWO, QP_ZERO,
            MODE_QP,
            QP_FOUR,
            "QP: 2×2+0=4"
        );
        
        // (-1)×1+0 = -1
        submit_test(
            QP_NEG_ONE, QP_ONE, QP_ZERO,
            MODE_QP,
            QP_NEG_ONE,
            "QP: (-1)×1+0=-1"
        );
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 2: DP Mode Tests (2 parallel operations)
        //======================================================================
        $display("\n--- Test Group 2: DP Mode (2×64-bit) ---\n");
        
        // Lane 0: 1×1+0=1, Lane 1: 2×2+0=4
        submit_test(
            {DP_TWO, DP_ONE},      // A: {lane1, lane0}
            {DP_TWO, DP_ONE},      // B
            {DP_ZERO, DP_ZERO},    // C
            MODE_DP,
            {DP_FOUR, DP_ONE},     // Expected: {4, 1}
            "DP: L0:1×1+0=1, L1:2×2+0=4"
        );
        
        // Lane 0: 2×3+1=7, Lane 1: 1×1+0=1
        submit_test(
            {DP_ONE, DP_TWO},
            {DP_ONE, DP_THREE},
            {DP_ZERO, DP_ONE},
            MODE_DP,
            {DP_ONE, DP_SEVEN},
            "DP: L0:2×3+1=7, L1:1×1+0=1"
        );
        
        // Test with negative: Lane 0: (-1)×1+0=-1, Lane 1: 2×2+0=4
        submit_test(
            {DP_TWO, DP_NEG_ONE},
            {DP_TWO, DP_ONE},
            {DP_ZERO, DP_ZERO},
            MODE_DP,
            {DP_FOUR, DP_NEG_ONE},
            "DP: L0:(-1)×1+0=-1, L1:2×2+0=4"
        );
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 3: SP Mode Tests (4 parallel operations)
        //======================================================================
        $display("\n--- Test Group 3: SP Mode (4×32-bit) ---\n");
        
        // All lanes: 1×1+0=1
        submit_test(
            {SP_ONE, SP_ONE, SP_ONE, SP_ONE},
            {SP_ONE, SP_ONE, SP_ONE, SP_ONE},
            {SP_ZERO, SP_ZERO, SP_ZERO, SP_ZERO},
            MODE_SP,
            {SP_ONE, SP_ONE, SP_ONE, SP_ONE},
            "SP: All lanes 1×1+0=1"
        );
        
        // Lane 0: 2×3+1=7, Lane 1: 2×2+0=4, Lane 2: 1×1+0=1, Lane 3: 1×1+1=2
        submit_test(
            {SP_ONE, SP_ONE, SP_TWO, SP_TWO},
            {SP_ONE, SP_ONE, SP_TWO, SP_THREE},
            {SP_ONE, SP_ZERO, SP_ZERO, SP_ONE},
            MODE_SP,
            {SP_TWO, SP_ONE, SP_FOUR, SP_SEVEN},
            "SP: L0:2×3+1=7, L1:2×2+0=4, L2:1×1+0=1, L3:1×1+1=2"
        );
        
        // Test with negative
        submit_test(
            {SP_TWO, SP_NEG_ONE, SP_TWO, SP_ONE},
            {SP_TWO, SP_ONE, SP_TWO, SP_ONE},
            {SP_ZERO, SP_ZERO, SP_ZERO, SP_ZERO},
            MODE_SP,
            {SP_FOUR, SP_NEG_ONE, SP_FOUR, SP_ONE},
            "SP: Mixed positive/negative"
        );
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 4: HP Mode Tests (8 parallel operations)
        //======================================================================
        $display("\n--- Test Group 4: HP Mode (8×16-bit) ---\n");
        
        // All lanes: 1×1+0=1
        submit_test(
            {HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
            {HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
            {HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO},
            MODE_HP,
            {HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
            "HP: All lanes 1×1+0=1"
        );
        
        // Mixed operations across 8 lanes
        submit_test(
            {HP_TWO, HP_ONE, HP_TWO, HP_ONE, HP_TWO, HP_ONE, HP_TWO, HP_ONE},
            {HP_THREE, HP_ONE, HP_TWO, HP_ONE, HP_TWO, HP_ONE, HP_ONE, HP_ONE},
            {HP_ONE, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO},
            MODE_HP,
            {HP_SEVEN, HP_ONE, HP_FOUR, HP_ONE, HP_FOUR, HP_ONE, HP_TWO, HP_ONE},
            "HP: Mixed operations 8 lanes"
        );
        
        // Test with negative
        submit_test(
            {HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE},
            {HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
            {HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO},
            MODE_HP,
            {HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE, HP_ONE, HP_NEG_ONE},
            "HP: Alternating signs"
        );
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 2) @(posedge clk);
        
        //======================================================================
        // Test Group 5: Pipeline Throughput Test (Mixed Modes)
        //======================================================================
        $display("\n--- Test Group 5: Pipeline Throughput (Mixed Modes) ---\n");
        
        // Submit operations in rapid succession with different modes
        submit_test(QP_TWO, QP_TWO, QP_ZERO, MODE_QP, QP_FOUR, "Pipe[0] QP: 2×2+0=4");
        submit_test({DP_TWO, DP_ONE}, {DP_TWO, DP_ONE}, {DP_ZERO, DP_ZERO}, MODE_DP, {DP_FOUR, DP_ONE}, "Pipe[1] DP: 2×2,1×1");
        submit_test({SP_TWO, SP_TWO, SP_ONE, SP_ONE}, {SP_TWO, SP_TWO, SP_ONE, SP_ONE}, {SP_ZERO, SP_ZERO, SP_ZERO, SP_ZERO}, MODE_SP, {SP_FOUR, SP_FOUR, SP_ONE, SP_ONE}, "Pipe[2] SP: 4 ops");
        submit_test({HP_TWO, HP_TWO, HP_TWO, HP_TWO, HP_ONE, HP_ONE, HP_ONE, HP_ONE}, 
                    {HP_TWO, HP_TWO, HP_TWO, HP_TWO, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
                    {HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO, HP_ZERO},
                    MODE_HP,
                    {HP_FOUR, HP_FOUR, HP_FOUR, HP_FOUR, HP_ONE, HP_ONE, HP_ONE, HP_ONE},
                    "Pipe[3] HP: 8 ops");
        submit_test(QP_ONE, QP_ONE, QP_ONE, MODE_QP, QP_TWO, "Pipe[4] QP: 1×1+1=2");
        
        valid_in = 1'b0;
        repeat (PIPELINE_DEPTH + 3) @(posedge clk);
        
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
    // Timeout
    //==========================================================================
    
    initial begin
        #500000;
        $display("\n*** TIMEOUT ***\n");
        $finish;
    end

endmodule