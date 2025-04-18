# This is MicroPython code that runs on the TT04 board's RP2040,
# to enable a host to communicate with raybox-zero running on the ASIC.
# See raybox-controller.py for the host PC side that sends us commands.
import time
from machine import Pin, SoftSPI

# Raybox-Zero SPI interface, can talk to either of RBZ's SPI peripherals:
# - "vectors" (POV) and "registers" (REG)
class RBZSPI:
    SPI_BAUD = 500_000 # 500kHz is max supported by MicroPython on RP2040
    def __init__(self, tt, interface):
        self.tt = tt
        self.debug = False
        self.interface = interface
        if interface == 'pov':
            self.align_right = False # When payload is padded to bytes, it is left-aligned.
            self.lbits = 0 # Left-aligned preamble bit count is N/A.
            self.csb = tt.pins.pin_ui_in2
            self.spi = SoftSPI(
                baudrate= RBZSPI.SPI_BAUD,
                sck     = tt.pins.pin_ui_in0,
                mosi    = tt.pins.pin_ui_in1,
                miso    = tt.pins.pin_uio5 # DUMMY: This SPI peripheral doesn't output data.
            )
        elif interface == 'reg':
            self.align_right = True # When payload is padded to bytes, it is right-aligned.
            self.lbits = 4 # Left-aligned preamble bit count is 4 (for command length).
            # Configure this interface's uio[4:2] as RP2040 outputs, leaving the rest as inputs
            # (i.e. unused by RP2040 as the ASIC uses them directly with the textures SPI ROM):
            tt.uio_oe_pico.value = 0b00011100 #SMELL: Do this with slices or a read-modify-write?
            self.csb = tt.pins.pin_uio4
            self.spi = SoftSPI(
                baudrate= RBZSPI.SPI_BAUD,
                sck     = tt.pins.pin_uio2,
                mosi    = tt.pins.pin_uio3,
                miso    = tt.pins.pin_uio5 # DUMMY: This SPI peripheral doesn't output data.
            )
        else:
            raise ValueError(f"Invalid interface {repr(interface)}; must be 'pov' or 'reg'")
        
    def __repr__(self): return f'RBZSPI({self.interface})'

    def enable(self):   self.csb(False)
    def disable(self):  self.csb(True)

    def txn_start(self):
        self.debug_print("txn_start")
        self.disable() # Inactive at start; ensures SPI is reset.
        self.enable()

    def txn_stop(self):
        self.debug_print("txn_stop")
        self.disable()

    # Expects a binary string or integer as input.
    # Returns a binary string representation that is the required length (count).
    def to_bin(self, data, count=None):
        if type(data) is int:
            data = bin(data)
            data = data[2:]
            if count is None:
                print(f"WARNING: SPI.send_bits() called with int data {data} but no count")
        if count is not None:
            data = ('0'*count + data)[-count:] # Zero-pad (or trim) to the required count.
        return data

    def debug_print(self, msg, data=None):
        if self.debug:
            out = [msg]
            if type(data) is bytes:
                out.append(' '.join(f'{byte:08b}' for byte in data))
            elif type(data) is not None:
                out.append(repr(data))
            print(f"{self.__class__.__name__}: {' '.join(out)}")


    def send_payload(self, data, count=None, debug=False):
        if self.debug or debug: start_time = time.ticks_us()
        self.txn_start()
        if type(data) is bytearray or type(data) is bytes:
            #NOTE: No bit alignment changes in this mode; assume bytes are to be written raw, as-is.
            self.spi.write(data)
            self.debug_print("Write:", data)
        else:
            # Build up a binary string:
            if type(data) is not list:
                # Just send an explicit value (of a given optional 'count' size):
                bin = self.to_bin(data, count)
            else:
                # Caller wants to concatenate multiple chunks in the one transaction
                # (e.g. packed data):
                bin = ''
                for chunk in data:
                    if type(chunk) is tuple:
                        # Tuple means we have both data,
                        # and the count of bits to transmit for that data:
                        bin += self.to_bin(chunk[0], chunk[1])
                    else:
                        # Not a tuple, so hopefully it's a finite string of bits:
                        bin += self.to_bin(chunk)
            # Now check how we are meant to pad this to whole bytes...
            # Most raybox-zero SPI payloads are not a multiple of 8 bits,
            # but this SoftSPI needs to send whole bytes.
            # The TT04 version's SPI interfaces simply discard extra bits,
            # so it's typical to use basic right-padding of the binary string
            # to a multiple of 8, but the TT07 version (and probably some others)
            # treat the first 4 bits as the command, and then the remainder gets
            # shifted continuously through a buffer (at least for the "registers"
            # interface), meaning we need to left-pad (hence right-align) the
            # data that comes after the command. Anyway, the SPI wrapper class
            # has self.align_right and self.lbits options to specify this...
            padding_bits = '0' * (-len(bin) % 8)
            if self.align_right:
                # Right-align, optionally picking off "lbits" and left-aligning them
                # first (i.e. padding is to the left of the data, and optionally
                # *between* the left and right parts).
                if self.lbits != 0:
                    bin = bin[:self.lbits] + padding_bits + bin[self.lbits:]
            else:
                # Left-align, so ignore lbits and right-pad to a whole number of bytes:
                bin += padding_bits
            # Convert this binary string to a bytearray and send it:
            send = int(bin,2).to_bytes(len(bin)//8, 'bin')
            self.spi.write(send)
            self.debug_print("Write:", send)
        self.txn_stop()
        if self.debug or debug:
            stop_time = time.ticks_us()
            diff = time.ticks_diff(stop_time, start_time)
            self.debug_print(f"SPI transmit time: {diff} us")

class POV(RBZSPI):
    def __init__(self):
        super().__init__(tt, 'pov')

    def set_raw_pov(self, pov, debug=False):
        self.send_payload(pov, 74, debug=debug)

class REG(RBZSPI):
    # Register names and sizes per https://github.com/algofoogle/raybox-zero/blob/922aa8e901d1d3e54e35c5253b0a44d7b32f681f/src/rtl/spi_registers.v#L77
    CMD_SKY    = 0;  LEN_SKY    =  6
    CMD_FLOOR  = 1;  LEN_FLOOR  =  6
    CMD_LEAK   = 2;  LEN_LEAK   =  6
    CMD_OTHER  = 3;  LEN_OTHER  = 12
    CMD_VSHIFT = 4;  LEN_VSHIFT =  6
    CMD_VINF   = 5;  LEN_VINF   =  1
    CMD_MAPD   = 6;  LEN_MAPD   = 16
    CMD_TEXADD0= 7;  LEN_TEXADD0= 24
    CMD_TEXADD1= 8;  LEN_TEXADD1= 24
    CMD_TEXADD2= 9;  LEN_TEXADD2= 24
    CMD_TEXADD3=10;  LEN_TEXADD3= 24

    def __init__(self):         super().__init__(tt, 'reg')

    def sky     (self, color):  self.send_payload([ (self.CMD_SKY,      4), (color, self.LEN_SKY     ) ])    # Set sky colour (6b data)
    def floor   (self, color):  self.send_payload([ (self.CMD_FLOOR,    4), (color, self.LEN_FLOOR   ) ])    # Set floor colour (6b data)
    def leak    (self, texels): self.send_payload([ (self.CMD_LEAK,     4), (texels,self.LEN_LEAK    ) ])    # Set floor 'leak' (in texels; 6b data)
    # The following require CI2311 or above:
    def other   (self, x, y):   self.send_payload([ (self.CMD_OTHER,4), (x,6), (y,6) ]) # Set 'other wall cell' position: X and Y, both 6b each, for a total of 12b.
    def vshift  (self, texels): self.send_payload([ (self.CMD_VSHIFT,   4), (texels,self.LEN_VSHIFT  ) ])    # Set texture V axis shift (texv addend).
    def vinf    (self, vinf):   self.send_payload([ (self.CMD_VINF,     4), (vinf,  self.LEN_VINF    ) ])    # Set infinite V mode (infinite height/size).
    def mapd    (self, x, y, xwall, ywall):
        self.send_payload([
            (self.CMD_MAPD,4),
            (x, 6),         # Map X position of divider
            (y, 6),         # Map Y position of divider
            (xwall, 2),     # Wall texture ID for X divider
            (ywall, 2)      # Wall texture ID for Y divider
        ])
    def texadd  (self, index, addend):
        self.send_payload([
            (self.CMD_TEXADD0+index,4),
            (addend, self.LEN_TEXADD0)
        ])



pov = POV()
reg = REG()
