/*
 * gui.h — Window manager and GUI widget API
 *
 * Architecture overview
 * ─────────────────────
 * The GUI is organized as a lightweight window manager:
 *
 *   Desktop
 *   ├── Top bar  (always drawn first, fixed at row 0)
 *   ├── Windows  (drawn in z-order; one window has keyboard focus)
 *   └── Status bar (always drawn last, fixed at row FB_ROWS-1)
 *
 * Each Window has:
 *   • A position and size in character-cell coordinates
 *   • A title string (shown in the title bar)
 *   • A draw callback — called by gui_render() to populate the
 *     window interior with content
 *   • An input callback — called when the window is focused and
 *     a key is received
 *   • A void* user_data pointer — passed to both callbacks
 *
 * Input model:
 *   TAB           → cycle focus to the next visible window
 *   Arrow keys    → passed to the focused window's input callback
 *   Enter / Space → passed to the focused window's input callback
 *   Any other key → passed to the focused window's input callback
 *
 * Widget helpers (gui_draw_*):
 *   Widgets are not objects; they are stateless drawing functions.
 *   They write directly into the framebuffer relative to the window
 *   origin, so the draw callback simply calls them.
 */

#ifndef GUI_H
#define GUI_H

#include "../include/types.h"
#include "../drivers/framebuffer.h"

/* ── Maximum number of concurrent windows ────────────────────────── */
#define GUI_MAX_WINDOWS  8

/* ── Window title buffer ─────────────────────────────────────────── */
#define GUI_TITLE_LEN   48

/* ── Window flags ────────────────────────────────────────────────── */
#define GUI_FLAG_VISIBLE  (1 << 0)  /* Window is drawn                */
#define GUI_FLAG_BORDER   (1 << 1)  /* Draw a box border              */
#define GUI_FLAG_TITLEBAR (1 << 2)  /* Draw title bar below top edge  */

/* ── Special key codes (returned by uart_getc_nb) ────────────────── */
#define KEY_TAB     '\t'
#define KEY_ENTER   '\r'
#define KEY_ENTER2  '\n'
#define KEY_ESC     '\033'
#define KEY_UP      'A'   /* After \033[ prefix stripped by caller */
#define KEY_DOWN    'B'
#define KEY_RIGHT   'C'
#define KEY_LEFT    'D'

/* ── Forward declaration ─────────────────────────────────────────── */
typedef struct Window Window;

/* ── Callback types ─────────────────────────────────────────────── */
typedef void (*GuiDrawFn )(Window *win);
typedef void (*GuiInputFn)(Window *win, char key);

/* ── Window descriptor ───────────────────────────────────────────── */
struct Window {
    int   x, y;                    /* Top-left corner (col, row)      */
    int   w, h;                    /* Width and height in cells       */
    char  title[GUI_TITLE_LEN];
    uint8_t    flags;
    GuiDrawFn  on_draw;
    GuiInputFn on_input;
    void      *user_data;          /* App-specific state pointer      */
};

/* ════════════════════════════════════════════════════════════════════
 *  GUI CORE API
 * ════════════════════════════════════════════════════════════════════ */

/**
 * gui_init() — Reset the window manager state and initialise the
 * framebuffer.  Must be called before any other gui_* function.
 */
void gui_init(void);

/**
 * gui_add_window() — Register a window and return its slot index.
 * Returns -1 if no slot is available.
 * The window is immediately visible.
 */
int gui_add_window(int x, int y, int w, int h,
                   const char *title,
                   uint8_t     flags,
                   GuiDrawFn   on_draw,
                   GuiInputFn  on_input,
                   void       *user_data);

/**
 * gui_set_focus() — Move keyboard focus to window at index 'idx'.
 */
void gui_set_focus(int idx);

/**
 * gui_focused() — Return the index of the currently focused window,
 * or -1 if no window is focused.
 */
int gui_focused(void);

/**
 * gui_get_window() — Retrieve a pointer to the Window structure at the
 * given slot index. Returns NULL if the index is out of range.
 */
Window *gui_get_window(int idx);

/**
 * gui_render() — Rebuild the framebuffer for the current frame and
 * call fb_flush().  Call this once per event-loop iteration.
 */
void gui_render(void);

/**
 * gui_handle_input() — Process one character from the UART and route
 * it to the focused window (or switch focus on TAB).
 * Returns 1 if the application should quit, 0 otherwise.
 */
int gui_handle_input(char key);

/**
 * gui_get_tick() — Return the lower 32 bits of the mcycle CSR.
 * Useful for animations and time displays.
 */
uint32_t gui_get_tick(void);

/* ════════════════════════════════════════════════════════════════════
 *  WIDGET DRAWING HELPERS
 *  These functions are called from a window's on_draw callback.
 *  Coordinates (rx, ry) are relative to the window's interior
 *  (i.e., the content area starts at the cell to the right of/
 *   below the left/top border).
 * ════════════════════════════════════════════════════════════════════ */

/**
 * gui_label() — Draw a simple text label.
 */
void gui_label(Window *win, int rx, int ry,
               const char *text, uint8_t fg, uint8_t bg);

/**
 * gui_label_bold() — Like gui_label but with bold attribute.
 */
void gui_label_bold(Window *win, int rx, int ry,
                    const char *text, uint8_t fg, uint8_t bg);

/**
 * gui_kv_row() — Draw a "Key: Value" pair on one row.
 * 'key'   is drawn with COL_LABEL_KEY colour.
 * 'value' is drawn with COL_LABEL_VAL colour.
 * The field is padded to 'width' characters so successive rows align.
 */
void gui_kv_row(Window *win, int rx, int ry, int key_width,
                const char *key, const char *value);

/**
 * gui_button() — Draw a button widget.
 * When 'focused' is true the button is highlighted with the active
 * button colour scheme.
 */
void gui_button(Window *win, int rx, int ry, int btn_w,
                const char *label, BOOL focused);

/**
 * gui_progress() — Draw a horizontal progress bar.
 * value  must be in [0, max].
 * bar_w  is the total width of the bar in cells (including brackets).
 */
void gui_progress(Window *win, int rx, int ry, int bar_w,
                  int value, int max);

/**
 * gui_separator() — Draw a horizontal divider line inside a window.
 */
void gui_separator(Window *win, int ry);

/**
 * gui_key_hint() — Draw a "[ KEY ] Description" hint on the status bar.
 * x, y are absolute screen coordinates (not window-relative).
 */
void gui_key_hint(int x, int y, const char *key, const char *desc);

#endif /* GUI_H */
