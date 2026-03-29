////////////////////////////////////////////////////////////////////////////////
// Module: qp_fma_toplv
// Description: Top-level Multiple-Precision FMA Unit
//              Supports QP, DP, SP, and HP precision modes
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
// Author: 
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module qp_fma_toplv (
    input  logic [127:0] A,
    input  logic [127:0] B,
    input  logic [127:0] C,
    input  logic [1:0]   precision,
    input  logic [7:0]   op,
    input  logic         clk,
    input  logic         rst,

    output logic [127:0] toplv_result
);

    //==========================================================================
    // Input Registers
    //==========================================================================
    
    logic [127:0] A_flpd, B_flpd, C_flpd;
    logic [1:0]   precision_flpd;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            A_flpd         <= 128'h0;
            B_flpd         <= 128'h0;
            C_flpd         <= 128'h0;
            precision_flpd <= 2'b00;
        end
        else begin
            A_flpd         <= A;
            B_flpd         <= B;
            C_flpd         <= C;
            precision_flpd <= precision;
        end
    end

    //==========================================================================
    // HP FMA Instances (8 parallel 16-bit operations)
    //==========================================================================

    logic [127:0] result_hp;      // packed HP results
    logic [7:0]   overflow_hp;    // per-lane overflow flags
    logic [7:0]   underflow_hp;   // per-lane underflow flags
    logic [7:0]   nan_hp;         // per-lane NaN flags

    // Instance 0: bits [15:0]
    hp_fma u_hp_fma0 (
        .a        ( A_flpd[15:0]      ),
        .b        ( B_flpd[15:0]      ),
        .c        ( C_flpd[15:0]      ),
        .result   ( result_hp[15:0]   ),
        .overflow ( overflow_hp[0]    ),
        .underflow( underflow_hp[0]   ),
        .nan_out  ( nan_hp[0]         )
    );

    // Instance 1: bits [31:16]
    hp_fma u_hp_fma1 (
        .a        ( A_flpd[31:16]     ),
        .b        ( B_flpd[31:16]     ),
        .c        ( C_flpd[31:16]     ),
        .result   ( result_hp[31:16]  ),
        .overflow ( overflow_hp[1]    ),
        .underflow( underflow_hp[1]   ),
        .nan_out  ( nan_hp[1]         )
    );

    // Instance 2: bits [47:32]
    hp_fma u_hp_fma2 (
        .a        ( A_flpd[47:32]     ),
        .b        ( B_flpd[47:32]     ),
        .c        ( C_flpd[47:32]     ),
        .result   ( result_hp[47:32]  ),
        .overflow ( overflow_hp[2]    ),
        .underflow( underflow_hp[2]   ),
        .nan_out  ( nan_hp[2]         )
    );

    // Instance 3: bits [63:48]
    hp_fma u_hp_fma3 (
        .a        ( A_flpd[63:48]     ),
        .b        ( B_flpd[63:48]     ),
        .c        ( C_flpd[63:48]     ),
        .result   ( result_hp[63:48]  ),
        .overflow ( overflow_hp[3]    ),
        .underflow( underflow_hp[3]   ),
        .nan_out  ( nan_hp[3]         )
    );

    // Instance 4: bits [79:64]
    hp_fma u_hp_fma4 (
        .a        ( A_flpd[79:64]     ),
        .b        ( B_flpd[79:64]     ),
        .c        ( C_flpd[79:64]     ),
        .result   ( result_hp[79:64]  ),
        .overflow ( overflow_hp[4]    ),
        .underflow( underflow_hp[4]   ),
        .nan_out  ( nan_hp[4]         )
    );

    // Instance 5: bits [95:80]
    hp_fma u_hp_fma5 (
        .a        ( A_flpd[95:80]     ),
        .b        ( B_flpd[95:80]     ),
        .c        ( C_flpd[95:80]     ),
        .result   ( result_hp[95:80]  ),
        .overflow ( overflow_hp[5]    ),
        .underflow( underflow_hp[5]   ),
        .nan_out  ( nan_hp[5]         )
    );

    // Instance 6: bits [111:96]
    hp_fma u_hp_fma6 (
        .a        ( A_flpd[111:96]    ),
        .b        ( B_flpd[111:96]    ),
        .c        ( C_flpd[111:96]    ),
        .result   ( result_hp[111:96] ),
        .overflow ( overflow_hp[6]    ),
        .underflow( underflow_hp[6]   ),
        .nan_out  ( nan_hp[6]         )
    );

    // Instance 7: bits [127:112]
    hp_fma u_hp_fma7 (
        .a        ( A_flpd[127:112]   ),
        .b        ( B_flpd[127:112]   ),
        .c        ( C_flpd[127:112]   ),
        .result   ( result_hp[127:112]),
        .overflow ( overflow_hp[7]    ),
        .underflow( underflow_hp[7]   ),
        .nan_out  ( nan_hp[7]         )
    );

    //==========================================================================
    // SP FMA Instances (4 parallel 32-bit operations)
    //==========================================================================

    logic [127:0] result_sp;      // packed SP results
    logic [3:0]   overflow_sp;
    logic [3:0]   underflow_sp;
    logic [3:0]   nan_sp;

    // Instance 0: bits [31:0]
    sp_fma u_sp_fma0 (
        .a        ( A_flpd[31:0]      ),
        .b        ( B_flpd[31:0]      ),
        .c        ( C_flpd[31:0]      ),
        .result   ( result_sp[31:0]   ),
        .overflow ( overflow_sp[0]    ),
        .underflow( underflow_sp[0]   ),
        .nan_out  ( nan_sp[0]         )
    );

    // Instance 1: bits [63:32]
    sp_fma u_sp_fma1 (
        .a        ( A_flpd[63:32]     ),
        .b        ( B_flpd[63:32]     ),
        .c        ( C_flpd[63:32]     ),
        .result   ( result_sp[63:32]  ),
        .overflow ( overflow_sp[1]    ),
        .underflow( underflow_sp[1]   ),
        .nan_out  ( nan_sp[1]         )
    );

    // Instance 2: bits [95:64]
    sp_fma u_sp_fma2 (
        .a        ( A_flpd[95:64]     ),
        .b        ( B_flpd[95:64]     ),
        .c        ( C_flpd[95:64]     ),
        .result   ( result_sp[95:64]  ),
        .overflow ( overflow_sp[2]    ),
        .underflow( underflow_sp[2]   ),
        .nan_out  ( nan_sp[2]         )
    );

    // Instance 3: bits [127:96]
    sp_fma u_sp_fma3 (
        .a        ( A_flpd[127:96]    ),
        .b        ( B_flpd[127:96]    ),
        .c        ( C_flpd[127:96]    ),
        .result   ( result_sp[127:96] ),
        .overflow ( overflow_sp[3]    ),
        .underflow( underflow_sp[3]   ),
        .nan_out  ( nan_sp[3]         )
    );

    //==========================================================================
    // DP FMA Instances (2 parallel 64-bit operations)
    //==========================================================================

    logic [127:0] result_dp;      // packed DP results (2 × 64b)
    logic [1:0]   overflow_dp;
    logic [1:0]   underflow_dp;
    logic [1:0]   nan_dp;

    // Instance 0: bits [63:0]
    dp_fma u_dp_fma0 (
        .a        ( A_flpd[63:0]      ),
        .b        ( B_flpd[63:0]      ),
        .c        ( C_flpd[63:0]      ),
        .result   ( result_dp[63:0]   ),
        .overflow ( overflow_dp[0]    ),
        .underflow( underflow_dp[0]   ),
        .nan_out  ( nan_dp[0]         )
    );

    // Instance 1: bits [127:64]
    dp_fma u_dp_fma1 (
        .a        ( A_flpd[127:64]    ),
        .b        ( B_flpd[127:64]    ),
        .c        ( C_flpd[127:64]    ),
        .result   ( result_dp[127:64] ),
        .overflow ( overflow_dp[1]    ),
        .underflow( underflow_dp[1]   ),
        .nan_out  ( nan_dp[1]         )
    );

    //==========================================================================
    // QP FMA Instance (1 × 128-bit operation)
    //==========================================================================

    logic [127:0] result_qp;
    logic         overflow_qp;
    logic         underflow_qp;
    logic         nan_qp;

    qp_fma u_qp_fma (
        .a        ( A_flpd            ),
        .b        ( B_flpd            ),
        .c        ( C_flpd            ),
        .result   ( result_qp         ),
        .overflow ( overflow_qp       ),
        .underflow( underflow_qp      ),
        .nan_out  ( nan_qp            )
    );

    //==========================================================================
    // Output Multiplexer
    //==========================================================================
    // precision[1:0]:
    //   2'b00 - QP mode: output = result_qp[127:0]
    //   2'b01 - DP mode: output = {result_dp[127:64], result_dp[63:0]}
    //   2'b10 - SP mode: output = {result_sp[127:96], result_sp[95:64], 
    //                              result_sp[63:32], result_sp[31:0]}
    //   2'b11 - HP mode: output = {result_hp[127:112], ..., result_hp[15:0]}
    //==========================================================================

    always_comb begin
        case (precision_flpd)
            2'b00: begin
                // QP Mode: Single 128-bit result
                toplv_result = result_qp;
            end
            
            2'b01: begin
                // DP Mode: Two 64-bit results packed
                // result_dp[127:64] from u_dp_fma1 (upper half)
                // result_dp[63:0]   from u_dp_fma0 (lower half)
                toplv_result = result_dp;
            end
            
            2'b10: begin
                // SP Mode: Four 32-bit results packed
                // result_sp[127:96] from u_sp_fma3
                // result_sp[95:64]  from u_sp_fma2
                // result_sp[63:32]  from u_sp_fma1
                // result_sp[31:0]   from u_sp_fma0
                toplv_result = result_sp;
            end
            
            2'b11: begin
                // HP Mode: Eight 16-bit results packed
                // result_hp[127:112] from u_hp_fma7
                // result_hp[111:96]  from u_hp_fma6
                // result_hp[95:80]   from u_hp_fma5
                // result_hp[79:64]   from u_hp_fma4
                // result_hp[63:48]   from u_hp_fma3
                // result_hp[47:32]   from u_hp_fma2
                // result_hp[31:16]   from u_hp_fma1
                // result_hp[15:0]    from u_hp_fma0
                toplv_result = result_hp;
            end
            
            default: begin
                toplv_result = result_qp;
            end
        endcase
    end

endmodule
