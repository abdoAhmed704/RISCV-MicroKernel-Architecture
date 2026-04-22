module instruction_mem
#(parameter MEM_Depth = 512,
  parameter MEM_Width = 32)(
  input [31:0]PC,
  output reg [31:0]inst);

  reg [MEM_Width-1:0]mem[MEM_Depth-1:0];
 
  initial begin
    // Point this path to the .hex file you just generated
    $readmemh("../../sw/build/firmware.hex", mem);
  end
  always @(*) begin
    inst = mem[PC >> 2]; // FIXED
  end

endmodule         // no condition on reading form mem and its async
