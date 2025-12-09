_start:
  li a0,0x42c0
  jal Q_sqrt_bf16
loop:
  j loop

.global Q_sqrt_bf16
.type Q_sqrt_bf16,%function
Q_sqrt_bf16: # number: a0 (標準 C ABI，參數在 a0)
  # 此函式正確，它保存了它使用的 s 暫存器
  addi sp,sp,-16  # 為 4 個暫存器 (ra, s0, s1, s2) 分配 16 bytes
  sw ra, 12(sp)   # 保存返回地址
  sw s0, 8(sp)    # 保存 s0 (callee-saved)
  sw s1, 4(sp)    # 保存 s1 (callee-saved)
  sw s2, 0(sp)    # 保存 s2 (callee-saved)
  
  mv s0, a0       # s0 = number (x) (保存原始輸入)
  
  # 1. 計算 x2 = x * 0.5
  li a1, 0x3f00   # a1 = 0.5 (arg 2)
  # a0 仍然是 number (x) (arg 1)
  jal bf16_mul    # a0 = bf16_mul(x, 0.5)
  mv s1, a0       # s1 = x2 (儲存到 callee-saved 暫存器)

  # 2. 計算 y = 0x5f37 - (x >> 1)
  li t1, 0x5f37
  srli t0, s0, 1  # t0 = x >> 1 (使用保存的 s0)
  sub s2, t1, t0  # s2 = y (儲存到 callee-saved 暫存器)
  
  # 3. 計算 temp = bf16_mul(y, y)
  mv a1, s2       # a1 = y (arg 2)
  mv a0, s2       # a0 = y (arg 1)
  jal bf16_mul    # a0 = y * y

  # 4. 計算 temp2 = bf16_mul(x2, temp)
  mv a1, a0       # a1 = temp (y*y) (arg 2)
  mv a0, s1       # a0 = x2 (從 s1 還原) (arg 1)
  jal bf16_mul    # a0 = x2 * y * y

  # 5. 計算 temp3 = bf16_sub(1.5, temp2)
  mv a1, a0       # a1 = temp2 (x2*y*y) (arg 2)
  li a0, 0x3fc0   # a0 = 1.5 (arg 1)
  jal bf16_sub    # a0 = 1.5 - (x2*y*y)

  # 6. 計算 result = bf16_mul(y, temp3)
  mv a1, a0       # a1 = temp3 (1.5 - ...) (arg 2)
  mv a0, s2       # a0 = y (從 s2 還原) (arg 1)
  jal bf16_mul    # a0 = y * (1.5 - ...)
  
  # 恢復暫存器並返回
  lw s2, 0(sp)
  lw s1, 4(sp)
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp,sp,16
  ret
  
  
#################
#  bf16_isnan   #
#################
.global bf16_isnan
.type bf16_isnan,%function
bf16_isnan:       # arg: a0
  addi sp, sp, -4
  sw s1, 0(sp)    # 保存 s1
  
  li s1,0x7F80 # BF16_EXP_MASK 
  and t0,a0,s1 # a & exp_mask
  bne t0,s1,bf16_isnan_false
  # check mantissa part is non-zero
  andi t0,a0,0x7F
  beq t0,x0,bf16_isnan_false 
  li a0,1       # Return 1 in a0
  j _isnan_epilogue
bf16_isnan_false:
  li a0,0       # Return 0 in a0
_isnan_epilogue:
  lw s1, 0(sp)    # 還原 s1
  addi sp, sp, 4
  ret

#################
#  bf16_isinf   #
#################
.global bf16_isinf
.type bf16_isinf,%function
bf16_isinf:       # arg: a0
  addi sp, sp, -4
  sw s1, 0(sp)    # 保存 s1
  
  li s1,0x7F80 # BF16_EXP_MASK 
  and t0,a0,s1 # a & exp_mask
  bne t0,s1,bf16_isinf_false
  # check mantissa part is zero
  andi t0,a0,0x7F
  bne t0,x0,bf16_isinf_false 
  li a0,1       # Return 1 in a0
  j _isinf_epilogue
bf16_isinf_false:
  li a0,0       # Return 0 in a0
