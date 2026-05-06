// `timescale 1ns/1ps

// module tb_sha256_avalon_wrapper();

//     // Signals
//     logic        clk;
//     logic        reset_n;
//     logic [4:0]  avs_address;
//     logic        avs_write;
//     logic [31:0] avs_writedata;
//     logic        avs_read;
//     logic [31:0] avs_readdata;

//     // Instantiate the Wrapper
//     sha256_avalon_wrapper dut (
//         .clk(clk),
//         .reset_n(reset_n),
//         .avs_address(avs_address),
//         .avs_write(avs_write),
//         .avs_writedata(avs_writedata),
//         .avs_read(avs_read),
//         .avs_readdata(avs_readdata)
//     );

//     // 50MHz Clock Generation
//     initial clk = 0;
//     always #10 clk = ~clk;

//     // Helper Task: Avalon Write
//     task avalon_write(input [4:0] addr, input [31:0] data);
//         begin
//             @(posedge clk);
//             avs_address = addr;
//             avs_write = 1;
//             avs_writedata = data;
//             @(posedge clk);
//             avs_write = 0;
//         end
//     endtask
        
//     task avalon_read(input [4:0] addr, output [31:0] read_val);
//         begin
//             @(posedge clk);
//             avs_address = addr;
//             avs_read = 1;
//             @(posedge clk); 
//             #1; 
            
//             
//             read_val = avs_readdata; 
//             $display("Read Address %0d: 0x%h", addr, read_val);
            
//             avs_read = 0;
//         end
//     endtask


//     logic [31:0] polled_data;
//     // Main Test Sequence
//     initial begin
//         
//         reset_n = 0;
//         avs_write = 0;
//         avs_read = 0;
//         avs_address = 0;
//         avs_writedata = 0;

//         #50;
//         reset_n = 1;
//         #20;

//         $display("--- Starting Empty String Test ---");

//         // 2. Write Padded Input (Empty String)
//         // Reg 0: 0x80000000
//         avalon_write(5'd0, 32'h80000000);
        
//         // Regs 1-14: 0x0
//         for (int i=1; i<15; i++) begin
//             avalon_write(i[4:0], 32'h0);
//         end
        
//         
//         avalon_write(5'd15, 32'h0);

//         
//         $display("Triggering Start...");
//         avalon_write(5'd24, 32'h1);

//         // 4. Poll Sticky Finish (Reg 24)
//         // We simulate polling by reading until bit 0 is high
//         do begin
//             avalon_read(5'd24, polled_data);
//             #40; 
//         end while ((polled_data & 32'h00000001) == 32'h00000000);
//         

//         $display("Core Finished! Reading Results...");

//         
//         for (int i=16; i<=23; i++) begin
//             avalon_read(i[4:0], polled_data);
//         end

//         #100;
//         $finish;
//     end

// endmodule

`timescale 1ns/1ps

module tb_sha256_avalon_wrapper();

    logic        clk;
    logic        reset_n;
    logic [4:0]  avs_address;
    logic        avs_write;
    logic [31:0] avs_writedata;
    logic        avs_read;
    logic [31:0] avs_readdata;

    // Instantiate the Wrapper
    sha256_avalon_wrapper dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .avs_address  (avs_address),
        .avs_write    (avs_write),
        .avs_writedata(avs_writedata),
        .avs_read     (avs_read),
        .avs_readdata (avs_readdata)
    );

    // -----------------------------------------------------------------------
    // 50 MHz clock
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        #6_000_000;
        $display("TIMEOUT: sticky_finish never asserted within 300 000 cycles.");
        $fatal(1, "Simulation timed out");
    end


    task avalon_write(input [4:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            avs_address   = addr;
            avs_write     = 1;
            avs_writedata = data;
            @(posedge clk);
            avs_write = 0;
        end
    endtask

    task avalon_read(input [4:0] addr, output [31:0] read_val);
        begin
            @(posedge clk);
            avs_address = addr;
            avs_read    = 1;
            @(posedge clk);
            #1;
            read_val = avs_readdata;
            // $display("Read Address %0d: 0x%08h", addr, read_val);
            avs_read = 0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [31:0]  polled_data;
    logic [31:0]  digest_words [0:7];
    logic [255:0] full_digest;
    logic [31:0]  winning_nonce;
    longint       start_time_ns;

    initial begin
        reset_n       = 0;
        avs_write     = 0;
        avs_read      = 0;
        avs_address   = 0;
        avs_writedata = 0;

        #50;
        reset_n = 1;
        #20;

        $display("--- Pipelined Wrapper Mining Test ---");
        $display("Block: padded empty string, starting nonce = 0");
        $display("Difficulty: digest[255:240] == 16'h0000 (~65 536 hashes expected)");
        $display("");

        avalon_write(5'd0, 32'h80000000);
        for (int i = 1; i < 15; i++)
            avalon_write(i[4:0], 32'h0);
        avalon_write(5'd15, 32'h0);

        $display("Triggering search (writing 1 to address 24)...");
        start_time_ns = $time;
        avalon_write(5'd24, 32'h1);

        do begin
            avalon_read(5'd24, polled_data);
            #40;
        end while ((polled_data & 32'h1) == 32'h0);

        $display("");
        $display("=== sticky_finish asserted at t = %0t (elapsed ~%0t) ===",
                 $time, $time - start_time_ns);

        avalon_read(5'd13, winning_nonce);
        $display("Winning nonce: 0x%08h (%0d decimal)", winning_nonce, winning_nonce);

        $display("Captured digest:");
        for (int i = 0; i < 8; i++) begin
            avalon_read(16 + i, digest_words[i]);
            full_digest[255 - i*32 -: 32] = digest_words[i];
        end
        $display("Full digest: %h", full_digest);

        $display("");
        if (full_digest[255:240] == 16'h0000)
            $display("PASS: digest[255:240] == 16'h0000 — difficulty target satisfied.");
        else begin
            $display("FAIL: digest[255:240] == 16'h%04h — difficulty target NOT satisfied.",
                     full_digest[255:240]);
            $fatal(1, "Difficulty check failed");
        end

        #100;
        $finish;
    end

endmodule