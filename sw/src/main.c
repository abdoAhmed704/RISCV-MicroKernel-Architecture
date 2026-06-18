int main()
{
    volatile int limit = 5;
    int sum = 0;
    for (int i = 1; i <= limit; i++) {
        sum += i;
    }
    return sum; // Expected return: 15 (0xF) in register a0 (x10)
}