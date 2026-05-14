OUTPUT_ARCH( "riscv" )
ENTRY( _start )

SECTIONS
{
  . = 0x00000000;
  .text : { *(.text) }
  
  . = 0x00002000;
  .data : { *(.data) }
  .bss  : { *(.bss) }
}