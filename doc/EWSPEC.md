# Spec for Anton's design (`top_ew_algofoogle`)

This is a purely-digital design for now. I hope to still include a very simple analog portion, but can leave it out if I don't finish it soon, or if it otherwise would be trouble for everyone to include.

## Size

I guessed at an area of 700x700&micro;m needed for my design. So far, it uses &lt; 30% of that. Another feature I hope to finish before next week will fill this more. Otherwise, it should be possible to shrink the area to 500x500&micro;m if necessary.


## Caravel Management SoC

The design has 47 internal inputs that can be controlled by the Caravel Managment SoC, running firmware. I'm intending to do this by using [47 of the internal Logic Analyser pins](#logic-analyser-pins) (all outputs from SoC, inputs to my design). Some are essential, but if 47 is too many, give me a target and I can cut it back.

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

**I will drop the analog part of my design for now.** If there is time in the coming days, I will see if I can get it in, but otherwise assume I will assign my analog pad to be a 9th digital pad instead.


### If only 9 pads are available to me, in total

...this is how I'll assign those pads to the ports in my top module:

| Pad | Dir | Top module port        |
|----:|:---:|------------------------|
|   1 | Out | `o_hsync`              |
|   2 | Out | `o_vsync`              |
|   3 | Out | `o_tex_csb`            |
|   4 | Out | `o_tex_sclk`           |
|   5 | I/O | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   6 | Out | `o_gpout[0]`           |
|   7 | Out | `o_gpout[1]`           |
|   8 |  In | `i_tex_in[1]`          |
|   9 |  In | `i_tex_in[2]`          |


### If 9 pads available PLUS extra shared/muxed INPUTS

Ellen advised that some digital inputs could *maybe* be shared between designs. I could use more *outputs*, so if the possible "shared" digital pads are *inputs* only, the bottom 4 rows capitalise on this to make my only 2 inputs shared with Ellen's. Hence, I can add 2 more outputs (`o_gpout[2]` and `o_gpout[3]`):

| Pad | Dir   | Top module port        |
|----:|:-----:|------------------------|
|   1 |  Out  | `o_hsync`              |
|   2 |  Out  | `o_vsync`              |
|   3 |  Out  | `o_tex_csb`            |
|   4 |  Out  | `o_tex_sclk`           |
|   5 |  I/O  | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   6 |  Out  | `o_gpout[0]`           |
|   7 |  Out  | `o_gpout[1]`           |
|**8**|**Out**| **`o_gpout[2]`**       |
|**9**|**Out**| **`o_gpout[3]`**       |
|*10* | *In*  | `i_tex_in[1]` **(shared)** |
|*11* | *In*  | `i_tex_in[2]` **(shared)** |


## If 9 pads available PLUS extra shared/muxed INPUTS and OUTPUTS

Finally, if there happen to be additional pads that can mux OUTPUTS too, I would add `o_gpout[4]` and `o_gpout[5]`:

| Pad  | Dir   | Top module port        |
|-----:|:-----:|------------------------|
|   1  |  Out  | `o_hsync`              |
|   2  |  Out  | `o_vsync`              |
|   3  |  Out  | `o_tex_csb`            |
|   4  |  Out  | `o_tex_sclk`           |
|   5  |  I/O  | **Bi-dir**; in port: `i_tex_in[0]`; out port: `o_tex_out0` (activated by `o_tex_oeb0`==0) |
|   6  |  Out  | `o_gpout[0]`           |
|   7  |  Out  | `o_gpout[1]`           |
|   8  |  Out  | `o_gpout[2]`           |
|   9  |  Out  | `o_gpout[3]`           |
|**10**|**Out**| `o_gpout[4]` **(shared)** |
|**11**|**Out**| `o_gpout[5]` **(shared)** |
| *12* | *In*  | `i_tex_in[1]` **(shared)** |
| *13* | *In*  | `i_tex_in[2]` **(shared)** |


## Logic Analyser pins

Below are the 47 signals that my design's top module takes as input ports, that I would like wired up to the SoC's LA output pins.

They are listed in order of importance **(most important at the top)**. If this list needs to be cut short, **ideally the ones that don't make the cut would be hard-wired to GND**, which then selects sensible defaults in my design...

1.  `i_reset_lock_a`
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
