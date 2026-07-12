# RISC-V QEMU OS + GUI

A bare-metal operating system with a **256-colour terminal GUI** designed to run on the **QEMU RISC-V virt machine**, separate from the custom RTL processor. 

Built entirely in C and RISC-V assembly — no standard library, no RTOS, no external dependencies.

---

## Project Layout

```
sw/src/qemu_os/
├── include/
│   └── types.h              Primitive types, MMIO macros, no-stdlib helpers
├── kernel/
│   ├── start.s              RV32IMA boot stub: hart filter, BSS zero, SP setup, trap vectors
│   ├── kernel.h             kernel_main() and syscall_dispatch() declarations
│   └── kernel.c             Boot banner, syscall dispatcher, entry point
├── drivers/
│   ├── uart.h / uart.c      NS16550A UART driver (QEMU virt, 0x10000000)
│   ├── framebuffer.h        80×24 cell-grid API, 256-colour palette constants
│   └── framebuffer.c        Double-buffered diff renderer → ANSI escape sequences
├── gui/
│   ├── gui.h                Window manager API + widget function declarations
│   └── gui.c                Window chrome, two-pass render, widget drawing
├── apps/
│   ├── desktop.h            desktop_run() entry point declaration
│   └── desktop.c            Three-window desktop shell with live CSR data
├── linker_qemu.ld           Memory map: code at 0x80000000 (QEMU DRAM)
├── Makefile                 GNU Make build (Linux / WSL / Git Bash)
├── build_qemu_os.ps1        Windows PowerShell build script
└── README.md                This file
```

---

## How It Was Built

### 1. Boot Layer (`kernel/start.s`)

