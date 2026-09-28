module BRAM #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int PC_LNG = 128,
    parameter int CHANNELS = 32
)(
    bram_if.slave(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) if_bram
);
    localparam int CHAN_BITS = $clog2(CHANNELS); 
    localparam int WORD_BITS = $clog2(PC_LNG);   
    localparam int W_DATA_WIDTH = DATA_WIDTH + DATA_WIDTH/8 + 1;
    //Память BRAM, организованная как массив каналов, каждый из которых содержит 128 слов по 32 бита
    logic [W_DATA_WIDTH-1:0] mem [CHANNELS-1:0][PC_LNG-1:0];
    
    logic [CHAN_BITS-1:0] wr_chan_id;
    logic [WORD_BITS-1:0] wr_word_idx;

    logic [CHAN_BITS-1:0] rd_chan_id;
    logic [WORD_BITS-1:0] rd_word_idx;

    logic[W_DATA_WIDTH-1:0] data_out_reg;
    assign wr_chan_id  = if_bram.addr_in[CHAN_BITS-1:0];
    assign wr_word_idx = if_bram.addr_in[CHAN_BITS+WORD_BITS-1 : CHAN_BITS];

    assign rd_chan_id  = if_bram.addr_out[CHAN_BITS-1:0];
    assign rd_word_idx = if_bram.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS];


    //3. Автомат Записи
    always_ff @(posedge if_bram.clk or negedge if_bram.rst_n) begin
        if (!if_bram.rst_n) begin
        end else begin
            if (if_bram.write_enable) begin
                mem[wr_chan_id][wr_word_idx] <= if_bram.data_in;
            end
        end
    end
 
    //4. Автомат Чтения
    always_ff @(posedge if_bram.clk or negedge if_bram.rst_n) begin
        if (!if_bram.rst_n) begin
        end else begin
            if_bram.data_out <= mem[rd_chan_id][rd_word_idx];
        end
    end

endmodule