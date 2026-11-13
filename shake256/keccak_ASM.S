    .syntax unified
    .thumb
    .cpu cortex-m4

    .text
    .global Keccak_ASM
    .type Keccak_ASM, %function

    .align 3
    round_constants:
        .word 0x00000001, 0x00000000
        .word 0x00000000, 0x00000089
        .word 0x00000000, 0x8000008b
        .word 0x00000000, 0x80008080
        .word 0x00000001, 0x0000008b
        .word 0x00000001, 0x00008000
        .word 0x00000001, 0x80008088
        .word 0x00000001, 0x80000082
        .word 0x00000000, 0x0000000b
        .word 0x00000000, 0x0000000a
        .word 0x00000001, 0x00008082
        .word 0x00000000, 0x00008003
        .word 0x00000001, 0x0000808b
        .word 0x00000001, 0x8000000b
        .word 0x00000001, 0x8000008a
        .word 0x00000001, 0x80000081
        .word 0x00000000, 0x80000081
        .word 0x00000000, 0x80000008
        .word 0x00000000, 0x00000083
        .word 0x00000000, 0x80008003
        .word 0x00000001, 0x80008088
        .word 0x00000000, 0x80000088
        .word 0x00000001, 0x00008000
        .word 0x00000000, 0x80008082

    .macro INTERLEAVE src_H, src_L, dst_E, dst_O, t1=r2, t2=r3
    eor \t1, \src_H, \src_L, lsr #16
    uxth \t1, \t1                       @ & 0x0000FFFF
    eor \dst_O, \src_H, \t1
    eor \dst_E, \src_L, \t1, lsl #16
    eor \t1, \dst_O, \dst_E, lsr #8
    and \t1, \t1, #0x00FF00FF
    eor \dst_O, \dst_O, \t1
    eor \dst_E, \dst_E, \t1, lsl #8
    eor \t1, \dst_O, \dst_E, lsr #4
    and \t1, \t1, #0x0F0F0F0F
    eor \dst_O, \dst_O, \t1
    eor \dst_E, \dst_E, \t1, lsl #4
    eor \t1, \dst_O, \dst_E, lsr #2
    and \t1, \t1, #0x33333333
    eor \dst_O, \dst_O, \t1
    eor \dst_E, \dst_E, \t1, lsl #2
    eor \t1, \dst_O, \dst_E, lsr #1
    and \t1, \t1, #0x55555555
    eor \dst_O, \dst_O, \t1
    eor \dst_E, \dst_E, \t1, lsl #1
    .endm

    .macro DEINTERLEAVE src_E, src_O, dst_L, dst_H, t1=r2, t2=r3
    eor \t1, \src_O, \src_E, lsr #1
    and \t1, \t1, #0x55555555
    eor \dst_H, \src_O, \t1
    eor \dst_L, \src_E, \t1, lsl #1
    eor \t1, \dst_H, \dst_L, lsr #2
    and \t1, \t1, #0x33333333
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #2
    eor \t1, \dst_H, \dst_L, lsr #4
    and \t1, \t1, #0x0F0F0F0F
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #4
    eor \t1, \dst_H, \dst_L, lsr #8
    and \t1, \t1, #0x00FF00FF
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #8
    eor \t1, \dst_H, \dst_L, lsr #16
    uxth \t1, \t1                       @ & 0x0000FFFF
    eor \dst_H, \dst_H, \t1
    eor \dst_L, \dst_L, \t1, lsl #16
    .endm

    @ GET: fetch source word, apply theta + rho conditionally
    @ produces one 32-bit word of one destination lane
    @ h = which word in destination lane is (0 = E, 1 = O) 
    .macro GET reg, src, n, h       @ Macro to conditionally rotate by n
    .if (\n & 1) == 0                   @ If even n (rho offset), 32-bit rotate by n/2 on each word       
    .set w, \h                          
    .set k, \n/2
    .else                               @ odd n then half-rotate to swap words
    .set w, 1-\h
    .set k, (\n+1)/2-\h
    .endif
    .set x, \src-5*(\src/5)             @ col x = src mod 5, lane's D is D[x]
    ldr \reg, [r0, #8*\src+4*w]         @ load w of source lane (r0 = source buffer)
    ldr r7, [sp, #40+8*x+4*w]         @ load the same word of D[x]
    eor \reg, \reg, r7                  @ theta: A ^= D, done on word in register
    .if k != 0      
    ror \reg, \reg, #(32-k)         @ rho: ROL32 k via ROR by 32-k
    .endif
    .endm

    @ One chi row of one half. r1 is dest buffer.
    @ output + iota goes into the accumulators r8-r12
    .macro CHIROW h, first, row, s0, n0, s1, n1, s2, n2, s3, n3, s4, n4
    GET r2, \s0, \n0, \h
    GET r3, \s1, \n1, \h
    GET r4, \s2, \n2, \h
    GET r5, \s3, \n3, \h
    GET r6, \s4, \n4, \h

    @ Chi step: A[j] = B[j] ^ (~B[j+1] & B[j+2])
    .if \first
    ldr r7, [lr, #4*\h]        @ round-constant (E = lr+0, O = lr+4);
    bic r8, r4, r3              @ A[0] = B0 ^ (~B1 & B2)
    eor r8, r8, r2
    eor r8, r8, r7            @ if first, iota eor into lane 0
    str r8, [r1, #40*\row+4*\h]
    bic r9, r5, r4            
    eor r9, r9, r3
    str r9, [r1, #40*\row+8+4*\h]
    bic r10, r6, r5 
    eor r10, r10, r4
    str r10, [r1, #40*\row+16+4*\h]
    bic r11, r2, r6            
    eor r11, r11, r5
    str r11, [r1, #40*\row+24+4*\h]
    bic r12, r3, r2   
    eor r12, r12, r6
    str r12, [r1, #40*\row+32+4*\h]
    .else 
    bic r7, r4, r3
    eor r7, r7, r2
    str r7, [r1, #40*\row+4*\h]
    eor r8, r8, r7
    bic r7, r5, r4
    eor r7, r7, r3
    str r7, [r1, #40*\row+8+4*\h]
    eor r9, r9, r7
    bic r7, r6, r5
    eor r7, r7, r4
    str r7, [r1, #40*\row+16+4*\h]
    eor r10, r10, r7
    bic r7, r2, r6
    eor r7, r7, r5
    str r7, [r1, #40*\row+24+4*\h]
    eor r11, r11, r7
    bic r7, r3, r2
    eor r7, r7, r6
    str r7, [r1, #40*\row+32+4*\h]
    eor r12, r12, r7
    .endif
    .endm

    @ (src, n) for each dest lane 5*row+j
    .macro HALF h
    CHIROW \h, 1, 0, 0, 0, 6, 44, 12,43, 18, 21, 24, 14
    CHIROW \h, 0, 1, 3, 28, 9, 20, 10,3, 16, 45, 22, 61
    CHIROW \h, 0, 2, 1, 1, 7, 6, 13, 25, 19, 8, 20, 18
    CHIROW \h, 0, 3, 4, 27, 5, 36, 11, 10, 17, 15, 23, 56
    CHIROW \h, 0, 4, 2, 62, 8, 55, 14, 39, 15, 41, 21, 2
    .endm

    Keccak_ASM:
        push {r4-r11, lr}
        sub sp, sp, #288
        adr lr, round_constants
        mov r2, #24
        str r2, [sp, #284]         @ round ctr
        mov r12, #0
        ParityLoop:                     @ parity C[x] = 
            add r3, r0, r12, lsl #3         @ r3 = r0 + 8x
            ldrd r4, r5, [r3, #0]           @ (r4 = x low, r5 = x high)
            ldrd r6, r7, [r3, #40]           @ (r6 = x+5 low, r7 = x+5 high)
            eor r4, r4, r6                   @ r4 = low halves
            eor r5, r5, r7                   @ r5 = high halves
            ldrd r6, r7, [r3, #80] 
            eor  r4, r4, r6
            eor  r5, r5, r7
            ldrd r6, r7, [r3, #120]
            eor  r4, r4, r6
            eor  r5, r5, r7
            ldrd r6, r7, [r3, #160]
            eor  r4, r4, r6
            eor  r5, r5, r7
            add  r3, sp, r12, lsl #3            @ r3 = &C[x]
            strd r4, r5, [r3]

            add r12, r12, #1 
            cmp r12, #5
            bne ParityLoop

        ldr r8,  [sp, #4]
        ldr r9,  [sp, #12]
        ldr r10, [sp, #20]
        ldr r11, [sp, #28]
        ldr r12, [sp, #36]
        add r1, sp, #80

        RoundLoop:
        @ D[x][z] = C[x-1][z] ^ C[x+1][z-1], D[x] = C[x-1] ^ ROL64(C[x+1], 1), 
        @ ROL64(C[x], 1) = (low << 1) | (high >> 31)
        ldr  r2, [sp, #0]
        ldr  r3, [sp, #8]
        ldr  r4, [sp, #16]
        ldr  r5, [sp, #24]
        ldr  r6, [sp, #32]

        @ D[0] = C[4] ^ ROL64(C[1], 1)         
        @ D_lo = Clo[x-1] ^ Clo[x+1]<<1 ^ Chi[x+1]>>31
        @ D_hi = Chi[x-1] ^ Chi[x+1]<<1 ^ Clo[x+1]>>31
        eor r7, r6, r9, ror #31         @ D0_E
        str r7, [sp, #40]
        eor r7, r12, r3                @ D0_O
        str r7, [sp, #44]

        eor r7, r2, r10, ror #31        
        str r7, [sp, #48]
        eor r7, r8,  r4
        str r7, [sp, #52]

        eor r7, r3, r11, ror #31        
        str r7, [sp, #56]
        eor r7, r9,  r5
        str r7, [sp, #60]

        eor r7, r4, r12, ror #31      
        str r7, [sp, #64]
        eor r7, r10, r6
        str r7, [sp, #68]

        eor r7, r5, r8,  ror #31      
        str r7, [sp, #72]
        eor r7, r11, r2
        str r7, [sp, #76]

        HALF 0                  @ rho/pi/chi/iota handler, E words
        str r8, [sp, #0]              @ new C E-words
        str r9, [sp, #8]
        str r10, [sp, #16]
        str r11, [sp, #24]
        str r12, [sp, #32]

        HALF 1                      @ O words
        add lr, lr, #8
        str r8, [sp, #4]
        str r9, [sp, #12]
        str r10, [sp, #20]
        str r11, [sp, #28]
        str r12, [sp, #36]

        mov r2, r0
        mov r0, r1
        mov r1, r2

    @ Theta, Chi, Pi merged into conditional CHIROW macro
    @ Iota Step: merged into CHIROW macro 
    @ (FIPS 202) https://keccak.team/keccak_specs_summary.html

        ldr r6, [sp, #284]
        subs r6, r6, #1
        str  r6, [sp, #284]
        bne  RoundLoop
        add  sp, sp, #288
        pop  {r4-r11, pc}
        .size Keccak_ASM, .-Keccak_ASM



.global Keccak_Il
.type Keccak_Il, %function
.align 2
@ uint64_t Keccak_Il(uint32_t lo, uint32_t hi)   r0=L, r1=H
@ interleaved lane: r0 = E (low word), r1 = O (high word)
Keccak_Il:
    INTERLEAVE r1, r0, r0, r1, r2
    bx lr
    .size Keccak_Il, .-Keccak_Il

.global Keccak_Deil
.type Keccak_Deil, %function
.align 2
@ lane: r0 = L (low word), r1 = H (high word)
Keccak_Deil:
    DEINTERLEAVE r0, r1, r0, r1, r2
    bx lr
    .size Keccak_Deil, .-Keccak_Deil