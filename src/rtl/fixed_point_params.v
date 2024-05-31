`ifndef _FIXED_POINT_PARAMS__H_
`define _FIXED_POINT_PARAMS__H_

//SMELL: Many of these notes, and even probably some of these defines, are left-over from the bigger Raybox design.
// Go thru all this and clean it up.

// A note on Qm:
// It seems the smaller the player step size, the bigger Qm needs to be. Non-power-of-2 steps could make this worse.
// For instance, with Q12.12, it seems the smallest reliable step quantum is 8, i.e. 8*(2^-12) => 0.001953125.
// This might be made better if we properly check for reciprocal saturation.
//NOTE: Minimum that currently works is Q10.9, but Q10.10 is better:
`define Qm          11                  // Signed. 9 is minimum: Below 9, texv is broken. Below 8, rayAddend overflows.
`define Qn          11                  // Currently 9 is lowest possible because of other bit-range maths, but 10+ is recommended.
`define Qmnc        22          // <== MUST EQUAL Qmn+Qn. Sort of the same as `Qmn, but that isn't useful for all my Verilog needs.
//NOTE: DON'T FORGET!!:
// > When changing `Qm or `Qn, you also need to update the LZCs (inc. `SZ)
// > and the equivalent values in sim_main.cpp if using the sim.
`define Qmn         (`Qm+`Qn)
`define QMI         (`Qm-1)             // Just for convenience; M-1.
`define QMNI        (`Qmn-1)            // Just for convenience; full bit count -1 for upper vector index.

//SMELL: Base all of these hardcoded numbers on Qm and Qn values:
`define Fn          [`QMI:-`Qn]
`define F           signed `Fn          // `Qm-1:0 is M (int), -1:-`Qn is N (frac).
`define FExt        [`Qm+`Qn-1:0]       // Same as F but for external use (i.e. with no negative bit indices, to help OpenLane LVS).
`define I           signed [`QMI:0]
`define f           [-1:-`Qn]           //SMELL: Not signed.
`define F2          signed [`Qm*2-1:-`Qn*2] // Double-sized F (e.g. result of multiplication).

// Unsigned version of `F; same bit depth, but avoids sign comparison;
// i.e. "negative" numbers compare to be greater than all positive numbers:
`define UF          unsigned `Fn

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

