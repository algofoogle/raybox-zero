# Spec for Anton's design (`top_ew_algofoogle`)

## TL;DR

Design is purely-digital for now. I hope to still include a very simple analog portion, but can leave it out if I don't finish it soon.

My macro (i.e. top module) is [`top_ew_algofoogle`](https://github.com/algofoogle/raybox-zero/blob/ew/src/rtl/top_ew_algofoogle.v). Its pins (ports) break out of all its *possible* connections, even though not necesarily all of them will be used together (depending on which way we agree to do pad sharing). The idea is that this allows a single hardened version of the macro to be instantiated with different (and extra) wiring where available, e.g. to use a mux provided by Matt Venn.

My design [needs the Caravel SoC](#caravel-management-soc) to run firmware and control *up to* [51 LA pins](#logic-analyser-pins) (inputs into my design).

I think we'll be fine in terms of [clocking](#clocking) and [holding in reset](#reset-lock).

I've worked out my intended pad use for each of:
1.  [If only 9 pads are available to me, in total](#if-only-9-pads-are-available-to-me-in-total)
2.  [If 9 pads available PLUS extra shared/muxed INPUTS](#if-9-pads-available-plus-extra-sharedmuxed-inputs)
3.  [If 9 pads available PLUS extra shared/muxed INPUTS and OUTPUTS](#if-9-pads-available-plus-extra-sharedmuxed-inputs-and-outputs)

Verilog snippets to instantiate each of those alternatives will be found in [raybox-zero's `ew` branch](https://github.com/algofoogle/raybox-zero/tree/ew), and specifically in the [`src/rtl/ew_caravel_snippets` path](https://github.com/algofoogle/raybox-zero/tree/ew/src/rtl/ew_caravel_snippets).


## Size

I guessed at an area of 700x700&micro;m needed for my design. So far, it uses &lt; 30% of that. Another feature I hope to finish before next week will fill this more. Otherwise, it should be possible to shrink the area to 500x500&micro;m if necessary.


## Caravel Management SoC

Besides the clock and external pads, the design has 51 internal inputs that can be controlled by the Caravel Managment SoC, running firmware. I'm intending to do this by using [51 of the internal Logic Analyser pins](#logic-analyser-pins) (all outputs from SoC, inputs to my design). Some are essential, but if 51 is too many, give me a target and I can cut it back.

I'm not using the Wishbone bus.


## Reset lock

So my design isn't free-running, it has to be explicitly 'enabled': I've got a reset 'lock' that is only released by two specific LA pins having *differing* values. In other words, the design's active-high reset is driven by the XNOR of those two chosen LA pins:

| LA[x] | LA[y] | reset                              |
|-------|-------|------------------------------------|
|   0   |   0   | 1 (asserted; design held in reset) |
|   1   |   1   | 1 (asserted; design held in reset) |
|   1   |   0   | 0 (released; design is running)    |
|   0   |   1   | 0 (released; design is running)    |

Irrespective of whether the LA pins start up all high, or all low, the design will be held in reset. Following power-on, I am *assuming* they won't all stay floating or in a random state. If they are, however, SoC firmware can rectify this.


## Clocking

My design's top module `i_clk` input port requires a clock of ~25MHz, 50% duty cycle. I don't think it matters where this comes from; `user_clock2` I *assume* would be fine (as suggested by Ellen and John), but I don't yet know what the different clock sources are or the impact of choosing one over another. Can `user_clock2` be turned off by the SoC or Housekeeping module, perhaps? Otherwise the reset lock above should provide enough protection.


## Pads

***I will drop the analog part of my design for now.** If there is time in the coming days, I will see if I can get it in, but otherwise assume I will assign my analog pad to be a 9th digital pad instead.*


### If only 9 pads are available to me, in total

I have a Verilog snippet ([`SNIPPET1_NoShare.v`](https://github.com/algofoogle/raybox-zero/blob/ew/src/rtl/ew_caravel_snippets/SNIPPET1_NoShare.v)) that just instantiates my design with no sharing/mux support. In other words, it just directly uses the 9 pads I've been assigned, plus internal clock, plus 51 LA pins.

My snippet uses convenience mapping [of the IOs](https://github.com/algofoogle/raybox-zero/blob/f085fa596394a6500e2a596dc613117d645b81d2/src/rtl/ew_caravel_snippets/SNIPPET1_NoShare.v#L12-L15) and [of the LAs](https://github.com/algofoogle/raybox-zero/blob/f085fa596394a6500e2a596dc613117d645b81d2/src/rtl/ew_caravel_snippets/SNIPPET1_NoShare.v#L17-L19) so that these can easily be changed if needed, and also to ensure I don't accidentally overlap with someone else.

For reference, this is how the pads are assigned to the ports in my top module:

| Pad | Dir | Top module port        |
|----:|:---:|------------------------|
|   0 | Out | `o_hsync`              |
|   1 | Out | `o_vsync`              |
|   2 | Out | `o_tex_csb`            |
|   3 | Out | `o_tex_sclk`           |
|   4 | I/O | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   5 | Out | `o_gpout[0]`           |
|   6 | Out | `o_gpout[1]`           |
|   7 |  In | `i_tex_in[1]`          |
|   8 |  In | `i_tex_in[2]`          |
| 9 total |

**NOTE TO SELF**: In this snippet, I've assigned my highest LA signal (`anton_la_in[50]`) to be the driver of `i_tex_in[3]` internally, even though I don't yet have an implementation for that input in the design. At least that way if I *do* implement it, there's still a way to drive it rather than leave it floating.


### If 9 pads available PLUS extra shared/muxed INPUTS

Ellen advised that some digital inputs could *maybe* be shared between designs. I could use more *outputs*, so if the possible "shared" digital pads are *inputs* only, the bottom 5 rows capitalise on this to make my only 2 inputs shared with Ellen's (and add a third). Hence, I can also add 2 more outputs (`o_gpout[2]` and `o_gpout[3]`):

| Pad | Dir   | Top module port        |
|----:|:-----:|------------------------|
|   0 |  Out  | `o_hsync`              |
|   1 |  Out  | `o_vsync`              |
|   2 |  Out  | `o_tex_csb`            |
|   3 |  Out  | `o_tex_sclk`           |
|   4 |  I/O  | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   5 |  Out  | `o_gpout[0]`           |
|   6 |  Out  | `o_gpout[1]`           |
|**7**|**Out**| **`o_gpout[2]`**       |
|**8**|**Out**| **`o_gpout[3]`**       |
| *9* | *In*  | `i_tex_in[1]` **(shared)** |
|*10* | *In*  | `i_tex_in[2]` **(shared)** |
|*11* | *In*  | `i_tex_in[3]` **(shared)** |
| 12 total |

## If 9 pads available PLUS extra shared/muxed INPUTS and OUTPUTS

Finally, if the *shared* pads could easily mux OUTPUTS as well as INPUTS, I would do the following (adding `o_gpout[4]` and `o_gpout[5]`):

| Pad  | Dir   | Top module port        |
|-----:|:-----:|------------------------|
|   0  |  Out  | `o_hsync`              |
|   1  |  Out  | `o_vsync`              |
|   2  |  Out  | `o_tex_csb`            |
|   3  |  Out  | `o_tex_sclk`           |
|   4  |  I/O  | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   5  |  Out  | `o_gpout[0]`           |
|   6  |  Out  | `o_gpout[1]`           |
|   7  |  Out  | `o_gpout[2]`           |
|   8  |  Out  | `o_gpout[3]`           |
| **9**|**Out**| `o_gpout[4]` **(shared)** |
|**10**|**Out**| `o_gpout[5]` **(shared)** |
| *11* | *In*  | `i_tex_in[1]` **(shared)** |
| *12* | *In*  | `i_tex_in[2]` **(shared)** |
| 13 total |

## Logic Analyser pins

I've nominated 51 LA signals below that the SoC will send to my design (i.e. they are inputs *into* my design).

These signals are numbered/listed in order of importance **(most important at the top)**. If this list needs to be cut short, **ideally the ones that don't make the cut would be hard-wired to GND**, which then selects sensible defaults in my design...

NOTE: In my instantiation Verilog snippets I've arbitrarily selected `la_data_in[114:64]` and used a convenience mapping to call them `anton_la_in[50:0]`. Hence, 0 below is LA[64], 1 below is LA[65], etc...

0.  `i_reset_lock_a`
1.  `i_reset_lock_b`
1.  `i_vec_csb`
1.  `i_vec_sclk`
1.  `i_vec_mosi`
1.  `i_gpout0_sel[0]`
1.  `i_gpout0_sel[1]`
1.  `i_gpout0_sel[2]`
1.  `i_gpout0_sel[3]`
1.  `i_gpout0_sel[4]`
1.  `i_gpout0_sel[5]`
1.  `i_debug_vec_overlay`
1.  `i_reg_csb`
1.  `i_reg_sclk`
1.  `i_reg_mosi`
1.  `i_gpout1_sel[0]`
1.  `i_gpout1_sel[1]`
1.  `i_gpout1_sel[2]`
1.  `i_gpout1_sel[3]`
1.  `i_gpout1_sel[4]`
1.  `i_gpout1_sel[5]`
1.  `i_gpout2_sel[0]`
1.  `i_gpout2_sel[1]`
1.  `i_gpout2_sel[2]`
1.  `i_gpout2_sel[3]`
1.  `i_gpout2_sel[4]`
1.  `i_gpout2_sel[5]`
1.  `i_debug_trace_overlay`
1.  `i_gpout3_sel[0]`
1.  `i_gpout3_sel[1]`
1.  `i_gpout3_sel[2]`
1.  `i_gpout3_sel[3]`
1.  `i_gpout3_sel[4]`
1.  `i_gpout3_sel[5]`
1.  `i_debug_map_overlay`
1.  `i_gpout4_sel[0]`
1.  `i_gpout4_sel[1]`
1.  `i_gpout4_sel[2]`
1.  `i_gpout4_sel[3]`
1.  `i_gpout4_sel[4]`
1.  `i_gpout4_sel[5]`
1.  `i_gpout5_sel[0]`
1.  `i_gpout5_sel[1]`
1.  `i_gpout5_sel[2]`
1.  `i_gpout5_sel[3]`
1.  `i_gpout5_sel[4]`
1.  `i_gpout5_sel[5]`
1.  `i_mode[0]`
1.  `i_mode[1]`
1.  `i_mode[2]`
1.  `i_tex_in[3]`

## TODO

*   Include questions for Matt e.g. those planned for the group call (**note to self**: in Journal 0166).
