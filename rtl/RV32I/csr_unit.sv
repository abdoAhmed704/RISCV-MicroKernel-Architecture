module csr_unit (
    input  logic        clk,
    input  logic        rst,
    input  logic [11:0] csr_addr,        // From instruction bits [31:20]
    input  logic [31:0] csr_write_data,  // Data from rs1 or immediate field
    input  logic [2:0]  funct3,          // Inst bits [14:12] to determine RW/RS/RC
    input  logic        is_system_instr, // From control unit
    
    // Trap handling sideband signals (From Trap Controller)
    input  logic        trap_active,     // High when an exception/ecall occurs
    input  logic        mret_active,     // High when MRET executes
    input  logic [31:0] trap_pc,         // The current PC to be saved
    input  logic [31:0] trap_cause,      // The cause code (e.g., 11 for ecall)

    // Outputs
    output logic [31:0] csr_read_data,   // Reading output back to integer rd reg
    output logic [31:0] mtvec_out,       // Constant broadcast to PC Mux
    output logic [31:0] mepc_out         // Constant broadcast to PC Mux
);

    // --- 1. Architectural Register Storage ---
    logic [31:0] mstatus; // Only bit [7] MPIE and bit [3] MIE are used here
    logic [31:0] mtvec;
    logic [31:0] mepc;
    logic [31:0] mcause;

    // Continuous broadcast outputs for the PC hijacking Mux
    assign mtvec_out = mtvec;
    assign mepc_out  = mepc;

    // --- 2. Combinatorial Read Port ---
    always_comb begin
        if (is_system_instr) begin
            case (csr_addr)
                12'h300: csr_read_data = mstatus;
                12'h305: csr_read_data = mtvec;
                12'h341: csr_read_data = mepc;
                12'h342: csr_read_data = mcause;
                default: csr_read_data = 32'b0;
            endcase
        end else begin
            csr_read_data = 32'b0;
        end
    end

    // --- 3. Internal ALU for Bitwise CSR Opcodes ---
    logic [31:0] updated_csr_val;
    
    always_comb begin
        case (funct3[1:0])
            2'b01:   updated_csr_val = csr_write_data;                  // CSRRW / CSRRWI (Write)
            2'b10:   updated_csr_val = csr_read_data | csr_write_data;   // CSRRS / CSRRSI (Set)
            2'b11:   updated_csr_val = csr_read_data & ~csr_write_data;  // CSRRC / CSRRCI (Clear)
            default: updated_csr_val = csr_read_data;
        endcase
    end

    // --- 4. Sequential Write Port & Trap Logic ---
    logic csr_write_en;
    assign csr_write_en = is_system_instr && (funct3 != 3'b000);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus <= 32'h00000000; // All interrupts disabled on reset
            mtvec   <= 32'h00000000;
            mepc    <= 32'h00000000;
            mcause  <= 32'h00000000;
        end 
        // TRAP ENTRY HIGHER PRIORITY OVER SOFTWARE WRITES
        else if (trap_active) begin
            mepc         <= trap_pc;
            mcause       <= trap_cause;
            mstatus[7]   <= mstatus[3]; // mstatus.MPIE = mstatus.MIE (Save old interrupt status)
            mstatus[3]   <= 1'b0;       // mstatus.MIE  = 0     (Disable interrupts globally)
        end 
        // TRAP EXIT VIA MRET
        else if (mret_active) begin
            mstatus[3]   <= mstatus[7]; // mstatus.MIE  = mstatus.MPIE (Restore old status)
            mstatus[7]   <= 1'b1;       // mstatus.MPIE = 1
        end 
        // STANDARD SOFTWARE CSR ACCESS
        else if (csr_write_en) begin
            case (csr_addr)
                12'h300: mstatus <= updated_csr_val;
                12'h305: mtvec   <= updated_csr_val;
                12'h341: mepc    <= updated_csr_val;
                12'h342: mcause  <= updated_csr_val;
                default: ; // Do nothing if trying to write to invalid/unsupported address
            endcase
        end
    end

endmodule