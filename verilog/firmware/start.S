.section .text.init
.globl _start

_start:

    /*
     * Stack is placed at the end of RAM.
     *
     * Our simulation RAM will be 16 KB:
     * 0x00000000 - 0x00003FFF
     *
     * Stack top = 0x00004000
     */
    li sp, 0x00004000

    call main

1:
    j 1b
