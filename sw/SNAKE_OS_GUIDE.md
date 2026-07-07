# Snake OS Demo Guide

This demo is a small M-mode "nano OS" plus a Snake game for the custom RV32I core.

## What Changed

Hardware:

- Added a virtual MMIO UART in `rtl/RV32I/riscv_data_mem.sv`.
- UART address: `0x00003FF0`.
- Store byte to `0x00003FF0`: prints the byte in the simulator terminal.
- Load byte from `0x00003FF0`: reads one key from `sw/input.txt` and clears the file.
- Increased instruction memory depth to 4096 words in `riscv_instruction_mem.sv`.
- Extended the testbench runtime and reduced per-cycle debug spam in `riscv_top_tb.sv`.

Software:

- Replaced the old CSR test firmware with a tiny kernel/game firmware in `sw/src/main.c`.
- Added syscall handling in `sw/src/start.s`.
- Added `sw/play_game.py` to feed keyboard input to the simulated UART.

## Why The AI Roadmap Was Adjusted

The original plan used `0x80000000` for MMIO. Your current memory stage raises an access fault for addresses `>= 16384`, so that address would trap instead of reaching the data memory. The demo uses `0x00003FF0`, which is inside the existing 16 KiB data address window.

The roadmap also jumped directly to preemptive multitasking and user-mode tasks. This demo starts with a simpler but working foundation:

- M-mode boot.
- M-mode trap handler.
- `ecall` syscalls.
- Cooperative "clock task" plus Snake game loop.

That is the right next step before adding real timer-driven context switching.

## Syscalls

The firmware uses `ecall` with:

| `a7` | Name | Input | Return |
|---:|---|---|---|
| 1 | putc | `a0 = character` | `a0 = 0` |
| 2 | getc | none | `a0 = key` or `0` |

The M-mode trap handler in `start.s` handles ECALL cause `11`.

## Build

From the repository root:

```powershell
cd sw
.\build.ps1
```

Or with Make, if your shell supports it:

```powershell
cd sw
make
```

The output firmware is:

```text
sw/build/firmware.hex
```

## Run

Terminal 1, start the keyboard feeder:

```powershell
python sw/play_game.py
```

Keep this terminal focused when you want to press keys. The Python script captures your keyboard inputs and writes them to a file for the simulation to read.

Terminal 2, run the RTL simulation from the repository root:

```powershell
.\run_xsim.bat
```

The simulation now runs until you stop it manually. Press `Ctrl+C` in the simulator terminal when you are done.

Controls:

| Key | Action |
|---|---|
| W | Move up |
| A | Move left |
| S | Move down |
| D | Move right |
| Q | Reset the game |

## Expected Behavior

The simulator terminal should print an ASCII Snake board. The snake head is `@`, the body is `o`, and food is `*`.

The screen uses ANSI clear/home escape sequences. If your simulator console does not interpret ANSI escape codes, you may see raw characters such as `^[ [ H`; the game is still running.

## Next Steps Toward A Real OS

1. Move the UART out of data memory into a dedicated bus/MMIO decoder.
2. Add a readable timer CSR or memory-mapped timer status.
3. Implement machine timer interrupts for scheduler ticks.
4. Save all integer registers on timer interrupt.
5. Add task control blocks with separate stacks.
6. Add a real user-mode transition path.
7. Delegate selected traps to S-mode once S-mode is stable.

graph TD
    %% Styling
    classDef software fill:#1e293b,stroke:#475569,stroke-width:2px,color:#f8fafc;
    classDef hardware fill:#0f766e,stroke:#14b8a6,stroke-width:2px,color:#f8fafc;
    classDef io fill:#b45309,stroke:#f59e0b,stroke-width:2px,color:#f8fafc;

    subgraph Host OS Environment
      UserKeyboard[User Keyboard Input]
      PythonFeeder[sw/play_game.py]:::software
      InputTxt[sw/input.txt]:::io
    end

    subgraph Hardware Simulation Layer (Vivado xsim)
      TB[riscv_top_tb.sv]:::hardware
      Pipeline[riscv_top_pipeline.sv]:::hardware
      DMEM[riscv_data_mem.sv]:::hardware
      TerminalStdout[Terminal Console Out]:::io
    end

    subgraph Bare-Metal Software Stack (RV32I)
      StartS[start.s Bootstrap]:::software
      MainC[main.c Snake OS Kernel]:::software
    end

    %% Data Connections
    UserKeyboard -->|Raw Keystrokes| PythonFeeder
    PythonFeeder -->|Writes ASCII char| InputTxt
    DMEM -->|Polls/Clears file via $fopen| InputTxt
    Pipeline -->|Loads/Stores| DMEM
    StartS -->|Calls| MainC
    MainC -->|Store Byte to 0x00003FF0| DMEM
    MainC -->|Load Byte from 0x00003FF0| DMEM
    DMEM -->|SystemVerilog $write| TerminalStdout
