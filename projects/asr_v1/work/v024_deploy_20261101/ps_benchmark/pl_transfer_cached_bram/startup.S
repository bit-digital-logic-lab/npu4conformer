/* Minimal EL3 entry: reset-only, no MMU/cache setup, no MMIO. */
#ifndef V024_EXPECTED_CNTFRQ
#define V024_EXPECTED_CNTFRQ 0
#endif
.section .boot,"ax"
.global _start
_start:
 msr daifset, #0xf
 mrs x0, CurrentEL
 cmp x0, #0xc
 b.ne stop
 mrs x0, sctlr_el3
 tst x0, #1
 b.ne stop
 tst x0, #4
 b.ne stop
 tst x0, #0x1000
 b.ne stop
 ldr x0, =vectors
 msr vbar_el3, x0
 isb
 ldr x0, =__stack_top
 mov sp, x0
 mrs x0, cptr_el3
 bic x0, x0, #0x400
 bic x0, x0, #(1 << 31)
 msr cptr_el3, x0
 isb
 mrs x0, cpacr_el1
 orr x0, x0, #(3 << 20)
 msr cpacr_el1, x0
 isb
 msr fpcr, xzr
 msr fpsr, xzr
 isb
#if V024_EXPECTED_CNTFRQ > 0
 ldr x0, =V024_EXPECTED_CNTFRQ
 msr cntfrq_el0, x0
 isb
#endif
 tlbi alle3
 ic iallu
 bl invalidate_dcaches
 dsb sy
 isb
 ldr x1, =MMUTableL0
 msr ttbr0_el3, x1
 ldr x1, =0x000000BB0400FF44
 msr mair_el3, x1
 ldr x1, =0x80823518
 msr tcr_el3, x1
 isb
 mov x1, #0x100d
 msr sctlr_el3, x1
 dsb sy
 isb
 ldr x0, =__bss_start
 ldr x1, =__bss_end
1: cmp x0,x1
 b.hs 2f
 str xzr,[x0],#8
 b 1b
2: bl run_benchmark
 bl invalidate_dcaches
 dsb sy
 mrs x0, sctlr_el3
 bic x0, x0, #0x1000
 bic x0, x0, #4
 bic x0, x0, #1
 msr sctlr_el3, x0
 isb
 tlbi alle3
 ic iallu
 dsb sy
 isb
.global benchmark_done
benchmark_done:
 b benchmark_done
stop:
 b stop
.balign 2048
vectors:
.rept 16
 b stop
 .space 124
.endr

/* AMD/Xilinx standalone_v9_4 boot.S, MIT; adapted set/way loop.
 * CCSIDR line shift +4 matches standalone_v9_4 xil_cache.c Xil_DCacheFlush. */
.global invalidate_dcaches
invalidate_dcaches:

	dmb     ISH
	mrs     x0, CLIDR_EL1          //; x0 = CLIDR
	ubfx    w2, w0, #24, #3        //; w2 = CLIDR.LoC
	cmp     w2, #0                 //; LoC is 0?
	b.eq    invalidateCaches_end   //; No cleaning required and enable MMU
	mov     w1, #0                 //; w1 = level iterator

invalidateCaches_flush_level:
	add     w3, w1, w1, lsl #1     //; w3 = w1 * 3 (right-shift for cache type)
	lsr     w3, w0, w3             //; w3 = w0 >> w3
	ubfx    w3, w3, #0, #3         //; w3 = cache type of this level
	cmp     w3, #2                 //; No cache at this level?
	b.lt    invalidateCaches_next_level

	lsl     w4, w1, #1
	msr     CSSELR_EL1, x4         //; Select current cache level in CSSELR
	isb                            //; ISB required to reflect new CSIDR
	mrs     x4, CCSIDR_EL1         //; w4 = CSIDR

	ubfx    w3, w4, #0, #3
	add    	w3, w3, #4             //; w3 = log2(line size in bytes)
	ubfx    w5, w4, #13, #15
	ubfx    w4, w4, #3, #10        //; w4 = Way number
	clz     w6, w4                 //; w6 = 32 - log2(number of ways)

invalidateCaches_flush_set:
	mov     w8, w4                 //; w8 = Way number
invalidateCaches_flush_way:
	lsl     w7, w1, #1             //; Fill level field
	lsl     w9, w5, w3
	orr     w7, w7, w9             //; Fill index field
	lsl     w9, w8, w6
	orr     w7, w7, w9             //; Fill way field
	dc      CISW, x7               //; Invalidate by set/way to point of coherency
	subs    w8, w8, #1             //; Decrement way
	b.ge    invalidateCaches_flush_way
	subs    w5, w5, #1             //; Descrement set
	b.ge    invalidateCaches_flush_set

invalidateCaches_next_level:
	dsb     sy                    // drain this level before the next level
	add     w1, w1, #1             //; Next level
	cmp     w2, w1
	b.gt    invalidateCaches_flush_level

invalidateCaches_end:
	ret

