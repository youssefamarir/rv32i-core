import sys
from pathlib import Path

ROM_BYTES = 4096


def bin_to_words(data):
    if not 0 < len(data) <= ROM_BYTES:
        raise SystemExit(f"Image must fit in the 4 KiB ROM (got {len(data)} bytes)")
    data = data.ljust(ROM_BYTES, b"\x00")
    return [int.from_bytes(data[i:i + 4], "little") for i in range(0, ROM_BYTES, 4)]


def convert(bin_path, hex_path):
    words = bin_to_words(Path(bin_path).read_bytes())
    Path(hex_path).write_text("".join(f"{w:08x}\n" for w in words), encoding="ascii")
    return words


def load_hex(hex_path):
    return [int(line, 16) for line in Path(hex_path).read_text(encoding="ascii").split()]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: mkhex.py <in.bin> <out.hex>")
    convert(sys.argv[1], sys.argv[2])
