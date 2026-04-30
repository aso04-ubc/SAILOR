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
            start_flag <= 1'b0;

            case (state)
                IDLE: begin
                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            start_flag <= 1'b1;
                            sticky_finish <= 1'b0;
                            nonce <= message_ram[13]; // initial nonce value given
                            state <= WAIT_START;
                        end else begin
                            sticky_finish <= 1'b0;
                        end
                    end
                end
                
                WAIT_START: begin
                    message_ram[13] <= nonce;
                    state <= RUNNING;
                end
                
                RUNNING: begin
                    if (core_finish) begin // found hash that passes the difficulty
                        if (flat_digest[255:240] == 16'h0000) begin
                            digest_capture <= flat_digest;
                            sticky_finish <= 1'b1;
                            state <= DONE;
                        end
                    end else begin
                        nonce <= nonce + 1;
                        start_flag <= 1'b1;
                        state <= WAIT_START;
                    end
                end
                
                DONE: begin
                    if (avs_write && avs_address == 24) begin
                        if (avs_writedata[0]) begin
                            start_flag <= 1'b1;
                            sticky_finish <= 1'b0;
                            state <= WAIT_START;
                        end else begin
                            sticky_finish <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
            endcase

            if (avs_write && avs_address < 16) begin
                message_ram[avs_address] <= avs_writedata;
            end
        end
    end

    always_comb begin
        avs_readdata = 32'b0;
        
        if (avs_address < 16) begin
            avs_readdata = message_ram[avs_address];
        end else if (avs_address >= 16 && avs_address <= 23) begin
            avs_readdata = digest_capture[255 - ((avs_address - 16) * 32) -: 32];
        end else if (avs_address == 24) begin
            avs_readdata = {31'b0, sticky_finish};
        end
    end

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