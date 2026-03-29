////////////////////////////////////////////////////////////////////////////////
// Module: qp_fma_toplv_pipelined
// Description: Top-level Multiple-Precision Pipelined FMA Unit
//              Supports QP, DP, SP, and HP precision modes
//              3-stage pipeline with 1 operation per cycle throughput
//
// Precision Modes (controlled by 'precision' input):
//   2'b00 - QP: 1 × 128-bit Quadruple-Precision FMA
//   2'b01 - DP: 2 × 64-bit Double-Precision FMAs
//   2'b10 - SP: 4 × 32-bit Single-Precision FMAs
//   2'b11 - HP: 8 × 16-bit Half-Precision FMAs
//
// Input Bit Allocations:
//   QP Mode: A[127:0], B[127:0], C[127:0] - single QP operands
//   DP Mode: A[127:64]/A[63:0], B[127:64]/B[63:0], C[127:64]/C[63:0] - 2 DP operands
//   SP Mode: A[127:96]/[95:64]/[63:32]/[31:0], etc. - 4 SP operands
//   HP Mode: A[127:112]/[111:96]/.../[15:0], etc. - 8 HP operands
//
// Pipeline:
//   Latency: 3 clock cycles
//   Throughput: 1 operation per clock cycle
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module qp_fma_toplv_pipelined (
    input  logic         clk,
    input  logic         rst,
    input  logic         valid_in,
    input  logic [127:0] A,
    input  logic [127:0] B,
    input  logic [127:0] C,
    input  logic [1:0]   precision,

    output logic [127:0] toplv_result,
    output logic [7:0]   overflow_flags,    // Per-lane overflow (meaning depends on precision)
    output logic [7:0]   underflow_flags,   // Per-lane underflow
    output logic [7:0]   nan_flags,         // Per-lane NaN
    output logic         valid_out
);

    //==========================================================================
    // Input Registers
    //==========================================================================
    
    logic [127:0] A_reg, B_reg, C_reg;
    logic [1:0]   precision_reg;
    logic         valid_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            A_reg         <= 128'h0;
            B_reg         <= 128'h0;
            C_reg         <= 128'h0;
            precision_reg <= 2'b00;
            valid_reg     <= 1'b0;
        end
        else begin
            A_reg         <= A;
            B_reg         <= B;
            C_reg         <= C;
            precision_reg <= precision;
            valid_reg     <= valid_in;
        end
    end

    //==========================================================================
    // Precision Pipeline (to align with FMA pipeline output)
    // FMA pipeline is 3 stages, input register adds 1 more cycle
    // Total latency from input to output: 4 cycles
    // Precision must be delayed to match result timing
    //==========================================================================
    
    logic [1:0] precision_d1, precision_d2, precision_d3;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            precision_d1 <= 2'b00;
            precision_d2 <= 2'b00;
            precision_d3 <= 2'b00;
        end
        else begin
            precision_d1 <= precision_reg;
            precision_d2 <= precision_d1;
            precision_d3 <= precision_d2;
        end
    end

    //==========================================================================
    // HP FMA Pipelined Instances (8 parallel 16-bit operations)
    //==========================================================================

    logic [127:0] result_hp;
    logic [7:0]   overflow_hp;
    logic [7:0]   underflow_hp;
    logic [7:0]   nan_hp;
    logic [7:0]   valid_hp;

    // Instance 0: bits [15:0]
    hp_fma_pipelined u_hp_fma0 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[15:0]        ),
        .b        ( B_reg[15:0]        ),
        .c        ( C_reg[15:0]        ),
        .result   ( result_hp[15:0]    ),
        .overflow ( overflow_hp[0]     ),
        .underflow( underflow_hp[0]    ),
        .nan_out  ( nan_hp[0]          ),
        .valid_out( valid_hp[0]        )
    );

    // Instance 1: bits [31:16]
    hp_fma_pipelined u_hp_fma1 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[31:16]       ),
        .b        ( B_reg[31:16]       ),
        .c        ( C_reg[31:16]       ),
        .result   ( result_hp[31:16]   ),
        .overflow ( overflow_hp[1]     ),
        .underflow( underflow_hp[1]    ),
        .nan_out  ( nan_hp[1]          ),
        .valid_out( valid_hp[1]        )
    );

    // Instance 2: bits [47:32]
    hp_fma_pipelined u_hp_fma2 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[47:32]       ),
        .b        ( B_reg[47:32]       ),
        .c        ( C_reg[47:32]       ),
        .result   ( result_hp[47:32]   ),
        .overflow ( overflow_hp[2]     ),
        .underflow( underflow_hp[2]    ),
        .nan_out  ( nan_hp[2]          ),
        .valid_out( valid_hp[2]        )
    );

    // Instance 3: bits [63:48]
    hp_fma_pipelined u_hp_fma3 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[63:48]       ),
        .b        ( B_reg[63:48]       ),
        .c        ( C_reg[63:48]       ),
        .result   ( result_hp[63:48]   ),
        .overflow ( overflow_hp[3]     ),
        .underflow( underflow_hp[3]    ),
        .nan_out  ( nan_hp[3]          ),
        .valid_out( valid_hp[3]        )
    );

    // Instance 4: bits [79:64]
    hp_fma_pipelined u_hp_fma4 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[79:64]       ),
        .b        ( B_reg[79:64]       ),
        .c        ( C_reg[79:64]       ),
        .result   ( result_hp[79:64]   ),
        .overflow ( overflow_hp[4]     ),
        .underflow( underflow_hp[4]    ),
        .nan_out  ( nan_hp[4]          ),
        .valid_out( valid_hp[4]        )
    );

    // Instance 5: bits [95:80]
    hp_fma_pipelined u_hp_fma5 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[95:80]       ),
        .b        ( B_reg[95:80]       ),
        .c        ( C_reg[95:80]       ),
        .result   ( result_hp[95:80]   ),
        .overflow ( overflow_hp[5]     ),
        .underflow( underflow_hp[5]    ),
        .nan_out  ( nan_hp[5]          ),
        .valid_out( valid_hp[5]        )
    );

    // Instance 6: bits [111:96]
    hp_fma_pipelined u_hp_fma6 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[111:96]      ),
        .b        ( B_reg[111:96]      ),
        .c        ( C_reg[111:96]      ),
        .result   ( result_hp[111:96]  ),
        .overflow ( overflow_hp[6]     ),
        .underflow( underflow_hp[6]    ),
        .nan_out  ( nan_hp[6]          ),
        .valid_out( valid_hp[6]        )
    );

    // Instance 7: bits [127:112]
    hp_fma_pipelined u_hp_fma7 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[127:112]     ),
        .b        ( B_reg[127:112]     ),
        .c        ( C_reg[127:112]     ),
        .result   ( result_hp[127:112] ),
        .overflow ( overflow_hp[7]     ),
        .underflow( underflow_hp[7]    ),
        .nan_out  ( nan_hp[7]          ),
        .valid_out( valid_hp[7]        )
    );

    //==========================================================================
    // SP FMA Pipelined Instances (4 parallel 32-bit operations)
    //==========================================================================

    logic [127:0] result_sp;
    logic [3:0]   overflow_sp;
    logic [3:0]   underflow_sp;
    logic [3:0]   nan_sp;
    logic [3:0]   valid_sp;

    // Instance 0: bits [31:0]
    sp_fma_pipelined u_sp_fma0 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[31:0]        ),
        .b        ( B_reg[31:0]        ),
        .c        ( C_reg[31:0]        ),
        .result   ( result_sp[31:0]    ),
        .overflow ( overflow_sp[0]     ),
        .underflow( underflow_sp[0]    ),
        .nan_out  ( nan_sp[0]          ),
        .valid_out( valid_sp[0]        )
    );

    // Instance 1: bits [63:32]
    sp_fma_pipelined u_sp_fma1 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[63:32]       ),
        .b        ( B_reg[63:32]       ),
        .c        ( C_reg[63:32]       ),
        .result   ( result_sp[63:32]   ),
        .overflow ( overflow_sp[1]     ),
        .underflow( underflow_sp[1]    ),
        .nan_out  ( nan_sp[1]          ),
        .valid_out( valid_sp[1]        )
    );

    // Instance 2: bits [95:64]
    sp_fma_pipelined u_sp_fma2 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[95:64]       ),
        .b        ( B_reg[95:64]       ),
        .c        ( C_reg[95:64]       ),
        .result   ( result_sp[95:64]   ),
        .overflow ( overflow_sp[2]     ),
        .underflow( underflow_sp[2]    ),
        .nan_out  ( nan_sp[2]          ),
        .valid_out( valid_sp[2]        )
    );

    // Instance 3: bits [127:96]
    sp_fma_pipelined u_sp_fma3 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[127:96]      ),
        .b        ( B_reg[127:96]      ),
        .c        ( C_reg[127:96]      ),
        .result   ( result_sp[127:96]  ),
        .overflow ( overflow_sp[3]     ),
        .underflow( underflow_sp[3]    ),
        .nan_out  ( nan_sp[3]          ),
        .valid_out( valid_sp[3]        )
    );

    //==========================================================================
    // DP FMA Pipelined Instances (2 parallel 64-bit operations)
    //==========================================================================

    logic [127:0] result_dp;
    logic [1:0]   overflow_dp;
    logic [1:0]   underflow_dp;
    logic [1:0]   nan_dp;
    logic [1:0]   valid_dp;

    // Instance 0: bits [63:0]
    dp_fma_pipelined u_dp_fma0 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[63:0]        ),
        .b        ( B_reg[63:0]        ),
        .c        ( C_reg[63:0]        ),
        .result   ( result_dp[63:0]    ),
        .overflow ( overflow_dp[0]     ),
        .underflow( underflow_dp[0]    ),
        .nan_out  ( nan_dp[0]          ),
        .valid_out( valid_dp[0]        )
    );

    // Instance 1: bits [127:64]
    dp_fma_pipelined u_dp_fma1 (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg[127:64]      ),
        .b        ( B_reg[127:64]      ),
        .c        ( C_reg[127:64]      ),
        .result   ( result_dp[127:64]  ),
        .overflow ( overflow_dp[1]     ),
        .underflow( underflow_dp[1]    ),
        .nan_out  ( nan_dp[1]          ),
        .valid_out( valid_dp[1]        )
    );

    //==========================================================================
    // QP FMA Pipelined Instance (1 × 128-bit operation)
    //==========================================================================

    logic [127:0] result_qp;
    logic         overflow_qp;
    logic         underflow_qp;
    logic         nan_qp;
    logic         valid_qp;

    qp_fma_pipelined u_qp_fma (
        .clk      ( clk                ),
        .rst      ( rst                ),
        .valid_in ( valid_reg          ),
        .a        ( A_reg              ),
        .b        ( B_reg              ),
        .c        ( C_reg              ),
        .result   ( result_qp          ),
        .overflow ( overflow_qp        ),
        .underflow( underflow_qp       ),
        .nan_out  ( nan_qp             ),
        .valid_out( valid_qp           )
    );

    //==========================================================================
    // Output Multiplexer
    //==========================================================================
    // precision_d3 is delayed to align with pipeline output
    // precision_d3[1:0]:
    //   2'b00 - QP mode: output = result_qp[127:0]
    //   2'b01 - DP mode: output = {result_dp[127:64], result_dp[63:0]}
    //   2'b10 - SP mode: output = {result_sp[127:96], ..., result_sp[31:0]}
    //   2'b11 - HP mode: output = {result_hp[127:112], ..., result_hp[15:0]}
    //==========================================================================

    always_comb begin
        case (precision_d3)
            2'b00: begin
                // QP Mode: Single 128-bit result
                toplv_result    = result_qp;
                overflow_flags  = {7'b0, overflow_qp};
                underflow_flags = {7'b0, underflow_qp};
                nan_flags       = {7'b0, nan_qp};
                valid_out       = valid_qp;
            end
            
            2'b01: begin
                // DP Mode: Two 64-bit results packed
                toplv_result    = result_dp;
                overflow_flags  = {6'b0, overflow_dp};
                underflow_flags = {6'b0, underflow_dp};
                nan_flags       = {6'b0, nan_dp};
                valid_out       = valid_dp[0];  // All lanes have same valid
            end
            
            2'b10: begin
                // SP Mode: Four 32-bit results packed
                toplv_result    = result_sp;
                overflow_flags  = {4'b0, overflow_sp};
                underflow_flags = {4'b0, underflow_sp};
                nan_flags       = {4'b0, nan_sp};
                valid_out       = valid_sp[0];  // All lanes have same valid
            end
            
            2'b11: begin
                // HP Mode: Eight 16-bit results packed
                toplv_result    = result_hp;
                overflow_flags  = overflow_hp;
                underflow_flags = underflow_hp;
                nan_flags       = nan_hp;
                valid_out       = valid_hp[0];  // All lanes have same valid
            end
            
            default: begin
                toplv_result    = result_qp;
                overflow_flags  = {7'b0, overflow_qp};
                underflow_flags = {7'b0, underflow_qp};
                nan_flags       = {7'b0, nan_qp};
                valid_out       = valid_qp;
            end
        endcase
    end

endmodule