# Raybox Zero

While [Raybox][] is my main HDL ray caster, this project is an attempt to do a minimalist version that might be able to fit
on TT04.

Differences from how Raybox was designed:
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
*   Tracing "rows" instead of "columns":
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

### Required

*   tracer logic and FSM
*   row renderer?
*   map
*   vga/rgb mux
*   view vectors (and SPI slave controller?)
*   reciprocal(s)
*   shared multiplier?

### Optional

*   texture SPI RAM master and local memory
*   external control pins
*   debugging IO
*   debug overlay
*   temporal ordered dither



[Raybox]: https://github.com/algofoogle/raybox
