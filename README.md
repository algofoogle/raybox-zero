# Raybox Zero

While [Raybox][] is my main HDL ray caster, this project is an attempt to do a minimalist version that might be able to fit on TT04.

## Running Verilator simulation on Windows

I went through "[Setting up under Windows](https://github.com/algofoogle/raybox#setting-up-under-windows)" on a new Windows 11 machine,
but note that there were some quirks:
*   The MSYS2 installer I used was [msys2-x86_64-20230718.exe](https://github.com/msys2/msys2-installer/releases/download/2023-07-18/msys2-x86_64-20230718.exe) (July 2023).
*   When it ran the terminal at the end, it ran "MSYS2 UCRT64", but I'm not certain this was completely compatible with my instructions above, and so I switched to "MSYS2 MINGW64".
*   When Verilator gets installed, it doesn't seem to get a runnable `verilator` in the PATH by default, so I had to make sure the `Makefile` in this repo switches to using `verilator_bin.exe` instead when run under Windows.

Other than that, I can run the simulator with:

```ps
make clean_sim
```

## Running on 8bitworkshop

The IDE at [8bitworkshop.com](https://8bitworkshop.com) is neat!

Sadly, the [Verilog (VGA @ 25 Mhz)](https://8bitworkshop.com/v3.10.1/?platform=verilog-vga) simulator can't run the design at this time. It comes up with an error `Error: extends width 64 != 32` which seems to stem from [here](https://github.com/sehugg/8bitworkshop/blob/70fdb6862244c0b5585d23a45ee08c57ec116a8f/src/common/hdl/vxmlparser.ts#L523) and is flagged in my `reciprocal` module on one of the multiplications.

I might see if there's something that can be done about this another time.

The [`8bw`](./8bw/) directory contains a top module (`rbzero_top`) that could otherwise be used to interface the main `rbzero` design with the 8bitworkshop simulator. It includes a `dither` module to go from RGB222 to RGB111.


## Differences from how Raybox was designed

### I/O constraints
These are some possible pinouts on TT04 or even more-constrained targets:

*   Standard pinout:
    *   All digital
    *   CLK and RESET
    *   8 inputs, 8 outputs, 8 bidir pins.
    *   26 total.
*   Constrained pinout:
    *   CLK and RESET
    *   2 RGB *analog* output pins
    *   2 sync digital outputs
    *   3 SPI slave pins (for host controller)
    *   4 SPI master pins (for RAM)
    *   13 total.
*   Super-constrained pinout:
    *   CLK and RESET
    *   4 SPI master pins (for RAM) -- use a "smart" slave that can provide both RAM and controller update registers.
    *   1 *analog* output pin -- composite video
    *   7 total.

### Tracing "rows" instead of "columns"

*   Column-tracing:
    *   A (say) 160x120 frame requires at least 6 bits of column height and 1 bit for side: 160x7 = 1120 bits.
    *   Add in 2-colour, and we need an extra bit: 160x8 = 1280 bits.
    *   Add in 32x32 textures, and we need at *least* an extra 5 bits: 160x13 = 2080 bits -- possibly more for scaling data.
*   Row-tracing:
    *   A (say) 512x480 frame requires 8 bits of column height and 1 bit for side, but potentially can be computed *per line*, so only 9 bits.
    *   Add in 8-colour, and we need an extra 3 bits.
    *   Add in 64x64 textures, and we need *at most* an extra 16 bits: ~28 bits total.
    *   NOTE: If we were IO-constrained, we could store texture data in external SPI RAM, and load the texture "row" into an internal
        64x6-bit buffer: 384 bits.
*   Note that with row-tracing we'd even have enough time to trace all during VBLANK and write them to external RAM, then
    pull individual row widths only when needed at the end of each line.
*   NOTE: Row-tracing doesn't HAVE to be only during HBLANK? Could be done during the whole line (for the next line).
    Same goes for external RAM access, *to an extent*.
*   Disadvantage: row-tracing is crappy. Wrong aspect ratio, and wrong orientation (unless you rotate the screen).

## Other modules

### Implemented

*   Basic row renderer (without texture mapping)
*   VGA RGB mux
*   LZC (hard-coded Q12.12)
*   Reciprocal approximator for Q12.12

### Required

*   tracer logic and FSM
*   map
*   view vectors (and SPI slave controller?)
*   shared multiplier?

### Optional

*   texture SPI RAM master and local memory
*   external control pins
*   debugging IO
*   debug overlay
*   temporal ordered dither

## Other ideas and notes

*   When tracing rows instead of columns, we don't need an immediate reciprocal, but could instead calculate it progressively
    as part of the FSM. This *might* allow for greater accuracy, and *could* also be a smaller amount of logic.
*   It would be cool if we had the option of changing vectors between rows (scanlines) so that we could potentially render different angles (split-screen)?

[Raybox]: https://github.com/algofoogle/raybox
