int main() {
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
        sum += i;
    }

    // Write result to a specific memory address for verification
    volatile int *res_ptr = (int *)0x2000; 
    *res_ptr = sum;

    return sum; 
}