_isinf_epilogue:
  lw s1, 0(sp)    # 還原 s1
  addi sp, sp, 4
  ret
  
#################
#  bf16_iszero  #
#################
.global bf16_iszero
.type bf16_iszero,%function
bf16_iszero:      # arg: a0
  addi sp, sp, -4
  sw s2, 0(sp)    # 保存 s2
  
  li s2,0x7FFF # mask exp and mant
  and t0,a0,s2
  bne t0,x0,bf16_iszero_false
  li a0,1       # Return 1 in a0
  j _iszero_epilogue
bf16_iszero_false:
  li a0,0       # Return 0 in a0
_iszero_epilogue:
  lw s2, 0(sp)    # 還原 s2
  addi sp, sp, 4
  ret

#################
#  f32_to_bf16  #
#################
.global f32_to_bf16
.type f32_to_bf16,%function
f32_to_bf16:      # arg: a0 (f32 bits)
  addi sp, sp, -4
  sw s2, 0(sp)    # 保存 s2
  
  li s2,0x7FFF # mask exp and mant
  mv t0,a0      # t0: f32bits (from a0)
  srli t1,t0,23
  andi t1,t1,0xFF
  addi t1,t1,-0xFF
  bne t1,x0,f32_to_bf16_else
  srli t1,t0,16
  li t0,0xFFFF
  and a0,t1,t0
  j _f32_epilogue
f32_to_bf16_else:
  srli t1,t0,16
  andi t1,t1,1
  add t1,t1,s2
  add t0,t0,t1
  srli a0,t0,16
_f32_epilogue:
  lw s2, 0(sp)    # 還原 s2
  addi sp, sp, 4
  ret
  
#################
#  bf16_to_f32  #
#################
.global bf16_to_f32
.type bf16_to_f32,%function
bf16_to_f32:      # arg: a0 (bf16 bits)
  slli a0,a0,16   # (from a0)
  ret             # 不需保存/還原

#################
#    bf16_add   #
#################
.global bf16_add
.type bf16_add,%function
bf16_add:         # a0: a, a1: b
  # Prologue: 保存 s0-s5
  addi sp, sp, -24
  sw s0, 0(sp)
  sw s1, 4(sp)
  sw s2, 8(sp)
  sw s3, 12(sp)
  sw s4, 16(sp)
  sw s5, 20(sp)

  srli s0,a0,15   # s0: sign_a (from a0)
  andi s0,s0,1   
  srli s1,a1,15   # s1: sign_b (from a1)
  andi s1,s1,1   
  srli s2,a0,7    # s2: exp_a (from a0)
  andi s2,s2,0xFF
  srli s3,a1,7    # s3: exp_b (from a1)
  andi s3,s3,0xFF
  andi s4,a0,0x7F # s4: mant_a (from a0)
  andi s5,a1,0x7F # s5: mant_b (from a1)

  li t0,0xFF  # t0: 0xFF
  bne s2,t0,exp_a_max_n
  bnez s4, _add_ret_a     # a is NaN
  # a is Inf
  bne s3,t0, _add_ret_a     # b is not Inf/NaN
  bnez s5, _add_ret_b     # b is NaN
  bne s0,s1, _add_ret_nan   # Inf + (-Inf) = NaN
  j _add_ret_a              # Inf + Inf = Inf
exp_a_max_n:
  beq s3,t0, _add_ret_b     # b is Inf/NaN
  
  # Handle zeros
  bnez s2,a_not_zero
  bnez s4,a_not_zero
  j _add_ret_b           # a is 0
a_not_zero:
  bnez s3,b_not_zero
  bnez s5,b_not_zero
  j _add_ret_a           # b is 0
b_not_zero:
  
  # 修正：使用 beqz (如果 exp 為 0，跳過)
  beqz s2, a_denorm_skip
  ori s4, s4, 0x80
a_denorm_skip:
  beqz s3, b_denorm_skip
  ori s5, s5, 0x80
b_denorm_skip:

  sub t1,s2,s3 # exp_diff: t1
  ble t1,x0,exp_diff_neg
  mv t3,s2 # result_exp: t3
  addi t4,t1,-8
  bgt t4,x0,_add_ret_a
  srl s5,s5,t1
  j res_exp_exit
