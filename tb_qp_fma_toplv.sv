////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_qp_fma_toplv
// Description: Testbench for the top-level Multiple-Precision FMA Unit
//              Tests output multiplexing for QP, DP, SP, and HP modes
//
// Precision Modes:
//   2'b00 - QP: 1 × 128-bit Quadruple-Precision FMA
//   2'b01 - DP: 2 × 64-bit Double-Precision FMAs
//   2'b10 - SP: 4 × 32-bit Single-Precision FMAs
//   2'b11 - HP: 8 × 16-bit Half-Precision FMAs
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module tb_qp_fma_toplv;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam CLK_PERIOD = 10;  // 100 MHz clock

    //==========================================================================
    // Signals
    //==========================================================================
    
    logic [127:0] A;
    logic [127:0] B;
    logic [127:0] C;
    logic [1:0]   precision;
    logic [7:0]   op;
    logic         clk;
    logic         rst;
    logic [127:0] toplv_result;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    qp_fma_toplv dut (
        .A           ( A            ),
        .B           ( B            ),
        .C           ( C            ),
        .precision   ( precision    ),
        .op          ( op           ),
        .clk         ( clk          ),
        .rst         ( rst          ),
        .toplv_result( toplv_result )
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Helper Functions for Value Conversion
    //==========================================================================
    
    // Half-precision to real conversion
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
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / 1024.0) * (2.0**(exp - 15));
        end
        return result;
    endfunction

    // Single-precision to real conversion
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
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / (2.0**23)) * (2.0**(exp - 127));
        end
        return result;
    endfunction

    // Double-precision to real conversion
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
            result = (sign ? -1.0 : 1.0) * (1.0 + real'(mant) / (2.0**52)) * (2.0**(exp - 1023));
        end
        return result;
    endfunction

    //==========================================================================
    // Test Sequence
    //==========================================================================
    
    initial begin
        $display("================================================================");
        $display("Top-Level FMA Multiplexing Testbench");
        $display("================================================================");
        
        // Initialize signals
        A = 128'b0;
        B = 128'b0;
        C = 128'b0;
        precision = 2'b00;
        op = 8'b0;
        rst = 1'b1;
        
        // Reset sequence
        @(posedge clk);
        @(posedge clk);
        rst = 1'b0;
        @(posedge clk);
        
        //======================================================================
        // Test 1: HP Mode (precision = 2'b11)
        // 8 parallel HP FMAs: A[i] × B[i] + C[i] for each 16-bit lane
        //======================================================================
        $display("\n========================================");
        $display("Test 1: HP Mode (8 parallel 16-bit FMAs)");
        $display("========================================");
        
        // HP values: 1.0 = 0x3C00, 2.0 = 0x4000, 3.0 = 0x4200, etc.
        // Lane 0: 1.0 × 1.0 + 0.0 = 1.0
        // Lane 1: 2.0 × 2.0 + 0.0 = 4.0
        // Lane 2: 1.5 × 2.0 + 0.0 = 3.0
        // Lane 3: 2.0 × 3.0 + 1.0 = 7.0
        // Lane 4: 1.0 × 1.0 + 1.0 = 2.0
        // Lane 5: 2.0 × 2.0 + 1.0 = 5.0
        // Lane 6: 0.5 × 4.0 + 0.0 = 2.0
        // Lane 7: 3.0 × 3.0 + 0.0 = 9.0
        
        A = {16'h4200, 16'h3800, 16'h4000, 16'h3C00,  // Lanes 7-4: 3.0, 0.5, 2.0, 1.0
             16'h4000, 16'h3E00, 16'h4000, 16'h3C00}; // Lanes 3-0: 2.0, 1.5, 2.0, 1.0
        B = {16'h4200, 16'h4400, 16'h4000, 16'h3C00,  // Lanes 7-4: 3.0, 4.0, 2.0, 1.0
             16'h4200, 16'h4000, 16'h4000, 16'h3C00}; // Lanes 3-0: 3.0, 2.0, 2.0, 1.0
        C = {16'h0000, 16'h0000, 16'h3C00, 16'h3C00,  // Lanes 7-4: 0.0, 0.0, 1.0, 1.0
             16'h3C00, 16'h0000, 16'h0000, 16'h0000}; // Lanes 3-0: 1.0, 0.0, 0.0, 0.0
        precision = 2'b11;
        
        @(posedge clk);  // Load inputs
        @(posedge clk);  // Wait for registered output
        @(posedge clk);  // Extra cycle for combinational logic
        #1;
        
        $display("Inputs:");
        $display("  A = 0x%032h", A);
        $display("  B = 0x%032h", B);
        $display("  C = 0x%032h", C);
        $display("  precision = %b (HP mode)", precision);
        $display("\nResults (toplv_result = 0x%032h):", toplv_result);
        
        for (int i = 0; i < 8; i++) begin
            $display("  Lane %0d: A=%.2f, B=%.2f, C=%.2f => Result=0x%04h (%.4f)",
                     i,
                     hp_to_real(A[i*16 +: 16]),
                     hp_to_real(B[i*16 +: 16]),
                     hp_to_real(C[i*16 +: 16]),
                     toplv_result[i*16 +: 16],
                     hp_to_real(toplv_result[i*16 +: 16]));
        end
        
        //======================================================================
        // Test 2: SP Mode (precision = 2'b10)
        // 4 parallel SP FMAs: A[i] × B[i] + C[i] for each 32-bit lane
        //======================================================================
        $display("\n========================================");
        $display("Test 2: SP Mode (4 parallel 32-bit FMAs)");
        $display("========================================");
        
        // SP values: 1.0 = 0x3F800000, 2.0 = 0x40000000, 3.0 = 0x40400000
        // Lane 0: 2.0 × 3.0 + 1.0 = 7.0
        // Lane 1: 1.5 × 2.0 + 0.5 = 3.5
        // Lane 2: 4.0 × 0.5 + 1.0 = 3.0
        // Lane 3: 5.0 × 2.0 + 0.0 = 10.0
        
        A = {32'h40A00000, 32'h40800000, 32'h3FC00000, 32'h40000000};  // 5.0, 4.0, 1.5, 2.0
        B = {32'h40000000, 32'h3F000000, 32'h40000000, 32'h40400000};  // 2.0, 0.5, 2.0, 3.0
        C = {32'h00000000, 32'h3F800000, 32'h3F000000, 32'h3F800000};  // 0.0, 1.0, 0.5, 1.0
        precision = 2'b10;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Inputs:");
        $display("  A = 0x%032h", A);
        $display("  B = 0x%032h", B);
        $display("  C = 0x%032h", C);
        $display("  precision = %b (SP mode)", precision);
        $display("\nResults (toplv_result = 0x%032h):", toplv_result);
        
        for (int i = 0; i < 4; i++) begin
            $display("  Lane %0d: A=%.4f, B=%.4f, C=%.4f => Result=0x%08h (%.6f)",
                     i,
                     sp_to_real(A[i*32 +: 32]),
                     sp_to_real(B[i*32 +: 32]),
                     sp_to_real(C[i*32 +: 32]),
                     toplv_result[i*32 +: 32],
                     sp_to_real(toplv_result[i*32 +: 32]));
        end
        
        //======================================================================
        // Test 3: DP Mode (precision = 2'b01)
        // 2 parallel DP FMAs: A[i] × B[i] + C[i] for each 64-bit lane
        //======================================================================
        $display("\n========================================");
        $display("Test 3: DP Mode (2 parallel 64-bit FMAs)");
        $display("========================================");
        
        // DP values: 1.0 = 0x3FF0000000000000, 2.0 = 0x4000000000000000
        // Lane 0: 2.0 × 3.0 + 1.0 = 7.0
        // Lane 1: 1.5 × 4.0 + 2.0 = 8.0
        
        A = {64'h3FF8000000000000, 64'h4000000000000000};  // 1.5, 2.0
        B = {64'h4010000000000000, 64'h4008000000000000};  // 4.0, 3.0
        C = {64'h4000000000000000, 64'h3FF0000000000000};  // 2.0, 1.0
        precision = 2'b01;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Inputs:");
        $display("  A = 0x%032h", A);
        $display("  B = 0x%032h", B);
        $display("  C = 0x%032h", C);
        $display("  precision = %b (DP mode)", precision);
        $display("\nResults (toplv_result = 0x%032h):", toplv_result);
        
        for (int i = 0; i < 2; i++) begin
            $display("  Lane %0d: A=%.6f, B=%.6f, C=%.6f => Result=0x%016h (%.10f)",
                     i,
                     dp_to_real(A[i*64 +: 64]),
                     dp_to_real(B[i*64 +: 64]),
                     dp_to_real(C[i*64 +: 64]),
                     toplv_result[i*64 +: 64],
                     dp_to_real(toplv_result[i*64 +: 64]));
        end
        
        //======================================================================
        // Test 4: QP Mode (precision = 2'b00)
        // 1 QP FMA: A × B + C (128-bit operation)
        //======================================================================
        $display("\n========================================");
        $display("Test 4: QP Mode (1 × 128-bit FMA)");
        $display("========================================");
        
        // QP 1.0 = 0x3FFF0000000000000000000000000000
        // QP 2.0 = 0x40000000000000000000000000000000
        // QP 3.0 = 0x40008000000000000000000000000000
        // Test: 2.0 × 3.0 + 1.0 = 7.0
        
        A = 128'h40000000000000000000000000000000;  // 2.0 in QP
        B = 128'h40008000000000000000000000000000;  // 3.0 in QP
        C = 128'h3FFF0000000000000000000000000000;  // 1.0 in QP
        precision = 2'b00;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Inputs:");
        $display("  A = 0x%032h (QP 2.0)", A);
        $display("  B = 0x%032h (QP 3.0)", B);
        $display("  C = 0x%032h (QP 1.0)", C);
        $display("  precision = %b (QP mode)", precision);
        $display("\nResult:");
        $display("  toplv_result = 0x%032h", toplv_result);
        $display("  Expected     = 0x4001C000000000000000000000000000 (QP 7.0)");
        
        //======================================================================
        // Test 5: Verify Multiplexer Switching
        // Apply same inputs, switch precision modes
        //======================================================================
        $display("\n========================================");
        $display("Test 5: Multiplexer Switching Verification");
        $display("========================================");
        
        // Use distinct patterns to verify correct mux selection
        A = 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        B = 128'h00000000000000000000000000000000;  // Zero to simplify
        C = 128'h12345678ABCDEF0011223344556677889900AABBCCDDEEFF00;
        
        $display("Fixed inputs: A=all 1s, B=all 0s, C=pattern");
        $display("Result should be C (since A×0 = 0, so result = 0 + C = C)");
        $display("");
        
        // Test each precision mode
        for (int p = 0; p < 4; p++) begin
            precision = p[1:0];
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            #1;
            
            case (p)
                0: $display("QP Mode (precision=00): result = 0x%032h", toplv_result);
                1: $display("DP Mode (precision=01): result = 0x%032h", toplv_result);
                2: $display("SP Mode (precision=10): result = 0x%032h", toplv_result);
                3: $display("HP Mode (precision=11): result = 0x%032h", toplv_result);
            endcase
        end
        
        //======================================================================
        // Test 6: Verify Lane Independence in HP Mode
        //======================================================================
        $display("\n========================================");
        $display("Test 6: HP Lane Independence");
        $display("========================================");
        
        // Each lane has unique values to verify independence
        // All lanes: 1.0 × 1.0 + lane_number = lane_number + 1
        A = {16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00,
             16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00};  // All 1.0
        B = {16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00,
             16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00};  // All 1.0
        // C values: lane 0=0, lane 1=1, lane 2=2, ... lane 7=7
        C = {16'h4700, 16'h4600, 16'h4500, 16'h4400,   // 7.0, 6.0, 5.0, 4.0
             16'h4200, 16'h4000, 16'h3C00, 16'h0000};  // 3.0, 2.0, 1.0, 0.0
        precision = 2'b11;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Test: 1.0 × 1.0 + lane_num for each lane");
        $display("Expected: Lane N result = N + 1");
        for (int i = 0; i < 8; i++) begin
            $display("  Lane %0d: C=%.1f => Result=%.1f (expected %.1f)",
                     i,
                     hp_to_real(C[i*16 +: 16]),
                     hp_to_real(toplv_result[i*16 +: 16]),
                     hp_to_real(C[i*16 +: 16]) + 1.0);
        end
        
        //======================================================================
        // Test 7: Verify Lane Independence in SP Mode
        //======================================================================
        $display("\n========================================");
        $display("Test 7: SP Lane Independence");
        $display("========================================");
        
        // Lane 0: 1×1+10 = 11, Lane 1: 1×1+20 = 21, Lane 2: 1×1+30 = 31, Lane 3: 1×1+40 = 41
        A = {32'h3F800000, 32'h3F800000, 32'h3F800000, 32'h3F800000};  // All 1.0
        B = {32'h3F800000, 32'h3F800000, 32'h3F800000, 32'h3F800000};  // All 1.0
        C = {32'h42200000, 32'h41F00000, 32'h41A00000, 32'h41200000};  // 40.0, 30.0, 20.0, 10.0
        precision = 2'b10;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Test: 1.0 × 1.0 + C for each lane");
        for (int i = 0; i < 4; i++) begin
            $display("  Lane %0d: C=%.1f => Result=%.1f (expected %.1f)",
                     i,
                     sp_to_real(C[i*32 +: 32]),
                     sp_to_real(toplv_result[i*32 +: 32]),
                     sp_to_real(C[i*32 +: 32]) + 1.0);
        end
        
        //======================================================================
        // Test 8: Verify Lane Independence in DP Mode
        //======================================================================
        $display("\n========================================");
        $display("Test 8: DP Lane Independence");
        $display("========================================");
        
        // Lane 0: 2×3+100 = 106, Lane 1: 3×4+200 = 212
        A = {64'h4008000000000000, 64'h4000000000000000};  // 3.0, 2.0
        B = {64'h4010000000000000, 64'h4008000000000000};  // 4.0, 3.0
        C = {64'h4069000000000000, 64'h4059000000000000};  // 200.0, 100.0
        precision = 2'b01;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        #1;
        
        $display("Test: A × B + C for each lane");
        for (int i = 0; i < 2; i++) begin
            real a_val, b_val, c_val, expected;
            a_val = dp_to_real(A[i*64 +: 64]);
            b_val = dp_to_real(B[i*64 +: 64]);
            c_val = dp_to_real(C[i*64 +: 64]);
            expected = a_val * b_val + c_val;
            $display("  Lane %0d: %.1f × %.1f + %.1f => Result=%.1f (expected %.1f)",
                     i, a_val, b_val, c_val,
                     dp_to_real(toplv_result[i*64 +: 64]),
                     expected);
        end
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n================================================================");
        $display("Testbench Complete");
        $display("================================================================");
        
        #100;
        $finish;
    end

endmodule