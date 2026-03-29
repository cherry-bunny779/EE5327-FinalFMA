////////////////////////////////////////////////////////////////////////////////
// Module: dp_fma
// Description: IEEE 754 Double-Precision Floating-Point Fused Multiply-Add
//              Computes A × B + C where A, B, C are 64-bit DP values
//              Instantiates dp_multiplier for the multiplication stage
//
// IEEE 754 DP Format (64 bits):
//   [63]    - Sign bit (S)
//   [62:52] - Exponent (E), 11 bits, bias = 1023
//   [51:0]  - Mantissa (M), 52 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module dp_fma (
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic [63:0] c,
    output logic [63:0] result,
    output logic        overflow,
    output logic        underflow,
    output logic        nan_out
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    logic [63:0] mult_result;
    logic        mult_overflow, mult_underflow, mult_nan;
    
    logic        s_a, s_b, s_c;
    logic [10:0] e_a, e_b, e_c;
    logic [51:0] m_a, m_b, m_c;
    
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf, b_is_inf, c_is_inf;
    logic a_is_nan, b_is_nan, c_is_nan;
    logic a_is_subnormal, b_is_subnormal, c_is_subnormal;
    
    //==========================================================================
    // Instantiate Multiplier
    //==========================================================================
    
    dp_multiplier u_mult (
        .a(a), .b(b), .result(mult_result),
        .overflow(mult_overflow), .underflow(mult_underflow), .nan_out(mult_nan)
    );
    
    //==========================================================================
    // Field Extraction
    //==========================================================================
    
    assign s_a = a[63]; assign e_a = a[62:52]; assign m_a = a[51:0];
    assign s_b = b[63]; assign e_b = b[62:52]; assign m_b = b[51:0];
    assign s_c = c[63]; assign e_c = c[62:52]; assign m_c = c[51:0];
    
    //==========================================================================
    // Special Case Detection
    //==========================================================================
    
    assign a_is_zero      = (e_a == 11'h000) && (m_a == 52'b0);
    assign b_is_zero      = (e_b == 11'h000) && (m_b == 52'b0);
    assign c_is_zero      = (e_c == 11'h000) && (m_c == 52'b0);
    assign a_is_inf       = (e_a == 11'h7FF) && (m_a == 52'b0);
    assign b_is_inf       = (e_b == 11'h7FF) && (m_b == 52'b0);
    assign c_is_inf       = (e_c == 11'h7FF) && (m_c == 52'b0);
    assign a_is_nan       = (e_a == 11'h7FF) && (m_a != 52'b0);
    assign b_is_nan       = (e_b == 11'h7FF) && (m_b != 52'b0);
    assign c_is_nan       = (e_c == 11'h7FF) && (m_c != 52'b0);
    assign a_is_subnormal = (e_a == 11'h000) && (m_a != 52'b0);
    assign b_is_subnormal = (e_b == 11'h000) && (m_b != 52'b0);
    assign c_is_subnormal = (e_c == 11'h000) && (m_c != 52'b0);
    
    logic product_is_zero, product_is_inf;
    assign product_is_zero = a_is_zero || b_is_zero;
    assign product_is_inf  = a_is_inf || b_is_inf;
    
    //==========================================================================
    // Stage 1: Product Calculation
    //==========================================================================
    
    logic         s_product;
    logic [52:0]  mantissa_a_full, mantissa_b_full;
    logic [105:0] product_mantissa;
    
    assign s_product = s_a ^ s_b;
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    assign product_mantissa = mantissa_a_full * mantissa_b_full;
    
    logic signed [12:0] e_a_unbiased, e_b_unbiased, e_product_unbiased;
    assign e_a_unbiased = a_is_subnormal ? -13'sd1022 : ($signed({2'b0, e_a}) - 13'sd1023);
    assign e_b_unbiased = b_is_subnormal ? -13'sd1022 : ($signed({2'b0, e_b}) - 13'sd1023);
    assign e_product_unbiased = e_a_unbiased + e_b_unbiased;
    
    logic product_norm_shift;
    logic signed [12:0] e_product_norm;
    logic [105:0] product_mantissa_norm;
    
    assign product_norm_shift = product_mantissa[105];
    assign e_product_norm = product_norm_shift ? (e_product_unbiased + 1) : e_product_unbiased;
    assign product_mantissa_norm = product_norm_shift ? product_mantissa : (product_mantissa << 1);
    
    //==========================================================================
    // Stage 2: Addend Preparation
    //==========================================================================
    
    logic [52:0] mantissa_c_full;
    logic signed [12:0] e_c_unbiased;
    
    assign mantissa_c_full = c_is_subnormal ? {1'b0, m_c} : {1'b1, m_c};
    assign e_c_unbiased = c_is_subnormal ? -13'sd1022 : ($signed({2'b0, e_c}) - 13'sd1023);
    
    //==========================================================================
    // Stage 3: Alignment
    //==========================================================================
    
    // Product: 106 bits, Addend: 53 bits
    // Working width: 106 + 53 + 2 = 161 bits
    
    localparam WORK_WIDTH = 161;
    
    logic signed [12:0] exp_diff;
    logic [WORK_WIDTH-1:0] product_aligned;
    logic [WORK_WIDTH-1:0] addend_aligned;
    logic signed [12:0] e_aligned;
    logic sticky_bit_align;
    
    assign exp_diff = e_product_norm - e_c_unbiased;
    
    always_comb begin
        product_aligned = '0;
        addend_aligned = '0;
        sticky_bit_align = 1'b0;
        
        product_aligned = {product_mantissa_norm, 55'b0};
        
        if (exp_diff >= 0) begin
            e_aligned = e_product_norm;
            
            if (exp_diff < WORK_WIDTH) begin
                logic [WORK_WIDTH-1:0] addend_temp;
                addend_temp = {mantissa_c_full, 108'b0};
                addend_aligned = addend_temp >> exp_diff;
                
                if (exp_diff > 0 && exp_diff <= 108) begin
                    sticky_bit_align = |(addend_temp << (WORK_WIDTH - exp_diff));
                end else if (exp_diff > 108) begin
                    sticky_bit_align = |mantissa_c_full;
                end
            end else begin
                addend_aligned = '0;
                sticky_bit_align = |mantissa_c_full;
            end
        end else begin
            e_aligned = e_c_unbiased;
            addend_aligned = {mantissa_c_full, 108'b0};
            
            if (-exp_diff < WORK_WIDTH) begin
                product_aligned = {product_mantissa_norm, 55'b0} >> (-exp_diff);
                
                if (-exp_diff > 0 && -exp_diff <= 55) begin
                    sticky_bit_align = |({product_mantissa_norm, 55'b0} << (WORK_WIDTH + exp_diff));
                end else if (-exp_diff > 55) begin
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
    logic [WORK_WIDTH:0] sum_mantissa;
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
    
    logic [7:0] lzc;
    logic [WORK_WIDTH:0] sum_normalized;
    logic signed [12:0] e_normalized;
    
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
    // Stage 6: Rounding
    //==========================================================================
    
    // Implicit 1 at bit WORK_WIDTH-1 (160)
    // Mantissa: [159:108] (52 bits)
    // Guard: bit 107, Round: bit 106, Sticky: [105:0]
    
    logic [51:0] m_truncated;
    logic guard, round_bit, sticky;
    logic round_up;
    logic [52:0] m_rounded;
    logic round_overflow;
    
    assign m_truncated = sum_normalized[WORK_WIDTH-2 -: 52];
    assign guard = sum_normalized[WORK_WIDTH-54];
    assign round_bit = sum_normalized[WORK_WIDTH-55];
    assign sticky = |sum_normalized[WORK_WIDTH-56:0] | sticky_bit_align;
    
    assign round_up = guard && (round_bit || sticky || m_truncated[0]);
    assign m_rounded = {1'b0, m_truncated} + {52'b0, round_up};
    assign round_overflow = m_rounded[52];
    
    //==========================================================================
    // Stage 7: Final Result Assembly
    //==========================================================================
    
    logic signed [12:0] e_final_unbiased;
    logic [12:0] e_final_biased;
    logic [10:0] e_out;
    logic [51:0] m_out;
    logic        s_out;
    
    assign e_final_unbiased = round_overflow ? (e_normalized + 1) : e_normalized;
    assign e_final_biased = e_final_unbiased + 13'sd1023;
    
    always_comb begin
        s_out = s_result_tmp; e_out = 11'b0; m_out = 52'b0;
        overflow = 1'b0; underflow = 1'b0; nan_out = 1'b0;
        
        if (a_is_nan || b_is_nan || c_is_nan) begin
            s_out = 1'b0; e_out = 11'h7FF; m_out = 52'h8000000000000; nan_out = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            s_out = 1'b0; e_out = 11'h7FF; m_out = 52'h8000000000000; nan_out = 1'b1;
        end
        else if (product_is_inf && c_is_inf && (s_product != s_c)) begin
            s_out = 1'b0; e_out = 11'h7FF; m_out = 52'h8000000000000; nan_out = 1'b1;
        end
        else if (product_is_inf || c_is_inf) begin
            s_out = product_is_inf ? s_product : s_c; e_out = 11'h7FF; m_out = 52'b0; overflow = 1'b1;
        end
        else if (product_is_zero && c_is_zero) begin
            s_out = s_product & s_c; e_out = 11'h000; m_out = 52'b0;
        end
        else if (product_is_zero) begin
            s_out = s_c; e_out = e_c; m_out = m_c;
        end
        else if (c_is_zero) begin
            s_out = mult_result[63]; e_out = mult_result[62:52]; m_out = mult_result[51:0];
        end
        else if (sum_mantissa == 0) begin
            s_out = 1'b0; e_out = 11'h000; m_out = 52'b0;
        end
        else if (e_final_biased <= 0) begin
            s_out = s_result_tmp; e_out = 11'h000; m_out = 52'b0; underflow = 1'b1;
        end
        else if (e_final_biased >= 2047) begin
            s_out = s_result_tmp; e_out = 11'h7FF; m_out = 52'b0; overflow = 1'b1;
        end
        else begin
            s_out = s_result_tmp;
            e_out = e_final_biased[10:0];
            m_out = round_overflow ? m_rounded[52:1] : m_rounded[51:0];
        end
    end
    
    assign result = {s_out, e_out, m_out};

endmodule