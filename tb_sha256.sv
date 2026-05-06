// `timescale 1ns/1ps

// module tb_sha256;

//     logic clk = 0;
//     logic reset;
//     logic start;
//     logic [511:0] block;
//     logic [255:0] digest;
//     logic finish;
//     logic [255:0] expected;

//     always #5 clk = ~clk;

//     sha256 dut (
//         .clock(clk),
//         .reset(reset),
//         .start(start),
//         .block(block),
//         .digest(digest),
//         .finish(finish)
//     );

//     integer file;
//     integer scan_result;

//     initial begin
//         #1000000;
//         $display("Error: Simulation timed out");
//         $finish;
//     end

//     initial begin

//         $dumpfile("wave.vcd");
//         $dumpvars(0, tb_sha256);

//         start = 0;
//         block = 0;
//         expected = 0;

//         $display("Applying Reset...");
//         reset = 0;
//         #20;
//         reset = 1; 
//         #10;

//         file = $fopen("examples.txt", "r");
//         if (file == 0) $fatal(1, "Open examples.txt failed");

//         while (!$feof(file)) begin

//             scan_result = $fscanf(file, "%h %h\n", block, expected);
            
//             if (scan_result == 2) begin
                
//                 @(negedge clk);
//                 reset = 0;
                
//                 @(negedge clk);
//                 reset = 1;

//                 @(negedge clk);
//                 start = 1;
                
//                 @(negedge clk);
//                 start = 0;

//                 wait(finish);
                
//                 @(posedge clk);

//                 if (digest !== expected) begin
//                     $display("Error at time %0t", $time);
//                     $display("Block:    %h", block);
//                     $display("Got:      %h", digest);
//                     $display("Expected: %h", expected);
//                     $fatal(1, "Hash Mismatch!");
//                 end else begin
//                     $display("Passed block %h...", block[511:480]);
//                 end
//             end
//         end

//         $fclose(file);
//         $display("Passed");
//         $finish;
//     end

// endmodule

`timescale 1ns/1ps
module tb_sha256_pipelined;

    logic         clock;
    logic         reset;
    logic         start;
    logic [511:0] block;
    logic [255:0] digest;
    logic         finish;

    sha256 dut (.*);

    // 100 MHz clock
    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    // Expected results
    logic [255:0] expected_queue [$];
    int           hashes_received = 0;
    int           hashes_matched  = 0;

    initial begin
        reset = 1'b0;
        start = 1'b0;
        block = '0;

        #20;
        reset = 1'b1;
        #10;

        $display("---------------------------------------------------------");
        $display("Starting Pipeline Test: Pushing 3 blocks continuously...");
        $display("---------------------------------------------------------");

        // ---- Drive inputs with a #1 to avoid races ----
        @(posedge clock); #1;
        start = 1'b1;
        block = {32'h80000000, 448'h0, 32'h00000000}; // ""
        expected_queue.push_back(256'he3b0c442_98fc1c14_9afbf4c8_996fb924_27ae41e4_649b934c_a495991b_7852b855);

        @(posedge clock); #1;
        start = 1'b1;
        block = {32'h61800000, 448'h0, 32'h00000008}; // "a"
        expected_queue.push_back(256'hca978112_ca1bbdca_fac231b3_9a23dc4d_a786eff8_147c4e72_b9807785_afee48bb);

        @(posedge clock); #1;
        start = 1'b1;
        block = {32'h61626380, 448'h0, 32'h00000018}; // "abc"
        expected_queue.push_back(256'hba7816bf_8f01cfea_414140de_5dae2223_b00361a3_96177a9c_b410ff61_f20015ad);

        @(posedge clock); #1;
        start = 1'b0;
        block = '0;

        // Wait for pipeline to flush
        repeat (80) @(posedge clock);

        // ---- Final reporting ----
        $display("---------------------------------------------------------");
        if (hashes_matched == 3)
            $display("TEST PASSED: All 3 pipelined hashes matched expected values!");
        else
            $display("TEST FAILED: Expected 3 matches, but got %0d.", hashes_matched);
        $display("---------------------------------------------------------");
        $finish;
    end

    always_ff @(posedge clock) begin
        if (finish) begin
            logic [255:0] expected_digest;
            if (expected_queue.size() > 0) begin
                expected_digest = expected_queue.pop_front();
                hashes_received++;
                if (digest === expected_digest) begin
                    $display("[Time %0t] Hash %0d MATCHED: %h", $time, hashes_received, digest);
                    hashes_matched++;
                end else begin
                    $display("[Time %0t] Hash %0d FAILED!", $time, hashes_received);
                    $display("  Expected: %h", expected_digest);
                    $display("  Got:      %h", digest);
                end
            end else begin
                $display("[Time %0t] ERROR: Unexpected valid output!", $time);
            end
        end
    end

endmodule