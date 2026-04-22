OUTPUT_ARCH( "riscv" )
ENTRY( _start )

SECTIONS
{
  . = 0x00000000;          /* Instruction Memory starts at 0 */
  .text : { *(.text) }
  
  . = 0x00002000;          /* Data Memory starts at 0x2000 */
  .data : { *(.data) }
  .bss  : { *(.bss) }
}
