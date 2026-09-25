ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        *(.text.init)
        *(.text*)
        *(.rodata*)
    } > RAM

    .data :
    {
        . = ALIGN(4);
        *(.data*)
    } > RAM

    .bss :
    {
        . = ALIGN(4);
        *(.bss*)
        *(COMMON)
    } > RAM

    . = ALIGN(4);

    _end = .;
}
