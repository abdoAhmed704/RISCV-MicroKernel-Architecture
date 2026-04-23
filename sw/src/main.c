void main()
{
    // We use 'volatile' so the compiler doesn't optimize these away
    volatile int a = 5;
    volatile int b = 10;
    volatile int sum = a + b; // Should be 15 (0xF)

    // Test a Memory Write
    volatile int *data_ptr = (int *)0x100;
    *data_ptr = sum;

    // Test a Memory Read
    volatile int check = *data_ptr;

    // The Infinite Trap (Essential!)
    while (1)
    {
        asm volatile("nop");
    }
}

// int main() {
//     int sum = 0;
//     for (int i = 1; i <= 10; i++) {
//         sum += i;
//     }

//     // Write result to a specific memory address for verification
//     volatile int *res_ptr = (int *)0x2000; 
//     *res_ptr = sum;

//     return sum; 
// }
