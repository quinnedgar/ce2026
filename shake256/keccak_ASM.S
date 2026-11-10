    .syntax unified
    .thumb
    .cpu cortex-m4

    .text
    .global Keccak_ASM
    .type Keccak_ASM, %function

    .align 3
    round_constants:
        .word 0x00000001, 0x00000000
        .word 0x00008082, 0x00000000
        .word 0x0000808a, 0x80000000
        .word 0x80008000, 0x80000000
        .word 0x0000808b, 0x00000000
        .word 0x80000001, 0x00000000
        .word 0x80008081, 0x80000000
        .word 0x00008009, 0x80000000
        .word 0x0000008a, 0x00000000
        .word 0x00000088, 0x00000000
        .word 0x80008009, 0x00000000
        .word 0x8000000a, 0x00000000
        .word 0x8000808b, 0x00000000
        .word 0x0000008b, 0x80000000
        .word 0x00008089, 0x80000000
        .word 0x00008003, 0x80000000
        .word 0x00008002, 0x80000000
        .word 0x00000080, 0x80000000
        .word 0x0000800a, 0x00000000
        .word 0x8000000a, 0x80000000
        .word 0x80008081, 0x80000000
        .word 0x00008080, 0x80000000
        .word 0x80000001, 0x00000000
        .word 0x80008008, 0x80000000

    @ Conditional rotation (rho) into new lane (pi)
    .macro RHOPI src, dst, n            @ Uses r4-r7, assumes r0 is state ptr
    ldrd r4, r5, [r0, #8*\src]
    eor  r4, r4, r8                     @ fused theta
    eor  r5, r5, r9
    .if \n == 0
    strd r4, r5, [r1, #8*\dst]        @ 0 rotation
    .elseif \n < 32                     @ 0 < n < 32 rotation
    lsl  r6, r4, #\n                    @ new low  = low << n | high >> (32-n)
    orr  r6, r6, r5, lsr #(32-\n)       
    lsl  r7, r5, #\n                    @ new high = high << n | low >> (32-n)
    orr  r7, r7, r4, lsr #(32-\n)
    strd r6, r7, [r1, #8*\dst]
    .elseif \n == 32
    strd r5, r4, [r1, #8*\dst]          @ n=32 just switch r4 w r5
    .else                               @ n > 32
    lsl  r6, r5, #(\n-32)               @ new low = high << n | low >> (64-n)
    orr  r6, r6, r4, lsr #(64-\n)
    lsl  r7, r4, #(\n-32)               @ new high = low << n | high >> (64-n)
    orr  r7, r7, r5, lsr #(64-\n)
    strd r6, r7, [r1, #8*\dst]
    .endif
    .endm

    @ Avoid rereading all lanes from memory each round in ParityLoop by merging parity calculation into chi step
    @ Modifications:
    @   first = 1 for row 0 (initialises the accumulators), else 0
    @   n = offset (row y, half h ->  n = 40*y + h)

    .macro CHIMIX n, first, rc=r7         @ r0 = A base, r1 = B base (low or high half)
    ldr  r2, [r1, #\n]                  @ B[0]
    ldr  r3, [r1, #\n+8]
    ldr  r4, [r1, #\n+16]
    ldr  r5, [r1, #\n+24]
    ldr  r6, [r1, #\n+32]
    .if \first                          @ Row 0, no zeroing and no extra XOR because C[x] = A[x] of row 0
    bic r8,  r4, r3                @ r8  = B2 & ~B1
    eor r8,  r8, r2                @ r8  = A[0] = B0 ^ (~B1 & B2)
    .ifnc \rc, none
        eor r8, r8, \rc          @ iota fused in for lane 0
    .endif
    str r8,  [r0, #\n]
    bic r9,  r5, r4
    eor r9,  r9, r3
    str r9,  [r0, #\n+8]
    bic r10, r6, r5
    eor r10, r10, r4
    str r10, [r0, #\n+16]
    bic r11, r2, r6
    eor r11, r11, r5 
    str r11, [r0, #\n+24]
    bic r12, r3, r2
    eor r12, r12, r6
    str r12, [r0, #\n+32]
    .else                          @ 1.3 update: Chi + XOR each result into accumulator.
    bic r7, r4, r3
    eor r7, r7, r2               @ A[0]
    str r7, [r0, #\n]
    eor r8, r8, r7                 @ C[0] ^= A[0]

    bic r7, r5, r4
    eor r7, r7, r3
    str r7, [r0, #\n+8]
    eor r9, r9, r7

    bic r7, r6, r5
    eor r7, r7, r4
    str r7, [r0, #\n+16]
    eor r10, r10, r7

    bic r7, r2, r6
    eor r7, r7, r5
    str r7, [r0, #\n+24]
    eor r11, r11, r7

    bic r7, r3, r2
    eor  r7, r7, r6
    str r7, [r0, #\n+32]
    eor r12, r12, r7
    .endif
    .endm


    .align 2
    Keccak_ASM:
        push {r4-r11, lr}
        sub sp, sp, #288
        adr lr, round_constants
        mov r2, #24
        str r2, [sp, #284]         @ round ctr
        mov r12, #0

    @ Theta Step (θ)
        ParityLoop:                     @ parity C[x] = 
            add r3, r0, r12, lsl #3     @ r3 = r0 + 8x
            ldrd r4, r5, [r3, #0]       @ (r4 = x low, r5 = x high)
            ldrd r6, r7, [r3, #40]      @ (r6 = x+5 low, r7 = x+5 high)
            eor r4, r4, r6              @ r4 = low halves
            eor r5, r5, r7              @ r5 = high halves
            ldrd r6, r7, [r3, #80] 
            eor  r4, r4, r6
            eor  r5, r5, r7
            ldrd r6, r7, [r3, #120]
            eor  r4, r4, r6
            eor  r5, r5, r7
            ldrd r6, r7, [r3, #160]
            eor  r4, r4, r6
            eor  r5, r5, r7
            add  r3, sp, r12, lsl #3    @ r3 = &C[x]
            strd r4, r5, [r3]

            add r12, r12, #1 
            cmp r12, #5
            bne ParityLoop

            ldr r8,  [sp, #4]
            ldr r9,  [sp, #12]
            ldr r10, [sp, #20]
            ldr r11, [sp, #28]
            ldr r12, [sp, #36]

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
        eor r1, r6,  r3,  lsl #1    @ D[0]
        eor r1, r1,  r9,  lsr #31
        eor r7, r12, r9,  lsl #1
        eor r7, r7,  r3,  lsr #31
        strd r1, r7, [sp, #40]

        eor r1, r2,  r4,  lsl #1
        eor r1, r1,  r10, lsr #31
        eor r7, r8,  r10, lsl #1
        eor r7, r7,  r4,  lsr #31
        strd r1, r7, [sp, #48]

        eor r1, r3,  r5,  lsl #1
        eor r1, r1,  r11, lsr #31
        eor r7, r9,  r11, lsl #1
        eor r7, r7,  r5,  lsr #31
        strd r1, r7, [sp, #56]

        eor r1, r4,  r6,  lsl #1
        eor r1, r1,  r12, lsr #31
        eor r7, r10, r12, lsl #1
        eor r7, r7,  r6,  lsr #31
        strd r1, r7, [sp, #64]

        eor r1, r5,  r2,  lsl #1
        eor r1, r1,  r8,  lsr #31
        eor r7, r11, r8,  lsl #1
        eor r7, r7,  r2,  lsr #31
        strd r1, r7, [sp, #72]

        add r1, sp, #80             
    @ Rho/Pi Step: n offset, write into new position dst in 200 byte buffer
        @ src = 0-24
        @ n = FIPS 202 offsets used in sample implementation code https://keccak.team/keccak_specs_summary.html
        @ table indexed with x = src mod 5, y = floor(src/5)
        @ dst = y + 5 * ((2x + 3y) mod 5)
        @ RHOPI src, dst, n
        add  r1, sp, #80
        ldrd r8, r9, [sp, #40]          @ D[0]
        RHOPI 0,  0,  0
        RHOPI 5,  16, 36
        RHOPI 10, 7,  3
        RHOPI 15, 23, 41
        RHOPI 20, 14, 18

        ldrd r8, r9, [sp, #48]          @ D[1]
        RHOPI 1,  10, 1
        RHOPI 6,  1,  44
        RHOPI 11, 17, 10
        RHOPI 16, 8,  45
        RHOPI 21, 24, 2

        ldrd r8, r9, [sp, #56]          @ D[2]
        RHOPI 2,  20, 62
        RHOPI 7,  11, 6
        RHOPI 12, 2,  43
        RHOPI 17, 18, 15
        RHOPI 22, 9,  61

        ldrd r8, r9, [sp, #64]          @ D[3]
        RHOPI 3,  5,  28
        RHOPI 8,  21, 55
        RHOPI 13, 12, 25
        RHOPI 18, 3,  21
        RHOPI 23, 19, 56

        ldrd r8, r9, [sp, #72]          @ D[4]
        RHOPI 4,  15, 27
        RHOPI 9,  6,  20
        RHOPI 14, 22, 39
        RHOPI 19, 13, 8
        RHOPI 24, 4,  14

    @ Chi Step: mix RHOPI buffer lanes back into state (r0)
    @ A[x] = B[x] ^ (~B[x+1] & B[x+2])
        ldr  r7, [lr]
        CHIMIX 0, 1
        CHIMIX 40, 0
        CHIMIX 80, 0
        CHIMIX 120, 0
        CHIMIX 160, 0
        str  r8,  [sp, #0]          @ C[0..4] low halves
        str  r9,  [sp, #8]
        str  r10, [sp, #16]
        str  r11, [sp, #24]
        str  r12, [sp, #32]

        ldr  r7, [lr, #4]
        CHIMIX 4,   1
        CHIMIX 44,  0
        CHIMIX 84,  0
        CHIMIX 124, 0
        CHIMIX 164, 0
        add  lr, lr, #8
        str  r8,  [sp, #4]          @ C[0..4] high halves
        str  r9,  [sp, #12]
        str  r10, [sp, #20]
        str  r11, [sp, #28]
        str  r12, [sp, #36]


    @ Iota Step: merged into CHIMIX macro 
    @ (FIPS 202) https://keccak.team/keccak_specs_summary.html

        ldr  r6, [sp, #284]
        subs r6, r6, #1
        str  r6, [sp, #284]
        bne  RoundLoop
        add  sp, sp, #288
        pop  {r4-r11, pc}
        .size Keccak_ASM, .-Keccak_ASM