exp_diff_neg:
  mv t3,s3 # result_exp: t3
  beq t1, x0, res_exp_exit # exp_diff is 0
  
  sub t4,x0,t1
  addi t5, t4, -8
  bgt t5,x0,_add_ret_b
  srl s4,s4,t4
  
res_exp_exit:
  bne s0,s1,sign_is_diff
  mv t2,s0 # result_sign = t2
  add t4,s4,s5 # result_mant = t4
  andi t5,t4,0x100
  beq t5,x0,_add_ret_encoded # return if no carry
  srli t4,t4,1
  addi t3,t3,1
  bge t3,t0,_add_ret_inf
  j _add_ret_encoded
sign_is_diff:
  blt s4,s5,b_lt_a
  mv t2,s0
  sub t4,s4,s5
  j b_lt_a_exit
b_lt_a:
  mv t2,s1
  sub t4,s5,s4
b_lt_a_exit:
  beq t4,x0,_add_ret_zero
denorm_loop:
  andi t5,t4,0x80
  bne t5,x0,_add_ret_encoded
  slli t4,t4,1
  addi t3,t3,-1
  blez t3,_add_ret_zero
  j denorm_loop

# --- bf16_add Local Helpers ---
_add_ret_a:
  mv a0,a0
  j _add_epilogue
_add_ret_b:
  mv a0,a1
  j _add_epilogue
_add_ret_nan:
  li a0,0x7FC0
  j _add_epilogue
_add_ret_inf:
  slli t2,t2,15
  li t1,0x7F80
  or a0,t1,t2
  j _add_epilogue
_add_ret_zero:
  slli t2,t2,15 # 修正：使用 t2 (sign)
  ori a0,t2,0
  j _add_epilogue
_add_ret_encoded:
  slli t2,t2,15
  li t0, 0xFF
  and t3,t3,t0
  slli t3,t3,7
  andi t4,t4,0x7F
  or a0,t2,t3 # 修正：or a0,t2,t3
  or a0,a0,t4
  j _add_epilogue

_add_epilogue:
  lw s0, 0(sp)
  lw s1, 4(sp)
  lw s2, 8(sp)
  lw s3, 12(sp)
  lw s4, 16(sp)
  lw s5, 20(sp)
  addi sp, sp, 24
  ret

#################
#    bf16_sub   #
#################
.global bf16_sub
.type bf16_sub,%function
bf16_sub:         # a0: a, a1: b
  # Prologue: 保存 ra
  addi sp, sp, -4
  sw ra, 0(sp)
  
  li t0, 0x8000 # BF16_SIGN_MASK 
  xor a1,a1,t0    # Invert sign of b (in a1)
  jal bf16_add
  
  # Epilogue: 還原 ra
  lw ra, 0(sp)
  addi sp, sp, 4
  ret

#################
#    bf16_mul   #
#################
.global bf16_mul
.type bf16_mul,%function
bf16_mul:         # a0: a, a1: b
  # Prologue: 保存 s0-s5
  addi sp, sp, -24
  sw s0, 0(sp)
  sw s1, 4(sp)
  sw s2, 8(sp)
  sw s3, 12(sp)
  sw s4, 16(sp)
  sw s5, 20(sp)

  srli s0,a0,15   # s0: sign_a (from a0)
  andi s0,s0,1   
  srli s1,a1,15   # s1: sign_b (from a1)
  andi s1,s1,1   
  srli s2,a0,7    # s2: exp_a (from a0)
  andi s2,s2,0xFF
  srli s3,a1,7    # s3: exp_b (from a1)
  andi s3,s3,0xFF
  andi s4,a0,0x7F # s4: mant_a (from a0)
  andi s5,a1,0x7F # s5: mant_b (from a1)

  xor t2,s0,s1 # res_sign: t2

  li t0,0xFF  # t0: 0xFF
  bne s2,t0,mul_exp_a_max_n
  bnez s4,_mul_ret_a
  bnez s3,_mul_ret_inf
  beqz s5,_mul_ret_nan
  j _mul_ret_inf
