# Raybox-zero Game Implementation: Testing Raybox-zero in hardware

The table below shows instances of where Raybox-zero (RBZ) was implemented in hardware. The left-hand column offers links to the respective bring-up/testing documentation for that instance.

Things start getting interesting as of [CI2311](./CI2311.md) because this is where the rendering works correctly, and external texture ROM is supported.

| Hardware | Repo | When | Version | Results |
|-|-|-|-|-|
| FPGA | TBA | Various | Various | Works |
| [TT04](https://github.com/algofoogle/tt04-raybox-zero/tree/main/demoboard) | [GH](https://github.com/algofoogle/tt04-raybox-zero) | [Sep 2023](https://tinytapeout.com/runs/tt04/tt_um_algofoogle_raybox_zero) | [1.0](https://github.com/algofoogle/raybox-zero/releases/tag/1.0) | Works, but very glitchy visuals (due to OpenLane synthesis bug) |
| [CI2311](./CI2311.md) | [GH](https://github.com/algofoogle/raybox-zero-caravel)[^1] | Nov 2023 | 1.3 | Works. Reduced ext. interface (pin-constrained) so also bit-bangs via LA |
| GFMPW-1 | [GH](https://github.com/algofoogle/algofoogle-multi-caravel), [EF](https://repositories.efabless.com/algofoogle/ztoa-team-group-caravel) | Dec 2023 | 1.4 | TBA |
| TT07 | [GH](https://github.com/algofoogle/tt07-raybox-zero) | [Jun 2024](https://tinytapeout.com/runs/tt07/tt_um_algofoogle_raybox_zero) | [1.5](https://github.com/algofoogle/raybox-zero/releases/tag/1.5) | TBA |
| TTIHP0.1 | [GH](https://github.com/TinyTapeout/tinytapeout-ihp-0p1) | Aug 2024 | [1.5](https://github.com/algofoogle/raybox-zero/releases/tag/1.5) | TBA | 
| CI2409 | TBA | Sep 2024 | [1.5](https://github.com/algofoogle/raybox-zero/releases/tag/1.5)[^2] | TBA |

NOTE: From memory, GFMPW-1 supports Trace Debug, but it is disabled in TT07 and CI2409.

[^1]: The CI2311 version's actual GitHub repo is private, as this was sharing commercial chipIgnite die area, so the [linked repo](https://github.com/algofoogle/raybox-zero-caravel) is just a representation of what got submitted, and has a different pin numbering.
[^2]: The v1.5 code used for CI2409 is the same as for TT07. It was copied into the repo from the [raybox-zero repo](https://github.com/algofoogle/raybox-zero). Just note that the pinout naturally differs between hardware implementations.
