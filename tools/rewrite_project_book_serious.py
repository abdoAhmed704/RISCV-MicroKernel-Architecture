from __future__ import annotations

from datetime import date
from pathlib import Path

import rewrite_project_book as doc


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DOCX = ROOT / "From Gates to Games - Project Book SERIOUS REWRITE.docx"


def p(parts: list[str], *items: str) -> None:
    for item in items:
        parts.append(doc.para(item))


def bullets(parts: list[str], *items: str) -> None:
    for item in items:
        parts.append(doc.bullet(item))


def code(parts: list[str], *items: str) -> None:
    for item in items:
        parts.append(doc.code_line(item))


def figure_list() -> str:
    figures = [
        "Figure 1. Register file block diagram.",
        "Figure 2. Immediate extension block diagram.",
        "Figure 3. ALU block diagram.",
        "Figure 4. Branch unit block diagram.",
        "Figure 5. Comparison between I-type and CI-type compressed formats.",
        "Figure 6. Comparison between R-type and CA-type compressed formats.",
        "Figure 7. Typical components in a modern memory hierarchy.",
        "Figure 8. Basic cache structure.",
        "Figure 9. Cache organization approaches.",
        "Figure 10. Cache design parameters.",
        "Figure 11. Main memory and arbiter reference diagram.",
        "Figure 12. Two-bit counter branch predictor.",
        "Figure 13. Branch predictor block diagram.",
        "Figure 14. Branch recovery block diagram.",
        "Figure 15. Next PC logic block diagram.",
        "Figure 16. Software implementation stack.",
        "Figure 17. CSR unit block diagram.",
        "Figure 18. misa register format.",
        "Figure 19. mstatus register fields.",
        "Figure 20. mip register fields.",
        "Figure 21. mie register fields.",
        "Figure 22. sstatus register fields.",
        "Figure 23. sip and sie supervisor CSR views.",
        "Figure 24. CSR instruction family.",
        "Figure 25. Trap flow ASM chart.",
        "Figure 26. Verification plan reference.",
        "Figure 27. R-type instruction testing reference.",
        "Figure 28. I-type instruction testing reference.",
        "Figure 29. Load, store, and U-type testing reference.",
        "Figure 30. Jump and branch expected output reference.",
        "Figure 31. Disassembly reference.",
        "Figure 32. Conversion to HEX reference.",
        "Figure 33. RISC-V DV flow reference.",
        "Figure 34. Compiler features reference.",
        "Figure 35. Application binary interface reference.",
    ]
    return "".join(doc.para(item, "BodyText") for item in figures)


