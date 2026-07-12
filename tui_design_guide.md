# Building a Terminal User Interface (TUI) From Scratch
### The Logical Journey: From Raw Serial Bytes to a Window Manager

This guide explains the step-by-step logic behind creating a fully interactive, multi-window GUI running entirely inside a text terminal, using nothing but bare-metal RISC-V assembly and C.

---

## Step 1: The Raw Pipe (The Character Stream)

### Q: What hardware resources do we start with?
**A:** We have absolutely no GPU, no HDMI output, no pixel buffer, and no graphics drivers. The only connection between our CPU (or QEMU virtual CPU) and the outside world is a **UART (Serial Port)** mapped to memory at address `0x10000000`. 
* We can only write 1 byte at a time to a register.
* We can only read 1 byte at a time from a register.
* Any character written to the transmitter register is sent sequentially to the host computer's screen.

### Q: If we can only send a stream of text, why doesn't the terminal just scroll down forever?
**A:** Because we use the terminal as a **vector graphics display** instead of a typewriter. We achieve this using **ANSI escape codes (VT100 protocol)**.

When we send standard text, the terminal prints it. But when we send a special control prefix (the ESC character, ASCII code `27`), the terminal stops printing and treats the incoming bytes as formatting instructions.

* Sending `ESC [ H` tells the terminal: *Move the cursor back to the top-left corner.*
* Sending `ESC [ 5 ; 10 H` tells the terminal: *Move the cursor exactly to row 5, column 10.*
* Sending `ESC [ 38;5;214m` tells the terminal: *Paint any subsequent characters orange.*

By combining coordinate control with text characters, we can draw borders (`#`, `-`, `|`) and values anywhere on the screen dynamically.

---

## Step 2: The Double-Buffer and Diffing Algorithm

### Q: Why does redrawing the screen make it flicker, and how do we fix it?
**A:** If our operating system wants to update the display, the simplest way is to clear the screen (`ESC [ 2 J`), move the cursor home, and print all 80×24 characters again. 
However, doing this 30 times a second creates two problems:
1. **Bandwidth Bottleneck:** Sending 1,920 characters plus control codes over a simulated 115200 baud serial connection is too slow, causing lag.
2. **Visual Flicker:** The time gap between clearing the screen and finishing the print is visible to the human eye, resulting in a constant, annoying strobe effect.

### Q: How does the virtual framebuffer resolve this?
**A:** We use **Double-Buffering** in the kernel RAM. We declare two character-cell grids in memory:
1. **`fb_cur[24][80]` (Current Buffer):** Where our applications write characters and colors.
2. **`fb_prev[24][80]` (Previous Buffer):** A snapshot of what the terminal emulator is currently displaying.

Instead of writing to the serial port immediately when an application draws text, it only writes to `fb_cur`. 
Once a frame is finished, we call `fb_flush()`. This function executes a **Diffing Algorithm**:

```
[For each cell from 0,0 to 24,80]
     │
     ├─► Is fb_cur[y][x] equal to fb_prev[y][x]?
     │         │
     │         ├─► YES: Do nothing (skip sending anything)
     │         │
     │         └─► NO:  1. Send cursor move code to (x, y)
     │                  2. Send color change codes (if foreground/background changed)
     │                  3. Send the single updated character
     │                  4. Copy fb_cur[y][x] to fb_prev[y][x]
```

If only one number changes on the screen (e.g., CPU cycles updating), `fb_flush()` will only transmit a few bytes to update that specific spot. The rest of the screen remains completely untouched and flicker-free.

---

## Step 3: Abstracting the Layout (The Window Manager)

### Q: How do we handle overlapping windows without hardcoding screen coordinates?
**A:** We create an abstraction layer called a **Window Manager**. Instead of applications writing directly to global screen coordinates `(x, y)`, they register a `Window` structure with its own dimensions, position, and callbacks:

* **Local Coordinates:** Every widget inside a window (buttons, progress bars, text labels) uses coordinates relative to the window's top-left corner `(rx, ry)`. The Window Manager translates these to absolute coordinates `(x + rx, y + ry)` internally.
* **Draw Callbacks:** Each window holds a pointer to a function: `void (*on_draw)(Window *win)`. When the OS needs to draw, it invokes this function.

### Q: How does the OS handle overlapping windows when rendering?
**A:** We use a **Two-Pass Rendering Engine**:
* **Pass 1:** Loop through all inactive (unfocused) windows and draw them.
* **Pass 2:** Draw the currently active (focused) window last.

Because the focused window is drawn last, its boundaries and borders overwrite any overlapping characters from inactive windows, guaranteeing that the active window always appears on top.

---

## Step 4: Real-time Interaction (Non-Blocking Input)

### Q: How can we capture key presses instantly without pausing the OS or pressing "Enter"?
**A:** In standard desktop terminals, input is **buffered** (characters are stored in a buffer and only sent to the application when you hit the Enter key). To make a real-time game or TUI, QEMU configures your host terminal to run in **Raw Mode**. In Raw Mode, every keypress is transmitted as a raw byte immediately.

Within our operating system loop, we cannot use a blocking read (like `getc()`) because it halts execution until a key is pressed, freezing our animations and progress bars. Instead, we use **Non-Blocking Polling**:

```
Loop:
  1. Read the Line Status Register (LSR) of the UART.
  2. If the "Data Ready" bit is 0:
         - Skip reading and proceed to the next step.
  3. If the "Data Ready" bit is 1:
         - Read the character byte from the Receiver Buffer Register (RBR).
         - Dispatch the key to the active window's `on_input` callback.
  4. Run application logic.
  5. Redraw the window states.
  6. Call fb_flush() to update the display.
  7. Loop back.
```

This ensures the OS clock ticks, animations play, and counter bars fill smoothly, while still responding instantly to user keypresses.

---

## How to Run and Interact with the TUI OS

To launch and interact with the TUI, follow these setup instructions.

### 1. Requirements
* **Windows Terminal** or **PuTTY** (Standard Command Prompt `cmd.exe` does not support the 256-color VT100 codes properly, resulting in garbled text).
* **QEMU** installed (`qemu-system-riscv32`).
* RISC-V GCC Toolchain.

### 2. Compilation
Compile the assembly bootstrap, kernel core, drivers, and window system into a single bootable ELF file:
```powershell
# Navigate to the QEMU OS source directory
cd sw/src/qemu_os

# Run the build script
powershell -ExecutionPolicy Bypass -File .\build_qemu_os.ps1
```

### 3. Launching
Start the virtual machine without graphical displays, routing its serial port directly to your active command window:
```powershell
qemu-system-riscv32 -machine virt -nographic -bios none -m 128M -kernel build/qemu_os.elf
```

### 4. Interactive Keyboard Shortcuts

| Shortcut | Description |
|---|---|
| **`TAB`** | Rotates the window focus (cycles which window is on top and active). |
| **`W` / `S`** or **`↑` / `↓`** | Navigates between items inside menu widgets (like the App Launcher). |
| **`ENTER`** | Activates the currently selected button or launches the highlighted app. |
| **`Q`** | Gracefully halts the operating system (triggers a `wfi` low-power park loop). |
| **`Ctrl-A` then `X`** | Exits the QEMU simulator entirely to return to your normal command line. |