mul_exp_a_max_n:
  bne s3,t0,mul_exp_b_max_n
  bnez s5,_mul_ret_b
  bnez s2,_mul_ret_inf
  beqz s4,_mul_ret_nan
  j _mul_ret_inf
mul_exp_b_max_n:

  li t1,0   # exp_adj: t1

  bnez s2,exp_a_nonzero
mant_a_norm_loop:
  andi t5, s4, 0x80      # 檢查隱含位
  bnez t5, mant_a_norm   # 找到了，跳出
  slli s4, s4, 1
  addi t1, t1, -1
  beqz s4, exp_a_nonzero # 如果 mantissa 為 0，跳出
  j mant_a_norm_loop
mant_a_norm:
  li s2, 1
exp_a_nonzero:
  ori s4,s4,0x80

  bnez s3,exp_b_nonzero
mant_b_norm_loop:
  andi t5, s5, 0x80      # 檢查隱含位
  bnez t5, mant_b_norm   # 找到了，跳出
  slli s5, s5, 1
  addi t1, t1, -1
  beqz s5, exp_b_nonzero # 如果 mantissa 為 0，跳出
  j mant_b_norm_loop
mant_b_norm:
  li s3, 1
exp_b_nonzero:
  ori s5,s5,0x80
mant_b_norm_exit:

  li t4, 0            # result = 0
  li t0, 16           # 16 bits to process

mult_loop:
  andi t5,s5,1        # check LSB of multiplier
  beqz t5,skip_add    # if 0, skip addition
  add t4,t4,s4        # if LSB=1, add multiplicand to result
skip_add:
  srli s5,s5,1        # shift multiplier right by 1
  slli s4,s4,1        # shift multiplicand left by 1
  addi t0,t0,-1
  bnez t0,mult_loop
mult_exit:
  add t3,s2,s3
  addi t3,t3,-127
  add t3,t3,t1 # result_exp
  
  li t5,0x8000
  and t5,t4,t5
  beqz t5,result_mant_adj_n
  srli t4,t4,8            # Shift 8
  andi t4,t4,0x7F         # Mask 7 bits
  addi t3,t3,1            # Increment exponent
  j check_result_exp
result_mant_adj_n:
  li t5,0x3F80
  and t4, t4, t5          # 遮罩出 bits 13-7
  srli t4, t4, 7          # 右移 7 位
  
check_result_exp:
  li t0,0xFF
  blt t3,t0,result_inf_n
  j _mul_ret_inf
result_inf_n:
  bgtz t3,_mul_ret_encoded
  addi t5,t3,6
  bltz t5,_mul_ret_zero
  li t5,1
  sub t5,t5,t3
  srl t4,t4,t5
  li t3,0
  j _mul_ret_encoded

# --- bf16_mul Local Helpers ---
_mul_ret_a:
  mv a0,a0
  j _mul_epilogue
_mul_ret_b:
  mv a0,a1
  j _mul_epilogue
_mul_ret_nan:
  li a0,0x7FC0
  j _mul_epilogue
_mul_ret_inf:
  slli t2,t2,15
  li t1,0x7F80
  or a0,t1,t2
  j _mul_epilogue
_mul_ret_zero:
  slli t2,t2,15
  ori a0,t2,0
  j _mul_epilogue
_mul_ret_encoded:
  slli t2,t2,15
  li t0, 0xFF
  and t3,t3,t0
  slli t3,t3,7
  andi t4,t4,0x7F
  or a0,t2,t3
  or a0,a0,t4
  j _mul_epilogue

_mul_epilogue:
  lw s0, 0(sp)
  lw s1, 4(sp)
  lw s2, 8(sp)
  lw s3, 12(sp)
  lw s4, 16(sp)
  lw s5, 20(sp)
  addi sp, sp, 24
  ret

