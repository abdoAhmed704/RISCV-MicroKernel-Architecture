from __future__ import annotations

import html
import os
import zipfile
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_DOCX = (
    ROOT.parent.parent.parent
    / "From Gates to OS Design and Implementation of a 64-bit RISC-V IMAC Core with Privilege Modes and Level-1 Caches Capable of Running OS.docx"
)
OUTPUT_DOCX = ROOT / "From Gates to Games - Project Book REWRITTEN.docx"


NS = {
    "wpc": "http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas",
    "mc": "http://schemas.openxmlformats.org/markup-compatibility/2006",
    "o": "urn:schemas-microsoft-com:office:office",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
    "v": "urn:schemas-microsoft-com:vml",
    "wp14": "http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing",
    "wp": "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    "w10": "urn:schemas-microsoft-com:office:word",
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "w14": "http://schemas.microsoft.com/office/word/2010/wordml",
    "wpg": "http://schemas.microsoft.com/office/word/2010/wordprocessingGroup",
    "wpi": "http://schemas.microsoft.com/office/word/2010/wordprocessingInk",
    "wne": "http://schemas.microsoft.com/office/word/2006/wordml",
    "wps": "http://schemas.microsoft.com/office/word/2010/wordprocessingShape",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "pic": "http://schemas.openxmlformats.org/drawingml/2006/picture",
}


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def run(text: str, bold: bool = False, italic: bool = False, code: bool = False) -> str:
    props = []
    if bold:
        props.append("<w:b/>")
    if italic:
        props.append("<w:i/>")
    if code:
        props.append('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>')
    rpr = f"<w:rPr>{''.join(props)}</w:rPr>" if props else ""
    return f'<w:r>{rpr}<w:t xml:space="preserve">{esc(text)}</w:t></w:r>'


def para(text: str = "", style: str | None = None, align: str | None = None) -> str:
    ppr = []
    if style:
        ppr.append(f'<w:pStyle w:val="{style}"/>')
    if align:
        ppr.append(f'<w:jc w:val="{align}"/>')
    ppr_xml = f"<w:pPr>{''.join(ppr)}</w:pPr>" if ppr else ""
    return f"<w:p>{ppr_xml}{run(text)}</w:p>"


def heading(text: str, level: int = 1) -> str:
    return para(text, f"Heading{level}")


def bullet(text: str) -> str:
    return para(f"- {text}", "ListParagraph")


def code_line(text: str) -> str:
    return f'<w:p><w:pPr><w:pStyle w:val="NoSpacing"/></w:pPr>{run(text, code=True)}</w:p>'


def page_break() -> str:
    return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'


def table(headers: list[str], rows: list[list[str]]) -> str:
    grid_cols = "".join('<w:gridCol w:w="2400"/>' for _ in headers)
    out = [
        "<w:tbl>",
        '<w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>',
        f"<w:tblGrid>{grid_cols}</w:tblGrid>",
    ]
    for row_index, row in enumerate([headers] + rows):
        out.append("<w:tr>")
        for cell in row:
            cell_runs = run(cell, bold=row_index == 0)
            out.append(f'<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr><w:p>{cell_runs}</w:p></w:tc>')
        out.append("</w:tr>")
    out.append("</w:tbl>")
    return "".join(out)


def image(rid: str, caption: str, fig_id: int, width_in: float = 5.9, height_in: float = 3.25) -> str:
    cx = int(width_in * 914400)
    cy = int(height_in * 914400)
    name = esc(caption)
    drawing = f"""
<w:p>
  <w:pPr><w:jc w:val="center"/></w:pPr>
  <w:r>
    <w:drawing>
      <wp:inline distT="0" distB="0" distL="0" distR="0">
        <wp:extent cx="{cx}" cy="{cy}"/>
        <wp:effectExtent l="0" t="0" r="0" b="0"/>
        <wp:docPr id="{fig_id}" name="Figure {fig_id}"/>
        <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>
        <a:graphic>
          <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
            <pic:pic>
              <pic:nvPicPr><pic:cNvPr id="{fig_id}" name="{name}"/><pic:cNvPicPr/></pic:nvPicPr>
              <pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
              <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
            </pic:pic>
          </a:graphicData>
        </a:graphic>
      </wp:inline>
    </w:drawing>
  </w:r>
</w:p>
"""
    return drawing + para(caption, "Caption", "center")


