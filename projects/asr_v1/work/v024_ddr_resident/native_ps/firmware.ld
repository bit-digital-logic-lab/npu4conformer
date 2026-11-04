ENTRY(_start)
MEMORY {
    OCM (rwx) : ORIGIN = 0xfffc0000, LENGTH = 128K
    PRIVATE (rwx) : ORIGIN = 0x0f000000, LENGTH = 8M
}
SECTIONS {
    .boot ORIGIN(OCM) : { KEEP(*(.boot)) } > OCM
    .tables ALIGN(4096) : { KEEP(*(.tables)) } > OCM
    .stack (NOLOAD) : { . = ALIGN(16); . += 0x8000; __stack_top = .; } > OCM
    .text ORIGIN(PRIVATE) : { *(.text*) *(.rodata*) } > PRIVATE
    .data : { *(.data*) } > PRIVATE
    .bss (NOLOAD) : { . = ALIGN(8); __bss_start = .; *(.bss*) *(COMMON); . = ALIGN(8); __bss_end = .; } > PRIVATE
    /DISCARD/ : { *(.comment*) *(.note*) *(.eh_frame*) }
}
