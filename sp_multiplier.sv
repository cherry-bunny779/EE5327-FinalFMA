////////////////////////////////////////////////////////////////////////////////
// Module: sp_multiplier
// Description: IEEE 754 Single-Precision Floating-Point Multiplier
//              Computes A × B where A and B are 32-bit SP values
//
// IEEE 754 SP Format (32 bits):
//   [31]    - Sign bit (S)
//   [30:23] - Exponent (E), 8 bits, bias = 127
//   [22:0]  - Mantissa (M), 23 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module sp_multiplier (
    input  logic [31:0] a,              // SP operand A
    input  logic [31:0] b,              // SP operand B
    output logic [31:0] result,         // SP result
    output logic        overflow,       // Overflow flag (infinity)
    output logic        underflow,      // Underflow flag (subnormal/zero)
    output logic        nan_out         // NaN output flag
);

    //==========================================================================
    // Field Extraction
    //==========================================================================
    
    // Operand A fields
    logic        s_a;
    logic [7:0]  e_a;
    logic [22:0] m_a;
    
    // Operand B fields
    logic        s_b;
    logic [7:0]  e_b;
    logic [22:0] m_b;
    
    assign s_a = a[31];
    assign e_a = a[30:23];
    assign m_a = a[22:0];
    
    assign s_b = b[31];
    assign e_b = b[30:23];
    assign m_b = b[22:0];

    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    logic a_is_zero, b_is_zero;
    logic a_is_inf,  b_is_inf;
    logic a_is_nan,  b_is_nan;
    logic a_is_subnormal, b_is_subnormal;
    
    assign a_is_zero     = (e_a == 8'h00) && (m_a == 23'b0);
    assign b_is_zero     = (e_b == 8'h00) && (m_b == 23'b0);
    assign a_is_inf      = (e_a == 8'hFF) && (m_a == 23'b0);
    assign b_is_inf      = (e_b == 8'hFF) && (m_b == 23'b0);
    assign a_is_nan      = (e_a == 8'hFF) && (m_a != 23'b0);
    assign b_is_nan      = (e_b == 8'hFF) && (m_b != 23'b0);
    assign a_is_subnormal = (e_a == 8'h00) && (m_a != 23'b0);
    assign b_is_subnormal = (e_b == 8'h00) && (m_b != 23'b0);

    //==========================================================================
    // Stage 1: Sign Calculation & Mantissa Preparation
    //==========================================================================
    
    logic        s_result_s1;
    logic [23:0] mantissa_a_full;  // 24 bits: implicit 1 + 23-bit mantissa
    logic [23:0] mantissa_b_full;
    logic [9:0]  e_sum_s1;         // Extended to handle overflow
    
    // Result sign = XOR of input signs
    assign s_result_s1 = s_a ^ s_b;
    
    // Prepend implicit 1 for normal numbers, 0 for subnormal
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    
    // Exponent calculation: E_a + E_b - bias (127)
    // For subnormal: actual exponent is -126 (stored as 0, but represents 2^-126)
    logic [8:0] e_a_actual, e_b_actual;
    assign e_a_actual = a_is_subnormal ? 9'd1 : {1'b0, e_a};
    assign e_b_actual = b_is_subnormal ? 9'd1 : {1'b0, e_b};
    assign e_sum_s1 = e_a_actual + e_b_actual - 9'd127;

    //==========================================================================
    // Stage 2: Mantissa Multiplication (24-bit × 24-bit = 48-bit)
    //==========================================================================
    
    logic [47:0] product_full;
    
    assign product_full = mantissa_a_full * mantissa_b_full;
    
    // Product format: XX.XXXXXX...
    // If MSB (bit 47) is 1, result is in range [2, 4) → need to shift right
    // If MSB is 0, result is in range [1, 2) → already normalized

    //==========================================================================
    // Stage 3: Normalization
    //==========================================================================
    
    logic        norm_shift;
    logic [9:0]  e_normalized;
    logic [47:0] mantissa_normalized;
    
    // Check if product >= 2.0 (bit 47 set)
    assign norm_shift = product_full[47];
    
    // Adjust exponent based on normalization
    assign e_normalized = norm_shift ? (e_sum_s1 + 10'd1) : e_sum_s1;
    
    // Shift mantissa if needed (align implicit 1 to bit 47)
    assign mantissa_normalized = norm_shift ? product_full : (product_full << 1);

    //==========================================================================
    // Stage 4: Rounding (Round to Nearest, Ties to Even)
    //==========================================================================
    
    // After normalization, mantissa_normalized[47] is the implicit 1
    // Bits [46:24] are the 23-bit mantissa to keep
    // Bit [23] is the guard bit (G)
    // Bit [22] is the round bit (R)
    // Bits [21:0] form the sticky bit (S) - OR of all bits
    
    logic        guard_bit;
    logic        round_bit;
    logic        sticky_bit;
    logic        round_up;
    logic [22:0] m_rounded;
    logic        mantissa_overflow;
    
    assign guard_bit  = mantissa_normalized[23];
    assign round_bit  = mantissa_normalized[22];
    assign sticky_bit = |mantissa_normalized[21:0];
    
    // Round to Nearest, Ties to Even:
    // Round up if G=1 AND (R=1 OR S=1 OR LSB=1)
    assign round_up = guard_bit && (round_bit || sticky_bit || mantissa_normalized[24]);
    
    // Apply rounding
    logic [23:0] m_with_round;
    assign m_with_round = {1'b0, mantissa_normalized[46:24]} + {23'b0, round_up};
    assign mantissa_overflow = m_with_round[23];  // Rounding caused overflow
    assign m_rounded = mantissa_overflow ? m_with_round[23:1] : m_with_round[22:0];

    //==========================================================================
    // Stage 5: Exponent Adjustment & Final Result Assembly
    //==========================================================================
    
    logic [9:0]  e_final;
    logic [7:0]  e_out;
    logic [22:0] m_out;
    logic        s_out;
    
    // Adjust exponent if rounding caused mantissa overflow
    assign e_final = mantissa_overflow ? (e_normalized + 10'd1) : e_normalized;
    
    //==========================================================================
    // Output Logic with Special Case Handling
    //==========================================================================
    
    always_comb begin
        // Default values
        s_out     = s_result_s1;
        e_out     = 8'b0;
        m_out     = 23'b0;
        overflow  = 1'b0;
        underflow = 1'b0;
        nan_out   = 1'b0;
        
        // Priority-based special case handling
        if (a_is_nan || b_is_nan) begin
            // NaN × anything = NaN
            s_out   = 1'b0;
            e_out   = 8'hFF;
            m_out   = 23'h400000;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            // Infinity × Zero = NaN
            s_out   = 1'b0;
            e_out   = 8'hFF;
            m_out   = 23'h400000;  // Quiet NaN
            nan_out = 1'b1;
        end
        else if (a_is_inf || b_is_inf) begin
            // Infinity × finite = Infinity
            s_out    = s_result_s1;
            e_out    = 8'hFF;
            m_out    = 23'b0;
            overflow = 1'b1;
        end
        else if (a_is_zero || b_is_zero) begin
            // Zero × anything = Zero
            s_out = s_result_s1;
            e_out = 8'h00;
            m_out = 23'b0;
        end
        else if (e_final[9] || (e_final <= 10'd0)) begin
            // Underflow: exponent too small (negative or zero)
            s_out     = s_result_s1;
            e_out     = 8'h00;
            m_out     = 23'b0;  // Flush to zero (simplified)
            underflow = 1'b1;
        end
        else if (e_final >= 10'd255) begin
            // Overflow: exponent too large
            s_out    = s_result_s1;
            e_out    = 8'hFF;
            m_out    = 23'b0;  // Infinity
            overflow = 1'b1;
        end
        else begin
            // Normal result
            s_out = s_result_s1;
            e_out = e_final[7:0];
            m_out = m_rounded;
        end
    end

    //==========================================================================
    // Output Assignment (Purely Combinational)
    //==========================================================================
    
    assign result = {s_out, e_out, m_out};

endmodule
