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

    // Added WAIT_START state to prevent false-finishes
    typedef enum logic [1:0] {
        IDLE,
        WAIT_START,
        RUNNING,
        DONE
    } state_t;
    
    state_t state;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            start_flag <= 1'b0;
            sticky_finish <= 1'b0;
            state <= IDLE;
            for (int i=0; i<16; i++) message_ram[i] <= 32'b0;
            digest_capture <= 256'b0;
        end else begin
            // Default: single-cycle pulse
            start_flag <= 1'b0;

            case (state)
                IDLE: begin
                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            start_flag <= 1'b1;
                            sticky_finish <= 1'b0;
                            state <= WAIT_START;
                        end else begin
                            // Handle the C code's clear command (0x0)
                            sticky_finish <= 1'b0;
                        end
                    end
                end
                
                WAIT_START: begin
                    // Wait 1 clock cycle for the core to recognize start_flag
                    // and lower its core_finish signal from any previous run.
                    state <= RUNNING;
                end
                
                RUNNING: begin
                    if (core_finish) begin
                        // Capture the digest when computation completes
                        digest_capture <= flat_digest;
                        sticky_finish <= 1'b1;
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            start_flag <= 1'b1;
                            sticky_finish <= 1'b0;
                            state <= WAIT_START;
                        end else begin
                            // Handle the C code's clear command to reset for the next test
                            sticky_finish <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
            endcase

            // Message RAM writes
            if (avs_write && avs_address < 16) begin
                message_ram[avs_address] <= avs_writedata;
            end
        end
    end

    // FIX: Pure address-based combinational read. 
    // Removing `if (avs_read)` ensures data is stable as long as address is stable, 
    // preventing the interconnect from sampling 0 due to 0-latency setup timing.
    always_comb begin
        avs_readdata = 32'b0; // default
        
        if (avs_address < 16) begin
            // Read back input RAM for debugging
            avs_readdata = message_ram[avs_address];
        end else if (avs_address >= 16 && avs_address <= 23) begin
            // Read from captured digest for stability
            avs_readdata = digest_capture[255 - ((avs_address - 16) * 32) -: 32];
        end else if (avs_address == 24) begin
            // Status: bit 0 = done
            avs_readdata = {31'b0, sticky_finish};
        end
    end

    // Flatten message RAM to block input
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