def serious_body() -> str:
    parts: list[str] = []

    parts.append(doc.para("From Gates to Games", "Title", "center"))
    parts.append(doc.para("Design and Implementation of a 32-bit RISC-V Pipelined Core with Privilege Modes, CSR Control, and a Bare-Metal Snake OS Demonstration", "Subtitle", "center"))
    parts.append(doc.para("Project Book / Technical Thesis", align="center"))
    parts.append(doc.para("Repository: RISCV-MicroKernel-Architecture", align="center"))
    parts.append(doc.para("Core: RV32I five-stage pipeline with Zicsr and custom privileged-control support", align="center"))
    parts.append(doc.para(f"Rewritten and rebuilt {date.today().isoformat()}", align="center"))
    parts.append(doc.para("Prepared as a formal replacement for the earlier project book, using the 64-bit RISC-V IMAC OS thesis as the structural and diagram reference.", align="center"))
    parts.append(doc.page_break())

    parts.append(doc.heading("ACKNOWLEDGMENTS"))
    p(parts,
      "This project brings together digital design, computer architecture, firmware, simulation, and application software. The work is not only a collection of SystemVerilog modules and not only a C program; it is a complete hardware/software path from an instruction word in memory to visible behavior in a terminal.",
      "The structure of this book follows the stronger thesis-style reference document: first the motivation and RISC-V background, then the base processor implementation, then optional extension context, privileged architecture, testing, and application demonstration. The technical content, however, is rewritten for the actual repository: a 32-bit RV32I pipeline with a custom CSR and privilege subsystem.",
      "Special attention is given to the CSR unit because it is the heart of the operating-system story. Without CSRs, the core can execute arithmetic and branches. With CSRs, it can enter trap handlers, remember faulting PCs, report causes, control interrupt enables, and return from privileged code.")

    parts.append(doc.heading("Abstract"))
    p(parts,
      "The objective of this project is to design, integrate, and demonstrate a small RISC-V platform capable of running real bare-metal software on a custom processor. The hardware is centered on a 32-bit five-stage RV32I pipeline. The pipeline supports instruction fetch, decode, execute, memory access, and writeback, with hazard forwarding, load-use stalling, branch and jump flushing, byte/halfword/word data memory operations, and top-level integration around instruction memory, data memory, and privileged control.",
      "The most important architectural addition beyond a normal teaching pipeline is the CSR and privilege subsystem. The CSR unit implements Machine-mode and Supervisor-mode concepts, explicit CSR decoding, CSR instruction execution, privilege permission checks, exception and interrupt selection, delegation, trap entry, trap return, timer state, cause registers, EPC registers, and PC redirection to mtvec, stvec, mepc, or sepc.",
      "The software stack consists of startup assembly, trap handlers, a linker-controlled bare-metal image, C firmware, and a Snake game demonstration. The demo uses a simulated memory-mapped UART at address 0x00003FF0. Store-byte operations transmit characters to the simulator terminal, while load-byte operations consume keyboard input supplied by a host-side script.",
      "This project should be described accurately. It is not yet a complete Linux-capable RV64IMAC SoC. It does not implement virtual memory through satp, a full user-mode protection model, external caches, or a production platform interrupt controller. Instead, it is a strong educational RV32I hardware/software system with a meaningful privileged-control core and a clear path toward a more complete OS-capable design.")

    parts.append(doc.heading("Table of Contents"))
    for item in [
        "1. Introduction",
        "2. RISC-V ISA Background",
        "3. System Overview",
        "4. Implementation of the Base Integer Instruction Set",
        "5. Pipeline Control, Hazards, and PC Redirection",
        "6. Extension Context: C, M, Caches, Atomics, and Branch Prediction",
        "7. Implementation of the Privileged ISA Subset",
        "8. CSR Register and Bitfield Reference",
        "9. Trap, Interrupt, Delegation, and Return Flow",
        "10. Software Stack and Snake OS Demonstration",
        "11. Build Flow, Simulation, and Verification",
        "12. Limitations, Future Work, and Conclusion",
    ]:
        parts.append(doc.para(item, "TOC1"))
    parts.append(doc.page_break())

    parts.append(doc.heading("List of Figures"))
    parts.append(figure_list())
    parts.append(doc.page_break())

    parts.append(doc.heading("List of Tables"))
    for item in [
        "Table 1. Document scope.",
        "Table 2. Base instruction groups.",
        "Table 3. Project layer map.",
        "Table 4. Pipeline stage summary.",
        "Table 5. Hazard classes and resolution.",
        "Table 6. Privilege modes.",
        "Table 7. CSR register map.",
        "Table 8. mstatus fields used by the core.",
        "Table 9. Trap cause examples.",
        "Table 10. Virtual UART behavior.",
        "Table 11. Verification strategy.",
    ]:
        parts.append(doc.para(item, "BodyText"))
    parts.append(doc.page_break())

    parts.append(doc.heading("1. Introduction"))
    parts.append(doc.heading("Motivation", 2))
    p(parts,
      "A processor can be explained at many levels. At the lowest level, it is a set of registers, multiplexers, adders, memories, and control signals. At the architectural level, it is an implementation of an instruction set. At the system level, it becomes interesting only when software can depend on it.",
      "The motivation of this project is to close that gap. The design starts from a five-stage RISC-V pipeline, adds the control machinery needed to make it run non-trivial programs, and then integrates a privileged CSR unit so software can install handlers, raise environment calls, respond to exceptions, and return from traps. Finally, the project proves the path by running a Snake game through a memory-mapped UART in simulation.",
      "The reference thesis used for this rewrite presents a broad RV64IMAC design with privilege modes, caches, branch prediction, FPGA work, ASIC work, and OS-capable goals. This book borrows the formal structure and selected diagrams from that document but does not copy its claims. The current repository is a smaller and more focused RV32I platform.")
    parts.append(doc.heading("Project Objectives", 2))
    bullets(parts,
            "Implement a five-stage pipelined RV32I processor in SystemVerilog.",
            "Support forwarding, load-use stalling, branch/jump flushing, and trap redirection.",
            "Implement a CSR unit that supports Machine and Supervisor mode concepts.",
            "Support Zicsr-style CSR instructions and privileged return instructions such as mret and sret.",
            "Provide exception and interrupt cause recording through mepc, mcause, sepc, and scause.",
            "Run mixed C and assembly firmware through a reproducible build flow.",
            "Demonstrate hardware/software integration through a Snake game using MMIO.",
            "Keep the design understandable enough to debug, extend, and present academically.")
    parts.append(doc.heading("Document Scope", 2))
    parts.append(doc.table(
        ["Included in detail", "Included as context only"],
        [
            ["RV32I pipeline datapath", "Full RV64 datapath"],
            ["CSR unit and privilege behavior", "Linux boot requirements"],
            ["Trap entry, delegation, and return", "Virtual memory and page tables"],
            ["Bare-metal firmware and Snake demo", "Production UART/PLIC/CLINT platform"],
            ["Simulation and build flow", "ASIC physical-design signoff"],
        ],
    ))

    parts.append(doc.heading("2. RISC-V ISA Background"))
    parts.append(doc.heading("What is RISC-V", 2))
    p(parts,
      "RISC-V is an open instruction set architecture designed around a small base ISA and optional extensions. The base integer ISA defines the instructions required for arithmetic, logic, shifts, loads, stores, branches, jumps, and system-level operations. Because the ISA is modular, a core can start with RV32I and later add extensions such as M for multiplication/division, C for compressed instructions, A for atomics, and privileged features for operating systems.",
      "The base RV32I register model contains thirty-two 32-bit integer registers named x0 through x31. Register x0 always reads as zero. Instructions are normally 32 bits wide, and instruction fields select source registers, destination registers, immediate encodings, operation classes, and branch/jump offsets.")
    parts.append(doc.heading("Base Integer Instruction Groups", 2))
    parts.append(doc.table(
        ["Group", "Examples", "Function in the core"],
        [
            ["R-type ALU", "add, sub, and, or, xor, sll, srl, sra, slt, sltu", "Register-register arithmetic and logic."],
            ["I-type ALU", "addi, andi, ori, xori, slti, sltiu", "Register-immediate arithmetic and logic."],
            ["Loads", "lb, lh, lw, lbu, lhu", "Read data memory and extend the result."],
            ["Stores", "sb, sh, sw", "Write selected byte lanes to data memory."],
            ["Branches", "beq, bne, blt, bge, bltu, bgeu", "Conditionally redirect the PC."],
            ["Jumps", "jal, jalr", "Redirect the PC and write the link address."],
            ["Upper immediates", "lui, auipc", "Construct 32-bit constants and PC-relative values."],
            ["System", "ecall, ebreak, CSR instructions, mret, sret", "Enter or leave privileged control paths."],
        ],
    ))
    parts.append(doc.heading("Privileged Architecture Concept", 2))
    p(parts, "The unprivileged ISA is enough for normal arithmetic programs. It is not enough for operating-system behavior. Privileged architecture adds control and status registers, trap vectors, exception causes, interrupt enables, and privilege modes. These mechanisms let firmware and kernels control the machine rather than running as ordinary untrusted code.")

    parts.append(doc.heading("3. System Overview"))
    p(parts, "The repository is organized as a full-stack system. RTL modules live under rtl/RV32I, firmware and build scripts live under sw, and simulation scripts connect the compiled firmware.hex image to the instruction memory.")
    parts.append(doc.table(
        ["Layer", "Main files", "Responsibility"],
        [
            ["Datapath", "riscv_fetch_stage.sv, riscv_decode_stage.sv, riscv_execute_stage.sv, riscv_memory_stage.sv", "Move instructions and operands through the five pipeline stages."],
            ["Control", "riscv_control_unit.sv, riscv_hazard_unit.sv, riscv_pc_src_controller.sv", "Decode operations, resolve hazards, and select the correct next PC."],
            ["Privilege", "riscv_csr_unit.sv, riscv_top_pipeline.sv", "Store CSR state, detect traps, route handlers, and restore privilege state."],
            ["Software", "start.s, main.c, linker.ld", "Boot the machine, install trap vectors, and run the demo firmware."],
            ["Application", "Snake game and virtual UART", "Render a terminal game and accept keyboard input through MMIO."],
        ],
    ))
    parts.append(doc.heading("Repository Structure", 2))
    code(parts,
         "RISCV-MicroKernel-Architecture/",
         "  rtl/RV32I/                  SystemVerilog processor and CSR modules",
         "  sw/src/start.s              startup and trap handler assembly",
         "  sw/src/main.c               C firmware and Snake application",
         "  sw/linker.ld                bare-metal linker script",
         "  sw/build.ps1                C/assembly firmware build script",
         "  sim/                        simulator command files",
         "  Standard/                   RISC-V reference manuals",
         "  book.md                     earlier markdown project-book draft")
    parts.append(doc.heading("High-Level Execution Flow", 2))
    code(parts,
         "C / assembly source",
         "  -> RISC-V GCC and linker",
         "  -> sw/build/firmware.elf",
         "  -> sw/build/firmware.hex",
         "  -> instruction memory",
         "  -> five-stage core",
         "  -> data memory / MMIO UART",
         "  -> simulator terminal and keyboard feeder")
    parts.append(doc.heading("Top-Level Integration", 2))
    p(parts, "The riscv_top_pipeline.sv module ties the pipeline stages to the CSR unit and exposes interrupt-related ports. It receives external interrupt requests, propagates decoded system instructions through the pipeline, sends exception information into the CSR unit, and uses CSR redirect outputs to select the next PC on trap entry and trap return.")

    parts.append(doc.heading("4. Implementation of the Base Integer Instruction Set"))
    p(parts, "The processor follows the classic five-stage structure: Instruction Fetch, Instruction Decode, Execute, Memory, and Writeback. Pipeline registers carry instruction fields, operand values, control signals, PC values, and exception metadata between stages.")
    parts.append(doc.table(
        ["Stage", "Name", "Main responsibility"],
        [
            ["IF", "Instruction Fetch", "Maintain PC, read instruction memory, compute PC + 4, accept redirects."],
            ["ID", "Instruction Decode", "Decode opcode/funct fields, read x-registers, generate immediates and controls."],
            ["EX", "Execute", "Run the ALU, compare branches, calculate targets, apply forwarding."],
            ["MEM", "Memory", "Perform load/store accesses and align/sign-extend loaded data."],
            ["WB", "Writeback", "Select ALU, memory, CSR, or PC+4 result and write rd."],
        ],
    ))
    parts.append(doc.heading("Register File and Immediate Generation", 2))
    p(parts, "The integer register file contains thirty-two 32-bit registers. Register x0 is hardwired to zero. The decode stage reads rs1 and rs2, while writeback updates rd when RegWrite is asserted. The implementation writes on the falling edge, which helps the simple pipeline observe newly written values without adding unnecessary bypass complexity.")
    parts.append(doc.image("rId17", "Figure 1. Register file block diagram.", 1))
    p(parts, "Immediate generation is separated into riscv_extend.sv. It reconstructs I, S, B, U, and J immediates from instruction bit fields and sign-extends them to 32 bits. Keeping this logic isolated makes decode easier to inspect and reduces repeated bit slicing across the datapath.")
    parts.append(doc.image("rId37", "Figure 2. Immediate extension block diagram.", 2))
    parts.append(doc.heading("Execute, Memory, and Writeback", 2))
    p(parts, "The execute stage receives decoded ALU controls, register operands, immediates, and forwarded data. It performs arithmetic, logical operations, branch comparisons, jump target calculation, and memory address generation. The memory stage performs data access and the writeback stage commits the selected result to the integer register file.")
    parts.append(doc.image("rId38", "Figure 3. ALU block diagram.", 3))
    parts.append(doc.image("rId39", "Figure 4. Branch unit block diagram.", 4))

    parts.append(doc.heading("5. Pipeline Control, Hazards, and PC Redirection"))
    p(parts,
      "Pipelining improves throughput by overlapping instructions, but it introduces hazards. The hazard unit resolves read-after-write dependencies through forwarding from later stages into Execute. When a load-use dependency cannot be forwarded in time, the unit stalls Fetch and Decode and flushes Execute for one cycle.",
      "Control hazards are handled by flushing wrong-path instructions after a taken branch, jump, exception, interrupt, or trap return. Privileged redirects have high priority because a trap must enter the handler precisely and must not allow younger instructions to commit incorrect state.")
    parts.append(doc.table(
        ["Hazard type", "Example", "Resolution"],
        [
            ["ALU RAW", "add x5,... followed by sub using x5", "Forward from MEM/WB to Execute input."],
            ["Load-use", "lw x5,0(x1) followed immediately by add using x5", "Stall PC and IF/ID, flush ID/EX."],
            ["Taken branch/jump", "beq taken or jal/jalr", "Flush younger wrong-path instructions."],
            ["Trap/return", "ecall, interrupt, mret, sret", "CSR unit overrides next PC and flushes pipeline."],
        ],
    ))
    parts.append(doc.heading("PC Selection Priority", 2))
    p(parts,
      "The next PC is not chosen only by PC + 4. Several events can override normal sequential execution. In a simple instruction stream, the fetch stage advances by four bytes. For branches and jumps, the execute/control logic provides a target. For traps and returns, the CSR unit provides the highest-priority redirect.",
      "This ordering is essential. If an interrupt or exception is accepted, the handler PC must win over branch or fall-through execution. If mret or sret is executed, the saved EPC must become the next PC.")
    parts.append(doc.image("rId153", "Figure 15. Next PC logic block diagram.", 15))

    parts.append(doc.heading("6. Extension Context: C, M, Caches, Atomics, and Branch Prediction"))
    p(parts,
      "The reference thesis contains full chapters for the M extension, C extension, atomic instructions, caches, and branch prediction. In this repository, those topics should be presented carefully. They are important to the broader RISC-V roadmap, but the current demonstrated system is centered on RV32I plus CSR/privilege support.",
      "This chapter therefore explains the role of those extensions as architectural context and future integration paths. The diagrams are retained because they help explain why an OS-capable RISC-V system eventually needs more than a base pipeline.")
    parts.append(doc.heading("Compressed Instruction Extension Context", 2))
    p(parts, "The C extension reduces code size by adding 16-bit compressed encodings for common operations. A core that supports C must fetch at halfword alignment, distinguish 16-bit and 32-bit encodings, expand compressed instructions into equivalent internal operations, and adjust PC stepping accordingly.")
    parts.append(doc.image("rId78", "Figure 5. Comparison between I-type and CI-type compressed formats.", 5))
    parts.append(doc.image("rId79", "Figure 6. Comparison between R-type and CA-type compressed formats.", 6))
    parts.append(doc.heading("Memory Hierarchy and Cache Context", 2))
    p(parts, "Caches become important when the processor is connected to a larger memory system. They exploit temporal and spatial locality to reduce average memory latency. A complete OS-capable SoC normally separates instruction cache, data cache, main memory arbitration, and memory-mapped I/O rules.")
    parts.append(doc.image("rId81", "Figure 7. Typical components in a modern memory hierarchy.", 7))
    parts.append(doc.image("rId84", "Figure 8. Basic cache structure.", 8))
    parts.append(doc.image("rId85", "Figure 9. Cache organization approaches.", 9))
    parts.append(doc.image("rId86", "Figure 10. Cache design parameters.", 10))
    parts.append(doc.image("rId147", "Figure 11. Main memory and arbiter reference diagram.", 11))
    parts.append(doc.heading("Branch Prediction Context", 2))
    p(parts, "The current pipeline resolves control flow through ordinary branch/jump handling and flushing. A more advanced implementation may add prediction to reduce lost cycles. The reference thesis diagrams are useful for explaining static prediction, dynamic two-bit counters, branch target prediction, and recovery after a wrong prediction.")
    parts.append(doc.image("rId150", "Figure 12. Two-bit counter branch predictor.", 12))
    parts.append(doc.image("rId151", "Figure 13. Branch predictor block diagram.", 13))
    parts.append(doc.image("rId152", "Figure 14. Branch recovery block diagram.", 14))

    parts.append(doc.heading("7. Implementation of the Privileged ISA Subset"))
    p(parts, "The CSR unit is the privileged-control center of the core. It handles CSR reads and writes, checks CSR address permissions, evaluates exceptions and interrupts, records trap state, updates privilege stacks, and requests PC redirection to mtvec, stvec, mepc, or sepc.")
    parts.append(doc.image("rId154", "Figure 16. Software implementation stack.", 16))
    parts.append(doc.image("rId155", "Figure 17. CSR unit block diagram.", 17))
    parts.append(doc.heading("Privilege Modes", 2))
    parts.append(doc.table(
        ["Mode", "Encoding", "Implementation status", "Purpose"],
        [
            ["User", "00", "Partial state value only", "Can be restored by return state, but no full U-mode CSR model exists."],
            ["Supervisor", "01", "Implemented", "Provides S-mode trap CSRs and delegated trap handling."],
            ["Reserved", "10", "Unused", "Should not be entered by software."],
            ["Machine", "11", "Implemented", "Reset mode and highest privilege level."],
        ],
    ))
    p(parts, "The core boots in Machine mode. Machine mode can configure trap vectors, delegation registers, interrupt enables, timers, and previous-privilege fields. Supervisor mode receives delegated traps and sees restricted S-mode CSR views such as sstatus, sie, sip, stvec, sepc, and scause.")
    parts.append(doc.heading("CSR Unit Responsibilities", 2))
    bullets(parts,
            "Execute csrrw, csrrs, csrrc, csrrwi, csrrsi, and csrrci.",
            "Reject illegal CSR addresses, read-only writes, and insufficient privilege access.",
            "Evaluate exceptions from the pipeline and interrupts from external/timer sources.",
            "Apply medeleg and mideleg to decide whether traps route to M-mode or S-mode.",
            "Write EPC and cause registers during trap entry.",
            "Update mstatus privilege-stack fields during trap entry and return.",
            "Generate handler and return PC redirects for the fetch stage.")
    parts.append(doc.image("rId156", "Figure 18. misa register format.", 18))
    parts.append(doc.image("rId157", "Figure 19. mstatus register fields.", 19))

    parts.append(doc.heading("8. CSR Register and Bitfield Reference"))
    p(parts, "The implementation is not a generic 4096-entry CSR RAM. Instead, riscv_csr_unit.sv explicitly decodes supported CSR addresses. This is simpler, easier to verify, and appropriate for an educational core.")
    parts.append(doc.table(
        ["CSR", "Address", "Role"],
        [
            ["mstatus", "0x300", "Machine interrupt enables and privilege stack fields MPP/MPIE/MIE/SPP/SPIE/SIE."],
            ["misa", "0x301", "Reported ISA and privilege capabilities."],
            ["medeleg", "0x302", "Exception delegation from M-mode to S-mode."],
            ["mideleg", "0x303", "Interrupt delegation from M-mode to S-mode."],
            ["mie", "0x304", "Machine interrupt enable bits."],
            ["mtvec", "0x305", "Machine trap vector base and mode."],
            ["mepc", "0x341", "PC saved on M-mode trap entry."],
            ["mcause", "0x342", "Cause saved on M-mode trap entry."],
            ["sstatus", "0x100", "Supervisor view of selected mstatus fields."],
            ["sie", "0x104", "Supervisor view of delegated interrupt enables."],
            ["stvec", "0x105", "Supervisor trap vector base and mode."],
            ["sepc", "0x141", "PC saved on S-mode trap entry."],
            ["scause", "0x142", "Cause saved on S-mode trap entry."],
            ["sip", "0x144", "Supervisor view of delegated pending interrupts."],
            ["mtime/mtimecmp", "custom decoded CSRs", "Internal time counter and compare registers."],
        ],
    ))
    parts.append(doc.heading("mstatus Fields Used by the Core", 2))
    parts.append(doc.table(
        ["Field", "Bit(s)", "Meaning"],
        [
            ["SIE", "1", "Supervisor global interrupt enable."],
            ["MIE", "3", "Machine global interrupt enable."],
            ["SPIE", "5", "Saved SIE value on S-mode trap entry."],
            ["MPIE", "7", "Saved MIE value on M-mode trap entry."],
            ["SPP", "8", "Previous privilege for sret."],
            ["MPP", "12:11", "Previous privilege for mret."],
        ],
    ))
    parts.append(doc.heading("Interrupt Views", 2))
    p(parts, "mip is computed from external interrupt inputs and timer comparisons. sip is a delegated supervisor view of pending interrupts. mie stores interrupt enables, while sie exposes delegated supervisor-enable bits.")
    parts.append(doc.image("rId158", "Figure 20. mip register fields.", 20))
    parts.append(doc.image("rId159", "Figure 21. mie register fields.", 21))
    parts.append(doc.image("rId160", "Figure 22. sstatus register fields.", 22))
    parts.append(doc.image("rId161", "Figure 23. sip and sie supervisor CSR views.", 23))
    parts.append(doc.heading("CSR Instructions", 2))
    p(parts, "The Zicsr instruction family lets software read, write, set, and clear CSR bits using either register operands or immediate fields. The CSR unit checks whether the instruction is active, whether the address exists, whether the current privilege is high enough for the CSR address, and whether software is attempting to write a read-only CSR.")
    parts.append(doc.image("rId162", "Figure 24. CSR instruction family.", 24))
    parts.append(doc.table(
        ["Instruction", "Operation", "Typical use"],
        [
            ["csrrw", "rd = CSR; CSR = rs1", "Install a new vector or status value."],
            ["csrrs", "rd = CSR; CSR = CSR | rs1", "Enable selected bits."],
            ["csrrc", "rd = CSR; CSR = CSR & ~rs1", "Disable selected bits."],
            ["csrrwi", "rd = CSR; CSR = uimm", "Small immediate writes."],
            ["csrrsi", "rd = CSR; CSR = CSR | uimm", "Small immediate set masks."],
            ["csrrci", "rd = CSR; CSR = CSR & ~uimm", "Small immediate clear masks."],
        ],
    ))
    parts.append(doc.heading("Educational Simplifications", 2))
    bullets(parts,
            "satp reads as zero; virtual memory is not implemented.",
            "mvendorid, marchid, mimpid, and mhartid read as zero.",
            "mip and sip are computed views instead of fully writable registers.",
            "mtime, mtimecmp, and stimecmp are implemented inside the CSR unit.",
            "The CSR file is explicit decode logic rather than a 4096-entry memory.")

    parts.append(doc.heading("9. Trap, Interrupt, Delegation, and Return Flow"))
    p(parts,
      "Trap handling is where the ordinary pipeline and privileged architecture meet. The pipeline reports exceptions such as illegal instruction, instruction address misalignment, ecall, ebreak, load access fault, and store access fault. The CSR unit also evaluates timer and external interrupt requests.",
      "If a trap is taken to Machine mode, the unit writes mepc and mcause, saves the old privilege mode in mstatus.MPP, saves MIE into MPIE, clears MIE, switches to Machine mode, and redirects the PC to mtvec. If the trap is delegated to Supervisor mode, the equivalent sepc/scause/SPP/SPIE/SIE/stvec path is used.")
    parts.append(doc.image("rId163", "Figure 25. Trap flow ASM chart.", 25))
    parts.append(doc.table(
        ["Event", "Cause code", "Saved PC", "Return"],
        [
            ["Illegal instruction", "2", "mepc or sepc", "mret or sret"],
            ["Instruction address misaligned", "0", "mepc or sepc", "mret or sret"],
            ["Breakpoint", "3", "mepc or sepc", "mret or sret"],
            ["Load access fault", "5", "mepc or sepc", "mret or sret"],
            ["Store access fault", "7", "mepc or sepc", "mret or sret"],
            ["ECALL from S-mode", "9", "mepc or sepc depending on delegation", "mret or sret"],
            ["ECALL from M-mode", "11", "mepc", "mret"],
            ["Machine timer interrupt", "interrupt bit + 7", "mepc", "mret"],
            ["Machine external interrupt", "interrupt bit + 11", "mepc", "mret"],
        ],
    ))
    parts.append(doc.heading("Trap Entry Timeline", 2))
    code(parts,
         "1. Pipeline detects exception or CSR unit detects enabled interrupt.",
         "2. CSR unit chooses final cause and target privilege.",
         "3. mepc/sepc receives the faulting or interrupted PC.",
         "4. mcause/scause receives the exception or interrupt cause.",
         "5. mstatus privilege-stack fields are updated.",
         "6. Current privilege mode changes to M-mode or S-mode.",
         "7. Fetch PC is redirected to mtvec or stvec.",
         "8. Younger pipeline instructions are flushed.")
    parts.append(doc.heading("Trap Return", 2))
    p(parts, "mret restores the privilege mode from mstatus.MPP, restores MIE from MPIE, sets MPIE, clears MPP, and redirects the PC to mepc. sret restores privilege from SPP, restores SIE from SPIE, sets SPIE, clears SPP, and redirects the PC to sepc. The top-level pipeline treats both instructions as PC override events.")

    parts.append(doc.heading("10. Software Stack and Snake OS Demonstration"))
    p(parts, "The software side demonstrates that the hardware can run real firmware rather than only isolated instruction tests. The mixed C/assembly flow builds start.s and main.c into firmware.elf and then converts it into firmware.hex for instruction memory.")
    parts.append(doc.heading("Boot and Trap Handlers", 2))
    p(parts, "The startup assembly exposes m_trap_handler and s_trap_handler. The C firmware programs mtvec and stvec with their addresses. On an exception, the handlers inspect the cause, advance the saved EPC when appropriate, perform simple service work, and return with mret or sret.")
    parts.append(doc.heading("Virtual UART MMIO", 2))
    p(parts, "The Snake demo uses a virtual UART in riscv_data_mem.sv. The UART address is 0x00003FF0. A store byte to this address prints a character in the simulator terminal. A load byte reads one key from sw/input.txt through the keyboard feeder script.")
    parts.append(doc.table(
        ["Address", "Access", "Behavior"],
        [
            ["0x00003FF0", "Store byte", "Transmit character to simulator console."],
            ["0x00003FF0", "Load byte", "Read one keyboard character from the feeder file."],
            ["0x00003FFC", "Platform address", "Reserved platform/status location in data memory."],
        ],
    ))
    parts.append(doc.heading("Snake Application", 2))
    p(parts,
      "The C application renders an ASCII Snake board. The snake head is '@', body cells are 'o', and food is '*'. The game accepts W/A/S/D movement controls and Q for reset. It is small, visible, and useful: if the pipeline, memory, CSR setup, or build flow fails, the demo quickly exposes the problem.",
      "A waveform-only CPU project can hide integration problems. The Snake demo forces many pieces to work together: instruction memory must load the image, the PC must step correctly, branches must loop correctly, loads and stores must handle byte data, the virtual UART must respond to MMIO, and the firmware must preserve enough state to keep the game alive.")

    parts.append(doc.heading("11. Build Flow, Simulation, and Verification"))
    parts.append(doc.heading("Compilation Flow", 2))
    code(parts,
         "cd sw",
         ".\\build.ps1",
         "python elf2hex.py build/firmware.elf build/firmware.hex",
         ".\\run_xsim.bat")
    p(parts, "The build scripts target rv32i_zicsr with the ilp32 ABI and no standard library. The linker script controls the bare-metal memory map, and firmware.hex is loaded by the RTL instruction memory.")
    parts.append(doc.image("rId191", "Figure 34. Compiler features reference.", 34))
    parts.append(doc.image("rId192", "Figure 35. Application binary interface reference.", 35))
    parts.append(doc.heading("Verification Strategy", 2))
    parts.append(doc.image("rId175", "Figure 26. Verification plan reference.", 26))
    p(parts, "Verification is organized around direct pipeline tests, CSR/privilege assembly tests, C/assembly firmware tests, and full-system Snake execution. Direct tests are useful for deterministic instruction behavior. The full-system test is useful for integration because it exercises instruction fetch, decode, ALU operations, memory access, MMIO, trap vector setup, and software loops together.")
    parts.append(doc.table(
        ["Test area", "Evidence to inspect", "Expected result"],
        [
            ["RV32I datapath", "riscv_test.s, waveforms, register traces", "Arithmetic, branches, loads, stores, and writeback agree with expected values."],
            ["Hazard unit", "Forwarding and stall signals", "RAW dependencies resolve; load-use hazards insert one bubble."],
            ["CSR instructions", "mscratch/mstatus/mtvec reads and writes", "CSR read-modify-write instructions return old value and update selected bits."],
            ["Trap handling", "mepc, mcause, sepc, scause, PC redirect", "Handler address is selected and return resumes at the saved PC."],
            ["Snake demo", "Simulator terminal", "Game board renders and keyboard input changes direction."],
        ],
    ))
    parts.append(doc.heading("Instruction-Level Test References", 2))
    parts.append(doc.image("rId177", "Figure 27. R-type instruction testing reference.", 27))
    parts.append(doc.image("rId179", "Figure 28. I-type instruction testing reference.", 28))
    parts.append(doc.image("rId181", "Figure 29. Load, store, and U-type testing reference.", 29))
    parts.append(doc.image("rId183", "Figure 30. Jump and branch expected output reference.", 30))
    parts.append(doc.heading("Tool Output References", 2))
    parts.append(doc.image("rId185", "Figure 31. Disassembly reference.", 31))
    parts.append(doc.image("rId187", "Figure 32. Conversion to HEX reference.", 32))
    parts.append(doc.image("rId188", "Figure 33. RISC-V DV flow reference.", 33))

    parts.append(doc.heading("12. Limitations, Future Work, and Conclusion"))
    parts.append(doc.heading("Current Limitations", 2))
    bullets(parts,
            "The system is RV32-oriented and should not be described as a finished 64-bit Linux-capable IMAC core.",
            "satp reads as zero and virtual memory/page-table translation is not implemented.",
            "User mode exists mainly as a privilege encoding that can be restored, not as a complete application isolation environment.",
            "The virtual UART is implemented inside data memory for simulation convenience.",
            "The timer is implemented inside the CSR unit rather than as a platform CLINT/ACLINT device.")
    parts.append(doc.heading("Future Work", 2))
    bullets(parts,
            "Move MMIO behind a dedicated bus decoder.",
            "Add a real platform interrupt controller and cleaner interrupt acknowledge protocol.",
            "Implement timer-driven context switching with complete register save/restore.",
            "Add user-mode task entry and protection checks.",
            "Extend the memory system toward instruction/data caches once the base privilege path is stable.",
            "Automate regression tests for CSR corner cases, delegation, and trap return sequencing.")
    parts.append(doc.heading("Conclusion", 2))
    p(parts,
      "From Gates to Games is best understood as a working hardware/software integration project. The RTL core provides a five-stage RV32I pipeline, the CSR unit adds privileged control and trap semantics, and the software stack proves the design by running a visible game through a simulated device interface.",
      "The result is not just a CPU block diagram. It is a small platform: firmware is compiled, loaded, executed, interrupted, and observed. That makes the project suitable for explanation, demonstration, and future extension toward a more complete operating-system-capable RISC-V system.")

    parts.append(doc.heading("References"))
    bullets(parts,
            "The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture.",
            "The RISC-V Instruction Set Manual, Volume II: Privileged Architecture.",
            "rtl/RV32I/CSR_UNIT_REFERENCE_MANUAL.md.",
            "rtl/RV32I/explain_Privilege.md.",
            "sw/SNAKE_OS_GUIDE.md.",
            "RISCV-MicroKernel-Architecture repository RTL and software sources.",
            "Reference thesis: From Gates to OS: Design and Implementation of a 64-bit RISC-V IMAC Core with Privilege Modes and Level-1 Caches Capable of Running OS.")

    sect_pr = """
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
  <w:cols w:space="708"/>
  <w:docGrid w:linePitch="360"/>
</w:sectPr>
"""
    return "".join(parts) + sect_pr


def main() -> None:
    doc.OUTPUT_DOCX = OUTPUT_DOCX
    doc.build_body = serious_body
    doc.main()


if __name__ == "__main__":
    main()
