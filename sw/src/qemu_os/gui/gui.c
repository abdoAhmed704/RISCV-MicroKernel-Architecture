/*
 * gui.c — Window manager and widget rendering engine
 *
 * How a frame is built:
 *
 *   1. fb_clear()            paint desktop background
 *   2. draw_topbar()         OS name, tick counter
 *   3. for each window:
 *        draw_window_chrome()  border + title bar
 *        win->on_draw()        window content (widgets)
 *   4. draw_statusbar()      key hints
 *   5. fb_flush()            diff & emit ANSI to UART
 */

#include "gui.h"
#include "../drivers/framebuffer.h"
#include "../drivers/uart.h"

/* ── Internal window table ──────────────────────────────────────── */
static Window  g_windows[GUI_MAX_WINDOWS];
static int     g_win_count   = 0;
static int     g_focused_idx = 0;

/* ── Tick counter (incremented each render) ─────────────────────── */
static uint32_t g_tick = 0;

/* ─────────────────────────────────────────────────────────────────
 * Internal: string copy (no stdlib)
 * ───────────────────────────────────────────────────────────────── */
static void kstrcpy(char *dst, const char *src, int max)
{
    int i = 0;
    while (src[i] && i < max - 1) { dst[i] = src[i]; i++; }
    dst[i] = '\0';
}


/* ─────────────────────────────────────────────────────────────────
 * Internal: draw the fixed top bar (row 0)
 * ───────────────────────────────────────────────────────────────── */
static void draw_topbar(void)
{
    /* Fill background */
    fb_fill(0, 0, FB_COLS, 1, ' ', COL_WIN_TITLE_FG, COL_WIN_FOCUS_BG);

    /* OS name on the left */
    fb_print_attr(1, 0, "RISC-V MicroKernel OS  v1.0",
                  COL_WHITE, COL_WIN_FOCUS_BG, ATTR_BOLD);

    /* Architecture tag in the centre area */
    fb_print(29, 0, "[ RV32IMA_Zicsr | M-mode ]",
             COL_LABEL_KEY, COL_WIN_FOCUS_BG);

    /* Tick counter on the right */
    char tick_buf[16];
    kitoa(g_tick, tick_buf);
    /* Right-align inside the last 14 columns */
    int tx = FB_COLS - 14;
    fb_print(tx,     0, "Tick:",     COL_SUBTEXT,    COL_WIN_FOCUS_BG);
    fb_print(tx + 6, 0, tick_buf,   COL_LABEL_VAL,  COL_WIN_FOCUS_BG);
}

/* ─────────────────────────────────────────────────────────────────
 * Internal: draw the fixed status bar (row FB_ROWS-1)
 * ───────────────────────────────────────────────────────────────── */
static void draw_statusbar(void)
{
    int y = FB_ROWS - 1;
    fb_fill(0, y, FB_COLS, 1, ' ', COL_STATUS_FG, COL_STATUS_BG);

    gui_key_hint(1,  y, "TAB",   "Next Window");
    gui_key_hint(18, y, "ENTER", "Select");
    gui_key_hint(31, y, "ARROW", "Navigate");
    gui_key_hint(44, y, "Q",     "Quit OS");

    /* Show focused window name on the right */
    if (g_focused_idx >= 0 && g_focused_idx < g_win_count) {
        const char *wname = g_windows[g_focused_idx].title;
        int         wlen  = (int)kstrlen(wname);
        fb_print(FB_COLS - wlen - 4, y, ">> ", COL_ACCENT, COL_STATUS_BG);
        fb_print(FB_COLS - wlen - 1, y, wname, COL_WHITE,  COL_STATUS_BG);
    }
}

/* ─────────────────────────────────────────────────────────────────
 * Internal: draw window chrome (border + title bar)
 * ───────────────────────────────────────────────────────────────── */
