/* Match MAIR and 4 KiB granule in the vetted A53 startup.S. Normal NC for
 * PS/PL transfers, WB for private CPU RAM, Device-nGnRnE for PL/SoC MMIO. */
.section .tables,"a"
.balign 4096
.global MMUTableL0
MMUTableL0:
.quad l1 + 3
.zero 4096-8
l1:
.quad l2 + 3, l2 + 4096 + 3, l2 + 8192 + 3, l2 + 12288 + 3
.zero 4096-32
l2:
.set addr,0
.rept 2048
    .if addr >= 0x08200000 && addr < 0x10000000 || addr == 0xffe00000
        .quad addr + 0x705
    .elseif addr < 0x80000000
        .quad addr + 0x701
    .else
        .quad addr + 0x60000000000409
    .endif
    .set addr,addr+0x200000
.endr
