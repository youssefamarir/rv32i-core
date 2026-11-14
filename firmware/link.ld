ENTRY(_start)
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 4K
}
SECTIONS {
    .text : { KEEP(*(.text.start)) *(.text .text.*) *(.rodata .rodata.*) *(.srodata .srodata.*) } > ROM
    .data : { *(.data .data.* .sdata .sdata.*) } > RAM AT> ROM
    .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.*) *(COMMON) } > RAM
    /DISCARD/ : { *(.eh_frame .eh_frame.*) *(.comment) *(.riscv.attributes) }
    ASSERT(SIZEOF(.data) == 0 && SIZEOF(.bss) == 0, "Implement data/bss startup before using mutable globals")
}