def figure_list() -> str:
    figures = [
        "Figure 1. Register file structure used by the integer datapath.",
        "Figure 2. Immediate extension logic for RISC-V instruction formats.",
        "Figure 3. ALU block diagram.",
        "Figure 4. Branch unit block diagram.",
        "Figure 5. Software implementation stack for privileged execution.",
        "Figure 6. CSR unit block diagram.",
        "Figure 7. misa register format.",
        "Figure 8. mstatus privilege and interrupt stack fields.",
        "Figure 9. mie/mip interrupt enable and pending fields.",
        "Figure 10. sstatus supervisor view.",
        "Figure 11. sip/sie supervisor interrupt views.",
        "Figure 12. CSR instruction family.",
        "Figure 13. Trap entry and return flow.",
        "Figure 14. Verification plan reference.",
    ]
    return "".join(para(item, "BodyText") for item in figures)


def build_body() -> str:
    parts: list[str] = []
    parts.append(para("From Gates to Games", "Title", "center"))
    parts.append(para("Design and Implementation of a 32-bit RISC-V Pipelined Core with CSR Privilege Support and a Bare-Metal Snake OS Demo", "Subtitle", "center"))
    parts.append(para("Project Book / White Paper", align="center"))
    parts.append(para("Project: RISCV-MicroKernel-Architecture", align="center"))
    parts.append(para(f"Rewritten {date.today().isoformat()}", align="center"))
    parts.append(page_break())

    parts.append(heading("ACKNOWLEDGMENTS"))
    parts.append(para("This project brings together processor microarchitecture, privileged control, firmware, toolchain integration, simulation, and application-level demonstration. The rewritten book follows the formal structure of the earlier OS thesis reference while documenting the actual RV32I hardware and software present in this repository."))
    parts.append(para("Special attention is given to the CSR and privilege unit because it is the architectural bridge between a normal instruction pipeline and software that behaves like a tiny operating system."))

    parts.append(heading("Abstract"))
    parts.append(para("This book documents the design and implementation of a 32-bit RISC-V hardware/software system built around a five-stage RV32I pipeline. The processor executes the base integer instruction set, resolves data and control hazards, supports byte/halfword/word memory operations, and integrates a Control and Status Register unit for Machine and Supervisor privilege behavior."))
    parts.append(para("The system also includes a bare-metal software stack: startup assembly, trap handlers, a C runtime, a simple syscall path, a memory-mapped virtual UART, and an interactive Snake application. Together these components demonstrate a complete path from instruction fetch to visible software behavior on a custom core."))
    parts.append(para("The design is educational rather than a full Linux-capable SoC. Address translation is intentionally absent, satp reads as zero, and the timer is implemented inside the CSR unit. Still, the core implements meaningful privileged mechanisms including mtvec/stvec routing, mepc/sepc capture, mcause/scause reporting, mret/sret return, delegation registers, interrupt enable/pending views, and trap-driven PC redirection."))

    parts.append(heading("Table of Contents"))
    toc = [
        "1. Introduction",
        "2. System Overview",
        "3. Implementation of the Base Integer Pipeline",
        "4. Hazard and Control Flow Management",
        "5. Implementation of the Privileged ISA Subset",
        "6. CSR Register Reference",
        "7. Trap, Interrupt, and Return Flow",
        "8. Software Stack and Snake OS Demo",
        "9. Build, Simulation, and Verification",
        "10. Limitations, Future Work, and Conclusion",
    ]
    parts.extend(para(item, "TOC1") for item in toc)
    parts.append(page_break())

    parts.append(heading("List of Figures"))
    parts.append(figure_list())
    parts.append(page_break())

    parts.append(heading("1. Introduction"))
    parts.append(heading("Motivation", 2))
    parts.append(para("A processor project becomes much more convincing when it moves beyond isolated RTL blocks. A working core should fetch real firmware, execute compiled code, respond to traps, communicate with a simulated device, and run a user-visible application. That is the purpose of this project: to connect gates to software behavior."))
    parts.append(para("The earlier thesis reference shows a formal way to explain a RISC-V core: introduce the ISA, document the pipeline, describe extensions, explain privilege support, then show testing and implementation. This book keeps that structure but narrows the technical claims to the repository implementation: an RV32I-style core with Zicsr and privileged-control support, not a finished 64-bit Linux core."))
    parts.append(heading("Project Objectives", 2))
    for item in [
        "Implement a five-stage pipelined RV32I processor in SystemVerilog.",
        "Support forwarding, load-use stalling, branch/jump flushing, and trap redirection.",
        "Implement a CSR unit that supports Machine and Supervisor mode concepts.",
        "Run mixed C and assembly firmware through a reproducible build flow.",
        "Demonstrate hardware/software integration through a Snake game using MMIO.",
        "Keep the design understandable enough to debug, extend, and present academically.",
    ]:
        parts.append(bullet(item))
    parts.append(heading("What is RISC-V", 2))
    parts.append(para("RISC-V is an open instruction set architecture. Its base integer ISA defines a small, clean set of instructions for arithmetic, control transfer, and memory access. Optional extensions and privileged specifications then add compressed instructions, multiplication/division, atomics, virtual memory, privilege modes, interrupts, exceptions, and operating-system support."))
    parts.append(para("This project focuses on the educational core of that ecosystem: RV32I execution plus CSR and privileged behavior sufficient for traps, syscalls, timer state, and Machine/Supervisor control."))

    parts.append(heading("2. System Overview"))
    parts.append(para("The repository is organized as a full-stack system. RTL modules live under rtl/RV32I, firmware and build scripts live under sw, and simulation scripts connect the compiled firmware.hex image to the instruction memory."))
    parts.append(table(
        ["Layer", "Main files", "Responsibility"],
        [
            ["Datapath", "riscv_fetch_stage.sv, riscv_decode_stage.sv, riscv_execute_stage.sv, riscv_memory_stage.sv", "Move instructions and operands through the five pipeline stages."],
            ["Control", "riscv_control_unit.sv, riscv_hazard_unit.sv, riscv_pc_src_controller.sv", "Decode operations, resolve hazards, and select the correct next PC."],
            ["Privilege", "riscv_csr_unit.sv, riscv_top_pipeline.sv", "Store CSR state, detect traps, route handlers, and restore privilege state."],
            ["Software", "start.s, main.c, linker.ld", "Boot the machine, install trap vectors, and run the demo firmware."],
            ["Application", "Snake game and virtual UART", "Render a terminal game and accept keyboard input through MMIO."],
        ],
    ))
    parts.append(heading("High-Level Execution Flow", 2))
    for line in [
        "C / assembly source",
        "  -> RISC-V GCC and linker",
        "  -> sw/build/firmware.elf",
        "  -> sw/build/firmware.hex",
        "  -> instruction memory",
        "  -> five-stage core",
        "  -> data memory / MMIO UART",
        "  -> simulator terminal and keyboard feeder",
    ]:
        parts.append(code_line(line))

    parts.append(heading("3. Implementation of the Base Integer Pipeline"))
    parts.append(para("The processor follows the classic five-stage structure: Instruction Fetch, Instruction Decode, Execute, Memory, and Writeback. Pipeline registers carry instruction fields, operand values, control signals, PC values, and exception metadata between stages."))
    parts.append(table(
        ["Stage", "Name", "Main responsibility"],
        [
            ["IF", "Instruction Fetch", "Maintain PC, read instruction memory, compute PC + 4, accept redirects."],
            ["ID", "Instruction Decode", "Decode opcode/funct fields, read x-registers, generate immediates and controls."],
            ["EX", "Execute", "Run the ALU, compare branches, calculate targets, apply forwarding."],
            ["MEM", "Memory", "Perform load/store accesses and align/sign-extend loaded data."],
            ["WB", "Writeback", "Select ALU, memory, CSR, or PC+4 result and write rd."],
        ],
    ))
    parts.append(heading("Register File and Immediate Generation", 2))
    parts.append(para("The integer register file contains thirty-two 32-bit registers. Register x0 is hardwired to zero. The decode stage reads rs1 and rs2, while writeback updates rd when RegWrite is asserted. The implementation writes on the falling edge, which helps the simple pipeline observe newly written values without adding extra complexity."))
    parts.append(image("rId17", "Figure 1. Register file structure used by the integer datapath.", 1))
    parts.append(para("Immediate generation is separated into riscv_extend.sv. It reconstructs I, S, B, U, and J immediates from instruction bit fields and sign-extends them to 32 bits. Keeping this logic isolated makes decode easier to inspect and reduces repeated bit slicing across the datapath."))
    parts.append(image("rId37", "Figure 2. Immediate extension logic for RISC-V instruction formats.", 2))
    parts.append(heading("Execute Stage", 2))
    parts.append(para("The execute stage receives decoded ALU controls, register operands, immediates, and forwarded data. It performs arithmetic, logical operations, branch comparisons, jump target calculation, and memory address generation."))
    parts.append(image("rId38", "Figure 3. ALU block diagram.", 3))
    parts.append(image("rId39", "Figure 4. Branch unit block diagram.", 4))
    parts.append(heading("Memory and Writeback", 2))
    parts.append(para("The memory stage accesses riscv_data_mem.sv. It supports byte, halfword, and word transfers and includes the virtual UART address used by the Snake demo. The writeback stage selects the final register value from the ALU result, loaded memory data, CSR read data, or PC + 4 for link instructions."))

    parts.append(heading("4. Hazard and Control Flow Management"))
    parts.append(para("Pipelining improves throughput by overlapping instructions, but it introduces hazards. The hazard unit resolves read-after-write dependencies through forwarding from later stages into Execute. When a load-use dependency cannot be forwarded in time, the unit stalls Fetch and Decode and flushes Execute for one cycle."))
    parts.append(para("Control hazards are handled by flushing wrong-path instructions after a taken branch, jump, exception, interrupt, or trap return. Privileged redirects have high priority because a trap must enter the handler precisely and must not allow younger instructions to commit incorrect state."))
    parts.append(table(
        ["Hazard type", "Example", "Resolution"],
        [
            ["ALU RAW", "add x5,... followed by sub using x5", "Forward from MEM/WB to Execute input."],
            ["Load-use", "lw x5,0(x1) followed immediately by add using x5", "Stall PC and IF/ID, flush ID/EX."],
            ["Taken branch/jump", "beq taken or jal/jalr", "Flush younger wrong-path instructions."],
            ["Trap/return", "ecall, interrupt, mret, sret", "CSR unit overrides next PC and flushes pipeline."],
        ],
    ))

    parts.append(heading("5. Implementation of the Privileged ISA Subset"))
    parts.append(para("The CSR unit is the privileged-control center of the core. It handles CSR reads and writes, checks CSR address permissions, evaluates exceptions and interrupts, records trap state, updates privilege stacks, and requests PC redirection to mtvec, stvec, mepc, or sepc."))
    parts.append(image("rId154", "Figure 5. Software implementation stack for privileged execution.", 5))
    parts.append(image("rId155", "Figure 6. CSR unit block diagram.", 6))
    parts.append(heading("Privilege Modes", 2))
    parts.append(table(
        ["Mode", "Encoding", "Implementation status", "Purpose"],
        [
            ["User", "00", "Partial state value only", "Can be restored by return state, but no full U-mode CSR model exists."],
            ["Supervisor", "01", "Implemented", "Provides S-mode trap CSRs and delegated trap handling."],
            ["Reserved", "10", "Unused", "Should not be entered by software."],
            ["Machine", "11", "Implemented", "Reset mode and highest privilege level."],
        ],
    ))
    parts.append(para("The core boots in Machine mode. Machine mode can configure trap vectors, delegation registers, interrupt enables, timers, and previous-privilege fields. Supervisor mode receives delegated traps and sees restricted S-mode CSR views such as sstatus, sie, sip, stvec, sepc, and scause."))
    parts.append(image("rId156", "Figure 7. misa register format.", 7))
    parts.append(image("rId157", "Figure 8. mstatus privilege and interrupt stack fields.", 8))

    parts.append(heading("6. CSR Register Reference"))
    parts.append(para("The implementation is not a generic 4096-entry CSR RAM. Instead, riscv_csr_unit.sv explicitly decodes supported CSR addresses. This is simpler, easier to verify, and appropriate for an educational core."))
    parts.append(table(
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
    parts.append(image("rId158", "Figure 9. mie/mip interrupt enable and pending fields.", 9))
    parts.append(image("rId160", "Figure 10. sstatus supervisor view.", 10))
    parts.append(image("rId161", "Figure 11. sip/sie supervisor interrupt views.", 11))
    parts.append(heading("CSR Instructions", 2))
    parts.append(para("The Zicsr instruction family lets software read, write, set, and clear CSR bits using either register operands or immediate fields. The CSR unit checks whether the instruction is active, whether the address exists, whether the current privilege is high enough for the CSR address, and whether software is attempting to write a read-only CSR."))
    parts.append(image("rId162", "Figure 12. CSR instruction family.", 12))
    parts.append(table(
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

    parts.append(heading("7. Trap, Interrupt, and Return Flow"))
    parts.append(para("Trap handling is where the ordinary pipeline and privileged architecture meet. The pipeline reports exceptions such as illegal instruction, instruction address misalignment, ecall, ebreak, load access fault, and store access fault. The CSR unit also evaluates timer and external interrupt requests."))
    parts.append(para("If a trap is taken to Machine mode, the unit writes mepc and mcause, saves the old privilege mode in mstatus.MPP, saves MIE into MPIE, clears MIE, switches to Machine mode, and redirects the PC to mtvec. If the trap is delegated to Supervisor mode, the equivalent sepc/scause/SPP/SPIE/SIE/stvec path is used."))
    parts.append(image("rId163", "Figure 13. Trap entry and return flow.", 13))
    parts.append(table(
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
    parts.append(heading("Trap Return", 2))
    parts.append(para("mret restores the privilege mode from mstatus.MPP, restores MIE from MPIE, sets MPIE, clears MPP, and redirects the PC to mepc. sret restores privilege from SPP, restores SIE from SPIE, sets SPIE, clears SPP, and redirects the PC to sepc. The top-level pipeline treats both instructions as PC override events."))

    parts.append(heading("8. Software Stack and Snake OS Demo"))
    parts.append(para("The software side demonstrates that the hardware can run real firmware rather than only isolated instruction tests. The mixed C/assembly flow builds start.s and main.c into firmware.elf and then converts it into firmware.hex for instruction memory."))
    parts.append(heading("Boot and Trap Handlers", 2))
    parts.append(para("The startup assembly exposes m_trap_handler and s_trap_handler. The C firmware programs mtvec and stvec with their addresses. On an exception, the handlers inspect the cause, advance the saved EPC when appropriate, perform simple service work, and return with mret or sret."))
    parts.append(heading("Virtual UART MMIO", 2))
    parts.append(para("The Snake demo uses a virtual UART in riscv_data_mem.sv. The UART address is 0x00003FF0. A store byte to this address prints a character in the simulator terminal. A load byte reads one key from sw/input.txt through the keyboard feeder script."))
    parts.append(table(
        ["Address", "Access", "Behavior"],
        [
            ["0x00003FF0", "Store byte", "Transmit character to simulator console."],
            ["0x00003FF0", "Load byte", "Read one keyboard character from the feeder file."],
            ["0x00003FFC", "Platform address", "Reserved platform/status location in data memory."],
        ],
    ))
    parts.append(heading("Snake Application", 2))
    parts.append(para("The C application renders an ASCII Snake board. The snake head is '@', body cells are 'o', and food is '*'. The game accepts W/A/S/D movement controls and Q for reset. It is small, visible, and useful: if the pipeline, memory, CSR setup, or build flow fails, the demo quickly exposes the problem."))

    parts.append(heading("9. Build, Simulation, and Verification"))
    parts.append(heading("Compilation Flow", 2))
    for line in [
        "cd sw",
        ".\\build.ps1",
        "python elf2hex.py build/firmware.elf build/firmware.hex",
        ".\\run_xsim.bat",
    ]:
        parts.append(code_line(line))
    parts.append(para("The build scripts target rv32i_zicsr with the ilp32 ABI and no standard library. The linker script controls the bare-metal memory map, and firmware.hex is loaded by the RTL instruction memory."))
    parts.append(heading("Verification Strategy", 2))
    parts.append(image("rId175", "Figure 14. Verification plan reference.", 14))
    parts.append(para("Verification is organized around direct pipeline tests, CSR/privilege assembly tests, C/assembly firmware tests, and full-system Snake execution. Direct tests are useful for deterministic instruction behavior. The full-system test is useful for integration because it exercises instruction fetch, decode, ALU operations, memory access, MMIO, trap vector setup, and software loops together."))
    parts.append(table(
        ["Test area", "Evidence to inspect", "Expected result"],
        [
            ["RV32I datapath", "riscv_test.s, waveforms, register traces", "Arithmetic, branches, loads, stores, and writeback agree with expected values."],
            ["Hazard unit", "Forwarding and stall signals", "RAW dependencies resolve; load-use hazards insert one bubble."],
            ["CSR instructions", "mscratch/mstatus/mtvec reads and writes", "CSR read-modify-write instructions return old value and update selected bits."],
            ["Trap handling", "mepc, mcause, sepc, scause, PC redirect", "Handler address is selected and return resumes at the saved PC."],
            ["Snake demo", "Simulator terminal", "Game board renders and keyboard input changes direction."],
        ],
    ))

    parts.append(heading("10. Limitations, Future Work, and Conclusion"))
    parts.append(heading("Current Limitations", 2))
    for item in [
        "The system is RV32-oriented and should not be described as a finished 64-bit Linux-capable IMAC core.",
        "satp reads as zero and virtual memory/page-table translation is not implemented.",
        "User mode exists mainly as a privilege encoding that can be restored, not as a complete application isolation environment.",
        "The virtual UART is implemented inside data memory for simulation convenience.",
        "The timer is implemented inside the CSR unit rather than as a platform CLINT/ACLINT device.",
    ]:
        parts.append(bullet(item))
    parts.append(heading("Future Work", 2))
    for item in [
        "Move MMIO behind a dedicated bus decoder.",
        "Add a real platform interrupt controller and cleaner interrupt acknowledge protocol.",
        "Implement timer-driven context switching with complete register save/restore.",
        "Add user-mode task entry and protection checks.",
        "Extend the memory system toward instruction/data caches once the base privilege path is stable.",
        "Automate regression tests for CSR corner cases, delegation, and trap return sequencing.",
    ]:
        parts.append(bullet(item))
    parts.append(heading("Conclusion", 2))
    parts.append(para("From Gates to Games is best understood as a working hardware/software integration project. The RTL core provides a five-stage RV32I pipeline, the CSR unit adds privileged control and trap semantics, and the software stack proves the design by running a visible game through a simulated device interface."))
    parts.append(para("The result is not just a CPU block diagram. It is a small platform: firmware is compiled, loaded, executed, interrupted, and observed. That makes the project suitable for explanation, demonstration, and future extension toward a more complete operating-system-capable RISC-V system."))

    parts.append(heading("References"))
    for item in [
        "The RISC-V Instruction Set Manual, Volume I: Unprivileged Architecture.",
        "The RISC-V Instruction Set Manual, Volume II: Privileged Architecture.",
        "rtl/RV32I/CSR_UNIT_REFERENCE_MANUAL.md.",
        "rtl/RV32I/explain_Privilege.md.",
        "sw/SNAKE_OS_GUIDE.md.",
        "RISCV-MicroKernel-Architecture repository RTL and software sources.",
        "Reference thesis: From Gates to OS: Design and Implementation of a 64-bit RISC-V IMAC Core with Privilege Modes and Level-1 Caches Capable of Running OS.",
    ]:
        parts.append(bullet(item))

    sect_pr = """
<w:sectPr>
  <w:pgSz w:w="11906" w:h="16838"/>
  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
  <w:cols w:space="708"/>
  <w:docGrid w:linePitch="360"/>
</w:sectPr>
"""
    return "".join(parts) + sect_pr


def document_xml() -> str:
    ns_attrs = " ".join(f'xmlns:{prefix}="{uri}"' for prefix, uri in NS.items())
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:document {ns_attrs} mc:Ignorable="w14 wp14">'
        f"<w:body>{build_body()}</w:body>"
        "</w:document>"
    )


def main() -> None:
    if not REFERENCE_DOCX.exists():
        raise FileNotFoundError(f"Reference document not found: {REFERENCE_DOCX}")

    xml = document_xml().encode("utf-8")
    temp_output = OUTPUT_DOCX.with_suffix(".tmp.docx")
    if temp_output.exists():
        temp_output.unlink()

    with zipfile.ZipFile(REFERENCE_DOCX, "r") as src, zipfile.ZipFile(temp_output, "w", zipfile.ZIP_DEFLATED) as dst:
        for item in src.infolist():
            if item.filename == "word/document.xml":
                dst.writestr(item, xml)
            elif item.filename == "docProps/core.xml":
                core = src.read(item.filename).decode("utf-8", errors="ignore")
                core = core.replace(
                    "From Gates to OS: Design and Implementation of a 64-bit RISC-V IMAC Core with Privilege Modes and Level-1 Caches Capable of Running OS",
                    "From Gates to Games: Design and Implementation of a 32-bit RISC-V Pipelined Core with CSR Privilege Support and a Bare-Metal Snake OS Demo",
                )
                dst.writestr(item, core.encode("utf-8"))
            else:
                dst.writestr(item, src.read(item.filename))

    if OUTPUT_DOCX.exists():
        OUTPUT_DOCX.unlink()
    os.replace(temp_output, OUTPUT_DOCX)
    print(OUTPUT_DOCX)


if __name__ == "__main__":
    main()
