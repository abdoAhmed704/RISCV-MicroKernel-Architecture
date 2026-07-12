/*
 * desktop.c — Desktop shell and interactive applications
 */

#include "desktop.h"
#include "../gui/gui.h"
#include "../drivers/framebuffer.h"
#include "../drivers/uart.h"
#include "../include/types.h"

/* ── Log ring buffer ─────────────────────────────────────────────── */
#define LOG_LINES   8
#define LOG_WIDTH  76

static char g_log[LOG_LINES][LOG_WIDTH + 1];
static int  g_log_head = 0;
static int  g_log_count = 0;

static void log_push(const char *msg)
{
    char *dst = g_log[g_log_head % LOG_LINES];
    int   i   = 0;
    while (msg[i] && i < LOG_WIDTH) { dst[i] = msg[i]; i++; }
    dst[i] = '\0';
    g_log_head = (g_log_head + 1) % LOG_LINES;
    if (g_log_count < LOG_LINES) g_log_count++;
}

/* ── RISC-V CSR helpers ─────────────────────────────────────────── */
static uint32_t csr_mhartid(void)  { uint32_t v; asm("csrr %0, mhartid"  : "=r"(v)); return v; }
static uint32_t csr_mstatus(void)  { uint32_t v; asm("csrr %0, mstatus"  : "=r"(v)); return v; }
static uint32_t csr_misa(void)     { uint32_t v; asm("csrr %0, misa"     : "=r"(v)); return v; }
static uint32_t csr_mcycle(void)   { uint32_t v; asm("csrr %0, mcycle"   : "=r"(v)); return v; }
static uint32_t csr_mtvec(void)    { uint32_t v; asm("csrr %0, mtvec"    : "=r"(v)); return v; }
static uint32_t csr_mscratch(void) { uint32_t v; asm("csrr %0, mscratch" : "=r"(v)); return v; }

/* ── Hardware CLINT Time Helpers ───────────────────────────────── */
static uint64_t read_mtime(void)
{
    uint32_t low, high, temp;
    do {
        high = MMIO32(0x0200BFFC);
        low  = MMIO32(0x0200BFF8);
        temp = MMIO32(0x0200BFFC);
    } while (high != temp);
    return ((uint64_t)high << 32) | low;
}

static void delay_ms(uint32_t ms)
{
    uint64_t start = read_mtime();
    /* QEMU virt CLINT time base is 10 MHz (10,000,000 Hz).
     * 10,000 ticks per millisecond. */
    uint64_t ticks = (uint64_t)ms * 10000;
    while (read_mtime() - start < ticks) {
        asm volatile ("nop");
    }
}


/* ── Active App State ───────────────────────────────────────────── */
static int g_active_app = -1;  /* -1 = Desktop, 0 = Snake, 1 = Pong, 2 = Tic-Tac-Toe, 3 = Monitor, 4 = CSR, 5 = Memory, 6 = About */

/* ── Window IDs ─────────────────────────────────────────────────── */
static int g_win_sysinfo = -1;
static int g_win_launcher = -1;
static int g_win_actlog = -1;
static int g_win_snake = -1;
static int g_win_pong = -1;
static int g_win_ttt = -1;
static int g_win_monitor = -1;
static int g_win_csr = -1;
static int g_win_mem = -1;
static int g_win_about = -1;

/* ─────────────────────────────────────────────────────────────────
 * WINDOW 0: System Info
 * ───────────────────────────────────────────────────────────────── */
static void sysinfo_draw(Window *win)
{
    char buf[20];

    gui_label_bold(win, 1, 0, "CPU Information", COL_ACCENT, COL_WIN_BG);
    gui_separator(win, 1);

    kitoa(csr_mhartid(), buf);
    gui_kv_row(win, 1, 2, 14, "Hart ID:      ", buf);

    uint32_t misa = csr_misa();
    char isa_str[16] = "RV32-";
    int  si = 5;
    for (int bit = 0; bit < 26 && si < 14; bit++) {
        if (misa & (1u << bit)) {
            char c = 'A' + bit;
            if (c=='I'||c=='M'||c=='A'||c=='S'||c=='U') {
                isa_str[si++] = c;
            }
        }
    }
    isa_str[si] = '\0';
    gui_kv_row(win, 1, 3, 14, "ISA:          ", isa_str);

    uint32_t mst  = csr_mstatus();
    uint32_t mpp  = (mst >> 11) & 0x3;
    const char *priv_str =
        mpp == 3 ? "M-Mode (Machine)" :
        mpp == 1 ? "S-Mode (Supervisor)" : "U-Mode (User)";
    gui_kv_row(win, 1, 4, 14, "Privilege:    ", priv_str);

    gui_kv_row(win, 1, 5, 14, "Int Enable:   ",
               (mst & 0x8) ? "Enabled" : "Disabled");

    gui_separator(win, 6);
    gui_label_bold(win, 1, 7, "CSR Snapshot", COL_ACCENT, COL_WIN_BG);
    gui_separator(win, 8);

    kitohex(csr_mtvec(),    buf);   gui_kv_row(win, 1, 9,  14, "mtvec:        ", buf);
    kitohex(csr_mstatus(),  buf);   gui_kv_row(win, 1, 10, 14, "mstatus:      ", buf);
    kitohex(csr_mscratch(), buf);   gui_kv_row(win, 1, 11, 14, "mscratch:     ", buf);

    gui_separator(win, 12);
    gui_label_bold(win, 1, 13, "Cycle Meter", COL_ACCENT, COL_WIN_BG);
    uint32_t cyc = csr_mcycle();
    int prog = (int)((cyc % 10000u) * 34u / 10000u);
    gui_progress(win, 1, 14, 34, prog, 34);
    kitoa(cyc, buf);
    gui_label(win, 1, 15, buf, COL_LABEL_VAL, COL_WIN_BG);
    gui_label(win, 1 + (int)kstrlen(buf), 15, " cycles", COL_SUBTEXT, COL_WIN_BG);

    gui_separator(win, 16);
    gui_label_bold(win, 1, 17, "Memory Map (QEMU virt)", COL_ACCENT, COL_WIN_BG);
    gui_kv_row(win, 1, 18, 14, "ROM:          ", "0x00001000");
    gui_kv_row(win, 1, 19, 14, "UART0:        ", "0x10000000");
    gui_kv_row(win, 1, 20, 14, "DRAM:         ", "0x80000000");
}

