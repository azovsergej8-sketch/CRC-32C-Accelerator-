//CRC_arbiter
interface CRC_arbiter;
    //Сигналы
    logic [31:0] data_in;
    logic [31:0] crc_out;
    logic [31:0] crc_in;
    logic data_in_valid;
    logic CRC_ready;
    logic arbiter_ready;
    logic clk;
    logic data_out_valid;
    logic stall;
    logic[1:0] byte_crc;
    
    //Модпорты для вычислительного ядра и арбитра
    //2. Ядро CRC
    modport CRC (
        input data_in, crc_in, valid, clk, byte_crc, stall,
        output crc_out, data_out_ready, bus_if.CRC_ready
    );
    //1. Арбитр
    modport arbiter (
        input crc_out, data_out_ready, bus_if.CRC_ready,
        output data_in, crc_in, valid, byte_crc, clk, stall
    );
endinterface

//Шина для связи с управляющим модулем
interface APB_Slave;
    logic[31:0] PADDR;
    logic[31:0] PWDATA;
    logic[31:0] PRDATA;
    logic PSEL;
    logic PENABLE;
    logic PWRITE;
    logic PREADY;
    logic PSLVERR;
    logic core_stall;

    //Модпорты для ядра и арбитра
    //1. Арбитр
    modport arbiter (
        input PADDR, PWDATA, PSEL, PENABLE, PWRITE,
        output PRDATA, PREADY, PSLVERR, core_stall
    );
    //2. Ядро
    modport arbiter (
        input PRDATA, PREADY, PSLVERR, core_stall,
        output PADDR, PWDATA, PSEL, PENABLE, PWRITE
    );
endinterface

//Шина для связи с каналами данных
interface AXI4_Full #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int CHANNELS = 32
);
    localparam int CHAN_BITS = $clog2(CHANNELS); 
    // 1. Write Address Channel
    logic [CHAN_BITS-1:0]   AWID;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic [7:0]            AWLEN;
    logic [2:0]            AWSIZE;
    logic [1:0]            AWBURST;
    logic                  AWVALID;
    logic                  AWREADY;

    // 2. Write Data Channel
    logic [DATA_WIDTH-1:0]   WDATA;
    logic [(DATA_WIDTH/8)-1:0] WSTRB;
    logic                    WLAST;
    logic                    WVALID;
    logic                    WREADY;

    // 3. Write Response Channel
    logic [ID_WIDTH-1:0]   BID;
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;

    // Модпорт для Арбитра
    modport arbiter (
        input  AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
        output AWREADY,
        input  WDATA, WSTRB, WLAST, WVALID,
        output WREADY,
        output BID, BRESP, BVALID,
        input  BREADY
    );

    // Модпорт для Внешнего Источника
    modport master (
        output AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID,
        input  AWREADY,
        output WDATA, WSTRB, WLAST, WVALID,
        input  WREADY,
        input  BID, BRESP, BVALID,
        output BREADY
    );
endinterface

interface clk_if(
    logic clk;
    logic rst_n
);
    modport clk_core (
        output clk, rst_n
    );
    modport slave (
        input clk, rst_n
    );
endinterface

interface bram_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int PC_LNG = 128,
    parameter int CHANNELS = 32
);
    logic [DATA_WIDTH-1:0] data_in;
    logic [DATA_WIDTH-1:0] data_out;
    logic [ADDR_WIDTH-1:0] addr_in;
    logic [ADDR_WIDTH-1:0] addr_out;
    logic write_enable;
    logic clk;
    logic rst_n;
    modport master (
        input data_out,
        output data_in, addr_in, addr_out, write_enable, clk, rst_n
    );
    modport slave (
        input data_in, addr_in, write_enable, addr_out, clk, rst_n,
        output data_out
    );
endinterface