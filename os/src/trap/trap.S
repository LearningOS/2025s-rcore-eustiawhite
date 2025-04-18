.altmacro
.macro SAVE_GP n
    sd x\n, \n*8(sp)
.endm
.macro LOAD_GP n
    ld x\n, \n*8(sp)
.endm
    .section .text
    .globl __alltraps
    .globl __restore
    .align 2
__alltraps:
    csrrw sp, sscratch, sp
    # now sp->kernel stack, sscratch->user stack
    # allocate a TrapContext on kernel stack
    addi sp, sp, -34*8
    # save general-purpose registers
    sd x1, 1*8(sp)
    # skip sp(x2), we will save it later
    sd x3, 3*8(sp)
    # skip tp(x4), application does not use it
    # save x5~x31
    .set n, 5
    .rept 27
        SAVE_GP %n
        .set n, n+1
    .endr
    # we can use t0/t1/t2 freely, because they were saved on kernel stack
    csrr t0, sstatus
    csrr t1, sepc
    sd t0, 32*8(sp)
    sd t1, 33*8(sp)
    # read user stack from sscratch and save it on the kernel stack
    csrr t2, sscratch
    sd t2, 2*8(sp)
    # set input argument of trap_handler(cx: &mut TrapContext)
    mv a0, sp
    call trap_handler

__restore:
    # now sp->kernel stack(after allocated), sscratch->user stack
    # restore sstatus/sepc
    #负责从内核栈顶的 Trap 上下文恢复通用寄存器和 CSR，这些值都存在sp指向的栈中
    ld t0, 32*8(sp)  #把 sp + 256 的 8 字节读入 t0(第 32 个槽，每个槽 8 字节)
    ld t1, 33*8(sp)
    ld t2, 2*8(sp)
    csrw sstatus, t0
    csrw sepc, t1
    csrw sscratch, t2
    #到此为止恢复了CSR
    # restore general-purpuse registers except sp/tp
    ld x1, 1*8(sp)
    ld x3, 3*8(sp)
    .set n, 5
    .rept 27
        LOAD_GP %n
        .set n, n+1
    .endr
    # release TrapContext on kernel stack
    addi sp, sp, 34*8
    # now sp->kernel stack, sscratch->user stack
    csrrw sp, sscratch, sp
    sret

#RISC-V 中读写 CSR 的指令是一类能不会被打断地完成多个读写操作的指令。
#这种不会被打断地完成多个操作的指令被称为 原子指令 (Atomic Instruction)。
#这里的 原子 的含义是“不可分割的最小个体”，也就是说指令的多个操作要么都不完成，要么全部完成，
#而不会处于某种中间状态。

#另外，RISC-V 架构中常规的数据处理和访存类指令只能操作通用寄存器而不能操作 CSR 。
#因此，当想要对 CSR 进行操作时，需要先使用读取 CSR 的指令将 CSR 读到一个通用寄存器中，
#而后操作该通用寄存器，最后再使用写入 CSR 的指令将该通用寄存器的值写入到 CSR 中。

#在特权级切换的时候，我们需要将 Trap 上下文保存在内核栈上，
#因此需要一个寄存器暂存内核栈地址，并以它作为基地址指针来依次保存 Trap 上下文的内容。
#但是所有的通用寄存器都不能够用作基地址指针，因为它们都需要被保存，
#如果覆盖掉它们，就会影响后续应用控制流的执行。

#事实上我们缺少了一个重要的中转寄存器，而 sscratch CSR 正是为此而生。
#从上面的汇编代码中可以看出，在保存 Trap 上下文的时候，它起到了两个作用：
#首先是保存了内核栈的地址，
#其次它可作为一个中转站让 sp （目前指向的用户栈的地址）的值可以暂时保存在 sscratch 。
#这样仅需一条 csrrw  sp, sscratch, sp 指令（交换对 sp 和 sscratch 两个寄存器内容）
#就完成了从用户栈到内核栈的切换，这是一种极其精巧的实现。