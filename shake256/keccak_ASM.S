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
    ldrd r4, r5, [r0, #8 * \src]
    eor  r4, r4, r8                     @ fused theta
    eor  r5, r5, r9
    .if \n == 0
    strd r4, r5, [r1, #8 * \dst]        @ 0 rotation
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
    .macro CHIMIX                       @ r0 = A base, r1 = B base (low or high half)
    mov r8, #0                          @ C[0]
    mov r9, #0
    mov r10, #0
    mov r11, #0
    mov r12, #0
    mov  lr,  #5
    1:
        ldr  r2, [r1, #0]               @ B[0]
        ldr  r3, [r1, #8]
        ldr  r4, [r1, #16]
        ldr  r5, [r1, #24]
        ldr  r6, [r1, #32]
        bic r7, r4, r3                  @ r7 = B2 & ~B1
        eor r7, r7, r2                  @ r7 = B0 ^ (~B1 & B2) = A[0]
        str r7, [r0, #0]
        eor  r8, r8, r7                 @ C[0] ^= A[0] Calculate next round parity (replace ParityLoop)
        bic r7, r5, r4
        eor r7, r7, r3
        str r7, [r0, #8]
        eor r9, r9, r7
        bic r7, r6, r5
        eor r7, r7, r4
        str r7, [r0, #16]
        eor r10, r10, r7
        bic r7, r2, r6
        eor r7, r7, r5
        str r7, [r0, #24]
        eor r11, r11, r7
        bic r7, r3, r2
        eor r7, r7, r6
        str r7, [r0, #32]
        eor r12, r12, r7

        add r0, r0, #40
        add r1, r1, #40
        subs lr, lr, #1
        bne 1b
    .endm
    .align 2
    Keccak_ASM:
        push {r4-r11, lr}
        sub  sp, sp, #288
        adr  r2, round_constants
        str  r2, [sp, #280]         @ pointer to the current round constant
        mov  r2, #24
        str  r2, [sp, #284]         @ round counter
        mov r12, #0

    @ Theta Step (θ)
        ParityLoop:                     @ Computes Parity C[x] = 
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

        RoundLoop:
        mov r12, #0
        @ D[x][z] = C[x-1][z] ^ C[x+1][z-1], D[x] = C[x-1] ^ ROL64(C[x+1], 1), 
        @ ROL64(C[x], 1) = (low << 1) | (high >> 31)

        @ D[0] = C[4] ^ ROL64(C[1], 1)         
        ldrd r4, r5, [sp, #8]       @ C[1] 
        ldrd r6, r7, [sp, #32]      @ C[4]
        lsl  r8, r4, #1            
        orr  r8, r8, r5, lsr #31    @ r8 = r4 << 1 | r5 >> 31
        lsl  r9, r5, #1            
        orr  r9, r9, r4, lsr #31    @ r9 = r5 << 1 | r4 >> 31
        eor r8, r6, r8              @ r8 = r6 ^ r8
        eor r9, r7, r9              @ r9 = r7 ^ r9
        strd r8, r9, [sp, #40]

        @D[1] = C[0] ^ ROL64(C[2], 1)
        ldrd r4, r5, [sp, #16]       @ C[2] 
        ldrd r6, r7, [sp]            @ C[0]
        lsl  r8, r4, #1
        orr  r8, r8, r5, lsr #31
        lsl  r9, r5, #1
        orr  r9, r9, r4, lsr #31
        eor r8, r6, r8
        eor r9, r7, r9
        strd r8, r9, [sp, #48]

        @D[2] = C[1] ^ ROL64(C[3], 1)
        ldrd r4, r5, [sp, #24]       @ C[3] 
        ldrd r6, r7, [sp, #8]        @ C[1]
        lsl  r8, r4, #1
        orr  r8, r8, r5, lsr #31
        lsl  r9, r5, #1
        orr  r9, r9, r4, lsr #31
        eor r8, r6, r8
        eor r9, r7, r9
        strd r8, r9, [sp, #56]

        @D[3] = C[2] ^ ROL64(C[4], 1)
        ldrd r4, r5, [sp, #32]       @ C[4] 
        ldrd r6, r7, [sp, #16]       @ C[2]
        lsl  r8, r4, #1
        orr  r8, r8, r5, lsr #31
        lsl  r9, r5, #1
        orr  r9, r9, r4, lsr #31
        eor r8, r6, r8
        eor r9, r7, r9
        strd r8, r9, [sp, #64]

        @D[4] = C[3] ^ ROL64(C[0], 1)
        ldrd r4, r5, [sp]            @ C[0] 
        ldrd r6, r7, [sp, #24]       @ C[3]
        lsl  r8, r4, #1
        orr  r8, r8, r5, lsr #31
        lsl  r9, r5, #1
        orr  r9, r9, r4, lsr #31
        eor r8, r6, r8
        eor r9, r7, r9
        strd r8, r9, [sp, #72]

        mov r12, #0
    
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
        CHIMIX                     @ low halves
        str  r8,  [sp, #0]          @ C[x] low
        str  r9,  [sp, #8]
        str  r10, [sp, #16]
        str  r11, [sp, #24]
        str  r12, [sp, #32]

        sub  r0, r0, #196       @ back to base + 4
        sub  r1, r1, #196
        CHIMIX                     @ high halves
        str  r8,  [sp, #4]          @ C[x] high
        str  r9,  [sp, #12]
        str  r10, [sp, #20]
        str  r11, [sp, #28]
        str  r12, [sp, #36]
        sub  r0, r0, #204           @ restore r0 = state base


    @ Iota Step: add in round constants (FIPS 202) https://keccak.team/keccak_specs_summary.html
    @ Break back to RoundLoop if not on final round
        ldr  r2, [sp, #280]
        ldrd r6, r7, [r2], #8       @ round constant
        str  r2, [sp, #280]
        ldrd r4, r5, [r0]           @ state lane 0
        eor  r4, r4, r6
        eor  r5, r5, r7
        strd r4, r5, [r0]
        ldrd r4, r5, [sp]           @ C[0]
        eor  r4, r4, r6
        eor  r5, r5, r7
        strd r4, r5, [sp]

        ldr  r2, [sp, #284]
        subs r2, r2, #1
        str  r2, [sp, #284]
        bne  RoundLoop
        add  sp, sp, #288
        pop  {r4-r11, pc}
        .size Keccak_ASM, .-Keccak_ASM