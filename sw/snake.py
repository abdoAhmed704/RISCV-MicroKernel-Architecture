#!/usr/bin/env python3
"""
RISC-V Snake OS — Native Terminal Edition
Same game logic as sw/src/main.c running on the RV32I core,
but executed natively so you can actually play it in real-time.
"""

import os
import sys
import time
import msvcrt

# ─── Game Constants (same as main.c) ────────────────────────────────
BOARD_W = 20
BOARD_H = 10
MAX_SNAKE = 64
TICK_RATE = 0.15  # seconds per game step (adjust for speed)

# ─── Game State ─────────────────────────────────────────────────────
snake_x = [0] * MAX_SNAKE
snake_y = [0] * MAX_SNAKE
snake_len = 0
direction = 0   # 0=up, 1=down, 2=left, 3=right
food_x = 0
food_y = 0
tick_count = 0
game_over = False


def game_init():
    global snake_len, direction, food_x, food_y, tick_count, game_over
    snake_len = 4
    snake_x[0] = 10; snake_y[0] = 5
    snake_x[1] = 9;  snake_y[1] = 5
    snake_x[2] = 8;  snake_y[2] = 5
    snake_x[3] = 7;  snake_y[3] = 5
    direction = 3  # moving right
    food_x = 14
    food_y = 4
    tick_count = 0
    game_over = False


def place_food():
    global food_x, food_y
    tries = 0
    while tries < 40:
        food_x = (food_x + 7) % BOARD_W
        food_y = (food_y + 3) % BOARD_H
        ok = True
        for i in range(snake_len):
            if snake_x[i] == food_x and snake_y[i] == food_y:
                ok = False
                break
        if ok:
            return
        tries += 1


def handle_input():
    global direction
    while msvcrt.kbhit():
        raw = msvcrt.getwch()
        if raw in ('\x00', '\xe0'):
            if msvcrt.kbhit():
                msvcrt.getwch()
            continue
        ch = raw.upper()
        if ch == 'W' and direction != 1: direction = 0
        elif ch == 'S' and direction != 0: direction = 1
        elif ch == 'A' and direction != 3: direction = 2
        elif ch == 'D' and direction != 2: direction = 3
        elif ch == 'Q': game_init()
        elif ch == '\x1b':  # ESC to quit
            sys.exit(0)


def game_step():
    global snake_len, game_over
    if game_over:
        return

    new_x = snake_x[0]
    new_y = snake_y[0]

    if direction == 0:
        if new_y == 0: game_over = True; return
        new_y -= 1
    elif direction == 1:
        new_y += 1
        if new_y >= BOARD_H: game_over = True; return
    elif direction == 2:
        if new_x == 0: game_over = True; return
        new_x -= 1
    else:
        new_x += 1
        if new_x >= BOARD_W: game_over = True; return

    for i in range(snake_len):
        if snake_x[i] == new_x and snake_y[i] == new_y:
            game_over = True
            return

    ate_food = (new_x == food_x and new_y == food_y)
    if ate_food and snake_len < MAX_SNAKE:
        snake_len += 1

    for i in range(snake_len - 1, 0, -1):
        snake_x[i] = snake_x[i - 1]
        snake_y[i] = snake_y[i - 1]
    snake_x[0] = new_x
    snake_y[0] = new_y

    if ate_food:
        place_food()


def render_board():
    # Move cursor to top-left (ANSI escape)
    sys.stdout.write('\033[H')

    lines = []
    lines.append('\033[1;36m╔══ RISC-V Snake OS ══╗\033[0m')
    lines.append(f' WASD move, Q reset, ESC quit')
    lines.append(f' T={tick_count:02X}  L={snake_len:02X}  {"" if not game_over else "GAME OVER!"}')
    lines.append('\033[33m' + '#' * (BOARD_W + 2) + '\033[0m')

    for y in range(BOARD_H):
        row = ['\033[33m#\033[0m']
        for x in range(BOARD_W):
            found = False
            for i in range(snake_len):
                if snake_x[i] == x and snake_y[i] == y:
                    if i == 0:
                        row.append('\033[1;32m@\033[0m')  # head = green @
                    else:
                        row.append('\033[32mo\033[0m')     # body = green o
                    found = True
                    break
            if not found:
                if x == food_x and y == food_y:
                    row.append('\033[1;31m*\033[0m')       # food = red *
                else:
                    row.append(' ')
        row.append('\033[33m#\033[0m')
        lines.append(''.join(row))

    lines.append('\033[33m' + '#' * (BOARD_W + 2) + '\033[0m')

    if game_over:
        lines.append('\033[1;31m  GAME OVER — Press Q to reset\033[0m')
    else:
        lines.append('')

    sys.stdout.write('\n'.join(lines) + '\n')
    sys.stdout.flush()


def main():
    # Enable ANSI escape codes on Windows 10+
    os.system('')
    # Clear screen
    os.system('cls')
    # Hide cursor
    sys.stdout.write('\033[?25l')

    game_init()
    render_board()

    try:
        while True:
            handle_input()
            if not game_over:
                game_step()
                tick_count += 1
            render_board()
            time.sleep(TICK_RATE)
    except KeyboardInterrupt:
        pass
    finally:
        # Show cursor again
        sys.stdout.write('\033[?25h')
        sys.stdout.flush()


if __name__ == '__main__':
    main()
