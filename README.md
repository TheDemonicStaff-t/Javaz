# WTF EVEN IS THIS???

This is an attempt at a java toolchain written in zig

- compiler
- assembler
- virtual machine
- dissassembler
- decompiler

# READER FOR ALLOCATED BYTE ARRAY

var stream = std.io.fixedBufferStream(allocated_array);
const reader = stream.reader();
