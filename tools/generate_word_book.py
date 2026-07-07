from __future__ import annotations

import html
import re
import shutil
import zipfile
from datetime import datetime
from pathlib import Path

import fitz
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "build" / "book_pretty"
OUT_DOCX = ROOT / "From Gates to Games - Project Book PRETTY.docx"

REFERENCE_DOCX = Path(
    r"C:\Users\ABDOU\Desktop\GP_folder\From Gates to OS Design and Implementation of a 64-bit RISC-V IMAC Core with Privilege Modes and Level-1 Caches Capable of Running OS.docx"
)
ARCH_PDF = Path(r"C:\Users\ABDOU\Desktop\GP_folder\RISC-V Complete Arch.drawio (1).pdf")
REF_MEDIA = ROOT / "build" / "reference_docx_media"

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
WP_NS = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
PIC_NS = "http://schemas.openxmlformats.org/drawingml/2006/picture"


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    files = [
        r"C:\Windows\Fonts\calibrib.ttf" if bold else r"C:\Windows\Fonts\calibri.ttf",
        r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf",
    ]
    for item in files:
        try:
            return ImageFont.truetype(item, size)
        except OSError:
            pass
    return ImageFont.load_default()


def center(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str,
           size: int = 28, bold: bool = True, color: str = "#0F172A") -> None:
    fnt = load_font(size, bold)
    lines = text.split("\n")
    metrics = [draw.textbbox((0, 0), line, font=fnt) for line in lines]
    heights = [b[3] - b[1] for b in metrics]
    widths = [b[2] - b[0] for b in metrics]
    total_h = sum(heights) + 8 * (len(lines) - 1)
    y = box[1] + ((box[3] - box[1]) - total_h) // 2
    for line, w, h in zip(lines, widths, heights):
        x = box[0] + ((box[2] - box[0]) - w) // 2
        draw.text((x, y), line, font=fnt, fill=color)
        y += h + 8


def arrow(draw: ImageDraw.ImageDraw, start: tuple[int, int], end: tuple[int, int],
          color: str = "#334155", width: int = 5) -> None:
    draw.line([start, end], fill=color, width=width)
    x1, y1 = start
    x2, y2 = end
    if abs(x2 - x1) >= abs(y2 - y1):
        if x2 >= x1:
            pts = [(x2, y2), (x2 - 18, y2 - 10), (x2 - 18, y2 + 10)]
        else:
            pts = [(x2, y2), (x2 + 18, y2 - 10), (x2 + 18, y2 + 10)]
    else:
        if y2 >= y1:
            pts = [(x2, y2), (x2 - 10, y2 - 18), (x2 + 10, y2 - 18)]
        else:
            pts = [(x2, y2), (x2 - 10, y2 + 18), (x2 + 10, y2 + 18)]
    draw.polygon(pts, fill=color)


def rounded_box(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str,
                fill: str, outline: str, text_color: str = "#0F172A", size: int = 27) -> None:
    draw.rounded_rectangle(box, radius=20, fill=fill, outline=outline, width=4)
    center(draw, box, text, size=size, bold=True, color=text_color)


def render_architecture_pdf() -> tuple[Path, tuple[int, int]]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / "fig01_full_architecture.png"
    doc = fitz.open(ARCH_PDF)
    page = doc[0]
    pix = page.get_pixmap(matrix=fitz.Matrix(3, 3), alpha=False)
    pix.save(out)
    doc.close()
    with Image.open(out) as img:
        return out, img.size


