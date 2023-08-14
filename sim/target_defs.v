// The Verilator (sim) version of target_defs.v

// This file is included by some of the main RTL files to specify things are unique
// to how that target's tools work.

// This instance of the file suits the needs of the Verilator-based simulation target.

//NOTE: This file has the same name as another used by other targets, to hopefully
// allow for generic `include statements that will end up picking the correct file
// by virtue of the compiler used.

`default_nettype none
`timescale 1ns / 1ps

//NOTE: Nothing else needing to be defined in this file right now, for this target.
