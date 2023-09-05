`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_

//SMELL: Many of these notes, and even probably some of these defines, are left-over from the bigger Raybox design.
// Go thru all this and clean it up.

// A note on Qm:
// It seems the smaller the player step size, the bigger Qm needs to be. Non-power-of-2 steps could make this worse.
// For instance, with Q12.12, it seems the smallest reliable step quantum is 8, i.e. 8*(2^-12) => 0.001953125.
// This might be made better if we properly check for reciprocal saturation.
`define Qm          10                  // Signed. 8 is minimum, else rayAddend overflows.
`define Qn          10                  // Currently 9 seems to be the lowest value for clean 640x480, but 10+ is recommended.
`define Qmn         (`Qm+`Qn)
`define QMI         (`Qm-1)             // Just for convenience; M-1.
//NOTE:
// DON'T FORGET! When changing `Qm or `Qn, you also need to update the LZCs (inc. `SZ)
// and the equivalent values in sim_main.cpp if using the sim.

// // These values are for "Distance fixed-point"; a feature specific to the tracer storing visual distance values.
// // Because this (probably) needs to go into on-chip memory, we constrain it to hopefully the minimum it needs to be
// // (which right now is 16 bits).
// //NOTE: Some sort of floating-point could probably work better, and in that case we've observed that probably 7~9 bits
// // would be sufficient, plus an exponent. This could even be calculated for us by the `reciprocal` module's LZC.
// `define DI          7                   // Integer part of possible visual distance. Supports 0..127, but realistically probably a max of 91 in a 64x64 map.
// `define DF          9                   // Fractional part of visual dist. Supports 1/512 precision (i.e. 1/2**9).
// `define DII         (`DI-1)
// `define DFI         (-`DF)
// `define Dbits       (`DI+`DF)

//SMELL: Base all of these hardcoded numbers on Qm and Qn values:
`define F           signed [`QMI:-`Qn]  // `Qm-1:0 is M (int), -1:-`Qn is N (frac).
`define FExt        [`Qm+`Qn-1:0]       // Same as F but for external use (i.e. with no negative bit indices, to help OpenLane LVS).
`define I           signed [`QMI:0]
`define f           [-1:-`Qn]           //SMELL: Not signed.
`define F2          signed [`Qm*2-1:-`Qn*2] // Double-sized F (e.g. result of multiplication).

// Unsigned version of `F; same bit depth, but avoids sign comparison;
// i.e. "negative" numbers compare to be greater than all positive numbers:
`define UF          unsigned [`QMI:-`Qn]

`define FF(f)       f[`QMI:-`Qn]        // Get full F out of something bigger (e.g. F2).
`define FI(f)       f[`QMI:0]           // Extract I part from an F.
`define IF(i)       {i,`Qn'b0}          // Expand I part to a full F.

`define Ff(f)       f[-1:-`Qn]          // Extract fractional part from an F. //SMELL: Discards sign!
`define fF(f)       {`Qm'b0,f}          // Build a full F from just a fractional part.

`define intF(i)     ((i)<<<`Qn)         // Convert const int to F.
`define Fint(f)     ((f)>>>`Qn)         // Convert F to int.

`define realF(r)    (((r)*(2.0**`Qn)))
`define Freal(f)    ((`FF(f))*(2.0**-`Qn))
`define FrealS(f)   ($signed(`FF(f))*(2.0**-`Qn)) // Signed helper.

`endif //_FIXED_POINT_PARAMS__H_

