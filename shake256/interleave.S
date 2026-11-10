    
    .syntax unified
    .thumb
    .cpu cortex-m4

    .text
    .global Keccak_ASM
    .type Keccak_ASM, %function
    .align 3
    .macro INTERLEAVE src_H, src_L, dst_E, dst_O, t1=r2, t2=r3
    movw \t2, #0x5555                   @ swap 1 bits
    movt \t2, #0x5555                   @ t2 = 0x55555555
    eor \t1, \src_H, \src_L, lsr #1
    and \t1, \t1, \t2
    eor \src_H, \src_H, \t1
    eor \src_L, \src_L, \t1, lsl #1

    movw \t2, #0x3333
    movt \t2, #0x3333
    eor \t1, \src_H, \src_L, lsr #2
    and \t1, \t1, \t2
    eor \src_H, \src_H, \t1
    eor \src_L, \src_L, \t1, lsl #2

    movw \t2, #0x0F0F
    movt \t2, #0x0F0F
    eor \t1, \src_H, \src_L, lsr #4
    and \t1, \t1, \t2
    eor \src_H, \src_H, \t1
    eor \src_L, \src_L, \t1, lsl #4

    movw \t2, #0x00FF
    movt \t2, #0x00FF
    eor \t1, \src_H, \src_L, lsr #8
    and \t1, \t1, \t2
    eor \src_H, \src_H, \t1
    eor \src_L, \src_L, \t1, lsl #8

    movw \t2, #0xFFFF
    movt \t2, #0x0000
    eor \t1, \src_H, \src_L, lsr #16
    and \t1, \t1, \t2
    eor \src_H, \src_H, \t1
    eor \src_L, \src_L, \t1, lsl #16

    mov  \dst_E, \src_L
    mov  \dst_O, \src_H
    .endm

    .macro DEINTERLEAVE src_E, src_O, dst_L, dst_H, t1=r2, t2=r3
    mov \dst_L, \src_E
    mov \dst_H, \src_O

    movw \t2, #0xFFFF
    movt \t2, #0x0000
    eor \t1, \dst_H, \dst_L, lsr #16
    and \t1, \t1, \t2
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #16

    movw \t2, #0x00FF
    movt \t2, #0x00FF
    eor \t1, \dst_H, \dst_L, lsr #8
    and \t1, \t1, \t2
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #8

    movw \t2, #0x0F0F
    movt \t2, #0x0F0F
    eor \t1, \dst_H, \dst_L, lsr #4
    and \t1, \t1, \t2
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #4

    movw \t2, #0x3333
    movt \t2, #0x3333
    eor \t1, \dst_H, \dst_L, lsr #2
    and \t1, \t1, \t2
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #2

    movw \t2, #0x5555
    movt \t2, #0x5555
    eor \t1, \dst_H, \dst_L, lsr #1
    and \t1, \t1, \t2
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #1
    .endm
        .align 2
Keccak_ASM:
    bx lr

    @ ---------------------------------------------------------------
    @ test_interleave
    @
    @   Runs the macro on a few known vectors and a round trip.
    @   Returns 0 in r0 on success, or the failed test number
    @   (1..N) in r0 on failure. Self-contained: no libc calls.
    @
    @   Callable from C as:  int test_interleave(void);
    @ ---------------------------------------------------------------
    .global test_interleave
    .type test_interleave, %function
    .align 2
test_interleave:
    push {r4-r7, lr}

    @ -------- Test 1: round-5 constant 0x0000000080000001 --------
    @ normal: src_H=0x00000000 src_L=0x80000001
    @ expect: even=0x00000001 odd=0x00008000
    movw r4, #0x0000
    movt r4, #0x0000                    @ src_H
    movw r5, #0x0001
    movt r5, #0x8000                    @ src_L
    INTERLEAVE r4, r5, r6, r7
    movw r1, #0x0001
    movt r1, #0x0000
    cmp  r6, r1
    bne  fail1
    movw r1, #0x8000
    movt r1, #0x0000
    cmp  r7, r1
    bne  fail1

    @ -------- Test 2: round-22 constant 0x8000000080008008 -------
    @ normal: src_H=0x80000000 src_L=0x80008008
    @ expect: even=0x00000000 odd=0x80008082
    movw r4, #0x0000
    movt r4, #0x8000                    @ src_H
    movw r5, #0x8008
    movt r5, #0x8000                    @ src_L
    INTERLEAVE r4, r5, r6, r7
    cmp  r6, #0
    bne  fail2
    movw r1, #0x8082
    movt r1, #0x8000
    cmp  r7, r1
    bne  fail2

    @ -------- Test 3: identity 0x0000000000000000 ----------------
    movs r4, #0
    movs r5, #0
    INTERLEAVE r4, r5, r6, r7
    cmp  r6, #0
    bne  fail3
    cmp  r7, #0
    bne  fail3

    @ -------- Test 4: round trip on a few patterns --------------
    @ pattern A: 0xDEADBEEFCAFEF00D
    movw r4, #0xF00D
    movt r4, #0xCAFE                    @ src_L
    movw r5, #0xBEEF
    movt r5, #0xDEAD                    @ src_H
    INTERLEAVE r4, r5, r6, r7
    @ save interleaved result
    mov  r4, r6
    mov  r5, r7
    DEINTERLEAVE r4, r5, r6, r7
    @ expect r6 = 0xCAFEF00D, r7 = 0xDEADBEEF
    movw r1, #0xF00D
    movt r1, #0xCAFE
    cmp  r6, r1
    bne  fail4
    movw r1, #0xBEEF
    movt r1, #0xDEAD
    cmp  r7, r1
    bne  fail4

    @ pattern B: 0x0123456789ABCDEF
    movw r4, #0xCDEF
    movt r4, #0x89AB                    @ src_L
    movw r5, #0x4567
    movt r5, #0x0123                    @ src_H
    INTERLEAVE r4, r5, r6, r7
    mov  r4, r6
    mov  r5, r7
    DEINTERLEAVE r4, r5, r6, r7
    movw r1, #0xCDEF
    movt r1, #0x89AB
    cmp  r6, r1
    bne  fail5
    movw r1, #0x4567
    movt r1, #0x0123
    cmp  r7, r1
    bne  fail5

    @ -------- All passed --------
    movs r0, #0
    b    done

fail1:  movs r0, #1
        b    done
fail2:  movs r0, #2
        b    done
fail3:  movs r0, #3
        b    done
fail4:  movs r0, #4
        b    done
fail5:  movs r0, #5
        b    done

done:
    pop  {r4-r7, pc}
    .size test_interleave, .-test_interleave
    .end
    