#################
#    bf16_div   #
#################
.global bf16_div
.type bf16_div,%function
bf16_div:         # a0: a, a1: b
  # Prologue: 保存 s0-s6
  addi sp, sp, -28
  sw s0, 0(sp)
  sw s1, 4(sp)
  sw s2, 8(sp)
  sw s3, 12(sp)
  sw s4, 16(sp)
  sw s5, 20(sp)
  sw s6, 24(sp)

  srli s0,a0,15   # s0: sign_a (from a0)
  andi s0,s0,1   
  srli s1,a1,15   # s1: sign_b (from a1)
  andi s1,s1,1   
  srli s2,a0,7    # s2: exp_a (from a0)
  andi s2,s2,0xFF
  srli s3,a1,7    # s3: exp_b (from a1)
  andi s3,s3,0xFF
  andi s4,a0,0x7F # s4: mant_a (from a0)
  andi s5,a1,0x7F # s5: mant_b (from a1)

  xor t2,s0,s1 # result_sign: t2

  li t0,0xFF  # t0: 0xFF
  bne s3,t0,div_exp_b_max_n
  bnez s5,_div_ret_b
  bne s2,t0,_div_ret_zero
  beqz s4,_div_ret_nan
  j _div_ret_zero
  
div_exp_b_max_n:
  bnez s3,div_b_zero_n
  bnez s5,div_b_zero_n
  bnez s2,_div_ret_inf
  beqz s4,_div_ret_nan # 0/0 is nan
  j _div_ret_inf # inf otherwise

div_b_zero_n:
  bne s2,t0,div_exp_a_max_n
  bnez s4,_div_ret_a
  j _div_ret_inf

div_exp_a_max_n: # check if a is zero
  bnez s2,div_a_zero_n
  beqz s4,_div_ret_zero
div_a_zero_n:
  beqz s2,div_a_denorm
  ori s4,s4,0x80
div_a_denorm:
  beqz s3,div_b_denorm
  ori s5,s5,0x80
div_b_denorm:
  slli s4,s4,15 # s4: dividend
                # s5: divisor
  li s6,0       # s6: quotient
  
  li t4,15      # t4: i
div_loop:
  bltz t4,div_loop_exit
  slli s6,s6,1
  sll t5,s5,t4
  addi t4,t4,-1
  blt s4,t5,div_loop
  sub s4,s4,t5
  ori s6,s6,1
  j div_loop
div_loop_exit:
  sub t3,s2,s3
  addi t3,t3,127
  bnez s2,div_exp_a_zero_n
  addi s3,s3,-1
div_exp_a_zero_n:
  bnez s3,div_exp_b_zero_n
  addi s3,s3,1
div_exp_b_zero_n:
  li t4,0x8000
  and t5,s6,t4
  beqz t5,quot_loop
  srli s6,s6,8
  j quot_exit
quot_loop: 
  and t5,s6,t4
  bnez t5,quot_loop_exit
  addi t5,t3,-1
  blez t5,quot_loop_exit  
  slli s6,s6,1
  addi t3,t3,-1
  j quot_loop
quot_loop_exit:
  srli s6,s6,8
quot_exit:
  andi s6,s6,0x7F

  mv t4,s6 # quotient as mantissa
  bge t3,t0,_div_ret_inf
  blez t3,_div_ret_zero
  j _div_ret_encoded

# --- bf16_div Local Helpers ---
_div_ret_a:
  mv a0,a0
  j _div_epilogue
_div_ret_b:
  mv a0,a1
  j _div_epilogue
_div_ret_nan:
  li a0,0x7FC0
  j _div_epilogue
_div_ret_inf:
  slli t2,t2,15
  li t1,0x7F80
  or a0,t1,t2
  j _div_epilogue
_div_ret_zero:
  slli t2,t2,15
  ori a0,t2,0
  j _div_epilogue
_div_ret_encoded:
  slli t2,t2,15
  li t0, 0xFF
  and t3,t3,t0
  slli t3,t3,7
  andi t4,t4,0x7F
  or a0,t2,t3
  or a0,a0,t4
  j _div_epilogue

_div_epilogue:
  lw s0, 0(sp)
  lw s1, 4(sp)
  lw s2, 8(sp)
  lw s3, 12(sp)
  lw s4, 16(sp)
  lw s5, 20(sp)
  lw s6, 24(sp)
  addi sp, sp, 28
  ret

