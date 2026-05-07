module DE1_SoC (
    ////////// HPS //////////
    inout  wire        HPS_CONV_USB_N,
    output wire [14:0] HPS_DDR3_ADDR,
    output wire [2:0]  HPS_DDR3_BA,
    output wire        HPS_DDR3_CAS_N,
    output wire        HPS_DDR3_CKE,
    output wire        HPS_DDR3_CK_N,
    output wire        HPS_DDR3_CK_P,
    output wire        HPS_DDR3_CS_N,
    output wire [3:0]  HPS_DDR3_DM,
    inout  wire [31:0] HPS_DDR3_DQ,
    inout  wire [3:0]  HPS_DDR3_DQS_N,
    inout  wire [3:0]  HPS_DDR3_DQS_P,
    output wire        HPS_DDR3_ODT,
    output wire        HPS_DDR3_RAS_N,
    output wire        HPS_DDR3_RESET_N,
    input  wire        HPS_DDR3_RZQ,
    output wire        HPS_DDR3_WE_N,
    inout  wire        HPS_ENET_GTX_CLK,
    inout  wire        HPS_ENET_INT_N,
    inout  wire        HPS_ENET_MDC,
    inout  wire        HPS_ENET_MDIO,
    inout  wire        HPS_ENET_RX_CLK,
    inout  wire [3:0]  HPS_ENET_RX_DATA,
    inout  wire        HPS_ENET_RX_DV,
    inout  wire [3:0]  HPS_ENET_TX_DATA,
    inout  wire        HPS_ENET_TX_EN,
    inout  wire        HPS_SD_CLK,
    inout  wire        HPS_SD_CMD,
    inout  wire [3:0]  HPS_SD_DATA,
    inout  wire        HPS_UART_RX,
    inout  wire        HPS_UART_TX,
    inout  wire        HPS_USB_CLKOUT,
    inout  wire [7:0]  HPS_USB_DATA,
    inout  wire        HPS_USB_DIR,
    inout  wire        HPS_USB_NXT,
    inout  wire        HPS_USB_STP,

    ////////// FPGA Pins //////////
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    output wire [9:0]  LEDR
);

    // Internal wires for MPU events (not physically mapped to pins)
    wire hps_mpu_event_o;
    wire hps_mpu_standbywfe;
    wire hps_mpu_standbywfi;

    march23system u0 (
        .clk_clk                         (CLOCK_50),           
        .reset_reset_n                   (KEY[0]),             

        // HPS MPU Events (Internal)
        .hps_0_h2f_mpu_events_eventi     (1'b0),               
        .hps_0_h2f_mpu_events_evento     (hps_mpu_event_o),    
        .hps_0_h2f_mpu_events_standbywfe (hps_mpu_standbywfe), 
        .hps_0_h2f_mpu_events_standbywfi (hps_mpu_standbywfi), 

        // HPS SD Card
        .hps_io_hps_io_sdio_inst_CMD     (HPS_SD_CMD),         
        .hps_io_hps_io_sdio_inst_D0      (HPS_SD_DATA[0]),     
        .hps_io_hps_io_sdio_inst_D1      (HPS_SD_DATA[1]),     
        .hps_io_hps_io_sdio_inst_CLK     (HPS_SD_CLK),         
        .hps_io_hps_io_sdio_inst_D2      (HPS_SD_DATA[2]),     
        .hps_io_hps_io_sdio_inst_D3      (HPS_SD_DATA[3]),     

        // HPS UART (Console)
        .hps_io_hps_io_uart0_inst_RX     (HPS_UART_RX),        
        .hps_io_hps_io_uart0_inst_TX     (HPS_UART_TX),        

        // HPS DDR3 Memory
        .memory_mem_a                    (HPS_DDR3_ADDR),      
        .memory_mem_ba                   (HPS_DDR3_BA),        
        .memory_mem_ck                   (HPS_DDR3_CK_P),      
        .memory_mem_ck_n                 (HPS_DDR3_CK_N),      
        .memory_mem_cke                  (HPS_DDR3_CKE),       
        .memory_mem_cs_n                 (HPS_DDR3_CS_N),      
        .memory_mem_ras_n                (HPS_DDR3_RAS_N),     
        .memory_mem_cas_n                (HPS_DDR3_CAS_N),     
        .memory_mem_we_n                 (HPS_DDR3_WE_N),      
        .memory_mem_reset_n              (HPS_DDR3_RESET_N),   
        .memory_mem_dq                   (HPS_DDR3_DQ),        
        .memory_mem_dqs                  (HPS_DDR3_DQS_P),     
        .memory_mem_dqs_n                (HPS_DDR3_DQS_N),     
        .memory_mem_odt                  (HPS_DDR3_ODT),       
        .memory_mem_dm                   (HPS_DDR3_DM),        
        .memory_oct_rzqin                (HPS_DDR3_RZQ)        
    );

    
endmodule