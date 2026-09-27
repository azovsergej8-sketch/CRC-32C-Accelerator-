module arbiter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int PC_LNG = 128,
    parameter int CHANNELS = 32
)(
    AXI4_Full#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)).arbiter axi4_full,
    CRC_arbiter.arbiter crc_arb,
    APB_Slave.arbiter apb,
    clk_if.slave if_clk,
    bram_if.master(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .PC_LNG(PC_LNG), .CHANNELS(CHANNELS)) if_bram
);
    //Локальные параметры
    localparam int CHAN_BITS = $clog2(CHANNELS); 
    localparam int WORD_BITS = $clog2(PC_LNG);

    //Соединения
    assign if_clk.clk = if_bram.clk;
    assign if_clk.rst_n = if_bram.rst_n;

    //Буфер для актуальных контрольных сумм и длин пакетов
    logic[31:0] crc_buffer[0:CHANNELS-1];
    logic[PC_LNG-1:0] length_buffer[0:CHANNELS-1];

    typedef enum logic {CRC, DATA} data_t;
    data_t data_type;
    
    
    assign data_type = 
    assign crc_arb. axi4_full.AWSIZE;
endmodule