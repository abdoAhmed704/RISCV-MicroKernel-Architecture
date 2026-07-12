/* Direct MMIO — bypass ecall/trap overhead entirely */
#define UART_ADDR ((volatile unsigned char *)0x00003FF0)

#define BOARD_W 20
#define BOARD_H 10
#define MAX_SNAKE 64

volatile int m_trap_occurred;
volatile int s_trap_occurred;
volatile int s_mode_entered;

void m_trap_handler(void);
void s_trap_handler(void);

static unsigned char snake_x[MAX_SNAKE];
static unsigned char snake_y[MAX_SNAKE];
static unsigned char snake_len;
static unsigned char dir;
static unsigned char food_x;
static unsigned char food_y;
static unsigned int tick_count;
static unsigned char game_over;

static void sys_putc(unsigned char ch)
{
    *UART_ADDR = ch;
}

static unsigned char sys_getc(void)
{
    return *UART_ADDR;
}

static void put_hex_nibble(unsigned int value)
{
    value &= 0xFu;
    if (value < 10u) {
        sys_putc((unsigned char)('0' + value));
    } else {
        sys_putc((unsigned char)('A' + value - 10u));
    }
}

static void put_hex8(unsigned int value)
{
    put_hex_nibble(value >> 4);
    put_hex_nibble(value);
}

static void screen_clear(void)
{
    sys_putc(27);
    sys_putc('[');
    sys_putc('2');
    sys_putc('J');
    sys_putc(27);
    sys_putc('[');
    sys_putc('H');
}

static void screen_home(void)
{
    sys_putc(27);
    sys_putc('[');
    sys_putc('H');
}

static void print_title(void)
{
    sys_putc('R'); sys_putc('I'); sys_putc('S'); sys_putc('C'); sys_putc('-');
    sys_putc('V'); sys_putc(' '); sys_putc('S'); sys_putc('n'); sys_putc('a');
    sys_putc('k'); sys_putc('e'); sys_putc(' '); sys_putc('O'); sys_putc('S');
    sys_putc('\n');
    sys_putc('W'); sys_putc('A'); sys_putc('S'); sys_putc('D'); sys_putc(' ');
    sys_putc('m'); sys_putc('o'); sys_putc('v'); sys_putc('e'); sys_putc(',');
    sys_putc(' '); sys_putc('Q'); sys_putc(' '); sys_putc('r'); sys_putc('e');
    sys_putc('s'); sys_putc('e'); sys_putc('t'); sys_putc('\n');
}

static void game_init(void)
{
    snake_len = 4;
    snake_x[0] = 10; snake_y[0] = 5;
    snake_x[1] = 9;  snake_y[1] = 5;
    snake_x[2] = 8;  snake_y[2] = 5;
    snake_x[3] = 7;  snake_y[3] = 5;
    dir = 3;
    food_x = 14;
    food_y = 4;
    tick_count = 0;
    game_over = 0;
}

static void place_food(void)
{
    unsigned char tries = 0;
    unsigned char ok = 0;

    while (!ok && tries < 40) {
        unsigned char i;
        ok = 1;
        food_x += 7;
        if (food_x >= BOARD_W) food_x -= BOARD_W;
        food_y += 3;
        if (food_y >= BOARD_H) food_y -= BOARD_H;

        for (i = 0; i < snake_len; i++) {
            if (snake_x[i] == food_x && snake_y[i] == food_y) {
                ok = 0;
            }
        }
        tries++;
    }
}

static void handle_input(void)
{
    unsigned char ch = sys_getc();
    if (ch >= 'a' && ch <= 'z') {
        ch = (unsigned char)(ch - 'a' + 'A');
    }

    if (ch == 'W' && dir != 1) dir = 0;
    if (ch == 'S' && dir != 0) dir = 1;
    if (ch == 'A' && dir != 3) dir = 2;
    if (ch == 'D' && dir != 2) dir = 3;
    if (ch == 'Q') game_init();
}

