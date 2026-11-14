MASK = 0xFFFFFFFF
SEEDS = [0x12345678, 0x9E3779B9, 0x7F4A7C15, 0x2545F491]
N = 24


def xorshift32(x):
    x ^= (x << 13) & MASK
    x ^= x >> 17
    x ^= (x << 5) & MASK
    return x & MASK


def checksum(values):
    h = 0x811C9DC5
    for i, v in enumerate(values):
        h ^= v
        h = ((((h << 5) | (h >> 27)) & MASK) + (h >> 3) + i) & MASK
        if h & 1:
            h ^= 0xA5A5A5A5
    return h


def expected():
    total = 0
    for k, s in enumerate(SEEDS):
        values = []
        for _ in range(N):
            s = xorshift32(s)
            values.append(s >> 8)
        total ^= (checksum(sorted(values)) + k) & MASK
    return total


if __name__ == "__main__":
    print(f"{expected():08x}")
