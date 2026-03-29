////////////////////////////////////////////////////////////////////////////////
// Module: dp_multiplier
// Description: IEEE 754 Double-Precision Floating-Point Multiplier
//              Computes A × B where A and B are 64-bit DP values
//
// IEEE 754 DP Format (64 bits):
//   [63]    - Sign bit (S)
//   [62:52] - Exponent (E), 11 bits, bias = 1023
//   [51:0]  - Mantissa (M), 52 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module dp_multiplier (
    input  logic [63:0] a,              // DP operand A
    input  logic [63:0] b,              // DP operand B
    output logic [63:0] result,         // DP result
    output logic        overflow,       // Overflow flag (infinity)
    output logic        underflow,      // Underflow flag (subnormal/zero)
    output logic        nan_out         // NaN output flag
);

    //==========================================================================
    // Field Extraction
    //==========================================================================
    
    // Operand A fields
    logic        s_a;
    logic [10:0] e_a;
    logic [51:0] m_a;
    
    // Operand B fields
    logic        s_b;
    logic [10:0] e_b;
    logic [51:0] m_b;
    
    assign s_a = a[63];
    assign e_a = a[62:52];
    assign m_a = a[51:0];
    
    assign s_b = b[63];
    assign e_b = b[62:52];
    assign m_b = b[51:0];

    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    logic a_is_zero, b_is_zero;
    logic a_is_inf,  b_is_inf;
    logic a_is_nan,  b_is_nan;
    logic a_is_subnormal, b_is_subnormal;
    
    assign a_is_zero      = (e_a == 11'h000) && (m_a == 52'b0);
    assign b_is_zero      = (e_b == 11'h000) && (m_b == 52'b0);
    assign a_is_inf       = (e_a == 11'h7FF) && (m_a == 52'b0);
    assign b_is_inf       = (e_b == 11'h7FF) && (m_b == 52'b0);
    assign a_is_nan       = (e_a == 11'h7FF) && (m_a != 52'b0);
    assign b_is_nan       = (e_b == 11'h7FF) && (m_b != 52'b0);
    assign a_is_subnormal = (e_a == 11'h000) && (m_a != 52'b0);
    assign b_is_subnormal = (e_b == 11'h000) && (m_b != 52'b0);

    //==========================================================================
    // Stage 1: Sign Calculation & Mantissa Preparation
    //==========================================================================
    
    logic         s_result_s1;
    logic [52:0]  mantissa_a_full;  // 53 bits: implicit 1 + 52-bit mantissa
    logic [52:0]  mantissa_b_full;
    logic [12:0]  e_sum_s1;         // Extended to handle overflow
    
    // Result sign = XOR of input signs
    assign s_result_s1 = s_a ^ s_b;
    
    // Prepend implicit 1 for normal numbers, 0 for subnormal
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    
    // Exponent calculation: E_a + E_b - bias (1023)
    logic [11:0] e_a_actual, e_b_actual;
    assign e_a_actual = a_is_subnormal ? 12'd1 : {1'b0, e_a};
    assign e_b_actual = b_is_subnormal ? 12'd1 : {1'b0, e_b};
    assign e_sum_s1 = e_a_actual + e_b_actual - 12'd1023;

    //==========================================================================
    // Stage 2: Mantissa Multiplication (53-bit × 53-bit = 106-bit)
    //==========================================================================
    
    logic [105:0] product_full;
    
    assign product_full = mantissa_a_full * mantissa_b_full;

    //==========================================================================
    // Stage 3: Normalization
    //==========================================================================
    
    logic         norm_shift;
    logic [12:0]  e_normalized;
    logic [105:0] mantissa_normalized;
    
    // Check if product >= 2.0 (bit 105 set)
    assign norm_shift = product_full[105];
    
    // Adjust exponent based on normalization
    assign e_normalized = norm_shift ? (e_sum_s1 + 13'd1) : e_sum_s1;
    
    // Shift mantissa if needed (align implicit 1 to bit 105)
    assign mantissa_normalized = norm_shift ? product_full : (product_full << 1);

    //==========================================================================
    // Stage 4: Rounding (Round to Nearest, Ties to Even)
    //==========================================================================
    
    // After normalization, mantissa_normalized[105] is the implicit 1
    // Bits [104:53] are the 52-bit mantissa to keep
    // Bit [52] is the guard bit (G)
    // Bit [51] is the round bit (R)
    // Bits [50:0] form the sticky bit (S)
    
    logic        guard_bit;
    logic        round_bit;
    logic        sticky_bit;
    logic        round_up;
    logic [51:0] m_rounded;
    logic        mantissa_overflow;
    
    assign guard_bit  = mantissa_normalized[52];
    assign round_bit  = mantissa_normalized[51];
    assign sticky_bit = |mantissa_normalized[50:0];
    
    // Round to Nearest, Ties to Even
    assign round_up = guard_bit && (round_bit || sticky_bit || mantissa_normalized[53]);
    
    // Apply rounding
    logic [52:0] m_with_round;
    assign m_with_round = {1'b0, mantissa_normalized[104:53]} + {52'b0, round_up};
    assign mantissa_overflow = m_with_round[52];
    assign m_rounded = mantissa_overflow ? m_with_round[52:1] : m_with_round[51:0];

    //==========================================================================
    // Stage 5: Exponent Adjustment & Final Result Assembly
    //==========================================================================
    
    logic [12:0] e_final;
    logic [10:0] e_out;
    logic [51:0] m_out;
    logic        s_out;
    
    assign e_final = mantissa_overflow ? (e_normalized + 13'd1) : e_normalized;

    //==========================================================================
    // Output Logic with Special Case Handling
    //==========================================================================
    
    always_comb begin
        // Default values
        s_out     = s_result_s1;
        e_out     = 11'b0;
        m_out     = 52'b0;
        overflow  = 1'b0;
        underflow = 1'b0;
        nan_out   = 1'b0;
        
        if (a_is_nan || b_is_nan) begin
            // NaN × anything = NaN
            s_out   = 1'b0;
            e_out   = 11'h7FF;
            m_out   = 52'h8000000000000;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            // Infinity × Zero = NaN
            s_out   = 1'b0;
            e_out   = 11'h7FF;
            m_out   = 52'h8000000000000;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if (a_is_inf || b_is_inf) begin
            // Infinity × finite = Infinity
            s_out    = s_result_s1;
            e_out    = 11'h7FF;
            m_out    = 52'b0;
            overflow = 1'b1;
        end
        else if (a_is_zero || b_is_zero) begin
            // Zero × anything = Zero
            s_out = s_result_s1;
            e_out = 11'h000;
            m_out = 52'b0;
        end
        else if (e_final[12] || (e_final <= 13'd0)) begin
            // Underflow
            s_out     = s_result_s1;
            e_out     = 11'h000;
            m_out     = 52'b0;
            underflow = 1'b1;
        end
        else if (e_final >= 13'd2047) begin
            // Overflow
            s_out    = s_result_s1;
            e_out    = 11'h7FF;
            m_out    = 52'b0;
            overflow = 1'b1;
        end
        else begin
            // Normal result
            s_out = s_result_s1;
            e_out = e_final[10:0];
            m_out = m_rounded;
        end
    end

    //==========================================================================
    // Output Assignment (Purely Combinational)
    //==========================================================================
    
    assign result = {s_out, e_out, m_out};

endmodule
