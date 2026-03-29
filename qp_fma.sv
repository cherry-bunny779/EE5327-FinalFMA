////////////////////////////////////////////////////////////////////////////////
// Module: qp_fma
// Description: IEEE 754 Quadruple-Precision Floating-Point Fused Multiply-Add
//              Computes A × B + C where A, B, C are 128-bit QP values
//              Instantiates qp_multiplier for the multiplication stage
//
// IEEE 754 QP Format (128 bits):
//   [127]     - Sign bit (S)
//   [126:112] - Exponent (E), 15 bits, bias = 16383
//   [111:0]   - Mantissa (M), 112 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module qp_fma (
    input  logic [127:0] a,              // QP operand A (multiplier)
    input  logic [127:0] b,              // QP operand B (multiplicand)
    input  logic [127:0] c,              // QP operand C (addend)
    output logic [127:0] result,         // QP result
    output logic         overflow,       // Overflow flag
    output logic         underflow,      // Underflow flag
    output logic         nan_out         // NaN output flag
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    // Multiplier outputs (used for A×B + 0 case)
    logic [127:0] mult_result;
    logic         mult_overflow;
    logic         mult_underflow;
    logic         mult_nan;
    
    // Field extraction for all operands
    logic         s_a, s_b, s_c;
    logic [14:0]  e_a, e_b, e_c;
    logic [111:0] m_a, m_b, m_c;
    
    // Special case flags
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf, b_is_inf, c_is_inf;
    logic a_is_nan, b_is_nan, c_is_nan;
    logic a_is_subnormal, b_is_subnormal, c_is_subnormal;
    
    //==========================================================================
    // Instantiate Multiplier
    //==========================================================================
    
    qp_multiplier u_mult (
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
    
    assign s_a = a[127];
    assign e_a = a[126:112];
    assign m_a = a[111:0];
    
    assign s_b = b[127];
    assign e_b = b[126:112];
    assign m_b = b[111:0];
    
    assign s_c = c[127];
    assign e_c = c[126:112];
    assign m_c = c[111:0];
    
    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    assign a_is_zero      = (e_a == 15'h0000) && (m_a == 112'b0);
    assign b_is_zero      = (e_b == 15'h0000) && (m_b == 112'b0);
    assign c_is_zero      = (e_c == 15'h0000) && (m_c == 112'b0);
    assign a_is_inf       = (e_a == 15'h7FFF) && (m_a == 112'b0);
    assign b_is_inf       = (e_b == 15'h7FFF) && (m_b == 112'b0);
    assign c_is_inf       = (e_c == 15'h7FFF) && (m_c == 112'b0);
    assign a_is_nan       = (e_a == 15'h7FFF) && (m_a != 112'b0);
    assign b_is_nan       = (e_b == 15'h7FFF) && (m_b != 112'b0);
    assign c_is_nan       = (e_c == 15'h7FFF) && (m_c != 112'b0);
    assign a_is_subnormal = (e_a == 15'h0000) && (m_a != 112'b0);
    assign b_is_subnormal = (e_b == 15'h0000) && (m_b != 112'b0);
    assign c_is_subnormal = (e_c == 15'h0000) && (m_c != 112'b0);
    
    logic product_is_zero, product_is_inf;
    assign product_is_zero = a_is_zero || b_is_zero;
    assign product_is_inf  = a_is_inf || b_is_inf;
    
    //==========================================================================
    // Stage 1: Product Calculation (Internal - Full Precision)
    //==========================================================================
    
    logic          s_product;
    logic [112:0]  mantissa_a_full, mantissa_b_full;
    logic [225:0]  product_mantissa;  // 113-bit × 113-bit = 226-bit max
    
    assign s_product = s_a ^ s_b;
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    assign product_mantissa = mantissa_a_full * mantissa_b_full;
    
    // Calculate product exponent using unbiased arithmetic
    logic signed [16:0] e_a_unbiased, e_b_unbiased, e_product_unbiased;
    assign e_a_unbiased = a_is_subnormal ? -17'sd16382 : ($signed({2'b0, e_a}) - 17'sd16383);
    assign e_b_unbiased = b_is_subnormal ? -17'sd16382 : ($signed({2'b0, e_b}) - 17'sd16383);
    assign e_product_unbiased = e_a_unbiased + e_b_unbiased;
    
    // Normalize product: ensure MSB is at bit 225
    logic          product_norm_shift;
    logic signed [16:0] e_product_norm;
    logic [225:0]  product_mantissa_norm;
    
    assign product_norm_shift = product_mantissa[225];
    assign e_product_norm = product_norm_shift ? (e_product_unbiased + 1) : e_product_unbiased;
    assign product_mantissa_norm = product_norm_shift ? product_mantissa : (product_mantissa << 1);
    
    //==========================================================================
    // Stage 2: Addend Preparation
    //==========================================================================
    
    logic [112:0] mantissa_c_full;
    logic signed [16:0] e_c_unbiased;
    
    assign mantissa_c_full = c_is_subnormal ? {1'b0, m_c} : {1'b1, m_c};
    assign e_c_unbiased = c_is_subnormal ? -17'sd16382 : ($signed({2'b0, e_c}) - 17'sd16383);
    
    //==========================================================================
    // Stage 3: Alignment
    //==========================================================================
    
    // Working width: 226 (product) + 113 (addend) + 2 (guard) = 341 bits
    localparam WORK_WIDTH = 341;
    
    logic signed [17:0] exp_diff;
    logic [WORK_WIDTH-1:0] product_aligned;
    logic [WORK_WIDTH-1:0] addend_aligned;
    logic signed [16:0] e_aligned;
    logic sticky_bit_align;
    
    assign exp_diff = e_product_norm - e_c_unbiased;
    
    always_comb begin
        product_aligned = '0;
        addend_aligned = '0;
        sticky_bit_align = 1'b0;
        
        // Product: 226 bits with implicit 1 at bit 225
        // Place at MSB of working width: {product_mantissa_norm, 115'b0}
        // This puts implicit 1 at bit 225+115 = 340 = WORK_WIDTH-1
        product_aligned = {product_mantissa_norm, 115'b0};
        
        if (exp_diff >= 0) begin
            // Product exponent >= Addend exponent
            e_aligned = e_product_norm;
            
            // Addend: 113 bits with implicit 1 at bit 112
            // Place at MSB: {mantissa_c_full, 228'b0} puts implicit 1 at bit 340
            // Then shift right by exp_diff
            if (exp_diff < WORK_WIDTH) begin
                logic [WORK_WIDTH-1:0] addend_temp;
                addend_temp = {mantissa_c_full, 228'b0};
                addend_aligned = addend_temp >> exp_diff;
                
                // Sticky bit from shifted-out bits
                if (exp_diff > 0 && exp_diff <= 228) begin
                    sticky_bit_align = |(addend_temp << (WORK_WIDTH - exp_diff));
                end else if (exp_diff > 228) begin
                    sticky_bit_align = |mantissa_c_full;
                end
            end else begin
                addend_aligned = '0;
                sticky_bit_align = |mantissa_c_full;
            end
        end else begin
            // Addend exponent > Product exponent
            e_aligned = e_c_unbiased;
            addend_aligned = {mantissa_c_full, 228'b0};
            
            // Shift product right by -exp_diff
            if (-exp_diff < WORK_WIDTH) begin
                product_aligned = {product_mantissa_norm, 115'b0} >> (-exp_diff);
                
                // Sticky bit from shifted-out bits
                if (-exp_diff > 0 && -exp_diff <= 115) begin
                    sticky_bit_align = |({product_mantissa_norm, 115'b0} << (WORK_WIDTH + exp_diff));
                end else if (-exp_diff > 115) begin
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
    logic [WORK_WIDTH:0] sum_mantissa;  // Extra bit for overflow
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
    // Stage 5: Normalization
    //==========================================================================
    
    logic [8:0] lzc;
    logic [WORK_WIDTH:0] sum_normalized;
    logic signed [16:0] e_normalized;
    
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
            // Need to shift left by lzc to normalize
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
    
    // After normalization, implicit 1 is at bit WORK_WIDTH-1 (bit 340)
    // Mantissa bits: [339:228] (112 bits)
    // Guard: bit 227, Round: bit 226, Sticky: bits [225:0]
    
    logic [111:0] m_truncated;
    logic guard, round_bit, sticky;
    logic round_up;
    logic [112:0] m_rounded;
    logic round_overflow;
    
    assign m_truncated = sum_normalized[WORK_WIDTH-2 -: 112];  // bits [339:228]
    assign guard = sum_normalized[WORK_WIDTH-114];              // bit 227
    assign round_bit = sum_normalized[WORK_WIDTH-115];          // bit 226
    assign sticky = |sum_normalized[WORK_WIDTH-116:0] | sticky_bit_align;  // bits [225:0]
    
    assign round_up = guard && (round_bit || sticky || m_truncated[0]);
    assign m_rounded = {1'b0, m_truncated} + {112'b0, round_up};
    assign round_overflow = m_rounded[112];
    
    //==========================================================================
    // Stage 7: Final Result Assembly with Special Cases
    //==========================================================================
    
    logic signed [16:0] e_final_unbiased;
    logic [16:0] e_final_biased;
    logic [14:0] e_out;
    logic [111:0] m_out;
    logic         s_out;
    
    assign e_final_unbiased = round_overflow ? (e_normalized + 1) : e_normalized;
    assign e_final_biased = e_final_unbiased + 17'sd16383;
    
    always_comb begin
        s_out     = s_result_tmp;
        e_out     = 15'b0;
        m_out     = 112'b0;
        overflow  = 1'b0;
        underflow = 1'b0;
        nan_out   = 1'b0;
        
        if (a_is_nan || b_is_nan || c_is_nan) begin
            s_out   = 1'b0;
            e_out   = 15'h7FFF;
            m_out   = {1'b1, 111'b0};
            nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            s_out   = 1'b0;
            e_out   = 15'h7FFF;
            m_out   = {1'b1, 111'b0};
            nan_out = 1'b1;
        end
        else if (product_is_inf && c_is_inf && (s_product != s_c)) begin
            s_out   = 1'b0;
            e_out   = 15'h7FFF;
            m_out   = {1'b1, 111'b0};
            nan_out = 1'b1;
        end
        else if (product_is_inf || c_is_inf) begin
            s_out    = product_is_inf ? s_product : s_c;
            e_out    = 15'h7FFF;
            m_out    = 112'b0;
            overflow = 1'b1;
        end
        else if (product_is_zero && c_is_zero) begin
            s_out = s_product & s_c;
            e_out = 15'h0000;
            m_out = 112'b0;
        end
        else if (product_is_zero) begin
            s_out = s_c;
            e_out = e_c;
            m_out = m_c;
        end
        else if (c_is_zero) begin
            s_out = mult_result[127];
            e_out = mult_result[126:112];
            m_out = mult_result[111:0];
        end
        else if (sum_mantissa == 0) begin
            s_out = 1'b0;
            e_out = 15'h0000;
            m_out = 112'b0;
        end
        else if (e_final_biased <= 0) begin
            s_out     = s_result_tmp;
            e_out     = 15'h0000;
            m_out     = 112'b0;
            underflow = 1'b1;
        end
        else if (e_final_biased >= 32767) begin
            s_out    = s_result_tmp;
            e_out    = 15'h7FFF;
            m_out    = 112'b0;
            overflow = 1'b1;
        end
        else begin
            s_out = s_result_tmp;
            e_out = e_final_biased[14:0];
            m_out = round_overflow ? m_rounded[112:1] : m_rounded[111:0];
        end
    end
    
    //==========================================================================
    // Output Assignment
    //==========================================================================
    
    assign result = {s_out, e_out, m_out};

endmodule