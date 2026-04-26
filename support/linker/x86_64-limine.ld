OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(silt_limine_entry)

PHDRS
{
  text PT_LOAD FLAGS(5);
  rodata PT_LOAD FLAGS(4);
  data PT_LOAD FLAGS(6);
}

SECTIONS
{
  . = 0xffffffff80000000;

  .text.silt.boot : ALIGN(4096) {
    KEEP(*(.text.silt.boot))
  } :text

  .text : ALIGN(4096) {
    *(.text .text.*)
  } :text

  .rodata : ALIGN(4096) {
    *(.rodata .rodata.*)
  } :rodata

  . = ALIGN(4096);

  .limine_requests_start : ALIGN(8) {
    KEEP(*(.limine_requests_start))
  } :data

  .limine_requests : ALIGN(8) {
    KEEP(*(.limine_requests))
  } :data

  .limine_requests_end : ALIGN(8) {
    KEEP(*(.limine_requests_end))
  } :data

  .data : ALIGN(4096) {
    *(.data .data.*)
  } :data

  .bss : ALIGN(4096) {
    *(COMMON)
    *(.bss .bss.*)
  } :data

  /DISCARD/ : {
    *(.comment)
    *(.note .note.*)
    *(.eh_frame .eh_frame.*)
  }
}