static void game_step(void)
{
    unsigned char new_x = snake_x[0];
    unsigned char new_y = snake_y[0];
    unsigned char i;
    unsigned char ate_food = 0;

    if (game_over) return;

    if (dir == 0) {
        if (new_y == 0) { game_over = 1; return; }
        new_y--;
    } else if (dir == 1) {
        new_y++;
        if (new_y >= BOARD_H) { game_over = 1; return; }
    } else if (dir == 2) {
        if (new_x == 0) { game_over = 1; return; }
        new_x--;
    } else {
        new_x++;
        if (new_x >= BOARD_W) { game_over = 1; return; }
    }

    for (i = 0; i < snake_len; i++) {
        if (snake_x[i] == new_x && snake_y[i] == new_y) {
            game_over = 1;
            return;
        }
    }

    if (new_x == food_x && new_y == food_y) {
        ate_food = 1;
        if (snake_len < MAX_SNAKE) {
            snake_len++;
        }
    }

    i = snake_len - 1;
    while (i > 0) {
        snake_x[i] = snake_x[i - 1];
        snake_y[i] = snake_y[i - 1];
        i--;
    }
    snake_x[0] = new_x;
    snake_y[0] = new_y;

    if (ate_food) {
        place_food();
    }
}

static unsigned char cell_has_snake(unsigned char x, unsigned char y, unsigned char *is_head)
{
    unsigned char i;
    for (i = 0; i < snake_len; i++) {
        if (snake_x[i] == x && snake_y[i] == y) {
            *is_head = (i == 0);
            return 1;
        }
    }
    *is_head = 0;
    return 0;
}

static void render_board(void)
{
    unsigned char x;
    unsigned char y;

    screen_home();
    print_title();
    sys_putc('T'); sys_putc('=');
    put_hex8(tick_count);
    sys_putc(' ');
    sys_putc('L'); sys_putc('=');
    put_hex8(snake_len);
    sys_putc('\n');

    for (x = 0; x < BOARD_W + 2; x++) sys_putc('#');
    sys_putc('\n');

    for (y = 0; y < BOARD_H; y++) {
        sys_putc('#');
        for (x = 0; x < BOARD_W; x++) {
            unsigned char is_head = 0;
            if (cell_has_snake(x, y, &is_head)) {
                sys_putc(is_head ? '@' : 'o');
            } else if (x == food_x && y == food_y) {
                sys_putc('*');
            } else {
                sys_putc(' ');
            }
        }
        sys_putc('#');
        sys_putc('\n');
    }

    for (x = 0; x < BOARD_W + 2; x++) sys_putc('#');
    sys_putc('\n');

    if (game_over) {
        sys_putc('G'); sys_putc('A'); sys_putc('M'); sys_putc('E'); sys_putc(' ');
        sys_putc('O'); sys_putc('V'); sys_putc('E'); sys_putc('R'); sys_putc(' ');
        sys_putc('-'); sys_putc(' '); sys_putc('Q'); sys_putc(' ');
        sys_putc('r'); sys_putc('e'); sys_putc('s'); sys_putc('e'); sys_putc('t');
        sys_putc('\n');
    }
}

static void clock_task(void)
{
    if (!game_over) {
        tick_count++;
    }
}

#define PLATFORM_ADDR ((volatile unsigned int *)0x00003FFC)

static void delay(void)
{
    volatile unsigned int i;
    unsigned int limit = 0u; // Run at maximum simulator speed (no artificial delay in Questa)
    
    if (*PLATFORM_ADDR == 0x454D554C) { // "EMUL" (web emulator)
        limit = 200000u; // Larger delay for high-speed emulated CPU
    }
    
    for (i = 0; i < limit; i++) {
        asm volatile ("nop");
    }
}

int main(void)
{
    asm volatile ("csrw mtvec, %0" :: "r"((unsigned int)m_trap_handler & ~0x3u));
    asm volatile ("csrw stvec, %0" :: "r"((unsigned int)s_trap_handler & ~0x3u));

    screen_clear();
    game_init();

    while (1) {
        handle_input();
        if (!game_over) {
            game_step();
            clock_task();
            render_board();
        }
        delay();
    }
}
