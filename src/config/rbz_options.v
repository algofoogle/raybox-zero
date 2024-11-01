// This file is only used by compilation/synthesis/simulation targets to specify which options
// we want, and it's expect this file will be part of whatever project/target is hosting the
// core raybox-zero code to specify conditional compilation.
`define USE_MAP_OVERLAY
`define USE_DEBUG_OVERLAY
`define TRACE_STATE_DEBUG  // Trace state is represented visually per each line on-screen.
//`define STANDBY_RESET // If defined use extra logic to avoid clocking regs during reset (for power saving/stability).
//`define RESET_TEXTURE_MEMORY // Should there be an explicit reset for local texture memory?
//`define RESET_TEXTURE_MEMORY_PATTERNED // If defined with RESET_TEXTURE_MEMORY, texture memory reset is a pattern instead of black.
//`define DEBUG_NO_TEXTURE_LOAD // If defined, prevent texture loading
//`define NO_EXTERNAL_TEXTURES
// `define ALT_FIXED_POINT_PARAMS
//     `define Qm    10   // Signed. 9 is minimum: Below 9, texv is broken. Below 8, rayAddend overflows.
//     `define Qn    9    // Currently 9 is lowest possible because of other bit-range maths, but 10+ is recommended.
//     `define Qmnc  19   // <== MUST EQUAL Qmn+Qn. Sort of the same as `Qmn, but that isn't useful for all my Verilog needs.
//     // The following matches LZC config (in lzc.v) to the above...
//     //NOTE: The FIRST defined of the following will be used:
//     // `define D17 // 17-bit range, e.g. Q8.9
//     // `define D18 // 18-bit range, e.g. Q9.9
//     `define D19 // 19-bit range, e.g. Q9.10
//     // `define D20 // 20-bit range, e.g. Q10.10
//     // `define D22 // 22-bit range, e.g. Q11.11
//     // `define D24 // 24-bit range, e.g. Q12.12
//     // `define D30 // 30-bit range, e.g. Q15.15, mostly for testing.
