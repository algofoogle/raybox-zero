# Raybox-zero Game Implementation

Here you will find information and code for actually testing/using Raybox-zero (RBZ) in hardware, in particular ASICs fabricated with Tiny Tapeout and/or Efabless.

There is [documentation](./doc/README.md) for this, with coverage for various generations of Raybox-zero in hardware.

The main thing you'll find here is layers of code, which you:
*   Run on a PC to take user input (keyboard/mouse) and thus manage the 'game state' and determine the current POV (point-of-view).
*   Run on a 'bridge' of some kind (e.g. RP2040) to take the POV data over USB and send into the chip (and otherwise control input pins of the chip).
*   Run as firmware on the chip's Caravel RISC-V CPU (if any); there is a run of RBZ that was pin-constrained so some of its pins could only be bit-banged internally by the CPU.

