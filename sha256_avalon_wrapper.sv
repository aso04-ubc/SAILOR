// ======================================================== ITERATIVE ======================================================== //
// module sha256_avalon_wrapper (
//     (* keep *) input  logic        clk,
//     (* keep *) input  logic        reset_n,

//     (* keep *) input  logic [4:0]  avs_address,
//     (* keep *) input  logic        avs_write,
//     (* keep *) input  logic [31:0] avs_writedata,
//     (* keep *) input  logic        avs_read,
//     (* keep *) output logic [31:0] avs_readdata
// );

//     logic [31:0] message_ram [0:15];
//     logic        start_flag;
    
//     logic [511:0] flat_block;
//     logic [255:0] flat_digest;
//     logic [255:0] digest_capture;
//     logic         core_finish;
//     logic         sticky_finish;
//     logic [31:0]  nonce;

//     typedef enum logic [1:0] {
//         IDLE,
//         WAIT_START,
//         RUNNING,
//         DONE
//     } state_t;
    
//     state_t state;

//     always_ff @(posedge clk or negedge reset_n) begin
//         if (!reset_n) begin
//             start_flag <= 1'b0;
//             sticky_finish <= 1'b0;
//             state <= IDLE;
//             for (int i=0; i<16; i++) message_ram[i] <= 32'b0;
//             digest_capture <= 256'b0;
//         end else begin
//             start_flag <= 1'b0;

//             case (state)
//                 IDLE: begin
//                     if (avs_write && avs_address == 24) begin
//                         if (avs_writedata[0]) begin
//                             start_flag <= 1'b1;
//                             sticky_finish <= 1'b0;
//                             nonce <= message_ram[13]; // initial nonce value given
//                             state <= WAIT_START;
//                         end else begin
//                             sticky_finish <= 1'b0;
//                         end
//                     end
//                 end
                
//                 WAIT_START: begin
//                     message_ram[13] <= nonce;
//                     state <= RUNNING;
//                 end
                
//                 RUNNING: begin
//                     if (core_finish) begin // found hash that passes the difficulty
//                         if (flat_digest[255:240] == 16'h0000) begin
//                             digest_capture <= flat_digest;
//                             sticky_finish <= 1'b1;
//                             state <= DONE;
//                         end
//                     end else begin
//                         nonce <= nonce + 1;
//                         start_flag <= 1'b1;
//                         state <= WAIT_START;
//                     end
//                 end
                
//                 DONE: begin
//                     if (avs_write && avs_address == 24) begin
//                         if (avs_writedata[0]) begin
//                             start_flag <= 1'b1;
//                             sticky_finish <= 1'b0;
//                             state <= WAIT_START;
//                         end else begin
//                             sticky_finish <= 1'b0;
//                             state <= IDLE;
//                         end
//                     end
//                 end
//             endcase

//             if (avs_write && avs_address < 16) begin
//                 message_ram[avs_address] <= avs_writedata;
//             end
//         end
//     end

//     always_comb begin
//         avs_readdata = 32'b0;
        
//         if (avs_address < 16) begin
//             avs_readdata = message_ram[avs_address];
//         end else if (avs_address >= 16 && avs_address <= 23) begin
//             avs_readdata = digest_capture[255 - ((avs_address - 16) * 32) -: 32];
//         end else if (avs_address == 24) begin
//             avs_readdata = {31'b0, sticky_finish};
//         end
//     end

//     genvar i;
//     generate
//         for (i = 0; i < 16; i++) begin : flatten_loop
//             assign flat_block[511 - (i * 32) -: 32] = message_ram[i];
//         end
//     endgenerate

//     sha256 my_hash_core (
//         .clock  (clk),
//         .reset  (reset_n),
//         .start  (start_flag),
//         .block  (flat_block),
//         .digest (flat_digest),
//         .finish (core_finish)
//     );

// endmodule