static void sysinfo_input(Window *win, char key)
{
    (void)win; (void)key;
}

/* ─────────────────────────────────────────────────────────────────
 * WINDOW 1: App Launcher
 * ───────────────────────────────────────────────────────────────── */
#define NUM_APPS  7

static const char *g_app_names[NUM_APPS] = {
    "  Snake Game       ",
    "  Pong Game        ",
    "  Tic-Tac-Toe      ",
    "  System Monitor   ",
    "  CSR Inspector    ",
    "  Memory Viewer    ",
    "  About OS         ",
};
static const char *g_app_desc[NUM_APPS] = {
    "Classic Snake (tuned speed)",
    "Solo wall-bounce paddle game",
    "Play Tic-Tac-Toe vs the CPU",
    "View live CPU load graph",
    "Inspect all M-mode CSR values",
    "Browse DRAM word by word",
    "OS version and build info",
};

typedef struct {
    int selected;
    int launched;
} LauncherState;

static LauncherState g_launcher = {0, -1};

static void launcher_draw(Window *win)
{
    gui_label_bold(win, 1, 0, "Select an Application", COL_ACCENT, COL_WIN_BG);
    gui_separator(win, 1);

    for (int i = 0; i < NUM_APPS; i++) {
        BOOL focused = (i == g_launcher.selected);
        /* Draw buttons on consecutive lines to fit all 7 apps */
        gui_button(win, 1, 2 + i, 21, g_app_names[i], focused);
    }

    gui_separator(win, 10);
    /* Draw dynamic descriptions at the bottom */
    gui_label_bold(win, 1, 11, "Description:", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 1, 12, g_app_desc[g_launcher.selected], COL_LABEL_VAL, COL_WIN_BG);
    gui_label(win, 1, 13, "Use UP/DOWN to select, ENTER to launch", COL_DIMTEXT, COL_WIN_BG);
}

/* Forward declarations */
static void launch_app(int app_id);
static void close_active_app(void);

static void launcher_input(Window *win, char key)
{
    (void)win;
    if (key == 'w' || key == 'W' || key == 'A') {
        if (g_launcher.selected > 0) g_launcher.selected--;
    }
    else if (key == 's' || key == 'S' || key == 'B') {
        if (g_launcher.selected < NUM_APPS - 1) g_launcher.selected++;
    }
    else if (key == '\r' || key == '\n' || key == ' ') {
        launch_app(g_launcher.selected);
    }
}

/* ─────────────────────────────────────────────────────────────────
 * WINDOW 2: Activity Log
 * ───────────────────────────────────────────────────────────────── */
static void actlog_draw(Window *win)
{
    gui_label_bold(win, 1, 0, "Activity Log", COL_ACCENT, COL_WIN_BG);
    gui_separator(win, 1);

    int visible_lines = win->h - 5;
    if (visible_lines < 1) visible_lines = 1;

    if (g_log_count == 0) {
        gui_label(win, 1, 2, "No events yet.  Boot messages will appear here.",
                  COL_DIMTEXT, COL_WIN_BG);
        return;
    }

    for (int i = 0; i < visible_lines && i < g_log_count; i++) {
        int log_idx = ((g_log_head - g_log_count + i + LOG_LINES) % LOG_LINES);
        char prefix[6];
        prefix[0] = '[';
        prefix[1] = '0' + ((g_log_count - (visible_lines - i)) / 10) % 10;
        prefix[2] = '0' + ((g_log_count - (visible_lines - i))     ) % 10;
        prefix[3] = ']';
        prefix[4] = ' ';
        prefix[5] = '\0';

        uint8_t fg = (i == visible_lines - 1) ? COL_LABEL_VAL : COL_SUBTEXT;
        gui_label(win, 1, 2 + i, prefix, COL_DIMTEXT, COL_WIN_BG);
        gui_label(win, 6, 2 + i, g_log[log_idx], fg, COL_WIN_BG);
    }
}

