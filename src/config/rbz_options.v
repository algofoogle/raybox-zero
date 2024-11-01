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