static void draw_window_chrome(int idx)
{
    Window *w    = &g_windows[idx];
    BOOL   focus = (idx == g_focused_idx);

    uint8_t bdr_fg = focus ? COL_WIN_FOCUS_BG  : COL_WIN_BORDER;
    uint8_t ttl_bg = focus ? COL_WIN_FOCUS_BG  : COL_WIN_TITLE_BG;

    /* Fill window interior with background colour */
    fb_fill(w->x, w->y, w->w, w->h, ' ', COL_TEXT, COL_WIN_BG);

    /* Draw border if requested */
    if (w->flags & GUI_FLAG_BORDER)
        fb_draw_box(w->x, w->y, w->w, w->h, bdr_fg, COL_WIN_BG);

    /* Draw title bar if requested (row y+1 inside the border) */
    if (w->flags & GUI_FLAG_TITLEBAR) {
        int ty = w->y + 1;
        /* Title bar row spans full window width */
        fb_fill(w->x + 1, ty, w->w - 2, 1, ' ', COL_WIN_TITLE_FG, ttl_bg);

        /* Window focus indicator */
        if (focus)
            fb_print_attr(w->x + 1, ty, "> ",
                          COL_LABEL_KEY, ttl_bg, ATTR_BOLD);
        else
            fb_print(w->x + 1, ty, "  ", COL_WIN_TITLE_FG, ttl_bg);

        fb_print_attr(w->x + 3, ty, w->title,
                      COL_WIN_TITLE_FG, ttl_bg, ATTR_BOLD);

        /* Bottom separator below title bar */
        fb_hline(w->x + 1, ty + 1, w->w - 2, bdr_fg, COL_WIN_BG);
    }
}

/* ─────────────────────────────────────────────────────────────────
 * Internal: compute content area origin for a window
 *   (the top-left interior cell available to on_draw callbacks)
 * ───────────────────────────────────────────────────────────────── */
static void win_content_origin(const Window *w, int *ox, int *oy)
{
    *ox = w->x + 1;                                      /* past border  */
    *oy = w->y + ((w->flags & GUI_FLAG_TITLEBAR) ? 3 : 1); /* past title */
}

/* ════════════════════════════════════════════════════════════════════
 *  PUBLIC API
 * ════════════════════════════════════════════════════════════════════ */

void gui_init(void)
{
    g_win_count   = 0;
    g_focused_idx = 0;
    g_tick        = 0;
    fb_init();
}

/* ─────────────────────────────────────────────────────────────────*/
int gui_add_window(int x, int y, int w, int h,
                   const char *title, uint8_t flags,
                   GuiDrawFn on_draw, GuiInputFn on_input,
                   void *user_data)
{
    if (g_win_count >= GUI_MAX_WINDOWS) return -1;
    int idx = g_win_count++;
    Window *win = &g_windows[idx];
    win->x = x; win->y = y; win->w = w; win->h = h;
    win->flags     = flags | GUI_FLAG_VISIBLE;
    win->on_draw   = on_draw;
    win->on_input  = on_input;
    win->user_data = user_data;
    kstrcpy(win->title, title, GUI_TITLE_LEN);
    return idx;
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_set_focus(int idx)
{
    if (idx >= 0 && idx < g_win_count)
        g_focused_idx = idx;
}

/* ─────────────────────────────────────────────────────────────────*/
int gui_focused(void) { return g_focused_idx; }

/* ─────────────────────────────────────────────────────────────────*/
Window *gui_get_window(int idx)
{
    if (idx >= 0 && idx < g_win_count)
        return &g_windows[idx];
    return NULL;
}

/* ─────────────────────────────────────────────────────────────────*/
uint32_t gui_get_tick(void) { return g_tick; }

/* ─────────────────────────────────────────────────────────────────*/
void gui_render(void)
{
    g_tick++;

    /* Paint desktop background */
    fb_clear(COL_DESKTOP_BG);

    /* Top bar */
    draw_topbar();

    /* Draw each visible window, unfocused first, focused last */
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; i < g_win_count; i++) {
            Window *w = &g_windows[i];
            if (!(w->flags & GUI_FLAG_VISIBLE)) continue;
            if (pass == 0 && i == g_focused_idx) continue;
            if (pass == 1 && i != g_focused_idx) continue;

            draw_window_chrome(i);

            if (w->on_draw)
                w->on_draw(w);
        }
    }

    /* Status bar (drawn on top of everything) */
    draw_statusbar();

    /* Push changes to the terminal */
    fb_flush();
}

