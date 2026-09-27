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

    //Память BRAM, организованная как массив каналов, каждый из которых содержит 128 слов по 32 бита
    logic [DATA_WIDTH-1:0] mem [CHANNELS-1:0][PC_LNG-1:0];
    
    logic [CHAN_BITS-1:0] wr_chan_id;
    logic [WORD_BITS-1:0] wr_word_idx;

    logic [CHAN_BITS-1:0] rd_chan_id;
    logic [WORD_BITS-1:0] rd_word_idx;

    assign wr_chan_id  = if_bram.addr_in[CHAN_BITS-1:0];
    assign wr_word_idx = if_bram.addr_in[CHAN_BITS+WORD_BITS-1 : CHAN_BITS];

    assign rd_chan_id  = if_bram.addr_out[CHAN_BITS-1:0];
    assign rd_word_idx = if_bram.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS];


    //3. Автомат Записи
    typedef enum logic { WRITE_1, WRITE_2 } write_state_t;
    write_state_t write_state;

    logic [CHAN_BITS-1:0]  wr_chan_reg;
    logic [WORD_BITS-1:0]  wr_word_reg;
    logic [DATA_WIDTH-1:0] wr_data_reg;

    always_ff @(posedge if_bram.clk or negedge if_bram.rst_n) begin
        if (!if_bram.rst_n) begin
            write_state <= WRITE_1;
            wr_chan_reg <= '0;
            wr_word_reg <= '0;
            wr_data_reg <= '0;
        end else begin
            case (write_state)
                WRITE_1: begin
                    if (if_bram.write_enable) begin
                        wr_chan_reg <= wr_chan_id;
                        wr_word_reg <= wr_word_idx;
                        wr_data_reg <= if_bram.data_in;
                        write_state <= WRITE_2;
                    end
                end
                WRITE_2: begin
                    mem[wr_chan_reg][wr_word_reg] <= wr_data_reg;

                    if (if_bram.write_enable) begin
                        wr_chan_reg <= wr_chan_id;
                        wr_word_reg <= wr_word_idx;
                        wr_data_reg <= if_bram.data_in;
                        write_state <= WRITE_2; 
                    end else begin
                        write_state <= WRITE_1;
                    end
                end
            endcase
        end
    end

    //4. Автомат Чтения
    typedef enum logic { READ_1, READ_2 } read_state_t;
    read_state_t read_state;

    logic [DATA_WIDTH-1:0] ram_pipe_reg; 
    logic [DATA_WIDTH-1:0] out_data_reg; 
    logic read_valid_reg;

    always_ff @(posedge if_bram.clk or negedge if_bram.rst_n) begin
        if (!if_bram.rst_n) begin
            read_state <= READ_1;
            ram_pipe_reg <= '0;
            out_data_reg <= '0;
            read_valid_reg <= 1'b0;
        end else begin
            case (read_state)
                READ_1: begin
                    if (!read_valid_reg || if_bram.read_ready) begin
                        ram_pipe_reg <= mem[rd_chan_id][rd_word_idx];
                        read_valid_reg <= 1'b0;
                        read_state <= READ_2;
                    end
                end

                READ_2: begin
                    out_data_reg <= ram_pipe_reg; 
                    read_valid_reg <= 1'b1;         
                    if (if_bram.read_ready) begin
                        ram_pipe_reg <= mem[rd_chan_id][rd_word_idx];
                        read_state <= READ_2;
                    end else begin
                        read_state <= READ_1;
                    end
                end
            endcase
        end
    end

    assign if_bram.data_out   = out_data_reg;
    assign if_bram.read_valid = read_valid_reg;
endmodule