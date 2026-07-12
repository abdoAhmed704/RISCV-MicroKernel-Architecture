/*
 * framebuffer.c — Virtual character-cell framebuffer implementation
 *
 * The framebuffer is a 2D array of Cell structs in RAM.
 * fb_flush() emits only changed cells to the terminal via UART using
 * ANSI VT100 escape sequences:
 *
 *   \033[<row>;<col>H        — absolute cursor position
 *   \033[1m                  — bold on
 *   \033[22m                 — bold off
 *   \033[38;5;<n>m           — set 256-color foreground
 *   \033[48;5;<n>m           — set 256-color background
 *   \033[0m                  — reset all attributes
 *   \033[?25l                — hide cursor
 *   \033[2J                  — clear screen
 */

#include "framebuffer.h"
#include "uart.h"

/* ── Framebuffer storage: current frame and previous frame ────────── */
static Cell fb_cur [FB_ROWS][FB_COLS];
static Cell fb_prev[FB_ROWS][FB_COLS];

/* ── Dirty flag: set when init forces a full repaint ──────────────── */
static BOOL fb_force_repaint = BOOL_TRUE;

/* ─────────────────────────────────────────────────────────────────
 * Private helper: emit a small non-negative integer without printf.
 * We can't use the C stdlib, so we hand-roll it.
 * ───────────────────────────────────────────────────────────────── */
static void emit_int(int n)
{
    char buf[5];
    int  i = 0;
    if (n == 0) { uart_putc('0'); return; }
    while (n) { buf[i++] = '0' + (n % 10); n /= 10; }
    while (i > 0) uart_putc(buf[--i]);
}

/* ── Move terminal cursor to 1-based (row, col) ────────────────── */
static void ansi_move(int row, int col)
{
    uart_putc('\033');
    uart_putc('[');
    emit_int(row);
    uart_putc(';');
    emit_int(col);
    uart_putc('H');
}

/* ── Set 256-color foreground ───────────────────────────────────── */
static void ansi_fg(uint8_t c)
{
    uart_puts("\033[38;5;");
    emit_int((int)c);
    uart_putc('m');
}

/* ── Set 256-color background ───────────────────────────────────── */
static void ansi_bg(uint8_t c)
{
    uart_puts("\033[48;5;");
    emit_int((int)c);
    uart_putc('m');
}

/* ================================================================= */
void fb_init(void)
{
    /* Hide terminal cursor so rendering looks clean */
    uart_puts("\033[?25l");

    /* Clear the terminal screen */
    uart_puts("\033[2J");

    /* Reset all attributes */
    uart_puts("\033[0m");

    /* Initialise both buffers to a known state */
    for (int r = 0; r < FB_ROWS; r++) {
        for (int c = 0; c < FB_COLS; c++) {
            fb_cur[r][c]  = (Cell){' ', COL_WHITE, COL_DESKTOP_BG, ATTR_NORMAL};
            /* Make prev differ so flush will paint everything */
            fb_prev[r][c] = (Cell){'\0', 0xFF, 0xFF, 0xFF};
        }
    }
    fb_force_repaint = BOOL_TRUE;
}

/* ================================================================= */
void fb_set(int x, int y, char ch, uint8_t fg, uint8_t bg)
{
    if ((unsigned)x >= FB_COLS || (unsigned)y >= FB_ROWS) return;
    fb_cur[y][x] = (Cell){ch, fg, bg, ATTR_NORMAL};
}

/* ================================================================= */
void fb_set_attr(int x, int y, char ch, uint8_t fg, uint8_t bg, uint8_t attr)
{
    if ((unsigned)x >= FB_COLS || (unsigned)y >= FB_ROWS) return;
    fb_cur[y][x] = (Cell){ch, fg, bg, attr};
}

/* ================================================================= */
void fb_fill(int x, int y, int w, int h, char ch, uint8_t fg, uint8_t bg)
{
    for (int r = y; r < y + h; r++)
        for (int c = x; c < x + w; c++)
            fb_set(c, r, ch, fg, bg);
}

