import time
import math
from machine import Pin, SoftSPI

# Make sure the raybox-zero project is selected and initialised:
tt.clock_project_stop()
tt.mode = RPMode.ASIC_RP_CONTROL
tt.reset_project(True)
tt.input_byte = 0
tt.shuttle.tt_um_algofoogle_raybox_zero.enable()
tt.clock_project_PWM(25_175_000)
tt.reset_project(False)
# Turn on debug overlay:
tt.in3(True)

# Raybox-Zero SPI interface:
class RBZSPI:
    SPI_BAUD = 500_000 # 500kHz is max supported by MicroPython on RP2040
    def __init__(self, tt, interface):
        self.tt = tt
        self.interface = interface
        if interface == 'pov':
            self.csb = tt.in2
            self.spi = SoftSPI(
                RBZSPI.SPI_BAUD,
                sck     = tt.in0.raw_pin,
                mosi    = tt.in1.raw_pin,
                miso    = tt.uio5.raw_pin # DUMMY: Not used; this SPI doesn't output data.
            )
        elif interface == 'reg':
            # Configure this interface's UIOs as outputs:
            for p in [tt.uio2, tt.uio3, tt.uio4]: p.mode = Pin.OUT
            self.csb = tt.uio4
            self.spi = SoftSPI(
                RBZSPI.SPI_BAUD,
                sck     = tt.uio2.raw_pin,
                mosi    = tt.uio3.raw_pin,
                miso    = tt.uio5.raw_pin # DUMMY: Not used; this SPI doesn't output data.
            )
        else:
            raise ValueError(f"Invalid interface {repr(interface)}; must be 'pov' or 'reg'")
        
    def __repr__(self): return f'RBZSPI({self.interface})'

    def enable(self):   self.csb(False)
    def disable(self):  self.csb(True)

    def txn_start(self):
        self.disable() # Inactive at start; ensures SPI is reset.
        self.enable()

    def txn_stop(self): self.disable()

    def to_bin(self, data, count=None):
        if type(data) is int:
            data = bin(data)
            data = data[2:]
            if count is None:
                print(f"WARNING: SPI.send_bits() called with int data {data} but no count")
        if count is not None:
            data = ('0'*count + data)[-count:] # Zero-pad up to the required count.
        return data

    def send_payload(self, data, count=None, debug=False):
        if debug: start_time = time.ticks_us()
        self.txn_start()
        if type(data) is bytearray or type(data) is bytes:
            self.spi.write(data)
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
            # Most raybox-zero SPI payloads are not a multiple of 8 bits,
            # but this SoftSPI needs to send whole bytes.
            # Thankfully raybox-zero SPI interfaces discard extra bits,
            # so we now RIGHT-pad the binary string to a multiple of 8:
            bin += '0' * (-len(bin) % 8)
            # Convert this binary string to a bytearray and send it:
            self.spi.write( int(bin,2).to_bytes(len(bin)//8, 'bin') )
        self.txn_stop()
        if debug:
            stop_time = time.ticks_us()
            diff = time.ticks_diff(stop_time, start_time)
            print(f"SPI transmit time: {diff} us")

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
        if debug: print(pov)

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
        if debug: print(pov)
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
    def vinf    (self, vinf):   self.send_payload([ (self.CMD_VSHIFT,   4), (vinf,  self.LEN_VINF    ) ])    # Set infinite V mode (infinite height/size).
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
                    pov.angular_pov(*(demo_povs[3][0:2]), float(a)/100.0 * math.pi/180.0)
                for a in range(-9200,-8800):
                    pov.angular_pov(*(demo_povs[3][0:2]), -float(a)/100.0 * math.pi/180.0)
            print('Done')

        else:
            time.sleep_ms(1000)
            print(f'Presenting view {i}: ', end='')
            start_time = time.ticks_us()
            pov.pov(*view)
            stop_time = time.ticks_us()
            diff = time.ticks_diff(stop_time, start_time)
            print(f"Total update time: {diff} us")