/* ─────────────────────────────────────────────────────────────────*/
int gui_handle_input(char key)
{
    /* TAB: cycle focus */
    if (key == KEY_TAB) {
        int next = (g_focused_idx + 1) % g_win_count;
        gui_set_focus(next);
        return 0;
    }

    /* Q at top level quits */
    if (key == 'q' || key == 'Q') return 1;

    /* Route to focused window */
    if (g_focused_idx >= 0 && g_focused_idx < g_win_count) {
        Window *w = &g_windows[g_focused_idx];
        if (w->on_input)
            w->on_input(w, key);
    }
    return 0;
}

/* ════════════════════════════════════════════════════════════════════
 *  WIDGET DRAWING HELPERS
 *  These translate window-relative (rx, ry) to screen (x, y).
 * ════════════════════════════════════════════════════════════════════ */

/* Resolve window-relative coords to absolute screen coords */
#define WIN_ABS(win, rx, ry, ax, ay)  \
    do { int _ox, _oy; win_content_origin(win, &_ox, &_oy); \
         (ax) = _ox + (rx); (ay) = _oy + (ry); } while(0)

/* ─────────────────────────────────────────────────────────────────*/
void gui_label(Window *win, int rx, int ry,
               const char *text, uint8_t fg, uint8_t bg)
{
    int ax, ay; WIN_ABS(win, rx, ry, ax, ay);
    fb_print(ax, ay, text, fg, bg);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_label_bold(Window *win, int rx, int ry,
                    const char *text, uint8_t fg, uint8_t bg)
{
    int ax, ay; WIN_ABS(win, rx, ry, ax, ay);
    fb_print_attr(ax, ay, text, fg, bg, ATTR_BOLD);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_kv_row(Window *win, int rx, int ry, int key_width,
                const char *key, const char *value)
{
    int ax, ay; WIN_ABS(win, rx, ry, ax, ay);
    fb_print_padded(ax, ay, key, key_width, COL_LABEL_KEY, COL_WIN_BG);
    fb_print(ax + key_width, ay, value, COL_LABEL_VAL, COL_WIN_BG);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_button(Window *win, int rx, int ry, int btn_w,
                const char *label, BOOL focused)
{
    int ax, ay; WIN_ABS(win, rx, ry, ax, ay);
    uint8_t bg = focused ? COL_BTN_ACTIVE_BG : COL_BTN_BG;
    uint8_t fg = focused ? COL_BTN_ACTIVE_FG : COL_BTN_FG;

    /* Draw brackets around the button */
    fb_set(ax, ay, '[', COL_BTN_BORDER, COL_WIN_BG);
    fb_print_padded(ax + 1, ay, label, btn_w - 2, fg, bg);
    fb_set(ax + btn_w - 1, ay, ']', COL_BTN_BORDER, COL_WIN_BG);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_progress(Window *win, int rx, int ry, int bar_w,
                  int value, int max)
{
    int ax, ay; WIN_ABS(win, rx, ry, ax, ay);
    if (max <= 0) max = 1;

    int fill = (value * (bar_w - 2)) / max;
    if (fill < 0) fill = 0;
    if (fill > bar_w - 2) fill = bar_w - 2;

    fb_set(ax, ay, '[', COL_WIN_BORDER, COL_WIN_BG);
    for (int i = 0; i < bar_w - 2; i++) {
        if (i < fill)
            fb_set(ax + 1 + i, ay, '#', COL_PROG_FILL,  COL_PROG_FILL);
        else
            fb_set(ax + 1 + i, ay, ' ', COL_PROG_EMPTY, COL_PROG_EMPTY);
    }
    fb_set(ax + bar_w - 1, ay, ']', COL_WIN_BORDER, COL_WIN_BG);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_separator(Window *win, int ry)
{
    int ox, oy; win_content_origin(win, &ox, &oy);
    fb_hline(ox, oy + ry, win->w - 2, COL_WIN_BORDER, COL_WIN_BG);
}

/* ─────────────────────────────────────────────────────────────────*/
void gui_key_hint(int x, int y, const char *key, const char *desc)
{
    fb_print(x,     y, "[",   COL_DIMTEXT,  COL_STATUS_BG);
    fb_print_attr(x + 1, y, key, COL_LABEL_KEY, COL_STATUS_BG, ATTR_BOLD);
    int klen = (int)kstrlen(key);
    fb_print(x + 1 + klen, y, "] ", COL_DIMTEXT, COL_STATUS_BG);
    fb_print(x + 3 + klen, y, desc, COL_STATUS_FG, COL_STATUS_BG);
}
