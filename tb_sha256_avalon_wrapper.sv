`timescale 1ns/1ps

module tb_sha256_avalon_wrapper();

    // Signals
    logic        clk;
    logic        reset_n;
    logic [4:0]  avs_address;
    logic        avs_write;
    logic [31:0] avs_writedata;
    logic        avs_read;
    logic [31:0] avs_readdata;

    // Instantiate the Wrapper
    sha256_avalon_wrapper dut (
        .clk(clk),
        .reset_n(reset_n),
        .avs_address(avs_address),
        .avs_write(avs_write),
        .avs_writedata(avs_writedata),
        .avs_read(avs_read),
        .avs_readdata(avs_readdata)
    );

    // 50MHz Clock Generation
    initial clk = 0;
    always #10 clk = ~clk;

    // Helper Task: Avalon Write
    task avalon_write(input [4:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            avs_address = addr;
            avs_write = 1;
            avs_writedata = data;
            @(posedge clk);
            avs_write = 0;
        end
    endtask
        
    task avalon_read(input [4:0] addr, output [31:0] read_val);
        begin
            @(posedge clk);
            avs_address = addr;
            avs_read = 1;
            @(posedge clk); 
            #1; 
            
            // Capture the data BEFORE turning off avs_read
            read_val = avs_readdata; 
            $display("Read Address %0d: 0x%h", addr, read_val);
            
            avs_read = 0;
        end
    endtask


    logic [31:0] polled_data;
    // Main Test Sequence
    initial begin
        // 1. Initialization
        reset_n = 0;
        avs_write = 0;
        avs_read = 0;
        avs_address = 0;
        avs_writedata = 0;

        #50;
        reset_n = 1;
        #20;

        $display("--- Starting Empty String Test ---");

        // 2. Write Padded Input (Empty String)
        // Reg 0: 0x80000000
        avalon_write(5'd0, 32'h80000000);
        
        // Regs 1-14: 0x0
        for (int i=1; i<15; i++) begin
            avalon_write(i[4:0], 32'h0);
        end
        
        // Reg 15: Length 0
        avalon_write(5'd15, 32'h0);

        // 3. Trigger Start (Reg 24)
        $display("Triggering Start...");
        avalon_write(5'd24, 32'h1);

        // 4. Poll Sticky Finish (Reg 24)
        // We simulate polling by reading until bit 0 is high
        do begin
            avalon_read(5'd24, polled_data); // Pass the variable into the task
            #40; 
        end while ((polled_data & 32'h00000001) == 32'h00000000);
        // Loop as long as Bit 0 is ZERO

        $display("Core Finished! Reading Results...");

        // 5. Read Result Registers (Reg 16-23)
        for (int i=16; i<=23; i++) begin
            avalon_read(i[4:0], polled_data); // Use polled_data here too
        end

        #100;
        $finish;
    end

endmodule