#################
#   bf16_sqrt   #
#################
.global bf16_sqrt
.type bf16_sqrt,%function
bf16_sqrt:        # a0: a
  # Prologue: 保存 s0, s2, s4
  addi sp, sp, -12
  sw s0, 0(sp)
  sw s2, 4(sp)
  sw s4, 8(sp)

  srli s0,a0,15   # s0: sign (from a0)
  andi s0,s0,1   
  srli s2,a0,7    # s2: exp (from a0)
  andi s2,s2,0xFF
  andi s4,a0,0x7F # s4: mant (from a0)

  li t0,0xFF  # t0: 0xFF
  bne s2,t0,sqrt_exp_max_n
  bnez s4,_sqrt_ret_a
  bnez s0,_sqrt_ret_nan
  j _sqrt_ret_a
sqrt_exp_max_n:
  bnez s2,sqrt_a_zero_n
  beqz s4,_sqrt_ret_zero
sqrt_a_zero_n:
  bnez s0,_sqrt_ret_nan
  beqz s2,_sqrt_ret_zero # 修正: exp=0 且 mant=0 才是 0

  addi t1,s2,-127 # t1: e, t2: new_exp
  ori t3,s4,0x80  # t3: m
  
  andi t4,t1,1
  beqz t4,sqrt_even_exp
  slli t3,t3,1
  addi t2,t1,-1
  srli t2,t2,1
  addi t2,t2,127
  j sqrt_adjexp_exit
sqrt_even_exp:
  srli t2,t1,1
  addi t2,t2,127
sqrt_adjexp_exit:
  li a2,90  # low
  li a3,256 # high
  li a4,128 # result
bs_loop:
  bgt a2,a3, bs_exit
  add t4,a2,a3
  srli t4,t4,1 # t4:mid

  # Multiply: t5: prod (簡易乘法，非 bf16_mul)
  li t5,0
  mv t6,t4
sqrt_mult_loop:
  beqz t6,sqrt_mult_exit
  add t5,t5,t4
  addi t6,t6,-1
  j sqrt_mult_loop
sqrt_mult_exit:
  srli t5,t5,7 # sq: t5
  bgt t5,t3,bs_else
  mv a4,t4
  addi a2,t4,1
  j bs_loop
bs_else:
  addi a3,t4,-1
  j bs_loop
bs_exit:
  li t4,256
  blt a4,t4,sqrt_result_norm_else
  srli a4,a4,1
  addi t3,t3,1 # 應為 t2 (new_exp)
  j sqrt_result_norm_exit
sqrt_result_norm_else:
  li t4,128
sqrt_result_norm_loop:
  bge a4,t4,sqrt_result_norm_exit
  li t5,1
  ble t2,t5,sqrt_result_norm_exit
  slli a4,a4,1 
  addi t2,t2,-1
  j sqrt_result_norm_loop
sqrt_result_norm_exit:
  mv t5,t2 # new_exp
  li t2,0 # sign
  andi t4,a4,0x7F # new_mant
  bge t5,t0,_sqrt_ret_inf
  blez t5,_sqrt_ret_zero
  j _sqrt_ret_encoded

# --- bf16_sqrt Local Helpers ---
_sqrt_ret_a:
  mv a0,a0
  j _sqrt_epilogue
_sqrt_ret_nan:
  li a0,0x7FC0
  j _sqrt_epilogue
_sqrt_ret_inf:
  li t2,0 # sign
  slli t2,t2,15
  li t1,0x7F80
  or a0,t1,t2
  j _sqrt_epilogue
_sqrt_ret_zero:
  li t2,0 # sign
  slli t2,t2,15
  ori a0,t2,0
  j _sqrt_epilogue
_sqrt_ret_encoded:
  slli t2,t2,15
  li t0, 0xFF
  and t5,t5,t0  # t5 是 new_exp
  slli t5,t5,7
  andi t4,t4,0x7F
  or a0,t2,t5   # t2 是 sign
  or a0,a0,t4
  j _sqrt_epilogue

_sqrt_epilogue:
  lw s0, 0(sp)
  lw s1, 4(sp)
  lw s2, 8(sp)
  addi sp, sp, 12
  ret
