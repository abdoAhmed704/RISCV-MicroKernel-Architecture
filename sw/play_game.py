#!/usr/bin/env python3
"""
Keyboard feeder for the RISC-V Snake demo.

Run this in one terminal while the RTL simulation runs in another terminal.
The SystemVerilog MMIO UART reads sw/input.txt and consumes one key at a time.
"""

from pathlib import Path
import os
import sys
import time

INPUT_FILE = Path(__file__).with_name("input.txt")
VALID_KEYS = {"w", "a", "s", "d", "q", "W", "A", "S", "D", "Q"}


def write_key(ch: str) -> None:
    INPUT_FILE.write_text(ch[:1], encoding="ascii")


def windows_loop() -> None:
    import msvcrt

    while True:
        if msvcrt.kbhit():
            raw = msvcrt.getwch()
            if raw in ("\x00", "\xe0"):
                if msvcrt.kbhit():
                    msvcrt.getwch()
                continue
            if raw == "\x03":
                raise KeyboardInterrupt
            if raw in VALID_KEYS:
                write_key(raw.upper())
        time.sleep(0.01)


def posix_loop() -> None:
    import select
    import termios
    import tty

    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        while True:
            ready, _, _ = select.select([sys.stdin], [], [], 0.01)
            if ready:
                ch = sys.stdin.read(1)
                if ch == "\x03":
                    raise KeyboardInterrupt
                if ch in VALID_KEYS:
                    write_key(ch.upper())
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)


def main() -> int:
    INPUT_FILE.write_text("", encoding="ascii")
    print("Snake keyboard feeder is running.")
    print("Use W/A/S/D to move, Q to reset. Press Ctrl+C to stop.")
    print(f"Writing keys to: {INPUT_FILE}")

    try:
        if os.name == "nt":
            windows_loop()
        else:
            posix_loop()
    except KeyboardInterrupt:
        INPUT_FILE.write_text("", encoding="ascii")
        print("\nStopped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
