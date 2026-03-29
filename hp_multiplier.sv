////////////////////////////////////////////////////////////////////////////////
// Module: hp_multiplier
// Description: IEEE 754 Half-Precision Floating-Point Multiplier
//              Computes A × B where A and B are 16-bit HP values
//
// IEEE 754 HP Format (16 bits):
//   [15]    - Sign bit (S)
//   [14:10] - Exponent (E), 5 bits, bias = 15
//   [9:0]   - Mantissa (M), 10 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module hp_multiplier (
    input  logic [15:0] a,              // HP operand A
    input  logic [15:0] b,              // HP operand B
    output logic [15:0] result,         // HP result
    output logic        overflow,       // Overflow flag (infinity)
    output logic        underflow,      // Underflow flag (subnormal/zero)
    output logic        nan_out         // NaN output flag
);

    //==========================================================================
    // Field Extraction
    //==========================================================================
    
    // Operand A fields
    logic        s_a;
    logic [4:0]  e_a;
    logic [9:0]  m_a;
    
    // Operand B fields
    logic        s_b;
    logic [4:0]  e_b;
    logic [9:0]  m_b;
    
    assign s_a = a[15];
    assign e_a = a[14:10];
    assign m_a = a[9:0];
    
    assign s_b = b[15];
    assign e_b = b[14:10];
    assign m_b = b[9:0];

    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    logic a_is_zero, b_is_zero;
    logic a_is_inf,  b_is_inf;
    logic a_is_nan,  b_is_nan;
    logic a_is_subnormal, b_is_subnormal;
    
    assign a_is_zero      = (e_a == 5'h00) && (m_a == 10'b0);
    assign b_is_zero      = (e_b == 5'h00) && (m_b == 10'b0);
    assign a_is_inf       = (e_a == 5'h1F) && (m_a == 10'b0);
    assign b_is_inf       = (e_b == 5'h1F) && (m_b == 10'b0);
    assign a_is_nan       = (e_a == 5'h1F) && (m_a != 10'b0);
    assign b_is_nan       = (e_b == 5'h1F) && (m_b != 10'b0);
    assign a_is_subnormal = (e_a == 5'h00) && (m_a != 10'b0);
    assign b_is_subnormal = (e_b == 5'h00) && (m_b != 10'b0);

    //==========================================================================
    // Stage 1: Sign Calculation & Mantissa Preparation
    //==========================================================================
    
    logic        s_result_s1;
    logic [10:0] mantissa_a_full;  // 11 bits: implicit 1 + 10-bit mantissa
    logic [10:0] mantissa_b_full;
    logic [6:0]  e_sum_s1;         // Extended to handle overflow
    
    // Result sign = XOR of input signs
    assign s_result_s1 = s_a ^ s_b;
    
    // Prepend implicit 1 for normal numbers, 0 for subnormal
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    
    // Exponent calculation: E_a + E_b - bias (15)
    logic [5:0] e_a_actual, e_b_actual;
    assign e_a_actual = a_is_subnormal ? 6'd1 : {1'b0, e_a};
    assign e_b_actual = b_is_subnormal ? 6'd1 : {1'b0, e_b};
    assign e_sum_s1 = e_a_actual + e_b_actual - 6'd15;

    //==========================================================================
    // Stage 2: Mantissa Multiplication (11-bit × 11-bit = 22-bit)
    //==========================================================================
    
    logic [21:0] product_full;
    
    assign product_full = mantissa_a_full * mantissa_b_full;

    //==========================================================================
    // Stage 3: Normalization
    //==========================================================================
    
    // 11-bit × 11-bit multiplication produces up to 22-bit result
    // Product of two 1.xxx numbers is in range [1.0, 4.0)
    // If product >= 2.0, the result has implicit 1 at bit 21, else at bit 20
    
    logic        norm_shift;
    logic [6:0]  e_normalized;
    logic [21:0] mantissa_normalized;
    
    // Check if product >= 2.0 (bit 21 set means product in [2.0, 4.0))
    assign norm_shift = product_full[21];
    
    // Adjust exponent based on normalization
    assign e_normalized = norm_shift ? (e_sum_s1 + 7'd1) : e_sum_s1;
    
    // Shift mantissa to align implicit 1 at bit 21
    assign mantissa_normalized = norm_shift ? product_full : (product_full << 1);

    //==========================================================================
    // Stage 4: Rounding (Round to Nearest, Ties to Even)
    //==========================================================================
    
    // After normalization, mantissa_normalized[21] is the implicit 1
    // Bits [20:11] are the 10-bit mantissa to keep
    // Bit [10] is the guard bit (G)
    // Bit [9] is the round bit (R)
    // Bits [8:0] form the sticky bit (S)
    
    logic        guard_bit;
    logic        round_bit;
    logic        sticky_bit;
    logic        round_up;
    logic [9:0]  m_rounded;
    logic        mantissa_overflow;
    
    assign guard_bit  = mantissa_normalized[10];
    assign round_bit  = mantissa_normalized[9];
    assign sticky_bit = |mantissa_normalized[8:0];
    
    // Round to Nearest, Ties to Even
    assign round_up = guard_bit && (round_bit || sticky_bit || mantissa_normalized[11]);
    
    // Apply rounding
    logic [10:0] m_with_round;
    assign m_with_round = {1'b0, mantissa_normalized[20:11]} + {10'b0, round_up};
    assign mantissa_overflow = m_with_round[10];
    assign m_rounded = mantissa_overflow ? m_with_round[10:1] : m_with_round[9:0];

    //==========================================================================
    // Stage 5: Exponent Adjustment & Final Result Assembly
    //==========================================================================
    
    logic [6:0]  e_final;
    logic [4:0]  e_out;
    logic [9:0]  m_out;
    logic        s_out;
    
    assign e_final = mantissa_overflow ? (e_normalized + 7'd1) : e_normalized;

    //==========================================================================
    // Output Logic with Special Case Handling
    //==========================================================================
    
    always_comb begin
        // Default values
        s_out     = s_result_s1;
        e_out     = 5'b0;
        m_out     = 10'b0;
        overflow  = 1'b0;
        underflow = 1'b0;
        nan_out   = 1'b0;
        
        if (a_is_nan || b_is_nan) begin
            // NaN × anything = NaN
            s_out   = 1'b0;
            e_out   = 5'h1F;
            m_out   = 10'h200;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            // Infinity × Zero = NaN
            s_out   = 1'b0;
            e_out   = 5'h1F;
            m_out   = 10'h200;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if (a_is_inf || b_is_inf) begin
            // Infinity × finite = Infinity
            s_out    = s_result_s1;
            e_out    = 5'h1F;
            m_out    = 10'b0;
            overflow = 1'b1;
        end
        else if (a_is_zero || b_is_zero) begin
            // Zero × anything = Zero
            s_out = s_result_s1;
            e_out = 5'h00;
            m_out = 10'b0;
        end
        else if (e_final[6] || (e_final <= 7'd0)) begin
            // Underflow
            s_out     = s_result_s1;
            e_out     = 5'h00;
            m_out     = 10'b0;
            underflow = 1'b1;
        end
        else if (e_final >= 7'd31) begin
            // Overflow
            s_out    = s_result_s1;
            e_out    = 5'h1F;
            m_out    = 10'b0;
            overflow = 1'b1;
        end
        else begin
            // Normal result
            s_out = s_result_s1;
            e_out = e_final[4:0];
            m_out = m_rounded;
        end
    end

    //==========================================================================
    // Output Assignment (Purely Combinational)
    //==========================================================================
    
    assign result = {s_out, e_out, m_out};

endmodule
