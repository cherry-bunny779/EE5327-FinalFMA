////////////////////////////////////////////////////////////////////////////////
// Module: sp_fma
// Description: IEEE 754 Single-Precision Floating-Point Fused Multiply-Add
//              Computes A × B + C where A, B, C are 32-bit SP values
//              Instantiates sp_multiplier for the multiplication stage
//
// IEEE 754 SP Format (32 bits):
//   [31]    - Sign bit (S)
//   [30:23] - Exponent (E), 8 bits, bias = 127
//   [22:0]  - Mantissa (M), 23 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module sp_fma (
    input  logic [31:0] a,              // SP operand A (multiplier)
    input  logic [31:0] b,              // SP operand B (multiplicand)
    input  logic [31:0] c,              // SP operand C (addend)
    output logic [31:0] result,         // SP result
    output logic        overflow,       // Overflow flag
    output logic        underflow,      // Underflow flag
    output logic        nan_out         // NaN output flag
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    // Multiplier outputs (used for A×B + 0 case)
    logic [31:0] mult_result;
    logic        mult_overflow;
    logic        mult_underflow;
    logic        mult_nan;
    
    // Field extraction for all operands
    logic        s_a, s_b, s_c;
    logic [7:0]  e_a, e_b, e_c;
    logic [22:0] m_a, m_b, m_c;
    
    // Special case flags
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf, b_is_inf, c_is_inf;
    logic a_is_nan, b_is_nan, c_is_nan;
    logic a_is_subnormal, b_is_subnormal, c_is_subnormal;
    
    //==========================================================================
    // Instantiate Multiplier
    //==========================================================================
    
    sp_multiplier u_mult (
        .a         (a),
        .b         (b),
        .result    (mult_result),
        .overflow  (mult_overflow),
        .underflow (mult_underflow),
        .nan_out   (mult_nan)
    );
    
    //==========================================================================
    // Field Extraction
    //==========================================================================
    
    assign s_a = a[31];
    assign e_a = a[30:23];
    assign m_a = a[22:0];
    
    assign s_b = b[31];
    assign e_b = b[30:23];
    assign m_b = b[22:0];
    
    assign s_c = c[31];
    assign e_c = c[30:23];
    assign m_c = c[22:0];
    
    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    assign a_is_zero      = (e_a == 8'h00) && (m_a == 23'b0);
    assign b_is_zero      = (e_b == 8'h00) && (m_b == 23'b0);
    assign c_is_zero      = (e_c == 8'h00) && (m_c == 23'b0);
    assign a_is_inf       = (e_a == 8'hFF) && (m_a == 23'b0);
    assign b_is_inf       = (e_b == 8'hFF) && (m_b == 23'b0);
    assign c_is_inf       = (e_c == 8'hFF) && (m_c == 23'b0);
    assign a_is_nan       = (e_a == 8'hFF) && (m_a != 23'b0);
    assign b_is_nan       = (e_b == 8'hFF) && (m_b != 23'b0);
    assign c_is_nan       = (e_c == 8'hFF) && (m_c != 23'b0);
    assign a_is_subnormal = (e_a == 8'h00) && (m_a != 23'b0);
    assign b_is_subnormal = (e_b == 8'h00) && (m_b != 23'b0);
    assign c_is_subnormal = (e_c == 8'h00) && (m_c != 23'b0);
    
    logic product_is_zero, product_is_inf;
    assign product_is_zero = a_is_zero || b_is_zero;
    assign product_is_inf  = a_is_inf || b_is_inf;
    
    //==========================================================================
    // Stage 1: Product Calculation (Internal - Full Precision)
    //==========================================================================
    
    logic        s_product;
    logic [23:0] mantissa_a_full, mantissa_b_full;
    logic [47:0] product_mantissa;  // 24-bit × 24-bit = 48-bit
    logic signed [9:0] e_product;   // Signed to handle underflow
    
    assign s_product = s_a ^ s_b;
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    assign product_mantissa = mantissa_a_full * mantissa_b_full;
    
    // Calculate product exponent (unbiased)
    // For normal: exp_actual = E - 127
    // For subnormal: exp_actual = 1 - 127 = -126
    logic signed [9:0] e_a_unbiased, e_b_unbiased;
    assign e_a_unbiased = a_is_subnormal ? -10'sd126 : ($signed({2'b0, e_a}) - 10'sd127);
    assign e_b_unbiased = b_is_subnormal ? -10'sd126 : ($signed({2'b0, e_b}) - 10'sd127);
    
    // Product exponent (unbiased): e_a + e_b
    // After normalization, may need +1 if product >= 2.0
    logic signed [9:0] e_product_unbiased;
    assign e_product_unbiased = e_a_unbiased + e_b_unbiased;
    
    // Normalize product: check if MSB (bit 47) is set
    logic product_norm_shift;
    logic signed [9:0] e_product_norm;
    logic [47:0] product_mantissa_norm;
    
    assign product_norm_shift = product_mantissa[47];
    assign e_product_norm = product_norm_shift ? (e_product_unbiased + 1) : e_product_unbiased;
    // After normalization, implicit 1 is at bit 47
    assign product_mantissa_norm = product_norm_shift ? product_mantissa : (product_mantissa << 1);
    
    //==========================================================================
    // Stage 2: Addend Preparation
    //==========================================================================
    
    logic [23:0] mantissa_c_full;
    logic signed [9:0] e_c_unbiased;
    
    assign mantissa_c_full = c_is_subnormal ? {1'b0, m_c} : {1'b1, m_c};
    assign e_c_unbiased = c_is_subnormal ? -10'sd126 : ($signed({2'b0, e_c}) - 10'sd127);
    
    //==========================================================================
    // Stage 3: Alignment
    //==========================================================================
    
    // The product mantissa is 48 bits with implicit 1 at bit 47 (value in [1,2))
    // The addend mantissa is 24 bits with implicit 1 at bit 23 (value in [1,2))
    // 
    // We need to align them based on exponent difference.
    // Use a 74-bit working width: 48 (product) + 24 (addend can shift left) + 2 (guard)
    
    localparam WORK_WIDTH = 74;
    
    logic signed [9:0] exp_diff;
    logic [WORK_WIDTH-1:0] product_aligned;
    logic [WORK_WIDTH-1:0] addend_aligned;
    logic signed [9:0] e_aligned;
    logic sticky_bit_align;
    
    // exp_diff > 0 means product exponent is larger
    assign exp_diff = e_product_norm - e_c_unbiased;
    
    always_comb begin
        product_aligned = '0;
        addend_aligned = '0;
        sticky_bit_align = 1'b0;
        
        // Position product at top of working width
        // Product is 48 bits, place it at [WORK_WIDTH-1 : WORK_WIDTH-48] = [73:26]
        product_aligned = {product_mantissa_norm, 26'b0};
        
        if (exp_diff >= 0) begin
            // Product exponent >= Addend exponent
            // Addend needs to shift right by exp_diff
            e_aligned = e_product_norm;
            
            // Addend is 24 bits, initially aligned with product's MSB
            // So addend starts at position [73:50], then shifts right by exp_diff
            if (exp_diff < WORK_WIDTH) begin
                // Calculate aligned position
                logic [WORK_WIDTH-1:0] addend_temp;
                addend_temp = {mantissa_c_full, 50'b0};  // Align MSBs initially
                addend_aligned = addend_temp >> exp_diff;
                
                // Sticky bit from bits shifted out
                if (exp_diff > 0 && exp_diff <= 50) begin
                    sticky_bit_align = |(addend_temp << (WORK_WIDTH - exp_diff));
                end else if (exp_diff > 50) begin
                    sticky_bit_align = |mantissa_c_full;
                end
            end else begin
                addend_aligned = '0;
                sticky_bit_align = |mantissa_c_full;
            end
        end else begin
            // Addend exponent > Product exponent
            // Product needs to shift right by -exp_diff
            e_aligned = e_c_unbiased;
            
            // Addend aligned at MSB
            addend_aligned = {mantissa_c_full, 50'b0};
            
            if (-exp_diff < WORK_WIDTH) begin
                product_aligned = {product_mantissa_norm, 26'b0} >> (-exp_diff);
                
                // Sticky bit from product bits shifted out
                if (-exp_diff > 0 && -exp_diff <= 26) begin
                    sticky_bit_align = |({product_mantissa_norm, 26'b0} << (WORK_WIDTH + exp_diff));
                end else if (-exp_diff > 26) begin
                    sticky_bit_align = |product_mantissa_norm;
                end
            end else begin
                product_aligned = '0;
                sticky_bit_align = |product_mantissa_norm;
            end
        end
    end
    
    //==========================================================================
    // Stage 4: Addition/Subtraction
    //==========================================================================
    
    logic effective_subtract;
    logic [WORK_WIDTH:0] sum_mantissa;  // Extra bit for carry
    logic s_result_tmp;
    
    assign effective_subtract = s_product ^ s_c;
    
    always_comb begin
        if (effective_subtract) begin
            if (product_aligned >= addend_aligned) begin
                sum_mantissa = {1'b0, product_aligned} - {1'b0, addend_aligned};
                s_result_tmp = s_product;
            end else begin
                sum_mantissa = {1'b0, addend_aligned} - {1'b0, product_aligned};
                s_result_tmp = s_c;
            end
        end else begin
            sum_mantissa = {1'b0, product_aligned} + {1'b0, addend_aligned};
            s_result_tmp = s_product;
        end
    end
    
    //==========================================================================
    // Stage 5: Normalization (Leading Zero Count)
    //==========================================================================
    
    logic [6:0] lzc;
    logic [WORK_WIDTH:0] sum_normalized;
    logic signed [9:0] e_normalized;
    
    // Count leading zeros starting from bit WORK_WIDTH-1 (not WORK_WIDTH)
    // Bit WORK_WIDTH is the overflow bit, handled separately
    always_comb begin
        lzc = 0;
        for (int i = WORK_WIDTH-1; i >= 0; i--) begin
            if (sum_mantissa[i]) begin
                lzc = (WORK_WIDTH-1) - i;
                break;
            end
        end
        if (sum_mantissa[WORK_WIDTH-1:0] == 0) lzc = WORK_WIDTH;
    end
    
    // Normalize: shift left to position MSB at bit WORK_WIDTH-1
    always_comb begin
        if (sum_mantissa[WORK_WIDTH]) begin
            // Overflow from addition - shift right by 1
            sum_normalized = sum_mantissa >> 1;
            e_normalized = e_aligned + 1;
        end else if (lzc == 0) begin
            // Already normalized (MSB at bit WORK_WIDTH-1)
            sum_normalized = sum_mantissa;
            e_normalized = e_aligned;
        end else if (lzc > 0) begin
            // Need to shift left by lzc
            sum_normalized = sum_mantissa << lzc;
            e_normalized = e_aligned - lzc;
        end else begin
            sum_normalized = sum_mantissa;
            e_normalized = e_aligned;
        end
    end
    
    //==========================================================================
    // Stage 6: Rounding (Round to Nearest, Ties to Even)
    //==========================================================================
    
    // After normalization, the implicit 1 is at bit WORK_WIDTH-1 (bit 73)
    // For SP, we need 23 mantissa bits: bits [72:50]
    // Guard bit: bit 49
    // Round bit: bit 48
    // Sticky: bits [47:0] OR sticky_bit_align
    
    logic [22:0] m_truncated;
    logic guard, round_bit, sticky;
    logic round_up;
    logic [23:0] m_rounded;
    logic round_overflow;
    
    assign m_truncated = sum_normalized[WORK_WIDTH-2 -: 23];  // [72:50]
    assign guard = sum_normalized[WORK_WIDTH-25];              // [49]
    assign round_bit = sum_normalized[WORK_WIDTH-26];          // [48]
    assign sticky = |sum_normalized[WORK_WIDTH-27:0] | sticky_bit_align;  // [47:0]
    
    // Round to Nearest, Ties to Even
    assign round_up = guard && (round_bit || sticky || m_truncated[0]);
    assign m_rounded = {1'b0, m_truncated} + {23'b0, round_up};
    assign round_overflow = m_rounded[23];
    
    //==========================================================================
    // Stage 7: Final Result Assembly with Special Cases
    //==========================================================================
    
    logic signed [9:0] e_final_unbiased;
    logic [9:0]  e_final_biased;
    logic [7:0]  e_out;
    logic [22:0] m_out;
    logic        s_out;
    
    assign e_final_unbiased = round_overflow ? (e_normalized + 1) : e_normalized;
    assign e_final_biased = e_final_unbiased + 10'sd127;
    
    always_comb begin
        // Defaults
        s_out     = s_result_tmp;
        e_out     = 8'b0;
        m_out     = 23'b0;
        overflow  = 1'b0;
        underflow = 1'b0;
        nan_out   = 1'b0;
        
        // Special cases (priority order)
        if (a_is_nan || b_is_nan || c_is_nan) begin
            s_out   = 1'b0;
            e_out   = 8'hFF;
            m_out   = 23'h400000;
            nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            s_out   = 1'b0;
            e_out   = 8'hFF;
            m_out   = 23'h400000;
            nan_out = 1'b1;
        end
        else if (product_is_inf && c_is_inf && (s_product != s_c)) begin
            s_out   = 1'b0;
            e_out   = 8'hFF;
            m_out   = 23'h400000;
            nan_out = 1'b1;
        end
        else if (product_is_inf || c_is_inf) begin
            s_out    = product_is_inf ? s_product : s_c;
            e_out    = 8'hFF;
            m_out    = 23'b0;
            overflow = 1'b1;
        end
        else if (product_is_zero && c_is_zero) begin
            s_out = s_product & s_c;
            e_out = 8'h00;
            m_out = 23'b0;
        end
        else if (product_is_zero) begin
            s_out = s_c;
            e_out = e_c;
            m_out = m_c;
        end
        else if (c_is_zero) begin
            s_out = mult_result[31];
            e_out = mult_result[30:23];
            m_out = mult_result[22:0];
        end
        else if (sum_mantissa == 0) begin
            // Exact cancellation
            s_out = 1'b0;  // +0 for round to nearest
            e_out = 8'h00;
            m_out = 23'b0;
        end
        else if (e_final_biased <= 0) begin
            // Underflow
            s_out     = s_result_tmp;
            e_out     = 8'h00;
            m_out     = 23'b0;
            underflow = 1'b1;
        end
        else if (e_final_biased >= 255) begin
            // Overflow
            s_out    = s_result_tmp;
            e_out    = 8'hFF;
            m_out    = 23'b0;
            overflow = 1'b1;
        end
        else begin
            // Normal result
            s_out = s_result_tmp;
            e_out = e_final_biased[7:0];
            m_out = round_overflow ? m_rounded[23:1] : m_rounded[22:0];
        end
    end
    
    //==========================================================================
    // Output Assignment
    //==========================================================================
    
    assign result = {s_out, e_out, m_out};

endmodule