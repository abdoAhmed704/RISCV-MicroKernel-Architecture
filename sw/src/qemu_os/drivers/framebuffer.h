/*
 * framebuffer.h — Virtual character-cell framebuffer API
 *
 * Architecture:
 *   The OS maintains an in-RAM grid of Cell structures (80 × 24).
 *   Each Cell stores a character, a 256-color foreground index, a
 *   256-color background index, and an attribute byte.
 *
 *   fb_flush() performs a diff against the previous frame and emits
 *   only the changed cells as ANSI VT100/256-color escape sequences
 *   over the UART.  This keeps the terminal output minimal even on a
 *   slow simulated UART.
 *
 * Color palette (256-color ANSI subset used by the GUI):
 *   Standard 16 colors:  indices 0–15
 *   216-color RGB cube:  indices 16–231  (6×6×6 steps)
 *   Greyscale ramp:      indices 232–255
 *
 * Selected named constants are defined below for convenience.
 */

#ifndef FRAMEBUFFER_H
#define FRAMEBUFFER_H

#include "../include/types.h"

/* ── Screen geometry ─────────────────────────────────────────────── */
#define FB_COLS  80
#define FB_ROWS  24

/* ── Attribute flags ─────────────────────────────────────────────── */
#define ATTR_NORMAL    0x00
#define ATTR_BOLD      0x01
#define ATTR_UNDERLINE 0x04
#define ATTR_REVERSE   0x08

/* ── Named 256-color indices used by the GUI ─────────────────────── */
/* Standard colours */
#define COL_BLACK           0
#define COL_WHITE          15
#define COL_BRIGHT_WHITE   15

/* Desktop / chrome */
#define COL_DESKTOP_BG     23   /* Dark teal  (6-cube: 0,3,3)      */
#define COL_DESKTOP_BG2    24   /* Teal       (6-cube: 0,3,4)      */
#define COL_STATUS_BG      17   /* Dark navy                       */
#define COL_STATUS_FG      15   /* White                           */

/* Window chrome */
#define COL_WIN_BG        234   /* Dark grey  (greyscale)          */
#define COL_WIN_BORDER    240   /* Mid grey   (greyscale)          */
#define COL_WIN_TITLE_BG   19   /* Dark blue                       */
#define COL_WIN_TITLE_FG   15   /* White                           */
#define COL_WIN_FOCUS_BG   27   /* Royal blue                      */
#define COL_WIN_FOCUS_FG   15   /* White                           */

/* Text */
#define COL_TEXT           15   /* White                           */
#define COL_SUBTEXT       245   /* Light grey                      */
#define COL_DIMTEXT       240   /* Dim grey                        */
#define COL_LABEL_KEY     226   /* Bright yellow (key hints)       */
#define COL_LABEL_VAL     159   /* Light cyan   (values)           */

/* Buttons */
#define COL_BTN_BG         22   /* Dark green                      */
#define COL_BTN_FG         15   /* White                           */
#define COL_BTN_ACTIVE_BG  40   /* Bright green                    */
#define COL_BTN_ACTIVE_FG   0   /* Black                           */
#define COL_BTN_BORDER    242   /* Grey border                     */

/* Accent */
#define COL_ACCENT        214   /* Orange                          */
#define COL_OK            118   /* Bright green                    */
#define COL_WARN          220   /* Amber                           */
#define COL_ERR           196   /* Bright red                      */

/* Progress bar */
#define COL_PROG_FILL      33   /* Dodger blue                     */
#define COL_PROG_EMPTY    236   /* Very dark grey                  */

/* ── Cell structure ──────────────────────────────────────────────── */
typedef struct {
    char    ch;
    uint8_t fg;
    uint8_t bg;
    uint8_t attr;   /* Combination of ATTR_* flags */
} Cell;

/* ─────────────────────────────────────────────────────────────────
 * Core framebuffer operations
 * ───────────────────────────────────────────────────────────────── */

/**
 * fb_init() — Clear the framebuffer and prepare the terminal.
 * Hides the cursor, clears the screen, and marks every cell as
 * "dirty" so the first fb_flush() paints the full screen.
 */
void fb_init(void);

/**
 * fb_set() — Write a single character cell.
 * Out-of-bounds coordinates are silently ignored.
 */
void fb_set(int x, int y, char ch, uint8_t fg, uint8_t bg);

/**
 * fb_set_attr() — Write a cell with an explicit attribute.
 */
void fb_set_attr(int x, int y, char ch, uint8_t fg, uint8_t bg, uint8_t attr);

/**
 * fb_fill() — Flood-fill a rectangular region with one cell.
 */
void fb_fill(int x, int y, int w, int h, char ch, uint8_t fg, uint8_t bg);

/**
 * fb_print() — Draw a NUL-terminated string horizontally.
 * Characters past the right edge of the screen are clipped.
 */
void fb_print(int x, int y, const char *s, uint8_t fg, uint8_t bg);

/**
 * fb_print_attr() — Draw a string with explicit attributes.
 */
void fb_print_attr(int x, int y, const char *s,
                   uint8_t fg, uint8_t bg, uint8_t attr);

/**
 * fb_print_padded() — Draw a string in a field of 'width' characters.
 * If the string is shorter it is right-padded with spaces.
 * If longer it is clipped on the right.
 */
void fb_print_padded(int x, int y, const char *s, int width,
                     uint8_t fg, uint8_t bg);

/**
 * fb_draw_box() — Draw an ASCII box border (using +-| characters).
 * The interior of the box is NOT filled; call fb_fill() separately.
 */
void fb_draw_box(int x, int y, int w, int h, uint8_t fg, uint8_t bg);

/**
 * fb_hline() — Draw a horizontal line of dashes.
 */
void fb_hline(int x, int y, int w, uint8_t fg, uint8_t bg);

/**
 * fb_flush() — Diff the framebuffer against the previous frame and
 * emit only the changed cells as ANSI escape sequences over UART.
 * Call once per render cycle, after all fb_set/fb_fill/fb_print calls.
 */
void fb_flush(void);

/**
 * fb_clear() — Fill the entire framebuffer with spaces in the given
 * background colour.  Does not flush.
 */
void fb_clear(uint8_t bg_color);

#endif /* FRAMEBUFFER_H */
