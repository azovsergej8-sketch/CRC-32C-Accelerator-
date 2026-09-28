module crc32c_engine (
    CRC_arbiter.CRC bus_if
);

  // Комбинационные функции (XOR-деревья) для разных ширин входных данных

  //1. Комбинационная функция расчета CRC-32C для 16-битного слова
  function automatic logic [31:0] calc_crc32c_w16(
    input logic [31:0] current_crc,
    input logic [15:0] data_in
  );
    logic [31:0] next_crc;
    begin
      next_crc[0] = ^(current_crc & 32'h00011F91) ^ ^(data_in & 16'h1F91);
      next_crc[1] = ^(current_crc & 32'h00023F23) ^ ^(data_in & 16'h3F23);
      next_crc[2] = ^(current_crc & 32'h00047E47) ^ ^(data_in & 16'h7E47);
      next_crc[3] = ^(current_crc & 32'h0008FC8E) ^ ^(data_in & 16'hFC8E);
      next_crc[4] = ^(current_crc & 32'h0010E68D) ^ ^(data_in & 16'hE68D);
      next_crc[5] = ^(current_crc & 32'h0020D28B) ^ ^(data_in & 16'hD28B);
      next_crc[6] = ^(current_crc & 32'h0040BA87) ^ ^(data_in & 16'hBA87);
      next_crc[7] = ^(current_crc & 32'h00806A9E) ^ ^(data_in & 16'h6A9E);
      next_crc[8] = ^(current_crc & 32'h0100D53C) ^ ^(data_in & 16'hD53C);
      next_crc[9] = ^(current_crc & 32'h0200B5E8) ^ ^(data_in & 16'hB5E8);
      next_crc[10] = ^(current_crc & 32'h04007440) ^ ^(data_in & 16'h7440);
      next_crc[11] = ^(current_crc & 32'h0800E881) ^ ^(data_in & 16'hE881);
      next_crc[12] = ^(current_crc & 32'h1000CE93) ^ ^(data_in & 16'hCE93);
      next_crc[13] = ^(current_crc & 32'h200082B6) ^ ^(data_in & 16'h82B6);
      next_crc[14] = ^(current_crc & 32'h40001AFC) ^ ^(data_in & 16'h1AFC);
      next_crc[15] = ^(current_crc & 32'h800035F9) ^ ^(data_in & 16'h35F9);
      next_crc[16] = ^(current_crc & 32'h00006BF2) ^ ^(data_in & 16'h6BF2);
      next_crc[17] = ^(current_crc & 32'h0000D7E5) ^ ^(data_in & 16'hD7E5);
      next_crc[18] = ^(current_crc & 32'h0000B05A) ^ ^(data_in & 16'hB05A);
      next_crc[19] = ^(current_crc & 32'h00007F24) ^ ^(data_in & 16'h7F24);
      next_crc[20] = ^(current_crc & 32'h0000FE48) ^ ^(data_in & 16'hFE48);
      next_crc[21] = ^(current_crc & 32'h0000E301) ^ ^(data_in & 16'hE301);
      next_crc[22] = ^(current_crc & 32'h0000D992) ^ ^(data_in & 16'hD992);
      next_crc[23] = ^(current_crc & 32'h0000ACB5) ^ ^(data_in & 16'hACB5);
      next_crc[24] = ^(current_crc & 32'h000046FB) ^ ^(data_in & 16'h46FB);
      next_crc[25] = ^(current_crc & 32'h00008DF7) ^ ^(data_in & 16'h8DF7);
      next_crc[26] = ^(current_crc & 32'h0000047E) ^ ^(data_in & 16'h047E);
      next_crc[27] = ^(current_crc & 32'h000008FC) ^ ^(data_in & 16'h08FC);
      next_crc[28] = ^(current_crc & 32'h000011F9) ^ ^(data_in & 16'h11F9);
      next_crc[29] = ^(current_crc & 32'h000023F2) ^ ^(data_in & 16'h23F2);
      next_crc[30] = ^(current_crc & 32'h000047E4) ^ ^(data_in & 16'h47E4);
      next_crc[31] = ^(current_crc & 32'h00008FC8) ^ ^(data_in & 16'h8FC8);
      return next_crc;
    end
  endfunction

  //2. Комбинационная функция расчета CRC-32C для 8-битного слова
  function automatic logic [31:0] calc_crc32c_w8(
    input logic [31:0] current_crc,
    input logic [7:0] data_in
  );
    logic [31:0] next_crc;
    begin
      next_crc[0] = ^(current_crc & 32'h0000011F) ^ ^(data_in & 8'h1F);
      next_crc[1] = ^(current_crc & 32'h0000023F) ^ ^(data_in & 8'h3F);
      next_crc[2] = ^(current_crc & 32'h0000047E) ^ ^(data_in & 8'h7E);
      next_crc[3] = ^(current_crc & 32'h000008FC) ^ ^(data_in & 8'hFC);
      next_crc[4] = ^(current_crc & 32'h000010E6) ^ ^(data_in & 8'hE6);
      next_crc[5] = ^(current_crc & 32'h000020D2) ^ ^(data_in & 8'hD2);
      next_crc[6] = ^(current_crc & 32'h000040BA) ^ ^(data_in & 8'hBA);
      next_crc[7] = ^(current_crc & 32'h0000806A) ^ ^(data_in & 8'h6A);
      next_crc[8] = ^(current_crc & 32'h000100D5) ^ ^(data_in & 8'hD5);
      next_crc[9] = ^(current_crc & 32'h000200B5) ^ ^(data_in & 8'hB5);
      next_crc[10] = ^(current_crc & 32'h00040074) ^ ^(data_in & 8'h74);
      next_crc[11] = ^(current_crc & 32'h000800E8) ^ ^(data_in & 8'hE8);
      next_crc[12] = ^(current_crc & 32'h001000CE) ^ ^(data_in & 8'hCE);
      next_crc[13] = ^(current_crc & 32'h00200082) ^ ^(data_in & 8'h82);
      next_crc[14] = ^(current_crc & 32'h0040001A) ^ ^(data_in & 8'h1A);
      next_crc[15] = ^(current_crc & 32'h00800035) ^ ^(data_in & 8'h35);
      next_crc[16] = ^(current_crc & 32'h0100006B) ^ ^(data_in & 8'h6B);
      next_crc[17] = ^(current_crc & 32'h020000D7) ^ ^(data_in & 8'hD7);
      next_crc[18] = ^(current_crc & 32'h040000B0) ^ ^(data_in & 8'hB0);
      next_crc[19] = ^(current_crc & 32'h0800007F) ^ ^(data_in & 8'h7F);
      next_crc[20] = ^(current_crc & 32'h100000FE) ^ ^(data_in & 8'hFE);
      next_crc[21] = ^(current_crc & 32'h200000E3) ^ ^(data_in & 8'hE3);
      next_crc[22] = ^(current_crc & 32'h400000D9) ^ ^(data_in & 8'hD9);
      next_crc[23] = ^(current_crc & 32'h800000AC) ^ ^(data_in & 8'hAC);
      next_crc[24] = ^(current_crc & 32'h00000046) ^ ^(data_in & 8'h46);
      next_crc[25] = ^(current_crc & 32'h0000008D) ^ ^(data_in & 8'h8D);
      next_crc[26] = ^(current_crc & 32'h00000004) ^ ^(data_in & 8'h04);
      next_crc[27] = ^(current_crc & 32'h00000008) ^ ^(data_in & 8'h08);
      next_crc[28] = ^(current_crc & 32'h00000011) ^ ^(data_in & 8'h11);
      next_crc[29] = ^(current_crc & 32'h00000023) ^ ^(data_in & 8'h23);
      next_crc[30] = ^(current_crc & 32'h00000047) ^ ^(data_in & 8'h47);
      next_crc[31] = ^(current_crc & 32'h0000008F) ^ ^(data_in & 8'h8F);
      return next_crc;
    end
  endfunction

  
