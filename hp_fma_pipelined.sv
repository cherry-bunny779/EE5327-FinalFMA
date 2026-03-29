////////////////////////////////////////////////////////////////////////////////
// Module: hp_fma_pipelined
// Description: IEEE 754 Half-Precision Floating-Point Fused Multiply-Add
//              with 3-stage pipeline
//              Computes A × B + C where A, B, C are 16-bit HP values
//
// Pipeline Structure:
//   Stage 1: Multiplication + Addend Alignment (parallel)
//   Stage 2: Addition/Subtraction + Leading Zero Count
//   Stage 3: Normalization + Rounding + Result Assembly
//
// Latency: 3 clock cycles
// Throughput: 1 operation per clock cycle
//
// IEEE 754 HP Format (16 bits):
//   [15]    - Sign bit (S)
//   [14:10] - Exponent (E), 5 bits, bias = 15
//   [9:0]   - Mantissa (M), 10 bits (implicit leading 1 for normal numbers)
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module hp_fma_pipelined (
    input  logic        clk,
    input  logic        rst,
    input  logic        valid_in,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic [15:0] c,
    output logic [15:0] result,
    output logic        overflow,
    output logic        underflow,
    output logic        nan_out,
    output logic        valid_out
);

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam WORK_WIDTH = 35;  // 22 + 11 + 2 guard bits
    
    //==========================================================================
    // Pipeline Valid Signals
    //==========================================================================
    
    logic valid_s1, valid_s2;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
        end else begin
            valid_s1 <= valid_in;
            valid_s2 <= valid_s1;
        end
    end

    //==========================================================================
    //==========================================================================
    // STAGE 1: Multiplication + Alignment (Combinational Logic)
    //==========================================================================
    //==========================================================================
    
    // Field extraction
    logic        s_a, s_b, s_c;
    logic [4:0]  e_a, e_b, e_c;
    logic [9:0]  m_a, m_b, m_c;
    
    assign s_a = a[15]; assign e_a = a[14:10]; assign m_a = a[9:0];
    assign s_b = b[15]; assign e_b = b[14:10]; assign m_b = b[9:0];
    assign s_c = c[15]; assign e_c = c[14:10]; assign m_c = c[9:0];
    
    // Special case detection
    logic a_is_zero, b_is_zero, c_is_zero;
    logic a_is_inf, b_is_inf, c_is_inf;
    logic a_is_nan, b_is_nan, c_is_nan;
    logic a_is_subnormal, b_is_subnormal, c_is_subnormal;
    
    assign a_is_zero      = (e_a == 5'h00) && (m_a == 10'b0);
    assign b_is_zero      = (e_b == 5'h00) && (m_b == 10'b0);
    assign c_is_zero      = (e_c == 5'h00) && (m_c == 10'b0);
    assign a_is_inf       = (e_a == 5'h1F) && (m_a == 10'b0);
    assign b_is_inf       = (e_b == 5'h1F) && (m_b == 10'b0);
    assign c_is_inf       = (e_c == 5'h1F) && (m_c == 10'b0);
    assign a_is_nan       = (e_a == 5'h1F) && (m_a != 10'b0);
    assign b_is_nan       = (e_b == 5'h1F) && (m_b != 10'b0);
    assign c_is_nan       = (e_c == 5'h1F) && (m_c != 10'b0);
    assign a_is_subnormal = (e_a == 5'h00) && (m_a != 10'b0);
    assign b_is_subnormal = (e_b == 5'h00) && (m_b != 10'b0);
    assign c_is_subnormal = (e_c == 5'h00) && (m_c != 10'b0);
    
    logic product_is_zero, product_is_inf;
    assign product_is_zero = a_is_zero || b_is_zero;
    assign product_is_inf  = a_is_inf || b_is_inf;
    
    // Mantissa multiplication
    logic        s_product;
    logic [10:0] mantissa_a_full, mantissa_b_full;
    logic [21:0] product_mantissa;
    
    assign s_product = s_a ^ s_b;
    assign mantissa_a_full = a_is_subnormal ? {1'b0, m_a} : {1'b1, m_a};
    assign mantissa_b_full = b_is_subnormal ? {1'b0, m_b} : {1'b1, m_b};
    assign product_mantissa = mantissa_a_full * mantissa_b_full;
    
    // Product exponent calculation
    logic signed [6:0] e_a_unbiased, e_b_unbiased, e_product_unbiased;
    assign e_a_unbiased = a_is_subnormal ? -7'sd14 : ($signed({2'b0, e_a}) - 7'sd15);
    assign e_b_unbiased = b_is_subnormal ? -7'sd14 : ($signed({2'b0, e_b}) - 7'sd15);
    assign e_product_unbiased = e_a_unbiased + e_b_unbiased;
    
    // Product normalization
    logic product_norm_shift;
    logic signed [6:0] e_product_norm;
    logic [21:0] product_mantissa_norm;
    
    assign product_norm_shift = product_mantissa[21];
    assign e_product_norm = product_norm_shift ? (e_product_unbiased + 1) : e_product_unbiased;
    assign product_mantissa_norm = product_norm_shift ? product_mantissa : (product_mantissa << 1);
    
    // Addend preparation
    // NOTE: When c_is_zero, mantissa_c_full must be 0 to avoid polluting the result
    logic [10:0] mantissa_c_full;
    logic signed [6:0] e_c_unbiased;
    
    assign mantissa_c_full = c_is_zero ? 11'b0 :
                             (c_is_subnormal ? {1'b0, m_c} : {1'b1, m_c});
    assign e_c_unbiased = c_is_subnormal ? -7'sd14 : ($signed({2'b0, e_c}) - 7'sd15);
    
    // Alignment
    logic signed [6:0] exp_diff;
    logic [WORK_WIDTH-1:0] product_aligned;
    logic [WORK_WIDTH-1:0] addend_aligned;
    logic signed [6:0] e_aligned;
    logic sticky_bit_align;
    logic effective_subtract;
    
    assign exp_diff = e_product_norm - e_c_unbiased;
    assign effective_subtract = s_product ^ s_c;
    
    always_comb begin
        product_aligned = '0;
        addend_aligned = '0;
        sticky_bit_align = 1'b0;
        e_aligned = e_product_norm;
        
        product_aligned = {product_mantissa_norm, 13'b0};
        
        if (exp_diff >= 0) begin
            e_aligned = e_product_norm;
            if (exp_diff < WORK_WIDTH) begin
                logic [WORK_WIDTH-1:0] addend_temp;
                addend_temp = {mantissa_c_full, 24'b0};
                addend_aligned = addend_temp >> exp_diff;
                if (exp_diff > 0 && exp_diff <= 24) begin
                    sticky_bit_align = |(addend_temp << (WORK_WIDTH - exp_diff));
                end else if (exp_diff > 24) begin
                    sticky_bit_align = |mantissa_c_full;
                end
            end else begin
                addend_aligned = '0;
                sticky_bit_align = |mantissa_c_full;
            end
        end else begin
            e_aligned = e_c_unbiased;
            addend_aligned = {mantissa_c_full, 24'b0};
            if (-exp_diff < WORK_WIDTH) begin
                product_aligned = {product_mantissa_norm, 13'b0} >> (-exp_diff);
                if (-exp_diff > 0 && -exp_diff <= 13) begin
                    sticky_bit_align = |({product_mantissa_norm, 13'b0} << (WORK_WIDTH + exp_diff));
                end else if (-exp_diff > 13) begin
                    sticky_bit_align = |product_mantissa_norm;
                end
            end else begin
                product_aligned = '0;
                sticky_bit_align = |product_mantissa_norm;
            end
        end
    end
    
    //==========================================================================
    // STAGE 1 -> STAGE 2 Pipeline Registers
    //==========================================================================
    
    logic [WORK_WIDTH-1:0] product_aligned_s1;
    logic [WORK_WIDTH-1:0] addend_aligned_s1;
    logic signed [6:0]     e_aligned_s1;
    logic                  sticky_bit_align_s1;
    logic                  effective_subtract_s1;
    logic                  s_product_s1;
    logic                  s_c_s1;
    
    logic                  a_is_nan_s1, b_is_nan_s1, c_is_nan_s1;
    logic                  a_is_inf_s1, b_is_inf_s1, c_is_inf_s1;
    logic                  a_is_zero_s1, b_is_zero_s1, c_is_zero_s1;
    logic                  product_is_zero_s1, product_is_inf_s1;
    logic [4:0]            e_c_s1;
    logic [9:0]            m_c_s1;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            product_aligned_s1    <= '0;
            addend_aligned_s1     <= '0;
            e_aligned_s1          <= '0;
            sticky_bit_align_s1   <= 1'b0;
            effective_subtract_s1 <= 1'b0;
            s_product_s1          <= 1'b0;
            s_c_s1                <= 1'b0;
            a_is_nan_s1           <= 1'b0;
            b_is_nan_s1           <= 1'b0;
            c_is_nan_s1           <= 1'b0;
            a_is_inf_s1           <= 1'b0;
            b_is_inf_s1           <= 1'b0;
            c_is_inf_s1           <= 1'b0;
            a_is_zero_s1          <= 1'b0;
            b_is_zero_s1          <= 1'b0;
            c_is_zero_s1          <= 1'b0;
            product_is_zero_s1    <= 1'b0;
            product_is_inf_s1     <= 1'b0;
            e_c_s1                <= '0;
            m_c_s1                <= '0;
        end else begin
            product_aligned_s1    <= product_aligned;
            addend_aligned_s1     <= addend_aligned;
            e_aligned_s1          <= e_aligned;
            sticky_bit_align_s1   <= sticky_bit_align;
            effective_subtract_s1 <= effective_subtract;
            s_product_s1          <= s_product;
            s_c_s1                <= s_c;
            a_is_nan_s1           <= a_is_nan;
            b_is_nan_s1           <= b_is_nan;
            c_is_nan_s1           <= c_is_nan;
            a_is_inf_s1           <= a_is_inf;
            b_is_inf_s1           <= b_is_inf;
            c_is_inf_s1           <= c_is_inf;
            a_is_zero_s1          <= a_is_zero;
            b_is_zero_s1          <= b_is_zero;
            c_is_zero_s1          <= c_is_zero;
            product_is_zero_s1    <= product_is_zero;
            product_is_inf_s1     <= product_is_inf;
            e_c_s1                <= e_c;
            m_c_s1                <= m_c;
        end
    end
    
    //==========================================================================
    //==========================================================================
    // STAGE 2: Addition/Subtraction + LZC (Combinational Logic)
    //==========================================================================
    //==========================================================================
    
    logic [WORK_WIDTH:0] sum_mantissa;
    logic                s_result_tmp;
    
    always_comb begin
        if (effective_subtract_s1) begin
            if (product_aligned_s1 >= addend_aligned_s1) begin
                sum_mantissa = {1'b0, product_aligned_s1} - {1'b0, addend_aligned_s1};
                s_result_tmp = s_product_s1;
            end else begin
                sum_mantissa = {1'b0, addend_aligned_s1} - {1'b0, product_aligned_s1};
                s_result_tmp = s_c_s1;
            end
        end else begin
            sum_mantissa = {1'b0, product_aligned_s1} + {1'b0, addend_aligned_s1};
            s_result_tmp = s_product_s1;
        end
    end
    
    // Leading zero count
    logic [5:0] lzc;
    
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
    
    //==========================================================================
    // STAGE 2 -> STAGE 3 Pipeline Registers
    //==========================================================================
    
    logic [WORK_WIDTH:0]   sum_mantissa_s2;
    logic [5:0]            lzc_s2;
    logic                  s_result_tmp_s2;
    logic signed [6:0]     e_aligned_s2;
    logic                  sticky_bit_align_s2;
    
    logic                  a_is_nan_s2, b_is_nan_s2, c_is_nan_s2;
    logic                  a_is_inf_s2, b_is_inf_s2, c_is_inf_s2;
    logic                  a_is_zero_s2, b_is_zero_s2, c_is_zero_s2;
    logic                  product_is_zero_s2, product_is_inf_s2;
    logic                  s_product_s2, s_c_s2;
    logic [4:0]            e_c_s2;
    logic [9:0]            m_c_s2;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sum_mantissa_s2       <= '0;
            lzc_s2                <= '0;
            s_result_tmp_s2       <= 1'b0;
            e_aligned_s2          <= '0;
            sticky_bit_align_s2   <= 1'b0;
            a_is_nan_s2           <= 1'b0;
            b_is_nan_s2           <= 1'b0;
            c_is_nan_s2           <= 1'b0;
            a_is_inf_s2           <= 1'b0;
            b_is_inf_s2           <= 1'b0;
            c_is_inf_s2           <= 1'b0;
            a_is_zero_s2          <= 1'b0;
            b_is_zero_s2          <= 1'b0;
            c_is_zero_s2          <= 1'b0;
            product_is_zero_s2    <= 1'b0;
            product_is_inf_s2     <= 1'b0;
            s_product_s2          <= 1'b0;
            s_c_s2                <= 1'b0;
            e_c_s2                <= '0;
            m_c_s2                <= '0;
        end else begin
            sum_mantissa_s2       <= sum_mantissa;
            lzc_s2                <= lzc;
            s_result_tmp_s2       <= s_result_tmp;
            e_aligned_s2          <= e_aligned_s1;
            sticky_bit_align_s2   <= sticky_bit_align_s1;
            a_is_nan_s2           <= a_is_nan_s1;
            b_is_nan_s2           <= b_is_nan_s1;
            c_is_nan_s2           <= c_is_nan_s1;
            a_is_inf_s2           <= a_is_inf_s1;
            b_is_inf_s2           <= b_is_inf_s1;
            c_is_inf_s2           <= c_is_inf_s1;
            a_is_zero_s2          <= a_is_zero_s1;
            b_is_zero_s2          <= b_is_zero_s1;
            c_is_zero_s2          <= c_is_zero_s1;
            product_is_zero_s2    <= product_is_zero_s1;
            product_is_inf_s2     <= product_is_inf_s1;
            s_product_s2          <= s_product_s1;
            s_c_s2                <= s_c_s1;
            e_c_s2                <= e_c_s1;
            m_c_s2                <= m_c_s1;
        end
    end
    
    //==========================================================================
    //==========================================================================
    // STAGE 3: Normalization + Rounding + Result Assembly (Combinational)
    //==========================================================================
    //==========================================================================
    
    // Normalization
    logic [WORK_WIDTH:0] sum_normalized;
    logic signed [6:0] e_normalized;
    
    always_comb begin
        if (sum_mantissa_s2[WORK_WIDTH]) begin
            sum_normalized = sum_mantissa_s2 >> 1;
            e_normalized = e_aligned_s2 + 1;
        end else if (lzc_s2 == 0) begin
            sum_normalized = sum_mantissa_s2;
            e_normalized = e_aligned_s2;
        end else if (lzc_s2 > 0) begin
            sum_normalized = sum_mantissa_s2 << lzc_s2;
            e_normalized = e_aligned_s2 - lzc_s2;
        end else begin
            sum_normalized = sum_mantissa_s2;
            e_normalized = e_aligned_s2;
        end
    end
    
    // Rounding
    logic [9:0] m_truncated;
    logic guard, round_bit, sticky;
    logic round_up;
    logic [10:0] m_rounded;
    logic round_overflow;
    
    assign m_truncated = sum_normalized[WORK_WIDTH-2 -: 10];
    assign guard = sum_normalized[WORK_WIDTH-12];
    assign round_bit = sum_normalized[WORK_WIDTH-13];
    assign sticky = |sum_normalized[WORK_WIDTH-14:0] | sticky_bit_align_s2;
    
    assign round_up = guard && (round_bit || sticky || m_truncated[0]);
    assign m_rounded = {1'b0, m_truncated} + {10'b0, round_up};
    assign round_overflow = m_rounded[10];
    
    // Final exponent calculation
    logic signed [6:0] e_final_unbiased;
    logic [6:0] e_final_biased;
    
    assign e_final_unbiased = round_overflow ? (e_normalized + 1) : e_normalized;
    assign e_final_biased = e_final_unbiased + 7'sd15;
    
    // Result assembly with special cases
    logic [4:0]  e_out;
    logic [9:0]  m_out;
    logic        s_out;
    logic        overflow_comb, underflow_comb, nan_out_comb;
    
    always_comb begin
        s_out = s_result_tmp_s2;
        e_out = 5'b0;
        m_out = 10'b0;
        overflow_comb = 1'b0;
        underflow_comb = 1'b0;
        nan_out_comb = 1'b0;
        
        if (a_is_nan_s2 || b_is_nan_s2 || c_is_nan_s2) begin
            s_out = 1'b0;
            e_out = 5'h1F;
            m_out = 10'h200;
            nan_out_comb = 1'b1;
        end
        else if ((a_is_inf_s2 && b_is_zero_s2) || (a_is_zero_s2 && b_is_inf_s2)) begin
            s_out = 1'b0;
            e_out = 5'h1F;
            m_out = 10'h200;
            nan_out_comb = 1'b1;
        end
        else if (product_is_inf_s2 && c_is_inf_s2 && (s_product_s2 != s_c_s2)) begin
            s_out = 1'b0;
            e_out = 5'h1F;
            m_out = 10'h200;
            nan_out_comb = 1'b1;
        end
        else if (product_is_inf_s2 || c_is_inf_s2) begin
            s_out = product_is_inf_s2 ? s_product_s2 : s_c_s2;
            e_out = 5'h1F;
            m_out = 10'b0;
            overflow_comb = 1'b1;
        end
        else if (product_is_zero_s2 && c_is_zero_s2) begin
            s_out = s_product_s2 & s_c_s2;
            e_out = 5'h00;
            m_out = 10'b0;
        end
        else if (product_is_zero_s2) begin
            s_out = s_c_s2;
            e_out = e_c_s2;
            m_out = m_c_s2;
        end
        else if (c_is_zero_s2) begin
            if (e_final_biased <= 0) begin
                s_out = s_result_tmp_s2;
                e_out = 5'h00;
                m_out = 10'b0;
                underflow_comb = 1'b1;
            end else if (e_final_biased >= 31) begin
                s_out = s_result_tmp_s2;
                e_out = 5'h1F;
                m_out = 10'b0;
                overflow_comb = 1'b1;
            end else begin
                s_out = s_result_tmp_s2;
                e_out = e_final_biased[4:0];
                m_out = round_overflow ? m_rounded[10:1] : m_rounded[9:0];
            end
        end
        else if (sum_mantissa_s2 == 0) begin
            s_out = 1'b0;
            e_out = 5'h00;
            m_out = 10'b0;
        end
        else if (e_final_biased <= 0) begin
            s_out = s_result_tmp_s2;
            e_out = 5'h00;
            m_out = 10'b0;
            underflow_comb = 1'b1;
        end
        else if (e_final_biased >= 31) begin
            s_out = s_result_tmp_s2;
            e_out = 5'h1F;
            m_out = 10'b0;
            overflow_comb = 1'b1;
        end
        else begin
            s_out = s_result_tmp_s2;
            e_out = e_final_biased[4:0];
            m_out = round_overflow ? m_rounded[10:1] : m_rounded[9:0];
        end
    end
    
    //==========================================================================
    // STAGE 3 Output Registers
    //==========================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            result    <= 16'b0;
            overflow  <= 1'b0;
            underflow <= 1'b0;
            nan_out   <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            result    <= {s_out, e_out, m_out};
            overflow  <= overflow_comb;
            underflow <= underflow_comb;
            nan_out   <= nan_out_comb;
            valid_out <= valid_s2;
        end
    end

endmodule