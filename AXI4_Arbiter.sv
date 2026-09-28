module arbiter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 8,
    parameter int PC_LNG = 128,
    parameter int CHANNELS = 32,
    parameter int GROUPS_NUM = 8
)(
    AXI4_Full#(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)).arbiter axi4_full,
    CRC_arbiter.arbiter crc_arb,
    APB_Slave.arbiter apb,
    clk_if.slave if_clk,
    bram_if#(.DATA_WIDTH(DATA_WIDTH + WSTRB_BITS + 1), .ADDR_WIDTH(ADDR_WIDTH), .PC_LNG(PC_LNG), .CHANNELS(CHANNELS/GROUPS_NUM)).master if_bram_0, if_bram_1, if_bram_2, if_bram_3, if_bram_4, if_bram_5, if_bram_6, if_bram_7
);
    // Локальные параметры
    localparam int CHAN_BITS = $clog2(CHANNELS);
    localparam int REG_BITS = $clog2(CHANNELS/4);
    localparam int WORD_BITS = $clog2(PC_LNG);
    localparam int ID_BITS = $clog2(ID_WIDTH);
    localparam int WSTRB_BITS = DATA_WIDTH + DATA_WIDTH/8 - 1;
    localparam int WLAST_BIT = DATA_WIDTH + DATA_WIDTH/8;
    localparam int ANSWR_APB_WDTH = ID_BITS + CHAN_BITS;
    localparam int GROUPS_BITS = $clog2(GROUPS_NUM);
    
    //Функция для поиска единицы в регистре активных каналов данных
    function automatic logic[CHANNELS/GROUPS_NUM-1:0] ffs_alg_mask(
        input logic[CHANNELS/GROUPS_NUM-1:0] channels_reg
    );
        logic[CHANNELS/GROUPS_NUM-1:0] single_hot_mask;
        single_hot_mask = channels_reg && (~channels_reg + 1);
        return single_hot_mask;
    endfunction

    //Функция преобразования one-hot в стандартный вид
    function automatic logic[GROUPS_NUM-1:0] one_hot_to_bin(
        input logic[CHANNELS/GROUPS_NUM-1:0] channels_reg
    );
        logic[CHAN_BITS-1:0] bin_idx;
        unique case(1'b1)
            channel_reg[0]: bin_idx = 3'd0;
            channel_reg[1]: bin_idx = 3'd1;
            channel_reg[2]: bin_idx = 3'd2;
            channel_reg[3]: bin_idx = 3'd3;
            channel_reg[4]: bin_idx = 3'd4;
            channel_reg[5]: bin_idx = 3'd5;
            channel_reg[6]: bin_idx = 3'd6;
            channel_reg[7]: bin_idx = 3'd7;
        endcase
        return bin_idx;
    endfunction

    //Функция выдачи по one-hot вектору
    function automatic logic[$clog2(WIDTH)-1:0] read_by_one_hot#(
        parameter int WIDTH = PC_LNG,
        parameter int LNGTH_ONE_HOT = CHANNELS/GROUPS_NUM,
        parameter
    )(
        input logic[LNGTH_ONE_HOT-1:0] one_hot_vector,
        input logic[CHAN_BITS+WORD_BITS-1:0] array[$clog2(PC_LNG)]
    );
        logic[$clog2(WIDTH)-1:0] res;
        result = '0;
        for(int i = 0; i < LNGTH_ONE_HOT; i++) begin
            result |= (array[i] & {WIDTH{one_hot_vector[i]}});
        end
        return result;
    endfunction
    // Соединения
    assign if_bram.clk = if_clk.clk;
    assign if_bram.rst_n = if_clk.rst_n;
    assign crc_arb.clk = if_clk.clk;

    // Буферы для актуальных контрольных сумм, длин и форматов слов пакетов
    logic[WORD_BITS:0] length_buffer[0:CHANNELS-1];
    logic[31:0] actual_crc[0:CHANNELS-1];
    logic[WORD_BITS-1:0] actual_length_buffer[0:CHANNELS-1];
    logic[1:0] actual_data_size[0:CHANNELS-1];
    logic[ID_BITS:0] actual_pkg_id[0:CHANNELS-1];
    logic[WORD_BITS-1:0] read_length_buffer_0[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_1[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_2[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_3[0:CHANNELS/GROUPS_NUM-1];
    logic[WORD_BITS-1:0] read_length_buffer_4[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_5[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_6[0:CHANNELS/GROUPS_NUM-1], read_length_buffer_7[0:CHANNELS/GROUPS_NUM-1];

    // Буфер для хранения контрольных сумм по каналу
    logic[32:0] crc_buffer[0:CHANNELS-1];

    //Буфер ответов для APB-master и указатели для записи и чтения
    logic[ANSWR_APB_WDTH:0] apb_answr_buffer[0:CHANNELS-1];
    logic[CHAN_BITS-1:0] apb_buf_wr_ptr, apb_buf_rd_ptr;
    
    assign apb.PREADY = (apb_buf_wr_ptr != apb_buf_rd_ptr);

    // Ошибка и флаги ошибок
    typedef enum logic[2:0]{SUCCESS = 3'b000, DATA_FULL = 3'b010, LGH_RWR = 3'b001, DT_LG_RWR = 3'b011} err_t;
    err_t error_state;
    logic is_addr_crct;
    logic inval_id_error, inval_lgth_error, invalid_crc_error;

    // Тип данных
    typedef enum logic {CRC, DATA} data_t;
    data_t data_type;
    
    assign data_type = axi4_full.AWADDR[ADDR_WIDTH-1] ? CRC : DATA;

    //Конвеер арбитража
    typedef enum logic { STALL, WORK} state_t;
    state_t state, next_state;

    // 1. Управляющие флаги стадий конвеера
    logic addr_ready, trans_active;
    logic data_ready, data_valid;
    logic read_1_ready, read_1_valid, read_2_ready,  CRC_1_ready, CRC_1_valid;

    //valid-ready для стадий чтения и работы CRC
    assign read_1_ready = !read_1_valid || read_2_ready;
    assign read_2_ready = !crc_arb.data_in_valid || CRC_1_ready;
    assign CRC_1_ready = !CRC_1_valid || crc_arb.CRC_res_ready;

    // 2. Логика смены стадий

    // 2.1. Стадии адреса и записи
    logic length_stat;
    logic[CHAN_BITS-1:0] actv_chn_id;
    logic inactive_trsn;
    logic inactive_bram_wr;


    assign data_ready = axi4_full.WREADY && axi4_full.WVALID;
    assign axi4_full.WREADY = trans_active;
    assign addr_ready = axi4_full.AWREADY && axi4_full.AWVALID;
    assign length_stat = length_buffer[actv_chn_id][WORD_BITS] && (length_buffer[actv_chn_id][WORD_BITS-1:0] != actual_length_buffer[actv_chn_id]);

    //Сброс сигналов транзакции и данных для записи
    assign inactive_trsn = !addr_ready && data_ready && ((data_type == CRC) || length_stat);
    assign inactive_bram_wr = if_bram.write_enable && (!data_ready || (data_type == CRC));

    // 2.2. Стадии чтения и вычисления

    // Маска и индес доступных данных для работы
    logic[CHANNELS/GROUPS_NUM-1:0] ready_channel_idx_hot_0, ready_channel_idx_hot_1, ready_channel_idx_hot_2, ready_channel_idx_hot_3;
    logic[CHANNELS/GROUPS_NUM-1:0] ready_channel_idx_hot_4, ready_channel_idx_hot_5, ready_channel_idx_hot_6, ready_channel_idx_hot_7;
    logic[CHAN_BITS-1:0] ready_channel_idx_0, ready_channel_idx_1, ready_channel_idx_2, ready_channel_idx_3, ready_channel_idx_4, ready_channel_idx_5, ready_channel_idx_6, ready_channel_idx_7;
    logic valid_data_read_1;
    logic valid_data_0_read_1, valid_data_1_read_1, valid_data_2_read_1, valid_data_3_read_1;
    logic valid_data_4_read_1, valid_data_5_read_1, valid_data_6_read_1, valid_data_7_read_1;
    logic[CHANNELS/GROUPS_NUM-1:0] ready_mask_0, ready_mask_1, ready_mask_2, ready_mask_3;
    logic[CHANNELS/GROUPS_NUM-1:0] ready_mask_4, ready_mask_5, ready_mask_6, ready_mask_7;
    logic[GROUPS_NUM-1:0] ready_data_state;
    logic is_avbl_0, is_avbl_1, is_avbl_2, is_avbl_3;
    logic is_avbl_4, is_avbl_5, is_avbl_6, is_avbl_7;
    logic CRC_1_end, CRC_res_end;

    //Флаги наличия каналов для чтения
    assign valid_data_0_read_1 = |ready_mask_0;
    assign valid_data_1_read_1 = |ready_mask_1;
    assign valid_data_2_read_1 = |ready_mask_2;
    assign valid_data_3_read_1 = |ready_mask_3;
    assign valid_data_4_read_1 = |ready_mask_4;
    assign valid_data_5_read_1 = |ready_mask_5;
    assign valid_data_6_read_1 = |ready_mask_6;
    assign valid_data_7_read_1 = |ready_mask_7;
    assign valid_data_read_1 = valid_data_0_read_1 || valid_data_1_read_1 || valid_data_2_read_1 || valid_data_3_read_1 || valid_data_4_read_1 || valid_data_5_read_1 || valid_data_6_read_1 || valid_data_7_read_1;
    assign ready_data_state = {valid_data_7_read_1 && is_avbl_7, valid_data_6_read_1 && is_avbl_6, valid_data_5_read_1 && is_avbl_5, valid_data_4_read_1 && is_avbl_4, valid_data_3_read_1 && is_avbl_3, valid_data_2_read_1 && is_avbl_2, valid_data_1_read_1 && is_avbl_1, valid_data_0_read_1 && is_avbl_0};

    //Индекксы каналов внутри групп
    assign ready_channel_idx_hot_0 = ffs_alg_mask(ready_mask_0);
    assign ready_channel_idx_hot_1 = ffs_alg_mask(ready_mask_1);
    assign ready_channel_idx_hot_2 = ffs_alg_mask(ready_mask_2);
    assign ready_channel_idx_hot_3 = ffs_alg_mask(ready_mask_3);
    assign ready_channel_idx_hot_4 = ffs_alg_mask(ready_mask_4);
    assign ready_channel_idx_hot_5 = ffs_alg_mask(ready_mask_5);
    assign ready_channel_idx_hot_6 = ffs_alg_mask(ready_mask_6);
    assign ready_channel_idx_hot_7 = ffs_alg_mask(ready_mask_7);

    //Бинарная форма
    assign ready_channel_idx_0 = one_hot_to_bin(ready_channel_idx_hot_0);
    assign ready_channel_idx_1 = one_hot_to_bin(ready_channel_idx_hot_1);
    assign ready_channel_idx_2 = one_hot_to_bin(ready_channel_idx_hot_2);
    assign ready_channel_idx_3 = one_hot_to_bin(ready_channel_idx_hot_3);
    assign ready_channel_idx_4 = one_hot_to_bin(ready_channel_idx_hot_4);
    assign ready_channel_idx_5 = one_hot_to_bin(ready_channel_idx_hot_5);
    assign ready_channel_idx_6 = one_hot_to_bin(ready_channel_idx_hot_6);
    assign ready_channel_idx_7 = one_hot_to_bin(ready_channel_idx_hot_7);

    // Флаги наличия активных канлов помимо текущего и сдвиговые регистры для обработки
    logic has_more_channels_0, has_more_channels_1, has_more_channels_2, has_more_channels_3;
    logic has_more_channels_4, has_more_channels_5, has_more_channels_6, has_more_channels_7;
    logic[CHANNELS/GROUPS_NUM-1:0] valid_channel_mask_0, valid_channel_mask_1, valid_channel_mask_2, valid_channel_mask_3;
    logic[CHANNELS/GROUPS_NUM-1:0] valid_channel_mask_4, valid_channel_mask_5, valid_channel_mask_6, valid_channel_mask_7;

    assign has_more_channels_0 = |(ready_mask_0 & (ready_mask_0 - 1'b1));
    assign has_more_channels_1 = |(ready_mask_1 & (ready_mask_1 - 1'b1));
    assign has_more_channels_2 = |(ready_mask_2 & (ready_mask_2 - 1'b1));
    assign has_more_channels_3 = |(ready_mask_3 & (ready_mask_3 - 1'b1));
    assign has_more_channels_4 = |(ready_mask_4 & (ready_mask_4 - 1'b1));
    assign has_more_channels_5 = |(ready_mask_5 & (ready_mask_5 - 1'b1));
    assign has_more_channels_6 = |(ready_mask_6 & (ready_mask_6 - 1'b1));
    assign has_more_channels_7 = |(ready_mask_7 & (ready_mask_7 - 1'b1));

    //Конвеерные регистры актуальных индексов
    logic[CHAN_BITS-1:0] read_idx_2;
    logic[CHAN_BITS-1:0] CRC_idx_1, CRC_idx_res;
    

    // Флаги ошибок в параметрах пакета
    assign error_state[0] = inval_id_error;
    assign error_state[1] = inval_lgth_error;
    assign inval_lgth_error = length_buffer[AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS] && (length_buffer[AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS-1:0] != axi4_full.AWLEN);
    assign inval_id_error = actual_pkg_id[AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][ID_BITS] && (actual_pkg_id[AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS-1:0] != axi4_full.AWID);
    assign is_addr_crct = !actual_pkg_id[AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][ID_BITS] || (!inval_lgth_error && !inval_id_error);

    //3. Логика конвеера
    always_ff@(posedge if_clk.clk or negedge if_clk.rst_n) begin
        if(rst_n) begin
            axi4_full.AWREADY <= 1;
            actv_chn_id <= CHANNELS;
        end else begin
            case(next_state);
                STALL: begin
                end
                WORK: begin
                    // 1. Стадия адреса
                    if(addr_ready) begin
                        if(is_addr_crct) begin
                            if(!length_buffer[axi4_full.AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS]) begin
                                actual_length_buffer[axi4_full.AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]] <= axi4_full.AWLEN;
                                length_buffer[axi4_full.AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS-1:0] <= 0;
                                length_buffer[axi4_full.AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]][WORD_BITS] <= 1;
                                actual_data_size[axi4_full.AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS]] <= axi4_full.AWSIZE;
                            end
                            actv_chn_id <= AWADDR[ADDR_WIDTH-2 : ADDR_WIDTH-1-CHAN_BITS];
                            data_type <= axi4_full.AWADDR[ADDR_WIDTH-1];
                            trans_active <= 1;
                        end else begin
                            axi4_full.BID <= axi4_full.AWID;
                            axi4_full.BRESP <= error_state;
                            axi4_full.BVALID <= 1;
                        end
                    end else if(axi4_full.BVALID && axi4_full.BREADY) axi4_full.BVALID <= 0;

                    // 2. Стадия записи данных
                    if(data_ready) begin
                        case(data_type):
                            DATA: begin
                                if_bram.addr_in[CHAN_BITS-1:0] <= actv_chn_id;
                                if_bram.addr_in[CHAN_BITS + WORD_BITS - 1 : CHAN_BITS] <= actual_length_buffer[actv_chn_id];
                                actual_length_buffer[actv_chn_id] <= actual_length_buffer[actv_chn_id] + 1;
                                unique case(actv_chn_id[4:2])
                                    3'b000: begin
                                        if_bram_0.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_0.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_0.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_0.write_enable <= 1;
                                    end
                                    3'b001: begin
                                        if_bram_1.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_1.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_1.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_1.write_enable <= 1;
                                    end
                                    3'b010: begin
                                        if_bram_2.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_2.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_2.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_2.write_enable <= 1;
                                    end
                                    3'b011: begin
                                        if_bram_3.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_3.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_3.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_3.write_enable <= 1;
                                    end
                                    3'b100: begin
                                        if_bram_4.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_4.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_4.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_4.write_enable <= 1;
                                    end
                                    3'b101: begin
                                        if_bram_5.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_5.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_5.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_5.write_enable <= 1;
                                    end
                                    3'b110: begin
                                        if_bram_6.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_6.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_6.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_6.write_enable <= 1;
                                    end
                                    3'b111: begin
                                        if_bram_7.data_in[DATA_WIDTH-1:0] <= axi4_full.WDATA;
                                        if_bram_7.data_in[WSTRB_BITS : DATA_WIDTH] <= axi4_full.WSTRB;
                                        if_bram_7.data_in[WLAST_BIT] <= axi4_full.WLAST;
                                        if_bram_7.write_enable <= 1;
                                    end
                                endcase
                                unique case(actv_chn_id[4:2])
                                    3'b000: if(!ready_mask_0[actv_chn_id[2:0]] && !valid_channel_mask_0[actv_chn_id[2:0]]) ready_mask_0[actv_chn_id[1:0]] <= 1;
                                    3'b001: if(!ready_mask_1[actv_chn_id[2:0]] && !valid_channel_mask_1[actv_chn_id[2:0]]) ready_mask_1[actv_chn_id[1:0]] <= 1;
                                    3'b010: if(!ready_mask_2[actv_chn_id[2:0]] && !valid_channel_mask_2[actv_chn_id[2:0]]) ready_mask_2[actv_chn_id[1:0]] <= 1;
                                    3'b011: if(!ready_mask_3[actv_chn_id[2:0]] && !valid_channel_mask_3[actv_chn_id[2:0]]) ready_mask_3[actv_chn_id[1:0]] <= 1;
                                    3'b100: if(!ready_mask_4[actv_chn_id[2:0]] && !valid_channel_mask_4[actv_chn_id[2:0]]) ready_mask_4[actv_chn_id[1:0]] <= 1;
                                    3'b101: if(!ready_mask_5[actv_chn_id[2:0]] && !valid_channel_mask_6[actv_chn_id[2:0]]) ready_mask_5[actv_chn_id[1:0]] <= 1;
                                    3'b110: if(!ready_mask_6[actv_chn_id[2:0]] && !valid_channel_mask_7[actv_chn_id[2:0]]) ready_mask_6[actv_chn_id[1:0]] <= 1;
                                    3'b111: if(!ready_mask_7[actv_chn_id[2:0]] && !valid_channel_mask_8[actv_chn_id[2:0]]) ready_mask_7[actv_chn_id[1:0]] <= 1;
                                endcase
                            end
                            CRC: begin
                                crc_buffer[actv_chn_id][31:0] <= axi4_full.WDATA;
                                crc_buffer[actv_chn_id][32] <= 1;
                            end
                        endcase
                    end

                    //Сброс сигнала готовности данных для записи
                    if(inactive_bram_wr) if_bram.write_enable <= 0;

                    //Сброс флага наличия активной транзакции
                    if(inactive_trsn) begin
                        trans_active <= 0;
                    end

                    // 3. Стадия чтения данных 1
                    if(read_1_ready && valid_data_read_1) begin
                        unique case(ready_data_state):
                            8'b????_???1: begin
                                if_bram_0.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_0;
                                if_bram_0.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_0, read_length_buffer_0);
                                read_idx_2 <= ready_channel_idx_0;
                                is_avbl_0 <= 0;
                            end
                            8'b????_??10: begin
                                if_bram_1.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_1;
                                if_bram_1.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_1, read_length_buffer_1);
                                read_idx_2 <= ready_channel_idx_1;
                                is_avbl_1 <= 0;
                            end
                            8'b????_?100: begin
                                if_bram_2.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_2;
                                if_bram_2.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_2, read_length_buffer_2);
                                read_idx_2 <= ready_channel_idx_2;
                                is_avbl_2 <= 0;
                            end
                            8'b????_1000: begin
                                if_bram_3.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_3;
                                if_bram_3.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_3, read_length_buffer_3);
                                read_idx_2 <= ready_channel_idx_3;
                                is_avbl_3 <= 0;
                            end
                            8'b???1_0000: begin
                                if_bram_4.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_4;
                                if_bram_4.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_4, read_length_buffer_4);
                                read_idx_2 <= ready_channel_idx_4;
                                is_avbl_4 <= 0;
                            end
                            8'b??10_0000: begin
                                if_bram_5.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_5;
                                if_bram_5.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_5, read_length_buffer_5);
                                read_idx_2 <= ready_channel_idx_5;
                                is_avbl_5 <= 0;
                            end
                            8'b?100_0000: begin
                                if_bram_6.addr_out[CHAN_BITS-1:0] <= ready_channel_idx_6;
                                if_bram_6.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_6, read_length_buffer_6);
                                read_idx_2 <= ready_channel_idx_6;
                                is_avbl_6 <= 0;
                            end
                            8'b1000_0000: begin
                                if_bram_7.addr_out[CHAN_BITS-1:0] <= ready_channel_idxt_7;
                                if_bram_7.addr_out[CHAN_BITS+WORD_BITS-1 : CHAN_BITS] <= read_by_one_hot(ready_channel_idx_hot_7, read_length_buffer_7);
                                read_idx_2 <= ready_channel_idx_7;
                                is_avbl_7 <= 0;
                            end
                        endcase
                        read_1_valid <= 1;
                    end else read_1_valid <= 0;

                    // Изменений состояния регистра активных каналов
                    unique case(1'b1)
                        is_avbl_0: begin
                            is_avbl_0 <= 1;
                            CRC_idx_1 <= read_idx_2;
                            if(read_length_buffer_0[read_idx_2] + 1 == actual_length_buffer[read_idx_2]) ready_mask_0[read_idx_2] <= 0;
                            else if(has_more_channels_0) begin
                                valid_channel_mask_0[read_idx_2] <= 1;
                                ready_mask_0[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_0) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_0[i]) begin
                                        ready_mask_0[i] <= 1;
                                        valid_channel_mask_0[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_0[read_idx_2] <= read_length_buffer_0[read_idx_2] + 1;
                        end
                        is_avbl_1: begin
                            is_avbl_1 <= 1;
                            CRC_idx_1 <= read_idx_2 + 4;
                            if(read_length_buffer_1[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 4]) ready_mask_1[read_idx_2] <= 0;
                            else if(has_more_channels_1) begin
                                valid_channel_mask_1[read_idx_2] <= 1;
                                ready_mask_1[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_1) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_1[i]) begin
                                        ready_mask_1[i] <= 1;
                                        valid_channel_mask_1[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_1[read_idx_2] <= read_length_buffer_1[read_idx_2] + 1;
                        end
                        is_avbl_2: begin
                            is_avbl_2 <= 1;
                            CRC_idx_1 <= read_idx_2 + 8;
                            if(read_length_buffer_2[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 8]) ready_mask_2[read_idx_2] <= 0;
                            else if(has_more_channels_2) begin
                                valid_channel_mask_2[read_idx_2] <= 1;
                                ready_mask_2[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_2) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_2[i])begin 
                                        ready_mask_2[i] <= 1;
                                        valid_channel_mask_2[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_2[read_idx_2] <= read_length_buffer_2[read_idx_2] + 1;
                        end
                        is_avbl_3: begin
                            is_avbl_3 <= 1;
                            CRC_idx_1 <= read_idx_2 + 12;
                            if(read_length_buffer_3[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 12]) ready_mask_3[read_idx_2] <= 0;
                            else if(has_more_channels_3) begin
                                valid_channel_mask_3[read_idx_2] <= 1;
                                ready_mask_3[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_3) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_3[i])begin 
                                        ready_mask_3[i] <= 1;
                                        valid_channel_mask_3[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_3[read_idx_2] <= read_length_buffer_3[read_idx_2] + 1;
                        end
                        is_avbl_4: begin
                            is_avbl_4 <= 1;
                            CRC_idx_1 <= read_idx_2 + 16;
                            if(read_length_buffer_4[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 16]) ready_mask_4[read_idx_2] <= 0;
                            else if(has_more_channels_4) begin
                                valid_channel_mask_4[read_idx_2] <= 1;
                                ready_mask_4[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_4) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_4[i])begin 
                                        ready_mask_4[i] <= 1;
                                        valid_channel_mask_4[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_4[read_idx_2] <= read_length_buffer_4[read_idx_2] + 1;
                        end
                        is_avbl_5: begin
                            is_avbl_5 <= 1;
                            CRC_idx_1 <= read_idx_2 + 20;
                            if(read_length_buffer_5[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 20]) ready_mask_5[read_idx_2] <= 0;
                            else if(has_more_channels_5) begin
                                valid_channel_mask_5[read_idx_2] <= 1;
                                ready_mask_5[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_5) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_5[i])begin 
                                        ready_mask_5[i] <= 1;
                                        valid_channel_mask_5[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_5[read_idx_2] <= read_length_buffer_5[read_idx_2] + 1;
                        end
                        is_avbl_6: begin
                            is_avbl_6 <= 1;
                            CRC_idx_1 <= read_idx_2 + 24;
                            if(read_length_buffer_6[read_idx_2] + 1 == actual_length_buffer[read_idx_2 + 24]) ready_mask_6[read_idx_2] <= 0;
                            else if(has_more_channels_6) begin
                                valid_channel_mask_6[read_idx_2] <= 1;
                                ready_mask_6[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_6) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_6[i])begin 
                                        ready_mask_3[i] <= 1;
                                        valid_channel_mask_6[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_6[read_idx_2] <= read_length_buffer_6[read_idx_2] + 1;
                        end
                        is_avbl_7: begin
                            is_avbl_7 <= 1;
                            CRC_idx_1 <= read_idx_2 + 28;
                            if(read_length_buffer_7[read_idx_2] + 1 == actual_length_buffer[read_idx_2]) ready_mask_7[read_idx_2] <= 0;
                            else if(has_more_channels_7) begin
                                valid_channel_mask_7[read_idx_2] <= 1;
                                ready_mask_7[read_idx_2] <= 0;
                            end
                            if(!has_more_channels_7) begin
                                for(int i = 0; i < CHANNELS/GROUPS_NUM; i++) begin
                                    if(valid_channel_mask_7[i])begin 
                                        ready_mask_7[i] <= 1;
                                        valid_channel_mask_7[i] <= 0;
                                    end
                                end
                            end
                            read_length_buffer_7[read_idx_2] <= read_length_buffer_7[read_idx_2] + 1;
                        end
                    endcase

                    // 4. Стадия чтения данных 2
                    if(read_2_ready && read_1_valid) begin
                        CRC_1_ready <= read_2_ready;
                        crc_arb.data_in_valid <= 1;
                        if(CRC_idx_res == read_idx_2) crc_arb.crc_in <= crc_arb.crc_out;
                        else crc_arb.crc_in <= actual_crc[read_idx_2];
                        crc_arb.data_in <= if_bram.data_out[DATA_WIDTH-1:0];
                        crc_arb.byte_crc <= if_bram.data_out[WSTRB_BITS : DATA_WIDTH];
                        CRC_1_end <= if_bram.data_out[WLAST_BIT];
                    end else crc_arb.data_in_valid <= 0;

                    // 5. Стадия CRC 1
                    if(CRC_1_ready && crc_arb.data_in_valid) begin
                        CRC_res_end <= CRC_1_end
                        CRC_idx_res <= CRC_idx_1;
                        CRC_1_valid <= 1;
                    end else CRC_1_valid <= 0;
                    // 6. Стадия CRC_res
                    if(crc_arb.CRC_res_ready && CRC_1_valid) begin
                        if(CRC_res_end) begin
                            actual_pkg_id[CRC_idx_res][ID_BITS] <= 0;
                            length_buffer[CRC_idx_res][WORD_BITS] <= 0;
                            crc_buffer[CRC_idx_res][32] <= 0;
                            apb_answr_buffer[apb_buf_wr_ptr][ANSWR_APB_WDTH] <= (crc_arb.crc_out == crc_buffer[CRC_idx_res]);
                            apb_answr_buffer[apb_buf_wr_ptr][ANSWR_APB_WDTH-1: ANSWR_APB_WDTH-ID_BITS] <= actual_pkg_id[ID_BITS-1:0];
                            apb_answr_buffer[apb_buf_wr_ptr][ANSWR_APB_WDTH-ID_BITS-1:0] <= CRC_idx_res;
                            apb_buf_wr_ptr <= apb_buf_wr_ptr + 1;
                            actual_crc[CRC_idx_res] <= '1;
                        end else begin
                            actual_crc[CRC_idx_res] <= crc_arb.crc_out;
                        end
                    end

                    //Отправка данных
                    if(apb.PREADY) begin
                        apb.PRDATA <= apb_answr_buffer[apb_buf_rd_ptr];
                        apb_buf_rd_ptr <= apb_buf_rd_ptr + 1;
                    end
                end
            endcase
        end
    end
endmodule