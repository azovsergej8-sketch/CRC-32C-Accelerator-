# CRC-32C (Castagnoli) - отраженное представление полинома
POLY = 0x82F63B78
import os

desktop = os.path.join(os.path.expanduser("~"), "Desktop")
target_folder = os.path.join(desktop, "CRC-32C Controller")

os.makedirs(target_folder, exist_ok=True)

def step_lfsr(reg: int, data_bit: int) -> int:
    fb = (reg ^ data_bit) & 1
    reg >>= 1
    if fb:
        reg ^= POLY
    return reg & 0xFFFFFFFF

def generate_matrices(data_bits_count: int = 32):
    # 1. Расчет Массива A
    matrix_A = []
    for j in range(32):
        r_init = 1 << j
        r_curr = r_init
        
        for _ in range(data_bits_count):
            r_curr = step_lfsr(r_curr, 0)
        matrix_A.append(r_curr)

    # 2. Расчет Массива B 
    matrix_B = []
    for k in range(data_bits_count):
        r_curr = 0
        
        for bit_idx in range(data_bits_count):
            in_bit = 1 if bit_idx == k else 0
            r_curr = step_lfsr(r_curr, in_bit)
        matrix_B.append(r_curr)

   
    
    rows_A = [0] * 32
    rows_B = [0] * 32

    for i in range(32):
        for j in range(32):
            if (matrix_A[j] >> i) & 1:
                rows_A[i] |= (1 << j)
        for k in range(data_bits_count):
            if (matrix_B[k] >> i) & 1:
                rows_B[i] |= (1 << k)

    return rows_A, rows_B

def generate_sv_function(width: int) -> str:
    rows_A, rows_B = generate_matrices(width)
    hex_digits_B = width // 4  # Определяем ширину hex-маски для входных данных (32->8, 16->4, 8->2)

    lines = []
    lines.append(f"  // Комбинационная функция расчета CRC-32C для {width}-битного слова")
    lines.append(f"  function automatic logic [31:0] calc_crc32c_w{width}(")
    lines.append(f"    input logic [31:0] current_crc,")
    lines.append(f"    input logic [{width-1}:0] data_in")
    lines.append(f"  );")
    lines.append(f"    logic [31:0] next_crc;")
    lines.append(f"    begin")


    for i in range(32):
        mask_a = f"32'h{rows_A[i]:08X}"
        mask_b = f"{width}'h{rows_B[i]:0{hex_digits_B}X}"
        lines.append(f"      next_crc[{i:2d}] = ^(current_crc & {mask_a}) ^ ^(data_in & {mask_b});")

    lines.append(f"      return next_crc;")
    lines.append(f"    end")
    lines.append(f"  endfunction\n")

    return "\n".join(lines)

def generate_sv_module() -> str:
    """Генерирует законченный RTL модуль с подлючением интерфейса CRC_arbiter."""
    
    func_32 = generate_sv_function(32)
    func_16 = generate_sv_function(16)
    func_8  = generate_sv_function(8)

    
    module_code = f"""// ============================================================================


module crc32c_engine (
    CRC_arbiter.CRC bus_if
);

  // --------------------------------------------------------------------------
  // Комбинационные функции (XOR-деревья) для разных ширин входных данных
  // --------------------------------------------------------------------------
{func_32}
{func_16}
{func_8}
  // --------------------------------------------------------------------------
  // Последовательная логика (Sequential Logic)
  // --------------------------------------------------------------------------
  always_ff @(posedge bus_if.clk or negedge bus_if.rst_n) begin
    if (!bus_if.rst_n) begin
      bus_if.crc_out <= 32'hFFFFFFFF; // Инициализация стандартным сообщением
      bus_if.ready   <= 1'b1;
    end else if (bus_if.init) begin
      bus_if.crc_out <= 32'hFFFFFFFF;
      bus_if.ready   <= 1'b1;
    end else if (bus_if.valid && bus_if.ready) begin
      // Выбор нужной функции вычисления в зависимости от строба шины
      case (bus_if.byte_enable)
        2'b11:   bus_if.crc_out <= calc_crc32c_w32(bus_if.crc_out, bus_if.data_in[31:0]);
        2'b01:   bus_if.crc_out <= calc_crc32c_w16(bus_if.crc_out, bus_if.data_in[15:0]);
        2'b00:   bus_if.crc_out <= calc_crc32c_w8 (bus_if.crc_out, bus_if.data_in[7:0]);
        default: bus_if.crc_out <= calc_crc32c_w32(bus_if.crc_out, bus_if.data_in[31:0]);
      endcase
    end
  end

endmodule
"""
    return module_code

if __name__ == "__main__":
    print("[Python] Расчет матриц и генерация RTL модуля...")
    sv_content = generate_sv_module()

    
    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    target_folder = os.path.join(desktop, "CRC-32C Controller")
    os.makedirs(target_folder, exist_ok=True)

    file_path = os.path.join(target_folder, "crc32c_engine.sv")

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(sv_content)

    print(f"[Python] Готово! Код успешно сохранен в файл: {file_path}")