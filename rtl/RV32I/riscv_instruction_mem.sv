module riscv_instruction_mem
#(parameter MEM_Depth = 4096,
  parameter MEM_Width = 32)(
  input [31:0]PC,
  output reg [31:0]inst);

  reg [MEM_Width-1:0]mem[MEM_Depth-1:0];
 
  initial begin
    // Point this path to the .hex file you just generated
    for (int i = 0; i < MEM_Depth; i++) mem[i] = 32'h0;

    $readmemh("sw/build/firmware.hex", mem);
    if (mem[0] == 32'h0) begin
      $readmemh("../../sw/build/firmware.hex", mem);
    end
  end

  always @(*) begin
    if (PC[1] == 1'b1) begin
      inst = {mem[((PC >> 2) + 1) < MEM_Depth ? ((PC >> 2) + 1) : 0][15:0], mem[PC >> 2][31:16]};
    end else begin
      inst = mem[PC >> 2];
    end
  end

endmodule         // no condition on reading form mem and its async
