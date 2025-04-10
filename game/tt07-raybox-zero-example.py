import time
import math
from machine import Pin, SoftSPI

# Stop any existing clock, and ensure we're in a normal RP2040 ASIC control mode:
tt.clock_project_stop()
tt.mode = RPMode.ASIC_RP_CONTROL

# Ensure RP2040 doesn't drive any of the uio pins initially:
tt.uio_oe_pico.value = 0b00000000

# Assert reset:
tt.reset_project(True)

# Select raybox-zero design:
tt.shuttle.tt_um_algofoogle_raybox_zero.enable()

# Set ui_in initial control state. Per ui_in:
# ui_in[7]: gen_tex:    1 for generated textures, 0 for SPI textures
# ui_in[6]: reg:        1 for registered outputs, 0 for direct combinatorial outputs
# ui_in[5]: inc_py:     1 to increment player Y position each frame
# ui_in[4]: inc_px:     1 to increment player X position each frame
# ui_in[3]: debug:      1 to show debug overlay
# ui_in[2]: pov_ss_n:   1 to disable point-of-view SPI control, 0 to enable (i.e. SPI /CS).
# ui_in[1]: pov_mosi:   POV SPI data to send into raybox-zero
# ui_in[0]: pov_sclk:   POV SPI clock
tt.ui_in = 0b10001100  # Use generated textures (initially), enable debug overlay, disable POV SPI.

# Project selection can de-assert reset (?) so assert it again:
tt.reset_project(True)

# Apply 10 clocks, to make sure reset takes effect:
for _ in range(10): tt.clock_project_once()

# Release reset:
tt.reset_project(False)

# Clock at 25MHz but with a weird duty cycle to help texture SPI ROM:
tt.clock_project_PWM(25_000_000, max_rp2040_freq=250_000_000, duty_u16=0xb000)

tt.ui_in = 0b00001100  # Disable generated textures (i.e. enable SPI textures).

# Raybox-Zero SPI interface wrapper for both SPI interfaces; POV and REG:
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

    def to_bin(self, data, count=None):
        if type(data) is int:
            data = bin(data)
            data = data[2:]
            if count is None:
                print(f"WARNING: SPI.send_bits() called with int data {data} but no count")
        if count is not None:
            data = ('0'*count + data)[-count:] # Zero-pad up to the required count.
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

    def set_raw_pov_chunks(self, px, py, fx, fy, vx, vy, debug=False):
        self.send_payload([
            (px, 15),   # playerX: UQ6.9
            (py, 15),   # playerY: UQ6.9
            (fx, 11),   # facingX: SQ2.9
            (fy, 11),   # facingY: SQ2.9
            (vx, 11),   # vplaneX: SQ2.9
            (vy, 11),   # vplaneY: SQ2.9
        ], debug=debug)

    def float_to_fixed(self, f, q: str = 'Q12.12') -> int:
        if q == 'Q12.12':
            #SMELL: Hard-coded to assume Q12.12 for now, where MSB is sign bit.
            t = int(f * (2.0**12.0))  # Just shift it left by 12 bits (fractional part scale) and make it an integer...
            return t & 0x00FFFFFF # ...then return only the lower 24 bits.
        elif q == 'UQ6.9':
            t = int(f * (2.0**9.0))
            return t & 0x00007FFF # 15 bits.
        elif q == 'SQ2.9':
            t = int(f * (2.0**9.0))
            return t & 0x000007FF # 11 bits.
        else:
            raise Exception(f"Unsupported fixed-point format: {q}")

    def pov(self, px, py, fx, fy, vx, vy, debug=False):
        pov = [
            self.float_to_fixed(px, 'UQ6.9'), self.float_to_fixed(py, 'UQ6.9'),
            self.float_to_fixed(fx, 'SQ2.9'), self.float_to_fixed(fy, 'SQ2.9'),
            self.float_to_fixed(vx, 'SQ2.9'), self.float_to_fixed(vy, 'SQ2.9')
        ]
        self.set_raw_pov_chunks(*pov, debug)
        if self.debug or debug: print(pov)

    def angular_pov(self, px, py, rad=None, deg=None, facing=1.0, vplane=0.5, debug=False):
        if rad is None and deg is None:
            rad = 0.0
        elif rad is None:
            rad = deg * math.pi / 180.0
        sina, cosa = math.sin(rad), math.cos(rad)
        pov = [
            px, py,
            sina*facing, cosa*facing,
            -cosa*vplane, sina*vplane
        ]
        if self.debug or debug: print(pov)
        self.pov(*pov, debug=debug)


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

# Let's go for light and dark blue backgrounds:
b0=0b_10_01_00
b1=0b_01_00_00
reg.sky(b1)
reg.floor(b0)

# These are the POVs I originally sent to Sylvain (@tnt) here:
# https://discord.com/channels/1009193568256135208/1222582697596162220/1224328766025891840

demo_povs = [
    # Mix of walls:
    [   13.107422,  7.855469,       # Player position
         0.119141, -0.992188,       # Normalized facing direction vector
         0.496094,  0.058594    ],  # Viewplane vector; prependicular to, and typically half of, the facing direction
    # Directly facing a corner:
    [   11.517578,  3.552734,
        -0.689453, -0.722656,
         0.361328, -0.345703    ],
    # Long wall at an angle:
    [   14.527344, 11.498047,
         0.552734, -0.832031,
         0.416016,  0.275391    ],
    # Uniform view of 3 wall types:
    [    6.820312,  9.496094,
         0.998047,  0.000000,
         0.000000,  0.500000    ],
    None
]

while True:
    for i in range(len(demo_povs)):
        view = demo_povs[i]
        if view is None:
            time.sleep_ms(1000)
            print('Doing full rotation test in 0.25-degree steps...')
            start_time = time.ticks_ms()
            count = 0
            for a in range(90*4,450*4+1):
                count += 1
                pov.angular_pov(*(demo_povs[3][0:2]), float(a)/4.0 * math.pi/180.0)
            stop_time = time.ticks_ms()
            diff = time.ticks_diff(stop_time, start_time)
            print(f"Total time for full rotation: {diff} ms => {float(diff)/float(count):.3f} ms/update")
            time.sleep_ms(1000)
            print('Doing fine-grained rotation test... ',end='')
            for w in range(2):
                for a in range(8800,9200):
                    # check = a in range(8990,9011)
                    # pov.debug = check
                    pov.angular_pov(*(demo_povs[3][0:2]), float(a)/100.0 * math.pi/180.0)
                    # if check:
                    #     print(a)
                    #     time.sleep(2)
                    #     reg.floor(0b_10_01_00 if a&1 == 0 else 0)
                for a in range(-9200,-8800):
                    # check = -a in range(8990,9011)
                    # pov.debug = check
                    pov.angular_pov(*(demo_povs[3][0:2]), -float(a)/100.0 * math.pi/180.0)
                    # if check:
                    #     print(a)
                    #     time.sleep(2)
                    #     reg.floor(0b_10_01_00 if a&1 == 0 else 0)
            print('Done')

        else:
            time.sleep_ms(1000)
            print(f'Presenting view {i}: ', end='')
            start_time = time.ticks_us()
            pov.pov(*view)
            stop_time = time.ticks_us()
            diff = time.ticks_diff(stop_time, start_time)
            print(f"Total update time: {diff} us")