def make_pipeline_diagram() -> tuple[Path, tuple[int, int]]:
    out = OUT_DIR / "fig02_pipeline.png"
    img = Image.new("RGB", (1800, 760), "#FFFFFF")
    d = ImageDraw.Draw(img)
    d.text((70, 45), "Processor Datapath: 5-Stage Pipeline", font=load_font(48, True), fill="#0F172A")
    stages = [
        ("IF", "PC selection\nInstruction memory"),
        ("ID", "Decode\nRegister read"),
        ("EX", "ALU\nBranch target"),
        ("MEM", "Data memory\nCSR decisions"),
        ("WB", "Result mux\nRegister write"),
    ]
    x0, y0, w, h, gap = 80, 175, 270, 150, 75
    for i, (name, desc) in enumerate(stages):
        x = x0 + i * (w + gap)
        rounded_box(d, (x, y0, x + w, y0 + h), f"{name}\n{desc}", "#E0F2FE", "#0284C7", "#0C4A6E", 26)
        if i < len(stages) - 1:
            arrow(d, (x + w + 8, y0 + h // 2), (x + w + gap - 8, y0 + h // 2), "#0F766E")
    rounded_box(d, (185, 430, 770, 545), "Hazard Unit\nForwarding, load-use stall, branch/trap flush", "#FEF3C7", "#D97706", "#7C2D12", 26)
    rounded_box(d, (1030, 430, 1610, 545), "CSR / Privilege Unit\nTrap vectors, EPC, cause, return control", "#FCE7F3", "#DB2777", "#831843", 26)
    arrow(d, (475, 430), (620, 325), "#B45309")
    arrow(d, (1320, 430), (1160, 325), "#BE185D")
    d.text((80, 640), "The pipeline overlaps instructions while control logic preserves precise architectural behavior.",
           font=load_font(30, False), fill="#334155")
    img.save(out)
    return out, img.size


def make_memory_diagram() -> tuple[Path, tuple[int, int]]:
    out = OUT_DIR / "fig03_memory_mmio.png"
    img = Image.new("RGB", (1700, 760), "#FFFFFF")
    d = ImageDraw.Draw(img)
    d.text((70, 45), "Memory and MMIO Organization", font=load_font(48, True), fill="#0F172A")
    rounded_box(d, (90, 180, 420, 300), "CPU MEM stage\nload/store request", "#E0F2FE", "#0284C7", "#0C4A6E")
    rounded_box(d, (585, 180, 940, 300), "Address check\nalignment + range", "#F8FAFC", "#64748B", "#1E293B")
    rounded_box(d, (1110, 95, 1530, 215), "Data RAM\nbyte / half / word", "#DCFCE7", "#16A34A", "#14532D")
    rounded_box(d, (1110, 295, 1530, 415), "UART MMIO\n0x00003FF0", "#FEF3C7", "#D97706", "#7C2D12")
    rounded_box(d, (1110, 495, 1530, 615), "Platform ID\n0x00003FFC", "#EDE9FE", "#7C3AED", "#4C1D95")
    arrow(d, (420, 240), (585, 240))
    arrow(d, (940, 240), (1110, 155))
    arrow(d, (940, 240), (1110, 355))
    arrow(d, (940, 240), (1110, 555))
    d.text((90, 655), "Current implementation keeps MMIO inside data memory for simulation. A later bus decoder should separate RAM and peripherals.",
           font=load_font(29, False), fill="#334155")
    img.save(out)
    return out, img.size


def make_trap_diagram() -> tuple[Path, tuple[int, int]]:
    out = OUT_DIR / "fig04_trap_flow.png"
    img = Image.new("RGB", (1700, 850), "#FFFFFF")
    d = ImageDraw.Draw(img)
    d.text((70, 45), "Precise Trap and Return Flow", font=load_font(48, True), fill="#0F172A")
    rounded_box(d, (610, 145, 1090, 250), "Exception / interrupt\nreaches MEM stage", "#FEE2E2", "#DC2626", "#7F1D1D")
    rounded_box(d, (610, 335, 1090, 440), "CSR trap arbiter\ncause + target mode", "#FEF3C7", "#D97706", "#7C2D12")
    rounded_box(d, (155, 570, 605, 700), "Machine route\nmepc, mcause, mtval\nfetch from mtvec", "#E0F2FE", "#0284C7", "#0C4A6E")
    rounded_box(d, (1095, 570, 1545, 700), "Supervisor route\nsepc, scause, stval\nfetch from stvec", "#DCFCE7", "#16A34A", "#14532D")
    rounded_box(d, (610, 695, 1090, 800), "Flush younger instructions\nredirect PC", "#EDE9FE", "#7C3AED", "#4C1D95")
    arrow(d, (850, 250), (850, 335), "#991B1B")
    arrow(d, (720, 440), (420, 570), "#334155")
    arrow(d, (980, 440), (1280, 570), "#334155")
    arrow(d, (605, 650), (610, 745), "#334155")
    arrow(d, (1095, 650), (1090, 745), "#334155")
    img.save(out)
    return out, img.size


def make_software_diagram() -> tuple[Path, tuple[int, int]]:
    out = OUT_DIR / "fig05_software_flow.png"
    img = Image.new("RGB", (1700, 760), "#FFFFFF")
    d = ImageDraw.Draw(img)
    d.text((70, 45), "Bare-Metal Software Stack", font=load_font(48, True), fill="#0F172A")
    labels = [
        ("Reset", "PC = 0"),
        ("_start", "set stack"),
        ("main()", "install vectors"),
        ("Snake OS", "input / step / render"),
        ("MMIO UART", "terminal I/O"),
    ]
    x, y, w, h, gap = 90, 220, 245, 130, 75
    for i, (a, b) in enumerate(labels):
        x0 = x + i * (w + gap)
        rounded_box(d, (x0, y, x0 + w, y + h), f"{a}\n{b}", "#ECFDF5", "#059669", "#064E3B", 26)
        if i < len(labels) - 1:
            arrow(d, (x0 + w + 8, y + h // 2), (x0 + w + gap - 8, y + h // 2), "#047857")
    rounded_box(d, (360, 500, 1340, 620), "The application runs directly on the custom processor and uses memory-mapped I/O for the visible game demo.",
                "#F8FAFC", "#64748B", "#334155", 29)
    img.save(out)
    return out, img.size


def copy_reference_image(name: str, target: str) -> tuple[Path, tuple[int, int]]:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    src = REF_MEDIA / name
    out = OUT_DIR / target
    shutil.copyfile(src, out)
    with Image.open(out) as img:
        return out, img.size


def build_figures() -> dict[str, tuple[Path, tuple[int, int], str]]:
    figures: dict[str, tuple[Path, tuple[int, int], str]] = {}
    path, size = render_architecture_pdf()
    figures["full_arch"] = (path, size, "Figure 1. Full hardware architecture from the project Draw.io design.")
    for key, maker, caption in [
        ("pipeline", make_pipeline_diagram, "Figure 2. Project-specific 5-stage pipeline organization."),
        ("memory", make_memory_diagram, "Figure 3. Current RAM/MMIO organization used by the bare-metal game."),
        ("trap", make_trap_diagram, "Figure 4. Precise trap routing through the CSR and privilege unit."),
        ("software", make_software_diagram, "Figure 5. Bare-metal boot and Snake OS execution path."),
    ]:
        p, s = maker()
        figures[key] = (p, s, caption)
    for key, src, dst, caption in [
        ("os_layers", "image147.png", "fig06_os_layers.png", "Figure 6. Reference OS/ABI/SBI/SEE layering model from the comparison document."),
        ("c_formats", "image70.png", "fig07_c_formats.png", "Figure 7. Reference compressed-instruction format overview."),
        ("csr_instr", "image155.png", "fig08_csr_instr.png", "Figure 8. Reference CSR instruction format overview."),
        ("cache_hierarchy", "image74.jpeg", "fig09_cache_hierarchy.jpeg", "Figure 9. Reference memory-hierarchy motivation for cache work."),
        ("cache_mapping", "image78.jpeg", "fig10_cache_mapping.jpeg", "Figure 10. Reference cache lookup/mapping concepts."),
        ("branch_fsm", "image143.jpeg", "fig11_branch_fsm.jpeg", "Figure 11. Reference two-bit branch-predictor state machine."),
    ]:
        p, s = copy_reference_image(src, dst)
        figures[key] = (p, s, caption)
    return figures


def run(text: str, bold: bool = False, italic: bool = False, color: str | None = None,
        size: int | None = None, mono: bool = False) -> str:
    props = []
    if bold:
        props.append("<w:b/>")
    if italic:
        props.append("<w:i/>")
    if color:
        props.append(f'<w:color w:val="{color}"/>')
    if size:
        props.append(f'<w:sz w:val="{size * 2}"/>')
    if mono:
        props.append('<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/>')
    rpr = f"<w:rPr>{''.join(props)}</w:rPr>" if props else ""
    preserve = ' xml:space="preserve"' if text.startswith(" ") or text.endswith(" ") else ""
    return f"<w:r>{rpr}<w:t{preserve}>{esc(text)}</w:t></w:r>"


def para(text: str = "", style: str | None = None, align: str | None = None,
         bold: bool = False, color: str | None = None, size: int | None = None) -> str:
    props = []
    if style:
        props.append(f'<w:pStyle w:val="{style}"/>')
    if align:
        props.append(f'<w:jc w:val="{align}"/>')
    ppr = f"<w:pPr>{''.join(props)}</w:pPr>" if props else ""
    return f"<w:p>{ppr}{run(text, bold=bold, color=color, size=size)}</w:p>"


def title(text: str) -> str:
    return para(text, align="center", bold=True, color="1F4E79", size=28)


def subtitle(text: str) -> str:
    return para(text, align="center", color="595959", size=15)


def h1(text: str) -> str:
    return para(text, style="Heading1")


def h2(text: str) -> str:
    return para(text, style="Heading2")


def h3(text: str) -> str:
    return para(text, style="Heading3")


def bullet(text: str) -> str:
    return para("- " + text, style="ListParagraph")


def numbered(n: int, text: str) -> str:
    return para(f"{n}. {text}", style="ListParagraph")


def page_break() -> str:
    return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'


def table(rows: list[list[str]]) -> str:
    cols = max(len(r) for r in rows)
    width = max(1200, 9000 // cols)
    out = [
        '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" '
        'w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr>'
        + "<w:tblGrid>"
        + "".join(f'<w:gridCol w:w="{width}"/>' for _ in range(cols))
        + "</w:tblGrid>"
    ]
    for i, row in enumerate(rows):
        out.append("<w:tr>")
        for cell in row + [""] * (cols - len(row)):
            fill = '<w:shd w:val="clear" w:color="auto" w:fill="D9EAF7"/>' if i == 0 else ""
            out.append(f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/>{fill}</w:tcPr>{para(cell)}</w:tc>')
        out.append("</w:tr>")
    out.append("</w:tbl>")
    return "".join(out) + para("")


def code(lines: list[str]) -> str:
    out = []
    for line in lines:
        out.append(
            '<w:p><w:pPr><w:pStyle w:val="NoSpacing"/>'
            '<w:shd w:val="clear" w:color="auto" w:fill="F3F4F6"/></w:pPr>'
            + run(line, mono=True, size=9)
            + "</w:p>"
        )
    return "".join(out) + para("")


def image_xml(rid: str, size: tuple[int, int], caption: str) -> str:
    width_px, height_px = size
    max_width_emu = 6_350_000
    max_height_emu = 4_750_000
    ratio = height_px / max(width_px, 1)
    cx = max_width_emu
    cy = int(cx * ratio)
    if cy > max_height_emu:
        cy = max_height_emu
        cx = int(cy / ratio)
    return f"""
<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>
<wp:inline distT="0" distB="0" distL="0" distR="0">
<wp:extent cx="{cx}" cy="{cy}"/>
<wp:effectExtent l="0" t="0" r="0" b="0"/>
<wp:docPr id="{abs(hash(rid)) % 100000}" name="{rid}"/>
<wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="{A_NS}" noChangeAspect="1"/></wp:cNvGraphicFramePr>
<a:graphic xmlns:a="{A_NS}"><a:graphicData uri="{PIC_NS}">
<pic:pic xmlns:pic="{PIC_NS}">
<pic:nvPicPr><pic:cNvPr id="0" name="{rid}"/><pic:cNvPicPr/></pic:nvPicPr>
<pic:blipFill><a:blip r:embed="{rid}" xmlns:r="{R_NS}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
</pic:pic></a:graphicData></a:graphic>
</wp:inline></w:drawing></w:r></w:p>
{para(caption, style="Caption", align="center")}
"""


class Book:
    def __init__(self, figures: dict[str, tuple[Path, tuple[int, int], str]]):
        self.parts: list[str] = []
        self.figures = figures
        self.used: dict[str, Path] = {}

    def add(self, xml: str) -> None:
        self.parts.append(xml)

    def fig(self, key: str) -> None:
        path, size, caption = self.figures[key]
        rid = "rIdFig" + re.sub(r"[^A-Za-z0-9]", "", key)
        self.parts.append(image_xml(rid, size, caption))
        self.used[rid] = path

    def xml(self) -> str:
        return "".join(self.parts)


def build_book(figures: dict[str, tuple[Path, tuple[int, int], str]]) -> tuple[str, dict[str, Path]]:
    b = Book(figures)

    b.add(title("From Gates to Games"))
    b.add(subtitle("Full-Stack Co-Design of a 5-Stage Pipelined RISC-V Processor and Bare-Metal Microkernel"))
    b.add(para(""))
    b.add(subtitle("Project Book / White Paper"))
    b.add(subtitle("RISCV-MicroKernel-Architecture"))
    b.add(subtitle(f"Generated {datetime.now():%d %B %Y}"))
    b.add(page_break())

    b.add(h1("Abstract"))
    b.add(para("This book documents our current RISC-V hardware/software design. The project combines a 5-stage pipelined processor, CSR and privilege support, memory and MMIO behavior, bare-metal startup code, trap handling, and an interactive Snake game used as a full-system demonstration."))
    b.add(para("The document is written as a white paper and project book. It explains the parts currently represented in this repository in detail, while C extension, M extension, caches, and branch prediction are included as system-level sections because those detailed chapters are expected to be written by their responsible contributors."))
    b.add(table([
        ["Area", "Current book treatment"],
        ["Processor", "Detailed 5-stage pipeline, hazards, memory, CSR, trap flow"],
        ["Software", "Detailed boot, trap handlers, MMIO, Snake OS demo"],
        ["C extension / M extension", "White-paper integration overview"],
        ["Caches / branch prediction", "White-paper integration overview with reference diagrams"],
    ]))
    b.add(page_break())

    b.add(h1("Table of Contents"))
    for i, item in enumerate([
        "Project Scope and Design Philosophy",
        "Complete Hardware Architecture",
        "Five-Stage Pipeline",
        "Hazards, Forwarding, and Control Flow",
        "Memory, MMIO, and Firmware Interface",
        "CSR and Privilege Architecture",
        "Bare-Metal Software and Snake OS",
        "Shared White-Paper Topics",
        "Verification and Project Evidence",
        "Roadmap and Conclusion",
    ], 1):
        b.add(numbered(i, item))
    b.add(page_break())

    b.add(h1("1. Project Scope and Design Philosophy"))
    b.add(para("The project is a full-stack RISC-V system. It is not only a processor core and not only a software demo. The central idea is that hardware and software are designed together until a visible application runs on the custom machine."))
    for item in [
        "The datapath must execute real compiled code.",
        "The control system must handle pipeline hazards and precise redirection.",
        "The CSR unit must provide the privileged foundation needed for traps and OS-style behavior.",
        "The software must prove the machine through long-running, interactive behavior.",
    ]:
        b.add(bullet(item))
    b.add(para("The Snake game is therefore a useful milestone. It uses arrays, loops, branches, loads, stores, stack behavior, terminal output, and keyboard input. A core that can run it reliably is already exercising more than isolated instruction tests."))

    b.add(h1("2. Complete Hardware Architecture"))
    b.add(para("The following figure is the full architecture diagram provided with the project. It is used as the primary hardware reference for this book."))
    b.fig("full_arch")
    b.add(para("At a system level, the design connects instruction fetch, decode, execute, memory, writeback, CSR control, and supporting memories. The architecture is intentionally modular: each stage and functional unit can be tested independently, while the top-level pipeline integrates them into a working processor."))
    b.add(table([
        ["Module group", "Role"],
        ["Fetch and instruction memory", "Maintain PC and supply instructions"],
        ["Decode and register file", "Generate control and read operands"],
        ["Execute and ALU", "Compute arithmetic, branch targets, and effective addresses"],
        ["Memory and MMIO", "Perform load/store behavior and terminal I/O"],
        ["CSR and privilege", "Handle traps, exceptions, interrupts, and returns"],
        ["Hazard logic", "Preserve correctness under pipeline overlap"],
    ]))

    b.add(h1("3. Five-Stage Pipeline"))
    b.fig("pipeline")
    b.add(para("The processor follows the classic five-stage organization: Instruction Fetch, Instruction Decode, Execute, Memory, and Writeback. This structure gives a clear separation between program-counter control, instruction decoding, ALU work, memory access, and architectural state update."))
    b.add(table([
        ["Stage", "Main work", "Important outputs"],
        ["IF", "Select PC and fetch instruction", "Instruction, PC, PC+4"],
        ["ID", "Decode instruction and read registers", "Control signals, operands, immediate"],
        ["EX", "ALU operation and branch target calculation", "ALU result, target address, branch decision"],
        ["MEM", "Data memory access and CSR/trap decision", "Load data, fault flags, CSR redirect"],
        ["WB", "Select result and write register file", "Final writeback value"],
    ]))
    b.add(h2("Instruction Decode Coverage"))
    b.add(table([
        ["Instruction family", "Examples", "Purpose"],
        ["R-type", "add, sub, and, or, xor", "Register-register ALU operations"],
        ["I-type", "addi, andi, ori, shifts", "Immediate ALU operations"],
        ["Loads/stores", "lb, lh, lw, sb, sh, sw", "Data memory access"],
        ["Control flow", "beq, bne, jal, jalr", "PC changes"],
        ["SYSTEM/CSR", "ecall, ebreak, mret, sret, csrrw", "Privilege and control state"],
    ]))

    b.add(h1("4. Hazards, Forwarding, and Control Flow"))
    b.add(para("Pipeline overlap creates hazards. The design handles these hazards with forwarding, stalls, and flushes. Forwarding allows a result from a later pipeline stage to feed an earlier Execute-stage operand without waiting for writeback. Load-use hazards require a one-cycle bubble because the loaded value is not available early enough for the immediately following Execute stage."))
    b.add(table([
        ["Hazard", "Cause", "Resolution"],
        ["ALU data hazard", "Consumer follows producer before writeback", "Forward from MEM/WB into EX"],
        ["Load-use hazard", "Consumer immediately follows a load", "Stall IF/ID and flush EX"],
        ["Control hazard", "Taken branch or jump changes PC", "Flush wrong-path instructions"],
        ["Trap redirect", "CSR unit redirects to handler or return PC", "Flush younger pipeline work"],
    ]))
    b.add(para("Branch prediction is treated later as a shared white-paper topic. Correctness does not depend on prediction; prediction only reduces the cost of control hazards when guesses are correct."))

    b.add(h1("5. Memory, MMIO, and Firmware Interface"))
    b.fig("memory")
    b.add(para("The current data memory supports byte, halfword, and word accesses. The Snake demo uses memory-mapped I/O at address 0x00003FF0 to communicate with the simulator terminal."))
    b.add(table([
        ["Address", "Access", "Meaning"],
        ["0x00003FF0", "store byte", "Print one character to the simulator terminal"],
        ["0x00003FF0", "load byte", "Read one cached keyboard character"],
        ["0x00003FFC", "load word", "Platform identification register"],
    ]))
    b.add(para("This direct MMIO design is excellent for a working simulation milestone. For the larger SoC direction, RAM and peripherals should be separated behind a bus or address decoder so caches can safely bypass MMIO regions."))

    b.add(h1("6. CSR and Privilege Architecture"))
    b.fig("trap")
    b.add(para("The CSR unit is the privileged-control center of the core. It stores trap vectors, exception PCs, cause registers, interrupt enables, delegation state, and return addresses. It also decides when the pipeline must redirect to a handler or return from a trap."))
    b.add(table([
        ["CSR group", "Examples", "Purpose"],
        ["Trap vectors", "mtvec, stvec", "Handler entry addresses"],
        ["Exception PCs", "mepc, sepc", "Saved interrupted/faulting PC"],
        ["Cause registers", "mcause, scause", "Reason for trap"],
        ["Trap values", "mtval, stval", "Bad instruction or address information"],
        ["Status/control", "mstatus, mie, mip", "Privilege and interrupt control"],
    ]))
    b.fig("csr_instr")
    b.add(para("CSR instructions are decoded from the SYSTEM opcode and allow software to read, write, set, or clear control registers. Illegal CSR access becomes an illegal-instruction exception, which is an important protection rule for privileged software."))

    b.add(h1("7. Bare-Metal Software and Snake OS"))
    b.fig("software")
    b.add(para("The software begins at _start in sw/src/start.s. It sets the stack pointer and calls main. The C program installs mtvec and stvec, initializes the game state, and enters the Snake loop."))
    b.add(table([
        ["File", "Responsibility"],
        ["sw/src/start.s", "Reset entry and trap handlers"],
        ["sw/src/main.c", "Snake game and MMIO runtime"],
        ["sw/linker.ld", "Firmware address layout"],
        ["sw/play_game.py", "Keyboard feeder for RTL simulation"],
        ["sw/build/firmware.hex", "Image loaded by instruction memory/emulator"],
    ]))
    b.add(h2("Snake as a System Test"))
    for item in [
        "It repeatedly executes compiled C control flow.",
        "It exercises byte-level MMIO output and input.",
        "It uses arrays, global variables, branches, and stack behavior.",
        "It provides visible confirmation that the machine is alive.",
    ]:
        b.add(bullet(item))
    b.fig("os_layers")
    b.add(para("The reference OS layering diagram is included to show where our current bare-metal firmware sits in the larger path toward a richer OS. Our current design is closer to the low-level firmware/runtime layer than to a complete hosted operating system."))

    b.add(h1("8. Shared White-Paper Topics"))
    b.add(h2("8.1 C Extension"))
    b.fig("c_formats")
    b.add(para("The C extension introduces 16-bit compressed instruction encodings. At system level, this affects fetch alignment, PC increment selection, decompression/predecode behavior, and branch target rules. The detailed compressed-instruction decoder belongs in the contributor-owned C-extension section."))
    b.add(h2("8.2 M Extension"))
    b.add(para("The M extension adds multiply and divide operations. At system level, this affects Execute-stage structure, ALU-control decoding, possible multi-cycle stalls, forwarding timing, and writeback. The exact multiplier/divider design belongs in the contributor-owned M-extension section."))
    b.add(h2("8.3 Caches"))
    b.fig("cache_hierarchy")
    b.fig("cache_mapping")
    b.add(para("Caches convert the simple memory model into a memory hierarchy. They affect instruction fetch latency, load/store latency, refill behavior, stall logic, and MMIO bypass. The key rule is that normal RAM may be cached, but UART, timer, and platform registers must remain uncached."))
    b.add(h2("8.4 Branch Prediction"))
    b.fig("branch_fsm")
    b.add(para("Branch prediction improves performance by guessing the next PC before a branch is resolved. It is not required for correctness: if a prediction is wrong, the processor must flush the wrong path and continue from the real target. The detailed predictor structure and measurements belong in the contributor-owned branch-prediction section."))

    b.add(h1("9. Verification and Project Evidence"))
    b.add(para("Verification is performed at multiple levels: module-level tests, full pipeline simulation, firmware build inspection, and the interactive Snake demo. The project also keeps disassembly output for software debugging."))
    b.add(table([
        ["Evidence", "What it proves"],
        ["Control and hazard simulations", "Decode and pipeline-control correctness"],
        ["CSR tests and reference manual", "Trap and privilege behavior"],
        ["firmware.dis", "Compiler output and instruction flow"],
        ["Snake demo", "Full-stack hardware/software integration"],
        ["Architecture diagram", "System-level design communication"],
    ]))
    b.add(h2("Recommended Final Checks"))
    for i, item in enumerate([
        "Rebuild firmware.hex from the current software source.",
        "Run the RTL simulation and confirm terminal rendering.",
        "Confirm keyboard input reaches the UART path.",
        "Run targeted hazard/control tests after datapath changes.",
        "Recheck trap behavior after CSR or privilege changes.",
    ], 1):
        b.add(numbered(i, item))

    b.add(h1("10. Roadmap and Conclusion"))
    b.add(para("The project is already beyond a simple datapath exercise. It has a pipelined processor, privileged control, firmware, MMIO, and a visible application. The next step is to keep that full-stack discipline while integrating the shared project features."))
    b.add(table([
        ["Next direction", "Reason"],
        ["Dedicated MMIO decoder", "Separate RAM and peripherals before cache integration"],
        ["Timer interrupt path", "Foundation for scheduling"],
        ["Register save/restore frame", "Needed for interrupt-driven multitasking"],
        ["C/M/cache/branch integration", "Move from base core to richer processor"],
        ["More complete OS boundary", "Move beyond single bare-metal application"],
    ]))
    b.add(para("From gates to games, the project demonstrates the most important engineering idea: a processor becomes meaningful when its hardware decisions are proven by software that actually runs."))
    return b.xml(), b.used


def document_xml(body: str) -> bytes:
    sect = (
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1150" w:right="950" w:bottom="1150" w:left="950" '
        'w:header="720" w:footer="720" w:gutter="0"/>'
        '<w:cols w:space="720"/><w:docGrid w:linePitch="360"/></w:sectPr>'
    )
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="{W_NS}" xmlns:r="{R_NS}" xmlns:wp="{WP_NS}" xmlns:a="{A_NS}" xmlns:pic="{PIC_NS}">
<w:body>{body}{sect}</w:body></w:document>'''.encode("utf-8")


def update_rels(data: bytes, used: dict[str, Path]) -> bytes:
    text = data.decode("utf-8")
    for rid, path in used.items():
        if rid in text:
            continue
        rel = (
            f'<Relationship Id="{rid}" '
            'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
            f'Target="media/{path.name}"/>'
        )
        text = text.replace("</Relationships>", rel + "</Relationships>")
    return text.encode("utf-8")


def ensure_content_types(data: bytes, used: dict[str, Path]) -> bytes:
    text = data.decode("utf-8")
    defaults = {
        "png": "image/png",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
    }
    for ext, ctype in defaults.items():
        if any(p.suffix.lower() == f".{ext}" for p in used.values()) and f'Extension="{ext}"' not in text:
            text = text.replace("</Types>", f'<Default Extension="{ext}" ContentType="{ctype}"/></Types>')
    return text.encode("utf-8")


def build() -> None:
    if not REFERENCE_DOCX.exists():
        raise FileNotFoundError(REFERENCE_DOCX)
    if not ARCH_PDF.exists():
        raise FileNotFoundError(ARCH_PDF)
    if not REF_MEDIA.exists():
        raise FileNotFoundError("Run media extraction first; build/reference_docx_media is missing.")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    figures = build_figures()
    body, used = build_book(figures)
    doc = document_xml(body)

    tmp = OUT_DOCX.with_suffix(".tmp.docx")
    shutil.copyfile(REFERENCE_DOCX, tmp)
    with zipfile.ZipFile(tmp, "r") as zin, zipfile.ZipFile(OUT_DOCX, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "word/document.xml":
                data = doc
            elif item.filename == "word/_rels/document.xml.rels":
                data = update_rels(data, used)
            elif item.filename == "[Content_Types].xml":
                data = ensure_content_types(data, used)
            zout.writestr(item, data)
        for path in used.values():
            zout.writestr(f"word/media/{path.name}", path.read_bytes())
    tmp.unlink(missing_ok=True)
    print(OUT_DOCX)


if __name__ == "__main__":
    build()