// ======================================================== PIPELINED ======================================================== //
module sha256_avalon_wrapper (
    (* keep *) input  logic        clk,
    (* keep *) input  logic        reset_n,

    (* keep *) input  logic [4:0]  avs_address,
    (* keep *) input  logic        avs_write,
    (* keep *) input  logic [31:0] avs_writedata,
    (* keep *) input  logic        avs_read,
    (* keep *) output logic [31:0] avs_readdata
);

    logic [31:0] message_ram [0:15];
    logic        start_flag;

    logic [511:0] flat_block;
    logic [255:0] flat_digest;
    logic [255:0] digest_capture;
    logic         core_finish;
    logic         sticky_finish;
    logic [31:0]  nonce;

    // Tracks which nonce is in each pipeline stage.
    // nonce_pipeline[0]  = nonce captured by the pipeline this cycle (newest)
    // nonce_pipeline[63] = nonce that entered the pipeline 64 cycles ago (oldest, matches current finish)
    logic [31:0] nonce_pipeline [0:63];

    typedef enum logic [1:0] {
        IDLE,
        WARMUP,
        RUNNING,
        DONE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_flag     <= 1'b0;
            sticky_finish  <= 1'b0;
            state          <= IDLE;
            nonce          <= 32'b0;
            digest_capture <= 256'b0;
            for (int i = 0; i < 16; i++) message_ram[i]    <= 32'b0;
            for (int i = 0; i < 64; i++) nonce_pipeline[i] <= 32'b0;
        end else begin
            start_flag <= 1'b0; // default: no start pulse

            case (state)

                // ----------------------------------------------------------------
                // IDLE: CPU loads message_ram and triggers a search via address 24.
                // ----------------------------------------------------------------
                IDLE: begin
                    if (avs_write && avs_address < 16)
                        message_ram[avs_address] <= avs_writedata;

                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            sticky_finish <= 1'b0;
                            nonce         <= message_ram[13]; // capture starting nonce
                            state         <= WARMUP;
                        end else begin
                            sticky_finish <= 1'b0;
                        end
                    end
                end

                // ----------------------------------------------------------------
                // WARMUP: one-cycle setup so that both message_ram[13] and
                // start_flag are valid on the same posedge entering RUNNING.
                //
                //   end of WARMUP  →  message_ram[13] = nonce_0 (starting nonce)
                //                     start_flag      = 1
                //
                // The pipelined core will therefore capture nonce_0 on the very
                // first RUNNING posedge (cycle 0), with no wasted cycles.
                // ----------------------------------------------------------------
                WARMUP: begin
                    message_ram[13] <= nonce;       // nonce_0 visible next posedge
                    nonce           <= nonce + 1;   // prepare nonce_1 for RUNNING cycle 0
                    start_flag      <= 1'b1;        // pipeline captures nonce_0 on RUNNING cycle 0
                    state           <= RUNNING;
                end

                // ----------------------------------------------------------------
                // RUNNING: feed a new block into the pipeline every cycle.
                //
                // The pipelined core accepts one block per cycle; results emerge
                // exactly 64 cycles later.  nonce_pipeline[63] always holds the
                // nonce that corresponds to the current finish output.
                //
                // Timing of key signals at posedge of RUNNING cycle N:
                //   start_flag      = 1  (set at end of cycle N-1)
                //   message_ram[13] = nonce_N (set at end of cycle N-1)
                //   core_finish     = result valid for nonce_{N-64}
                //   nonce_pipeline[63] = nonce_{N-64}  ← matching the finish output
                // ----------------------------------------------------------------
                RUNNING: begin
                    // ---- Shift the nonce tracking pipeline ----
                    // Uses pre-update message_ram[13] (non-blocking read = nonce_N).
                    for (int k = 63; k > 0; k--)
                        nonce_pipeline[k] <= nonce_pipeline[k-1];
                    nonce_pipeline[0] <= message_ram[13]; // nonce being captured this cycle

                    // ---- Check result from 64 cycles ago ----
                    if (core_finish && flat_digest[255:240] == 16'h0000) begin
                        // Found a hash that satisfies the difficulty target
                        digest_capture  <= flat_digest;
                        message_ram[13] <= nonce_pipeline[63]; // save winning nonce for CPU readback
                        sticky_finish   <= 1'b1;
                        state           <= DONE;
                        // start_flag stays 0: stop feeding the pipeline
                    end else begin
                        // Keep feeding new blocks every cycle
                        start_flag      <= 1'b1;
                        message_ram[13] <= nonce;       // nonce_{N+1} for next cycle
                        nonce           <= nonce + 1;
                    end
                end

                // ----------------------------------------------------------------
                // DONE: CPU reads the digest (addresses 16-23) and the winning
                // nonce (address 13).  Writing 1 to address 24 restarts; writing
                // 0 returns to IDLE so the block can be reloaded.
                // ----------------------------------------------------------------
                DONE: begin
                    if (avs_write && avs_address < 16)
                        message_ram[avs_address] <= avs_writedata;

                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            // Continue search from the nonce after the winning one
                            sticky_finish <= 1'b0;
                            nonce         <= message_ram[13] + 1;
                            state         <= WARMUP;
                        end else begin
                            sticky_finish <= 1'b0;
                            state         <= IDLE;
                        end
                    end
                end

            endcase
        end
    end

    // ---- Avalon read-back ----
    always_comb begin
        avs_readdata = 32'b0;

        if (avs_address < 16) begin
            avs_readdata = message_ram[avs_address];          // block words (13 = nonce)
        end else if (avs_address >= 16 && avs_address <= 23) begin
            avs_readdata = digest_capture[255 - ((avs_address - 16) * 32) -: 32]; // digest
        end else if (avs_address == 24) begin
            avs_readdata = {31'b0, sticky_finish};            // status
        end
    end

    // ---- Flatten message_ram into a single 512-bit block bus ----
    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : flatten_loop
            assign flat_block[511 - (i * 32) -: 32] = message_ram[i];
        end
    endgenerate

    sha256 my_hash_core (
        .clock  (clk),
        .reset  (reset_n),
        .start  (start_flag),
        .block  (flat_block),
        .digest (flat_digest),
        .finish (core_finish)
    );

endmodule