/* ================================================================= */
void fb_print(int x, int y, const char *s, uint8_t fg, uint8_t bg)
{
    while (*s && x < FB_COLS)
        fb_set(x++, y, *s++, fg, bg);
}

/* ================================================================= */
void fb_print_attr(int x, int y, const char *s,
                   uint8_t fg, uint8_t bg, uint8_t attr)
{
    while (*s && x < FB_COLS)
        fb_set_attr(x++, y, *s++, fg, bg, attr);
}

/* ================================================================= */
void fb_print_padded(int x, int y, const char *s, int width,
                     uint8_t fg, uint8_t bg)
{
    int drawn = 0;
    while (*s && x < FB_COLS && drawn < width) {
        fb_set(x++, y, *s++, fg, bg);
        drawn++;
    }
    while (drawn < width && x < FB_COLS) {
        fb_set(x++, y, ' ', fg, bg);
        drawn++;
    }
}

/* ================================================================= */
void fb_draw_box(int x, int y, int w, int h, uint8_t fg, uint8_t bg)
{
    int x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1;

    /* Corners */
    fb_set(x1, y1, '+', fg, bg);
    fb_set(x2, y1, '+', fg, bg);
    fb_set(x1, y2, '+', fg, bg);
    fb_set(x2, y2, '+', fg, bg);

    /* Top and bottom edges */
    for (int c = x1 + 1; c < x2; c++) {
        fb_set(c, y1, '-', fg, bg);
        fb_set(c, y2, '-', fg, bg);
    }

    /* Left and right edges */
    for (int r = y1 + 1; r < y2; r++) {
        fb_set(x1, r, '|', fg, bg);
        fb_set(x2, r, '|', fg, bg);
    }
}

/* ================================================================= */
void fb_hline(int x, int y, int w, uint8_t fg, uint8_t bg)
{
    for (int c = x; c < x + w && c < FB_COLS; c++)
        fb_set(c, y, '-', fg, bg);
}

/* ================================================================= */
void fb_clear(uint8_t bg_color)
{
    fb_fill(0, 0, FB_COLS, FB_ROWS, ' ', COL_WHITE, bg_color);
}

/* ================================================================= */
void fb_flush(void)
{
    /* Tracking state avoids redundant ANSI escape sequences */
    uint8_t cur_fg   = 0xFF;
    uint8_t cur_bg   = 0xFF;
    uint8_t cur_attr = 0xFF;

    int     last_r = -1, last_c_end = -1; /* last row / col after last char */

    for (int r = 0; r < FB_ROWS; r++) {
        for (int c = 0; c < FB_COLS; c++) {
            Cell *cur  = &fb_cur [r][c];
            Cell *prev = &fb_prev[r][c];

            /* Skip unchanged cells */
            if (!fb_force_repaint &&
                cur->ch   == prev->ch &&
                cur->fg   == prev->fg &&
                cur->bg   == prev->bg &&
                cur->attr == prev->attr)
                continue;

            /* Move cursor only if necessary */
            BOOL need_move = !(last_r == r && last_c_end == c);
            if (need_move) {
                ansi_move(r + 1, c + 1);  /* ANSI uses 1-based indexing */
            }
            last_r     = r;
            last_c_end = c + 1;

            /* Bold / attribute */
            if (cur->attr != cur_attr) {
                if (cur->attr & ATTR_BOLD)
                    uart_puts("\033[1m");
                else
                    uart_puts("\033[22m");
                cur_attr = cur->attr;
                /* Changing bold resets colors on some terminals */
                cur_fg = cur_bg = 0xFF;
            }

            /* Foreground color */
            if (cur->fg != cur_fg) {
                ansi_fg(cur->fg);
                cur_fg = cur->fg;
            }

            /* Background color */
            if (cur->bg != cur_bg) {
                ansi_bg(cur->bg);
                cur_bg = cur->bg;
            }

            /* Emit the character */
            uart_putc(cur->ch);

            /* Update previous-frame snapshot */
            *prev = *cur;
        }
    }

    /* Move cursor below the visible area so it doesn't blink on content */
    ansi_move(FB_ROWS + 1, 1);
    uart_puts("\033[0m");   /* Reset attributes */

    fb_force_repaint = BOOL_FALSE;
}
