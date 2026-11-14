#include <stdint.h>

#define N 24

static const uint32_t seeds[4] = {0x12345678u, 0x9E3779B9u, 0x7F4A7C15u, 0x2545F491u};

static uint32_t xorshift32(uint32_t x)
{
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return x;
}

__attribute__((noipa)) static void fill(uint32_t *a, unsigned n, uint32_t s)
{
    for (unsigned i = 0; i < n; i++) {
        s = xorshift32(s);
        a[i] = s >> 8;
    }
}

__attribute__((noipa)) static void sort(uint32_t *a, unsigned n)
{
    for (unsigned i = 1; i < n; i++) {
        uint32_t v = a[i];
        unsigned j = i;
        while (j > 0 && a[j - 1] > v) {
            a[j] = a[j - 1];
            j--;
        }
        a[j] = v;
    }
}

__attribute__((noipa)) static uint32_t checksum(const uint32_t *a, unsigned n)
{
    uint32_t h = 0x811C9DC5u;
    for (unsigned i = 0; i < n; i++) {
        h ^= a[i];
        h = ((h << 5) | (h >> 27)) + (h >> 3) + i;
        if (h & 1u)
            h ^= 0xA5A5A5A5u;
    }
    return h;
}

int main(void)
{
    uint32_t a[N];
    uint32_t total = 0;
    for (unsigned k = 0; k < 4; k++) {
        fill(a, N, seeds[k]);
        sort(a, N);
        total ^= checksum(a, N) + k;
    }
    return (int)total;
}
