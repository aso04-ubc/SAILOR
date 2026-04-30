`timescale 1ns/1ps

module tb_sha256;

    logic clk = 0;
    logic reset;
    logic start;
    logic [511:0] block;
    logic [255:0] digest;
    logic finish;
    logic [255:0] expected;

    always #5 clk = ~clk;

    sha256 dut (
        .clock(clk),
        .reset(reset),
        .start(start),
        .block(block),
        .digest(digest),
        .finish(finish)
    );

    integer file;
    integer scan_result;

    initial begin
        #1000000;
        $display("Error: Simulation timed out");
        $finish;
    end

    initial begin

        $dumpfile("wave.vcd");
        $dumpvars(0, tb_sha256);

        start = 0;
        block = 0;
        expected = 0;

        $display("Applying Reset...");
        reset = 0;
        #20;
        reset = 1; 
        #10;

        file = $fopen("examples.txt", "r");
        if (file == 0) $fatal(1, "Open examples.txt failed");

        while (!$feof(file)) begin

            scan_result = $fscanf(file, "%h %h\n", block, expected);
            
            if (scan_result == 2) begin
                
                @(negedge clk);
                reset = 0;
                
                @(negedge clk);
                reset = 1;

                @(negedge clk);
                start = 1;
                
                @(negedge clk);
                start = 0;

                wait(finish);
                
                @(posedge clk);

                if (digest !== expected) begin
                    $display("Error at time %0t", $time);
                    $display("Block:    %h", block);
                    $display("Got:      %h", digest);
                    $display("Expected: %h", expected);
                    $fatal(1, "Hash Mismatch!");
                end else begin
                    $display("Passed block %h...", block[511:480]);
                end
            end
        end

        $fclose(file);
        $display("Passed");
        $finish;
    end

endmodule