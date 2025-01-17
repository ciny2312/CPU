`define VectorSize 32

// LS_TYPE: 4 bit
// [3] { 0: r, 1: w }
// [2:0] { 000: b, 001: h, 010: w, 011: d, 100: b, 101: h, 110: w, 111: d  }
// dword may not support
`define LS_TYPE_BIT 4
`define LSB_SIZE_BIT 3

`define ROB_TYPE_BIT 2
`define ROB_TYPE_RG 2'b00
`define ROB_TYPE_ST 2'b01
`define ROB_TYPE_BR 2'b10
`define ROB_TYPE_EX 2'b11

`define ICACHE_SIZE_BIT 3

`define ROB_BIT 5
`define ROB_WIDTH (1 << `ROB_BIT)

`define RS_TYPE_BIT 5 // 1 Br, 1 [30] and 3 func
`define RS_SIZE_BIT 3