// 1. Тракт управления
logic stg1_valid;
logic stg2_valid, stg2_ready;
logic{32:0} stg1_crc;
logic[31:0] stg1_data;


assign bus_if.CRC_ready = !stg1_valid  || stg2_ready;
assign stg2_ready = !bus_if.data_out_valid || bus_if.arbiter_ready;


// 2. Тракт данных (вычислительные стадии)
always_ff @(posedge clk) begin
    if(!bus_if.stall) begin
      // Стадия 1
      if(bus_if.CRC_ready && bus_if.data_in_valid) begin
        stg1_valid <= 1;
        case(byte_crc)
          2'b00: begin
            stg1_crc[31:0]  <= calc_crc32c_w8(bus_if.crc_in, bus_if.data_in[7:0]);
            stg1_crc[32] <= 1'b0; 
          end
          2'b01: begin
            stg1_crc[31:0]  <= calc_crc32c_w16(bus_if.crc_in, bus_if.data_in[15:0]);
            stg1_crc[32] <= 1'b0; 
          end
          2'b10: begin
            stg1_crc[31:0]  <= calc_crc32c_w16(bus_if.crc_in, bus_if.data_in[15:0]);
            stg1_data <= bus_if.data_in[31:16];
            stg1_crc[32] <= 1'b1;
          end
        endcase
      end else stg1_valid <= 0;
    
      // Стадия 2
      if(stg2_ready && stg1_valid) begin
        bus_if.data_out_valid <= 1;
        case(stg1_crc[32])
          1'b0: begin
            bus_if.crc_out <= stg1_crc[31:0];
          end
          1'b1: begin
            bus_if.crc_out <= calc_crc32c_w16(stg1_crc[31:0], stg1_data);
          end
        endcase
      end else if() begin
        bus_if.data_out_valid <= 0;
      end

    end else begin
      bus_if.crc_out <= stg1_crc;
      case(stg1_crc[32])
      1'b0: begin
        bus_if.crc_out <= stg1_crc[31:0];
      end
      1'b1: begin
        bus_if.crc_out <= calc_crc32c_w16(stg1_crc[31:0], stg1_data);
      end
      endcase
      bus_if_data_out_ready <= 1'b1;
    end
end
endmodule
