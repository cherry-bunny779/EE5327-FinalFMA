////////////////////////////////////////////////////////////////////////////////
// Module: qp_fma_toplv_pipelined_serial
// Description: Top-level Multiple-Precision Pipelined FMA Unit with Serial Input
//              8-bit wide input interface with internal 128-bit buffering
//              Supports QP, DP, SP, and HP precision modes
//
// Serial Input Interface:
//   - A_in[7:0], B_in[7:0], C_in[7:0]: 8-bit input ports
//   - load_en: Enable signal to load data into buffers
//   - Buffers fill LSB-first over 16 clock cycles
//   - data_valid asserted when all buffers are full
//   - FMA operation starts automatically when data_valid is asserted
//
// Precision Modes (controlled by 'precision' input):
//   2'b00 - QP: 1 × 128-bit Quadruple-Precision FMA
//   2'b01 - DP: 2 × 64-bit Double-Precision FMAs
//   2'b10 - SP: 4 × 32-bit Single-Precision FMAs
//   2'b11 - HP: 8 × 16-bit Half-Precision FMAs
//
// Timing:
//   - Input buffering: 16 clock cycles (128 bits / 8 bits per cycle)
//   - FMA pipeline: 3 clock cycles
//   - Total latency: 19 clock cycles from first input to valid output
//
// Author: Claude
// Date: 2025
////////////////////////////////////////////////////////////////////////////////

module qp_fma_toplv_pipelined_serial (
    input  logic        clk,
    input  logic        rst,
    
    // Serial input interface (8-bit wide)
    input  logic [7:0]  A_in,
    input  logic [7:0]  B_in,
    input  logic [7:0]  C_in,
    input  logic        load_en,          // Enable loading into buffers
    
    // Control inputs
    input  logic [1:0]  precision,        // Precision mode select
    
    // Status outputs
    output logic        data_valid,       // Asserted when buffers are full
    output logic        busy,             // Asserted during buffer loading
    
    // FMA outputs
    output logic [127:0] toplv_result,
    output logic [7:0]   overflow_flags,
    output logic [7:0]   underflow_flags,
    output logic [7:0]   nan_flags,
    output logic         valid_out
);

    //==========================================================================
    // Parameters
    //==========================================================================
    
    localparam BUFFER_WIDTH = 128;
    localparam INPUT_WIDTH  = 8;
    localparam LOAD_CYCLES  = BUFFER_WIDTH / INPUT_WIDTH;  // 16 cycles
    
    //==========================================================================
    // Internal Signals - Input Buffers
    //==========================================================================
    
    logic [BUFFER_WIDTH-1:0] A_buffer;
    logic [BUFFER_WIDTH-1:0] B_buffer;
    logic [BUFFER_WIDTH-1:0] C_buffer;
    logic [1:0]              precision_buffer;
    
    //==========================================================================
    // Buffer Load Counter
    //==========================================================================
    
    logic [4:0] load_counter;  // Counts 0-15 (16 cycles)
    logic       buffer_full;
    logic       loading;
    
    // Buffer is full when counter reaches 16 (all bytes loaded)
    assign buffer_full = (load_counter == LOAD_CYCLES);
    assign busy = loading && !buffer_full;
    
    //==========================================================================
    // Buffer Loading State Machine
    //==========================================================================
    
    typedef enum logic [1:0] {
        IDLE,
        LOADING,
        READY,
        WAIT_COMPLETE
    } state_t;
    
    state_t state, next_state;
    
    // State register
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (load_en) begin
                    next_state = LOADING;
                end
            end
            
            LOADING: begin
                if (buffer_full) begin
                    next_state = READY;
                end else if (!load_en) begin
                    // Continue loading even if load_en drops
                    // Or optionally: next_state = IDLE; to abort
                end
            end
            
            READY: begin
                // Data valid for one cycle, then wait for FMA to complete
                next_state = WAIT_COMPLETE;
            end
            
            WAIT_COMPLETE: begin
                // Wait for valid_out, then return to IDLE
                if (valid_out) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Loading flag
    assign loading = (state == LOADING) || (state == IDLE && load_en);
    
    //==========================================================================
    // Load Counter
    //==========================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            load_counter <= 5'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (load_en) begin
                        load_counter <= 5'b1;  // Start counting from 1
                    end else begin
                        load_counter <= 5'b0;
                    end
                end
                
                LOADING: begin
                    if (load_counter < LOAD_CYCLES) begin
                        load_counter <= load_counter + 1'b1;
                    end
                end
                
                READY, WAIT_COMPLETE: begin
                    // Hold counter value
                end
                
                default: begin
                    load_counter <= 5'b0;
                end
            endcase
        end
    end
    
    //==========================================================================
    // Input Buffers - Shift Register Implementation
    // Data is loaded LSB-first: first byte goes to bits [7:0]
    //==========================================================================
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            A_buffer <= 128'b0;
            B_buffer <= 128'b0;
            C_buffer <= 128'b0;
            precision_buffer <= 2'b0;
        end else begin
            if (state == IDLE && load_en) begin
                // First byte - load into LSB position
                A_buffer <= {120'b0, A_in};
                B_buffer <= {120'b0, B_in};
                C_buffer <= {120'b0, C_in};
                precision_buffer <= precision;
            end else if (state == LOADING && load_counter < LOAD_CYCLES) begin
                // Subsequent bytes - shift and load
                // New data goes into MSB, existing data shifts right
                // This fills buffer from LSB to MSB
                A_buffer <= {A_in, A_buffer[BUFFER_WIDTH-1:INPUT_WIDTH]};
                B_buffer <= {B_in, B_buffer[BUFFER_WIDTH-1:INPUT_WIDTH]};
                C_buffer <= {C_in, C_buffer[BUFFER_WIDTH-1:INPUT_WIDTH]};
            end
            // Hold values in READY and WAIT_COMPLETE states
        end
    end
    
    //==========================================================================
    // Data Valid Signal
    // Asserted for one clock cycle when buffers are full and ready
    //==========================================================================
    
    assign data_valid = (state == READY);
    
    //==========================================================================
    // FMA Core Instantiation
    //==========================================================================
    
    // Internal signals to FMA core
    logic         fma_valid_in;
    logic [127:0] fma_A, fma_B, fma_C;
    logic [1:0]   fma_precision;
    
    // Connect buffered data to FMA
    assign fma_valid_in  = data_valid;
    assign fma_A         = A_buffer;
    assign fma_B         = B_buffer;
    assign fma_C         = C_buffer;
    assign fma_precision = precision_buffer;
    
    //==========================================================================
    // Pipelined FMA Core
    //==========================================================================
    
    qp_fma_toplv_pipelined u_fma_core (
        .clk            ( clk              ),
        .rst            ( rst              ),
        .valid_in       ( fma_valid_in     ),
        .A              ( fma_A            ),
        .B              ( fma_B            ),
        .C              ( fma_C            ),
        .precision      ( fma_precision    ),
        .toplv_result   ( toplv_result     ),
        .overflow_flags ( overflow_flags   ),
        .underflow_flags( underflow_flags  ),
        .nan_flags      ( nan_flags        ),
        .valid_out      ( valid_out        )
    );

endmodule