static void actlog_input(Window *win, char key)
{
    (void)win; (void)key;
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 0: Snake Game
 * ───────────────────────────────────────────────────────────────── */
#define SNAKE_BOARD_W  76
#define SNAKE_BOARD_H  16
#define SNAKE_MAX      128

typedef struct {
    int x[SNAKE_MAX];
    int y[SNAKE_MAX];
    int len;
    int dx, dy;
    int fx, fy;
    int score;
    int hi_score;
    BOOL game_over;
    uint32_t last_move_tick;
} SnakeGame;

static SnakeGame g_snake;

static void snake_init(void)
{
    g_snake.len = 4;
    g_snake.x[0] = 10; g_snake.y[0] = 5;
    g_snake.x[1] = 9;  g_snake.y[1] = 5;
    g_snake.x[2] = 8;  g_snake.y[2] = 5;
    g_snake.x[3] = 7;  g_snake.y[3] = 5;
    g_snake.dx = 1;    g_snake.dy = 0;
    g_snake.fx = 20;   g_snake.fy = 8;
    g_snake.score = 0;
    g_snake.game_over = BOOL_FALSE;
    g_snake.last_move_tick = gui_get_tick();
}

static void snake_update(void)
{
    if (g_snake.game_over) return;

    /* Move body */
    for (int i = g_snake.len - 1; i > 0; i--) {
        g_snake.x[i] = g_snake.x[i - 1];
        g_snake.y[i] = g_snake.y[i - 1];
    }

    /* Move head */
    g_snake.x[0] += g_snake.dx;
    g_snake.y[0] += g_snake.dy;

    /* Boundary collision */
    if (g_snake.x[0] < 0 || g_snake.x[0] >= SNAKE_BOARD_W ||
        g_snake.y[0] < 0 || g_snake.y[0] >= SNAKE_BOARD_H) {
        g_snake.game_over = BOOL_TRUE;
        return;
    }

    /* Self collision */
    for (int i = 1; i < g_snake.len; i++) {
        if (g_snake.x[0] == g_snake.x[i] && g_snake.y[0] == g_snake.y[i]) {
            g_snake.game_over = BOOL_TRUE;
            return;
        }
    }

    /* Food eating */
    if (g_snake.x[0] == g_snake.fx && g_snake.y[0] == g_snake.fy) {
        g_snake.score += 10;
        if (g_snake.score > g_snake.hi_score)
            g_snake.hi_score = g_snake.score;
        if (g_snake.len < SNAKE_MAX)
            g_snake.len++;

        /* Generate new food position */
        BOOL on_body = BOOL_TRUE;
        while (on_body) {
            uint32_t seed = csr_mcycle();
            g_snake.fx = seed % SNAKE_BOARD_W;
            g_snake.fy = (seed / 7) % SNAKE_BOARD_H;

            on_body = BOOL_FALSE;
            for (int i = 0; i < g_snake.len; i++) {
                if (g_snake.fx == g_snake.x[i] && g_snake.fy == g_snake.y[i]) {
                    on_body = BOOL_TRUE;
                    break;
                }
            }
        }
    }
}

static void snake_draw(Window *win)
{
    char buf[32];

    /* Update game state based on ticks (6 ticks at 30 FPS = 5 moves/sec) */
    uint32_t current_tick = gui_get_tick();
    if (current_tick - g_snake.last_move_tick >= 6) {
        snake_update();
        g_snake.last_move_tick = current_tick;
    }

    /* Draw Header/Info */
    kitoa(g_snake.score, buf);
    gui_label(win, 1, 0, "Score: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 8, 0, buf, COL_LABEL_VAL, COL_WIN_BG);

    kitoa(g_snake.hi_score, buf);
    gui_label(win, 18, 0, "Hi-Score: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 28, 0, buf, COL_LABEL_VAL, COL_WIN_BG);

    gui_label(win, 45, 0, "WASD: Navigate | R: Restart | ESC: Exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Draw Board Frame */
    fb_fill(win->x + 1, win->y + 5, SNAKE_BOARD_W + 2, SNAKE_BOARD_H + 2, ' ', COL_TEXT, COL_BLACK);
    fb_draw_box(win->x + 1, win->y + 5, SNAKE_BOARD_W + 2, SNAKE_BOARD_H + 2, COL_WIN_BORDER, COL_BLACK);

    /* Draw Food */
    fb_set(win->x + 2 + g_snake.fx, win->y + 6 + g_snake.fy, '*', COL_ACCENT, COL_BLACK);

    /* Draw Snake Body */
    for (int i = 1; i < g_snake.len; i++) {
        fb_set(win->x + 2 + g_snake.x[i], win->y + 6 + g_snake.y[i], 'o', COL_OK, COL_BLACK);
    }
    /* Draw Head */
    fb_set(win->x + 2 + g_snake.x[0], win->y + 6 + g_snake.y[0], '@', COL_LABEL_KEY, COL_BLACK);

    /* Game Over Message Overlay */
    if (g_snake.game_over) {
        fb_fill(win->x + 25, win->y + 11, 30, 5, ' ', COL_WHITE, COL_DESKTOP_BG);
        fb_draw_box(win->x + 25, win->y + 11, 30, 5, COL_ERR, COL_DESKTOP_BG);
        fb_print(win->x + 35, win->y + 12, "GAME OVER", COL_ERR, COL_DESKTOP_BG);
        fb_print(win->x + 27, win->y + 14, "Press R to play again", COL_WHITE, COL_DESKTOP_BG);
    }
}

static void snake_input(Window *win, char key)
{
    (void)win;
    if (key == 'w' || key == 'W' || key == 'A') {
        if (g_snake.dy != 1) { g_snake.dx = 0; g_snake.dy = -1; }
    }
    else if (key == 's' || key == 'S' || key == 'B') {
        if (g_snake.dy != -1) { g_snake.dx = 0; g_snake.dy = 1; }
    }
    else if (key == 'a' || key == 'A' || key == 'D') {
        if (g_snake.dx != 1) { g_snake.dx = -1; g_snake.dy = 0; }
    }
    else if (key == 'd' || key == 'D' || key == 'C') {
        if (g_snake.dx != -1) { g_snake.dx = 1; g_snake.dy = 0; }
    }
    else if (key == 'r' || key == 'R') {
        snake_init();
    }
    else if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 1: Solo Pong Game
 * ───────────────────────────────────────────────────────────────── */
typedef struct {
    int px;       /* Paddle X */
    int pw;       /* Paddle Width */
    int bx, by;   /* Ball X, Y */
    int bdx, bdy; /* Ball direction */
    int score;
    int hi_score;
    BOOL game_over;
    uint32_t last_move_tick;
} PongGame;

static PongGame g_pong;

static void pong_init(void)
{
    g_pong.px = 33;
    g_pong.pw = 10;
    g_pong.bx = 38;
    g_pong.by = 4;
    g_pong.bdx = 1;
    g_pong.bdy = 1;
    g_pong.score = 0;
    g_pong.game_over = BOOL_FALSE;
    g_pong.last_move_tick = gui_get_tick();
}

static void pong_update(void)
{
    if (g_pong.game_over) return;

    g_pong.bx += g_pong.bdx;
    g_pong.by += g_pong.bdy;

    /* Bounce left/right walls */
    if (g_pong.bx <= 0) {
        g_pong.bx = 0;
        g_pong.bdx = -g_pong.bdx;
    } else if (g_pong.bx >= SNAKE_BOARD_W - 1) {
        g_pong.bx = SNAKE_BOARD_W - 1;
        g_pong.bdx = -g_pong.bdx;
    }

    /* Bounce ceiling */
    if (g_pong.by <= 0) {
        g_pong.by = 0;
        g_pong.bdy = -g_pong.bdy;
    }

    /* Paddle collision */
    if (g_pong.by == SNAKE_BOARD_H - 1) {
        if (g_pong.bx >= g_pong.px && g_pong.bx < g_pong.px + g_pong.pw) {
            g_pong.bdy = -g_pong.bdy;
            g_pong.score += 5;
            if (g_pong.score > g_pong.hi_score)
                g_pong.hi_score = g_pong.score;
        }
    }

    /* Ball drop gameover */
    if (g_pong.by >= SNAKE_BOARD_H) {
        g_pong.game_over = BOOL_TRUE;
    }
}

static void pong_draw(Window *win)
{
    char buf[32];

    /* Update ball movement every 2 ticks */
    uint32_t current_tick = gui_get_tick();
    if (current_tick - g_pong.last_move_tick >= 2) {
        pong_update();
        g_pong.last_move_tick = current_tick;
    }

    /* Draw Header/Info */
    kitoa(g_pong.score, buf);
    gui_label(win, 1, 0, "Score: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 8, 0, buf, COL_LABEL_VAL, COL_WIN_BG);

    kitoa(g_pong.hi_score, buf);
    gui_label(win, 18, 0, "Hi-Score: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 28, 0, buf, COL_LABEL_VAL, COL_WIN_BG);

    gui_label(win, 45, 0, "A/D: Move Paddle | R: Restart | ESC: Exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Draw Board Frame */
    fb_fill(win->x + 1, win->y + 5, SNAKE_BOARD_W + 2, SNAKE_BOARD_H + 2, ' ', COL_TEXT, COL_BLACK);
    fb_draw_box(win->x + 1, win->y + 5, SNAKE_BOARD_W + 2, SNAKE_BOARD_H + 2, COL_WIN_BORDER, COL_BLACK);

    /* Draw Paddle */
    for (int i = 0; i < g_pong.pw; i++) {
        fb_set(win->x + 2 + g_pong.px + i, win->y + 6 + SNAKE_BOARD_H - 1, '=', COL_OK, COL_BLACK);
    }

    /* Draw Ball */
    if (!g_pong.game_over) {
        fb_set(win->x + 2 + g_pong.bx, win->y + 6 + g_pong.by, 'O', COL_ACCENT, COL_BLACK);
    }

    /* Game Over Message Overlay */
    if (g_pong.game_over) {
        fb_fill(win->x + 25, win->y + 11, 30, 5, ' ', COL_WHITE, COL_DESKTOP_BG);
        fb_draw_box(win->x + 25, win->y + 11, 30, 5, COL_ERR, COL_DESKTOP_BG);
        fb_print(win->x + 35, win->y + 12, "GAME OVER", COL_ERR, COL_DESKTOP_BG);
        fb_print(win->x + 27, win->y + 14, "Press R to play again", COL_WHITE, COL_DESKTOP_BG);
    }
}

static void pong_input(Window *win, char key)
{
    (void)win;
    if (key == 'a' || key == 'A' || key == 'D') {
        if (g_pong.px > 0) g_pong.px -= 3;
    }
    else if (key == 'd' || key == 'D' || key == 'C') {
        if (g_pong.px < SNAKE_BOARD_W - g_pong.pw) g_pong.px += 3;
    }
    else if (key == 'r' || key == 'R') {
        pong_init();
    }
    else if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 2: Tic-Tac-Toe Game
 * ───────────────────────────────────────────────────────────────── */
typedef struct {
    int board[9]; /* 0 = Empty, 1 = Player (X), 2 = CPU (O) */
    int cursor;   /* 0 to 8 select cell */
    int winner;   /* 0 = None, 1 = Player, 2 = CPU, 3 = Draw */
    BOOL player_turn;
} TttGame;

static TttGame g_ttt;

static void ttt_init(void)
{
    for (int i = 0; i < 9; i++) g_ttt.board[i] = 0;
    g_ttt.cursor = 4;
    g_ttt.winner = 0;
    g_ttt.player_turn = BOOL_TRUE;
}

static int check_ttt_winner(const int *board)
{
    static const int wins[8][3] = {
        {0,1,2}, {3,4,5}, {6,7,8}, /* rows */
        {0,3,6}, {1,4,7}, {2,5,8}, /* cols */
        {0,4,8}, {2,4,6}           /* diags */
    };
    for (int i = 0; i < 8; i++) {
        if (board[wins[i][0]] != 0 &&
            board[wins[i][0]] == board[wins[i][1]] &&
            board[wins[i][0]] == board[wins[i][2]]) {
            return board[wins[i][0]];
        }
    }
    BOOL has_empty = BOOL_FALSE;
    for (int i = 0; i < 9; i++) {
        if (board[i] == 0) has_empty = BOOL_TRUE;
    }
    if (!has_empty) return 3; /* Draw */
    return 0;
}

static void ttt_cpu_move(void)
{
    /* 1. Try to win */
    for (int i = 0; i < 9; i++) {
        if (g_ttt.board[i] == 0) {
            g_ttt.board[i] = 2;
            if (check_ttt_winner(g_ttt.board) == 2) return;
            g_ttt.board[i] = 0;
        }
    }
    /* 2. Block player */
    for (int i = 0; i < 9; i++) {
        if (g_ttt.board[i] == 0) {
            g_ttt.board[i] = 1;
            if (check_ttt_winner(g_ttt.board) == 1) {
                g_ttt.board[i] = 2;
                return;
            }
            g_ttt.board[i] = 0;
        }
    }
    /* 3. Play center */
    if (g_ttt.board[4] == 0) {
        g_ttt.board[4] = 2;
        return;
    }
    /* 4. Play first empty */
    for (int i = 0; i < 9; i++) {
        if (g_ttt.board[i] == 0) {
            g_ttt.board[i] = 2;
            return;
        }
    }
}

static void ttt_draw(Window *win)
{
    gui_label_bold(win, 1, 0, "Tic-Tac-Toe vs CPU AI", COL_ACCENT, COL_WIN_BG);
    gui_label(win, 45, 0, "WASD: Move Cursor | ENTER: Place | ESC: Exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Render the grid cells */
    int bx = 28;
    int by = 5;

    /* Draw Tic-Tac-Toe Board outline */
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
            int cell_idx = r * 3 + c;
            BOOL selected = (cell_idx == g_ttt.cursor && g_ttt.winner == 0);
            uint8_t bg = selected ? COL_BTN_ACTIVE_BG : COL_BLACK;
            uint8_t fg = selected ? COL_BTN_ACTIVE_FG : COL_WHITE;

            char char_symbol = ' ';
            if (g_ttt.board[cell_idx] == 1) {
                char_symbol = 'X';
                if (!selected) fg = COL_OK;
            } else if (g_ttt.board[cell_idx] == 2) {
                char_symbol = 'O';
                if (!selected) fg = COL_ACCENT;
            }

            /* Draw 5x3 character box per cell */
            fb_fill(win->x + bx + c * 8, win->y + by + r * 4, 7, 3, ' ', fg, bg);
            fb_set(win->x + bx + c * 8 + 3, win->y + by + r * 4 + 1, char_symbol, fg, bg);
        }
    }

    /* Draw Board Lines */
    for (int row_line = 0; row_line < 2; row_line++) {
        fb_hline(win->x + bx, win->y + by + 3 + row_line * 4, 23, COL_WIN_BORDER, COL_WIN_BG);
    }
    for (int col_line = 0; col_line < 2; col_line++) {
        for (int line_y = 0; line_y < 11; line_y++) {
            fb_set(win->x + bx + 7 + col_line * 8, win->y + by + line_y, '|', COL_WIN_BORDER, COL_WIN_BG);
        }
    }

    /* Draw game over state overlay */
    if (g_ttt.winner != 0) {
        fb_fill(win->x + 25, win->y + 11, 30, 5, ' ', COL_WHITE, COL_DESKTOP_BG);
        fb_draw_box(win->x + 25, win->y + 11, 30, 5, COL_WIN_FOCUS_BG, COL_DESKTOP_BG);
        if (g_ttt.winner == 1) {
            fb_print(win->x + 31, win->y + 12, "YOU WIN!", COL_OK, COL_DESKTOP_BG);
        } else if (g_ttt.winner == 2) {
            fb_print(win->x + 31, win->y + 12, "CPU WINS!", COL_ERR, COL_DESKTOP_BG);
        } else {
            fb_print(win->x + 32, win->y + 12, "IT'S A DRAW", COL_ACCENT, COL_DESKTOP_BG);
        }
        fb_print(win->x + 27, win->y + 14, "Press R to play again", COL_WHITE, COL_DESKTOP_BG);
    }
}

static void ttt_input(Window *win, char key)
{
    (void)win;
    if (g_ttt.winner == 0 && g_ttt.player_turn) {
        if (key == 'w' || key == 'W' || key == 'A') {
            if (g_ttt.cursor >= 3) g_ttt.cursor -= 3;
        }
        else if (key == 's' || key == 'S' || key == 'B') {
            if (g_ttt.cursor <= 5) g_ttt.cursor += 3;
        }
        else if (key == 'a' || key == 'A' || key == 'D') {
            if (g_ttt.cursor % 3 > 0) g_ttt.cursor -= 1;
        }
        else if (key == 'd' || key == 'D' || key == 'C') {
            if (g_ttt.cursor % 3 < 2) g_ttt.cursor += 1;
        }
        else if (key == '\r' || key == '\n' || key == ' ') {
            if (g_ttt.board[g_ttt.cursor] == 0) {
                g_ttt.board[g_ttt.cursor] = 1;
                g_ttt.winner = check_ttt_winner(g_ttt.board);

                if (g_ttt.winner == 0) {
                    g_ttt.player_turn = BOOL_FALSE;
                    ttt_cpu_move();
                    g_ttt.winner = check_ttt_winner(g_ttt.board);
                    g_ttt.player_turn = BOOL_TRUE;
                }
            }
        }
    }

    if (key == 'r' || key == 'R') {
        ttt_init();
    }
    else if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 3: CPU Performance Monitor
 * ───────────────────────────────────────────────────────────────── */
#define MON_HIST_SIZE 74
static uint32_t g_mon_history[MON_HIST_SIZE];
static int      g_mon_size = 0;
static uint32_t g_last_cycles = 0;

static void monitor_draw(Window *win)
{
    char buf[32];
    uint32_t cycles = csr_mcycle();
    uint32_t delta = cycles - g_last_cycles;
    g_last_cycles = cycles;

    /* Scaled load calculation based on instruction activity */
    uint32_t load = (delta / 1200) % 100;
    if (load > 100) load = 100;
    if (load < 5) load = 5; /* idle load */

    /* Append to history rolling buffer */
    if (g_mon_size < MON_HIST_SIZE) {
        g_mon_history[g_mon_size++] = load;
    } else {
        for (int i = 0; i < MON_HIST_SIZE - 1; i++) {
            g_mon_history[i] = g_mon_history[i + 1];
        }
        g_mon_history[MON_HIST_SIZE - 1] = load;
    }

    gui_label_bold(win, 1, 0, "Live CPU Performance Monitor", COL_ACCENT, COL_WIN_BG);
    gui_label(win, 50, 0, "Press ESC to exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Draw Waveform / Vertical Histogram */
    for (int col = 0; col < g_mon_size; col++) {
        uint32_t val = g_mon_history[col];
        int h = (val * 13) / 100;
        if (h > 13) h = 13;
        if (h < 1) h = 1;

        for (int row = 0; row < 13; row++) {
            int ay = win->y + 5 + row;
            int ax = win->x + 2 + col;
            if (13 - row <= h) {
                uint8_t color = (val > 80) ? COL_ERR : ((val > 50) ? COL_WARN : COL_OK);
                fb_set(ax, ay, '#', color, COL_BLACK);
            } else {
                fb_set(ax, ay, ' ', COL_TEXT, COL_BLACK);
            }
        }
    }

    /* Draw border around chart */
    fb_draw_box(win->x + 1, win->y + 4, MON_HIST_SIZE + 2, 15, COL_WIN_BORDER, COL_WIN_BG);

    /* Print live parameters below */
    kitoa(load, buf);
    gui_label(win, 1, 18, "Current Load: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 15, 18, buf, COL_LABEL_VAL, COL_WIN_BG);
    gui_label(win, 18, 18, "%", COL_LABEL_VAL, COL_WIN_BG);

    kitoa(cycles, buf);
    gui_label(win, 30, 18, "Cycle count: ", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 43, 18, buf, COL_LABEL_VAL, COL_WIN_BG);
}

static void monitor_input(Window *win, char key)
{
    (void)win;
    if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 4: CSR Inspector
 * ───────────────────────────────────────────────────────────────── */
typedef struct {
    const char *name;
    uint16_t    addr;
    const char *desc;
} CsrDefinition;

static const CsrDefinition g_csr_defs[] = {
    {"mstatus",   0x300, "Machine Status: Controls global interrupts and privileges."},
    {"misa",      0x301, "Machine ISA: Declares supported subsets (I, M, A, S, U)."},
    {"mvendorid", 0xF11, "Vendor ID: Standard manufacturer identifier code."},
    {"marchid",   0xF12, "Architecture ID: Core processor design designator."},
    {"mimpid",    0xF13, "Implementation ID: Chip revision configuration tag."},
    {"mhartid",   0xF14, "Hart ID: Numbered thread core ID (typically 0 on boot)."},
    {"mtvec",     0x305, "Trap Vector: Exception redirection address entry vector."},
    {"mscratch",  0x340, "Scratch: Temporary read-write register for trap routine stack."},
    {"mepc",      0x341, "Exception PC: Saved address of instruction causing the trap."},
    {"mcause",    0x342, "Trap Cause: Unique integer reason indicating why exception hit."},
    {"mtval",     0x343, "Trap Value: Context data (e.g. invalid instruction code)."},
    {"mcycle",    0xB00, "Cycle Counter: CPU clock ticks elapsed since CPU reset."}
};
#define NUM_CSRS 12

static int g_selected_csr = 0;

static uint32_t read_csr_value(uint16_t addr)
{
    uint32_t val = 0;
    switch (addr) {
        case 0x300: asm volatile("csrr %0, mstatus" : "=r"(val)); break;
        case 0x301: asm volatile("csrr %0, misa" : "=r"(val)); break;
        case 0xF11: asm volatile("csrr %0, mvendorid" : "=r"(val)); break;
        case 0xF12: asm volatile("csrr %0, marchid" : "=r"(val)); break;
        case 0xF13: asm volatile("csrr %0, mimpid" : "=r"(val)); break;
        case 0xF14: asm volatile("csrr %0, mhartid" : "=r"(val)); break;
        case 0x305: asm volatile("csrr %0, mtvec" : "=r"(val)); break;
        case 0x340: asm volatile("csrr %0, mscratch" : "=r"(val)); break;
        case 0x341: asm volatile("csrr %0, mepc" : "=r"(val)); break;
        case 0x342: asm volatile("csrr %0, mcause" : "=r"(val)); break;
        case 0x343: asm volatile("csrr %0, mtval" : "=r"(val)); break;
        case 0xB00: asm volatile("csrr %0, mcycle" : "=r"(val)); break;
    }
    return val;
}

static void csr_draw(Window *win)
{
    char buf[32];
    gui_label_bold(win, 1, 0, "Interactive CSR Inspector", COL_ACCENT, COL_WIN_BG);
    gui_label(win, 50, 0, "UP/DOWN to select | ESC to exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Draw Left Menu - CSR list */
    for (int i = 0; i < NUM_CSRS; i++) {
        BOOL sel = (i == g_selected_csr);
        uint8_t fg = sel ? COL_BTN_ACTIVE_FG : COL_TEXT;
        uint8_t bg = sel ? COL_BTN_ACTIVE_BG : COL_WIN_BG;
        gui_label(win, 1, 3 + i, g_csr_defs[i].name, fg, bg);
    }

    /* Separator line */
    for (int y = 0; y < 14; y++) {
        fb_set(win->x + 15, win->y + 5 + y, '|', COL_WIN_BORDER, COL_WIN_BG);
    }

    /* Draw Right Panel - Details */
    const CsrDefinition *cur = &g_csr_defs[g_selected_csr];
    gui_label_bold(win, 18, 3, "Register details:", COL_ACCENT, COL_WIN_BG);

    gui_kv_row(win, 18, 5, 14, "CSR Name:     ", cur->name);

    kitohex(cur->addr, buf);
    gui_kv_row(win, 18, 6, 14, "Address:      ", buf);

    uint32_t val = read_csr_value(cur->addr);
    kitohex(val, buf);
    gui_kv_row(win, 18, 7, 14, "Value Hex:    ", buf);

    kitoa(val, buf);
    gui_kv_row(win, 18, 8, 14, "Value Dec:    ", buf);

    /* Draw instruction modification instructions for writable ones */
    if (cur->addr == 0x340) { /* mscratch */
        gui_separator(win, 10);
        gui_label_bold(win, 18, 11, "Writable register!", COL_OK, COL_WIN_BG);
        gui_label(win, 18, 12, "Press + to increment value in hardware", COL_WHITE, COL_WIN_BG);
        gui_label(win, 18, 13, "Press - to decrement value in hardware", COL_WHITE, COL_WIN_BG);
    }

    gui_separator(win, 15);
    gui_label_bold(win, 1, 17, "Description:", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 1, 18, cur->desc, COL_LABEL_VAL, COL_WIN_BG);
}

static void csr_input(Window *win, char key)
{
    (void)win;
    if (key == 'w' || key == 'W' || key == 'A') {
        if (g_selected_csr > 0) g_selected_csr--;
    }
    else if (key == 's' || key == 'S' || key == 'B') {
        if (g_selected_csr < NUM_CSRS - 1) g_selected_csr++;
    }
    else if (key == '+') {
        if (g_csr_defs[g_selected_csr].addr == 0x340) { /* mscratch */
            uint32_t val = read_csr_value(0x340);
            asm volatile("csrw mscratch, %0" :: "r"(val + 1));
            log_push("Hardware scratch register incremented");
        }
    }
    else if (key == '-') {
        if (g_csr_defs[g_selected_csr].addr == 0x340) {
            uint32_t val = read_csr_value(0x340);
            asm volatile("csrw mscratch, %0" :: "r"(val - 1));
            log_push("Hardware scratch register decremented");
        }
    }
    else if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 5: Memory Viewer
 * ───────────────────────────────────────────────────────────────── */
typedef struct {
    uint32_t start_addr;
    uint32_t cursor_addr;
} MemoryViewerState;

static MemoryViewerState g_mem_view = {0x80000000, 0x80000000};

static void memory_draw(Window *win)
{
    char buf[32];
    gui_label_bold(win, 1, 0, "Interactive Memory Viewer (DRAM)", COL_ACCENT, COL_WIN_BG);
    gui_label(win, 50, 0, "UP/DOWN to select | + / - to edit | ESC to exit", COL_DIMTEXT, COL_WIN_BG);
    gui_separator(win, 1);

    /* Table headers */
    gui_label_bold(win, 1, 3, "Address", COL_LABEL_KEY, COL_WIN_BG);
    gui_label_bold(win, 15, 3, "Hex Word", COL_LABEL_KEY, COL_WIN_BG);
    gui_label_bold(win, 30, 3, "Byte 0  Byte 1  Byte 2  Byte 3", COL_LABEL_KEY, COL_WIN_BG);
    gui_label_bold(win, 62, 3, "ASCII", COL_LABEL_KEY, COL_WIN_BG);
    gui_separator(win, 4);

    uint32_t addr = g_mem_view.start_addr;
    for (int r = 0; r < 12; r++) {
        if (addr >= 0x80000000 && addr < 0x88000000) {
            uint32_t val = MMIO32(addr);
            BOOL active = (addr == g_mem_view.cursor_addr);
            uint8_t fg = active ? COL_BTN_ACTIVE_FG : COL_TEXT;
            uint8_t bg = active ? COL_BTN_ACTIVE_BG : COL_WIN_BG;

            kitohex(addr, buf);
            gui_label(win, 1, 5 + r, buf, COL_LABEL_KEY, bg);

            kitohex(val, buf);
            gui_label(win, 15, 5 + r, buf, fg, bg);

            /* Byte values */
            for (int b = 0; b < 4; b++) {
                uint8_t byte = (val >> (b * 8)) & 0xFF;
                char b_str[4];
                b_str[0] = "0123456789ABCDEF"[(byte >> 4) & 0xF];
                b_str[1] = "0123456789ABCDEF"[byte & 0xF];
                b_str[2] = ' ';
                b_str[3] = '\0';
                gui_label(win, 30 + b * 8, 5 + r, b_str, COL_LABEL_VAL, bg);
            }

            /* ASCII translation */
            char a_str[5];
            for (int b = 0; b < 4; b++) {
                uint8_t byte = (val >> (b * 8)) & 0xFF;
                a_str[b] = (byte >= 32 && byte < 127) ? (char)byte : '.';
            }
            a_str[4] = '\0';
            gui_label(win, 62, 5 + r, a_str, fg, bg);
        }
        addr += 4;
    }

    gui_separator(win, 17);
    gui_label(win, 1, 18, "DRAM Map: 0x80000000 - 0x88000000 (128M)", COL_SUBTEXT, COL_WIN_BG);
}

static void memory_input(Window *win, char key)
{
    (void)win;
    if (key == 'w' || key == 'W' || key == 'A') {
        if (g_mem_view.cursor_addr > 0x80000000) {
            g_mem_view.cursor_addr -= 4;
            if (g_mem_view.cursor_addr < g_mem_view.start_addr) {
                g_mem_view.start_addr = g_mem_view.cursor_addr;
            }
        }
    }
    else if (key == 's' || key == 'S' || key == 'B') {
        if (g_mem_view.cursor_addr < 0x88000000 - 4) {
            g_mem_view.cursor_addr += 4;
            if (g_mem_view.cursor_addr >= g_mem_view.start_addr + 12 * 4) {
                g_mem_view.start_addr = g_mem_view.cursor_addr - 11 * 4;
            }
        }
    }
    else if (key == '+') {
        uint32_t val = MMIO32(g_mem_view.cursor_addr);
        MMIO32(g_mem_view.cursor_addr) = val + 1;
        log_push("Memory incremented at cursor address");
    }
    else if (key == '-') {
        uint32_t val = MMIO32(g_mem_view.cursor_addr);
        MMIO32(g_mem_view.cursor_addr) = val - 1;
        log_push("Memory decremented at cursor address");
    }
    else if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APPLICATION 6: About System
 * ───────────────────────────────────────────────────────────────── */
static void about_draw(Window *win)
{
    gui_label_bold(win, 1, 0, "About RISC-V MicroKernel OS", COL_ACCENT, COL_WIN_BG);
    gui_separator(win, 1);

    gui_label(win, 1, 3, "Kernel Target:  RV32IMA_Zicsr freestanding binary", COL_WHITE, COL_WIN_BG);
    gui_label(win, 1, 5, "Built with:     xPack GCC 15.2.0 for bare-metal targets", COL_WHITE, COL_WIN_BG);
    gui_label(win, 1, 7, "GUI Engine:     Interactive double-buffered TUI shell", COL_WHITE, COL_WIN_BG);
    gui_label(win, 1, 9, "Baud rate:      115200 8N1 serial port MMIO", COL_WHITE, COL_WIN_BG);

    gui_separator(win, 11);
    gui_label_bold(win, 1, 13, "OS Contributors:", COL_LABEL_KEY, COL_WIN_BG);
    gui_label(win, 1, 14, "Developed as a co-design testbed for RISC-V Microkernels.", COL_SUBTEXT, COL_WIN_BG);

    gui_label(win, 1, 18, "Press ESC to return to Desktop.", COL_DIMTEXT, COL_WIN_BG);
}

static void about_input(Window *win, char key)
{
    (void)win;
    if (key == '\033') {
        close_active_app();
    }
}

/* ─────────────────────────────────────────────────────────────────
 * APP LAUNCH CONTROLS
 * ───────────────────────────────────────────────────────────────── */
static void launch_app(int app_id)
{
    g_active_app = app_id;

    /* Hide Desktop Windows */
    Window *w_info = gui_get_window(g_win_sysinfo);
    Window *w_launch = gui_get_window(g_win_launcher);
    Window *w_log = gui_get_window(g_win_actlog);

    if (w_info) w_info->flags &= ~GUI_FLAG_VISIBLE;
    if (w_launch) w_launch->flags &= ~GUI_FLAG_VISIBLE;
    if (w_log) w_log->flags &= ~GUI_FLAG_VISIBLE;

    /* Display selected app window */
    int active_win_idx = -1;
    if (app_id == 0) { snake_init(); active_win_idx = g_win_snake; log_push("Launched Snake Game"); }
    else if (app_id == 1) { pong_init(); active_win_idx = g_win_pong; log_push("Launched Pong Game"); }
    else if (app_id == 2) { ttt_init(); active_win_idx = g_win_ttt; log_push("Launched Tic-Tac-Toe"); }
    else if (app_id == 3) { active_win_idx = g_win_monitor; log_push("Launched Performance Monitor"); }
    else if (app_id == 4) { active_win_idx = g_win_csr; log_push("Launched CSR Inspector"); }
    else if (app_id == 5) { active_win_idx = g_win_mem; log_push("Launched Memory Viewer"); }
    else if (app_id == 6) { active_win_idx = g_win_about; log_push("Launched About Screen"); }

    if (active_win_idx >= 0) {
        Window *app_win = gui_get_window(active_win_idx);
        if (app_win) {
            app_win->flags |= GUI_FLAG_VISIBLE;
            gui_set_focus(active_win_idx);
        }
    }
}

static void close_active_app(void)
{
    /* Hide active app window */
    int active_win_idx = -1;
    if (g_active_app == 0) active_win_idx = g_win_snake;
    else if (g_active_app == 1) active_win_idx = g_win_pong;
    else if (g_active_app == 2) active_win_idx = g_win_ttt;
    else if (g_active_app == 3) active_win_idx = g_win_monitor;
    else if (g_active_app == 4) active_win_idx = g_win_csr;
    else if (g_active_app == 5) active_win_idx = g_win_mem;
    else if (g_active_app == 6) active_win_idx = g_win_about;

    if (active_win_idx >= 0) {
        Window *app_win = gui_get_window(active_win_idx);
        if (app_win) app_win->flags &= ~GUI_FLAG_VISIBLE;
    }

    g_active_app = -1;
    log_push("Returned to Desktop shell");

    /* Restore Desktop Windows */
    Window *w_info = gui_get_window(g_win_sysinfo);
    Window *w_launch = gui_get_window(g_win_launcher);
    Window *w_log = gui_get_window(g_win_actlog);

    if (w_info) w_info->flags |= GUI_FLAG_VISIBLE;
    if (w_launch) w_launch->flags |= GUI_FLAG_VISIBLE;
    if (w_log) w_log->flags |= GUI_FLAG_VISIBLE;

    gui_set_focus(g_win_launcher);
}

/* ─────────────────────────────────────────────────────────────────
 * DESKTOP BOOT LOGO (drawn once to log)
 * ───────────────────────────────────────────────────────────────── */
static void splash_log(void)
{
    log_push("RISC-V MicroKernel OS booted successfully");
    log_push("Platform: QEMU virt (RV32IMA_Zicsr), UART0 @ 0x10000000");
    log_push("Framebuffer: 80x24 ANSI VT100 (256-colour terminal)");
    log_push("GUI engine: Multi-app overlay shell");
    log_push("Press TAB to switch focus. ENTER to launch. Q to quit.");
}

/* ─────────────────────────────────────────────────────────────────
 * desktop_run() — main entry point
 * ───────────────────────────────────────────────────────────────── */
void desktop_run(void)
{
    gui_init();

    /* ── [0] System Info — left column ── */
    g_win_sysinfo = gui_add_window(
        0, 1, 38, 22,
        "System Info",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        sysinfo_draw, sysinfo_input, NULL
    );

    /* ── [1] App Launcher — right column ── */
    g_win_launcher = gui_add_window(
        38, 1, 42, 15,
        "App Launcher",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        launcher_draw, launcher_input, NULL
    );

    /* ── [2] Activity Log — bottom right ── */
    g_win_actlog = gui_add_window(
        38, 16, 42, 7,
        "Activity Log",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        actlog_draw, actlog_input, NULL
    );

    /* ── [3] Snake Game Window — overlay ── */
    g_win_snake = gui_add_window(
        0, 1, 80, 22,
        "Playable Snake Game",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        snake_draw, snake_input, NULL
    );
    /* Initially hidden */
    Window *ws = gui_get_window(g_win_snake);
    if (ws) ws->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [4] Pong Game Window — overlay ── */
    g_win_pong = gui_add_window(
        0, 1, 80, 22,
        "Playable Solo Pong",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        pong_draw, pong_input, NULL
    );
    Window *wp = gui_get_window(g_win_pong);
    if (wp) wp->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [5] Tic-Tac-Toe Window — overlay ── */
    g_win_ttt = gui_add_window(
        0, 1, 80, 22,
        "Tic-Tac-Toe vs CPU AI",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        ttt_draw, ttt_input, NULL
    );
    Window *wt = gui_get_window(g_win_ttt);
    if (wt) wt->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [6] System Monitor Window — overlay ── */
    g_win_monitor = gui_add_window(
        0, 1, 80, 22,
        "Performance Waveform Monitor",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        monitor_draw, monitor_input, NULL
    );
    Window *wm = gui_get_window(g_win_monitor);
    if (wm) wm->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [7] CSR Inspector Window — overlay ── */
    g_win_csr = gui_add_window(
        0, 1, 80, 22,
        "CSR Register Inspector",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        csr_draw, csr_input, NULL
    );
    Window *wc = gui_get_window(g_win_csr);
    if (wc) wc->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [8] Memory Viewer Window — overlay ── */
    g_win_mem = gui_add_window(
        0, 1, 80, 22,
        "DRAM Memory Browser",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        memory_draw, memory_input, NULL
    );
    Window *we = gui_get_window(g_win_mem);
    if (we) we->flags &= ~GUI_FLAG_VISIBLE;

    /* ── [9] About OS Window — overlay ── */
    g_win_about = gui_add_window(
        0, 1, 80, 22,
        "OS Information Details",
        GUI_FLAG_BORDER | GUI_FLAG_TITLEBAR,
        about_draw, about_input, NULL
    );
    Window *wa = gui_get_window(g_win_about);
    if (wa) wa->flags &= ~GUI_FLAG_VISIBLE;

    /* Focus starts on the launcher */
    gui_set_focus(g_win_launcher);

    /* Write boot messages to the log */
    splash_log();

    /* ── Main event loop ─────────────────────────────────────── */
    while (1) {
        gui_render();

        int key_raw = uart_getc_nb();
        if (key_raw >= 0) {
            char key = (char)key_raw;

            if (key == '\033') {
                int c2 = uart_getc_nb();
                if (c2 == '[') {
                    int c3 = uart_getc_nb();
                    if (c3 >= 0) key = (char)c3; /* A=up B=dn C=rt D=lt */
                    else         key = 0;
                }
            }

            if (key) {
                if (key != '\t' && key != '\033') {
                    char kmsg[32];
                    const char *kpref = "Key pressed: [";
                    int j = 0;
                    while (kpref[j]) { kmsg[j] = kpref[j]; j++; }
                    kmsg[j++] = (key >= 0x20 && key < 0x7F) ? key : '?';
                    kmsg[j++] = ']';
                    kmsg[j] = '\0';
                    log_push(kmsg);
                }

                int quit = gui_handle_input(key);
                if (quit) break;
            }
        }

        /* Limit event loop to 30 FPS (approx 33 ms per frame) */
        delay_ms(33);
    }
}