The RISC-V ISA guarantees that QEMU begins execution at the very first word of the kernel ELF, which our linker script places at physical address `0x80000000` (the start of QEMU's simulated DRAM).

```
Power on
  └─> _start (0x80000000)
        ├─ Filter: only hart 0 continues; others park at wfi
        ├─ Disable interrupts: csrw mstatus, zero
        ├─ Set stack pointer: SP = 0x80020000 (128 KiB above code)
        ├─ Zero BSS: loop over [_bss_start .. _bss_end]
        ├─ Install M-mode trap vector: csrw mtvec, m_trap_handler
        ├─ Install S-mode trap vector: csrw stvec, s_trap_handler
        └─> call kernel_main()
```

The M-mode trap handler saves caller-saved registers, reads `mcause`, and calls `syscall_dispatch()` (a C function) for `ECALL` (cause 11). All other exceptions simply advance `mepc` past the trapping instruction.

### 2. UART Driver (`drivers/uart.c`)

The QEMU virt machine exposes a **NS16550A-compatible UART** at MMIO address `0x10000000`. The driver:

- Sets the baud-rate divisor for 115200 baud (clock = 1.8432 MHz → divisor = 1)
- Configures **8-N-1** framing via the Line Control Register
- Enables and clears the TX/RX FIFOs
- Exposes `uart_putc()` (spin on LSR bit 5) and `uart_getc_nb()` (poll LSR bit 0)

All terminal output — including every ANSI escape sequence — flows through `uart_putc()`.

### 3. Framebuffer (`drivers/framebuffer.c`)

Instead of a pixel framebuffer (which would need a GPU driver), the OS uses a **character-cell virtual framebuffer**:

```
typedef struct {
    char    ch;    // Character to display
    uint8_t fg;    // 256-colour ANSI foreground index
    uint8_t bg;    // 256-colour ANSI background index
    uint8_t attr;  // ATTR_BOLD | ATTR_UNDERLINE | ...
} Cell;

Cell fb_cur [24][80];   // Current frame
Cell fb_prev[24][80];   // Previous frame (for diffing)
```

`fb_flush()` **diffs** the current frame against the previous one and emits ANSI sequences only for cells that changed:

```
\033[<row>;<col>H    — move cursor
\033[38;5;<n>m       — set 256-colour foreground
\033[48;5;<n>m       — set 256-colour background
\033[1m / \033[22m   — bold on/off
```

This is the exact technique used by real embedded TUIs (ncurses, Busybox shell, embedded Linux consoles).

### 4. GUI Engine (`gui/gui.c`)

The window manager maintains a table of up to 8 `Window` descriptors. Each window has:

| Field | Purpose |
|---|---|
| `x, y, w, h` | Position and size in cell coordinates |
| `title` | Shown in the title bar |
| `flags` | `GUI_FLAG_BORDER`, `GUI_FLAG_TITLEBAR` |
| `on_draw` | Callback invoked every frame to draw content |
| `on_input` | Callback invoked when focused and a key arrives |
| `user_data` | App-private state pointer |

**Render order (two passes):**
1. All unfocused windows are drawn first.
2. The focused window is drawn last (on top).

This ensures the active window's border is never occluded.

**Widget helpers** (`gui_label`, `gui_kv_row`, `gui_button`, `gui_progress`, `gui_separator`) accept window-relative `(rx, ry)` coordinates and translate them to absolute screen coordinates internally.

### 5. Desktop Shell (`apps/desktop.c`)

Three windows fill the 80×24 screen:

```
+--- RISC-V MicroKernel OS v1.0 ---------[ RV32IMA_Zicsr | M-mode ]---Tick:NNN+
|                                                                               |
| +-- System Info ----------+  +-- App Launcher -------------------------+     |
| | CPU Information         |  | Select an Application                   |     |
| | ─────────────────────── |  | ─────────────────────────────────────── |     |
| | Hart ID:      0         |  | [  Snake Game        ] Play Snake...    |     |
| | ISA:          RV32-IMA  |  | [  System Monitor    ] View CPU load    |     |
| | Privilege:    M-Mode    |  | [  CSR Inspector     ] Inspect CSRs     |     |
| | Int Enable:   Disabled  |  | [  Memory Viewer     ] Browse DRAM      |     |
| | ─────────────────────── |  | [  About OS          ] Version info     |     |
| | CSR Snapshot            |  |                                         |     |
| | mtvec:   0x80000NNN     |  | Use UP/DOWN to select, ENTER to launch  |     |
| | mstatus: 0x00000000     |  +─────────────────────────────────────────+     |
| | ─────────────────────── |                                                   |
| | Cycle Meter             |  +-- Activity Log ─────────────────────────+     |
| | [################    ]  |  | [00] OS booted successfully              |     |
| | 1234567 cycles          |  | [01] Platform: QEMU virt  RV32IMA_Zicsr |     |
| | ─────────────────────── |  | [02] GUI engine: 3 windows, diff-render |     |
| | Memory Map (QEMU virt)  |  | [03] Press TAB to switch window focus   |     |
| | ROM:     0x00001000     |  +─────────────────────────────────────────+     |
| | UART0:   0x10000000     |                                                   |
| | DRAM:    0x80000000     |                                                   |
+-+-------------------------+-------------------------------------------------+-+
| [TAB] Next Window  [ENTER] Select  [ARROW] Navigate  [Q] Quit OS             |
+-------------------------------------------------------------------------------+
```

**System Info** reads live RISC-V CSRs on every frame (`mhartid`, `misa`, `mstatus`, `mtvec`, `mscratch`, `mcycle`) and renders a live CPU-cycle progress bar.

**App Launcher** is a navigable button list (W/S or ↑/↓ + ENTER).

**Activity Log** is a ring buffer (8 lines) that records boot messages, key presses, and button activations.

---

## Prerequisites

### Toolchain
The same **xPack RISC-V GCC** toolchain used by the main project:
```
C:\path\to\toolchain\bin\
```
No extra tools are needed; the build script uses the same `riscv-none-elf-gcc.exe` and `riscv-none-elf-ld.exe`.

### QEMU
Install **QEMU for Windows** from https://www.qemu.org/download/#windows  
The package you need is `qemu-system-riscv32`.

Verify with:
```powershell
qemu-system-riscv32 --version
```

### Terminal
Use **Windows Terminal** or **PuTTY** — both support 256-colour ANSI codes and the GUI will look correct. The standard Windows Command Prompt does **not** support 256-colour ANSI and the output will look garbled.

---

## How to Build

Open **Windows Terminal** (or any terminal with PowerShell), then:

```powershell
# Navigate into the OS source directory
cd sw/src/qemu_os

# Run the build script
powershell -ExecutionPolicy Bypass -File .\build_qemu_os.ps1
```

**Expected output:**
```
================================================================
  RISC-V QEMU OS + GUI  —  Build Script
================================================================

  Compiling: kernel\start.s           OK
  Compiling: kernel\kernel.c          OK
  Compiling: drivers\uart.c           OK
  Compiling: drivers\framebuffer.c    OK
  Compiling: gui\gui.c                OK
  Compiling: apps\desktop.c          OK

  Linking -> build\qemu_os.elf        OK
  Binary   -> build\qemu_os.bin       OK
  Disasm   -> build\qemu_os.dis       OK

  Output files:
    qemu_os.elf                    XXXX bytes
    qemu_os.bin                    XXXX bytes

================================================================
  Build SUCCESSFUL!
================================================================
```

---

## How to Run

### Step 1 — Maximise your terminal
Make the terminal window at least **80 columns × 25 rows** (the GUI is 80×24 + 1 OS status row). The larger the better.

### Step 2 — Run QEMU

```powershell
qemu-system-riscv32 `
    -machine virt `
    -nographic `
    -bios none `
    -m 128M `
    -kernel build\qemu_os.elf
```

Alternatively with GNU Make (Git Bash / WSL):
```bash
make run
```

### Step 3 — Interact with the GUI

| Key | Action |
|---|---|
| `TAB` | Switch focus between windows |
| `W` / `↑` | Move selection up (in App Launcher) |
| `S` / `↓` | Move selection down (in App Launcher) |
| `ENTER` | Activate the selected button |
| `Q` | Quit the OS (halt the hart) |
| `Ctrl-A` then `X` | Quit QEMU itself |

### Step 4 — Quit QEMU
Press **Ctrl-A** then **X** (two-key sequence: hold Ctrl, press A, release, press X).

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        QEMU virt machine                    │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  Software Stack                      │   │
│  │                                                      │   │
│  │  apps/desktop.c   ← Three-window desktop shell       │   │
│  │       │                                              │   │
│  │  gui/gui.c        ← Window manager + widget helpers  │   │
│  │       │                                              │   │
│  │  drivers/         ← UART driver, framebuffer engine  │   │
│  │  framebuffer.c         (80×24 cell grid, ANSI diff)  │   │
│  │       │                                              │   │
│  │  kernel/kernel.c  ← Syscall dispatcher, boot banner  │   │
│  │       │                                              │   │
│  │  kernel/start.s   ← Hart filter, BSS zero, mtvec    │   │
│  └──────────┬───────────────────────────────────────────┘   │
│             │ MMIO                                           │
│  ┌──────────┴────────────┐                                   │
│  │  NS16550A UART         │  0x10000000                      │
│  │  (115200 8N1)          │                                   │
│  └──────────┬────────────┘                                   │
└─────────────┼───────────────────────────────────────────────┘
              │ ANSI VT100 escape sequences (text stream)
              ▼
      Windows Terminal / PuTTY
      (renders 256-colour GUI)
```

---

## How the "GUI" Works Without a GPU

The OS uses **ANSI VT100 terminal escape codes** to create a rich visual interface:

1. **Positioning**: `\033[row;colH` moves the terminal cursor to exact coordinates.
2. **256 colours**: `\033[38;5;Nm` sets foreground, `\033[48;5;Nm` sets background using any of 256 indexed colours.
3. **Attributes**: `\033[1m` enables bold rendering.
4. **Double-buffering**: The framebuffer engine diffs the current and previous frame so only changed cells are transmitted — keeping the render fast even at 115200 baud.

This is exactly how programs like `ncurses`, `vim`, `htop`, and many embedded Linux UIs work.

---

## Extending the OS

| What to add | Where to add it |
|---|---|
| New application window | Add a draw/input callback pair in `apps/desktop.c` |
| New widget type | Add a `gui_*` function in `gui/gui.c` and declare it in `gui/gui.h` |
| New syscall | Add a `case N:` in `syscall_dispatch()` in `kernel/kernel.c` |
| Timer interrupts | Enable `mie.MTIE`, add CLINT MMIO driver (`0x02004000`), handle cause `0x80000007` in `m_trap_handler` |
| Cooperative scheduler | Add a task table and call `task_switch()` from the timer IRQ handler |
| Porting back to custom RTL | Replace UART base address (`0x10000000` → `0x00003FF0`) and linker origin (`0x80000000` → `0x00000000`) |
