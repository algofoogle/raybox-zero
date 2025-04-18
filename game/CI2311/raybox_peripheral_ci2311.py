from machine import UART, Pin, PWM
import time

class RayboxZeroUart:
    def __init__(self):
        # Clock generator:
        io0 = Pin(0, Pin.OUT)
        pwm = PWM(io0)
        pwm.freq(25_000_000) # 25MHz clock for RBZ chip, but Caravel CPU is independently at 50MHz.
        pwm.duty_u16(0x8000)
        # UART:
        self.uart = UART(1, baudrate=48000, tx=Pin(4), rx=Pin(5), timeout=1000)
        # Pins for controlling internal signals:
        self.pin_Run        = Pin(7,  Pin.OUT, value=1) # Set low to reset.
        self.pin_HideVec    = Pin(8,  Pin.OUT, value=0) # When low, vectors debug overlay is enabled.
        self.pin_Textures   = Pin(9,  Pin.OUT, value=1) # When high, texture SPI is enabled.
        self.pin_RegOut     = Pin(10, Pin.OUT, value=1) # When high, use registered outputs.
        self.pin_NoDemo     = Pin(13, Pin.OUT, value=1) # When high, disable player X/Y auto-incrementing.
        # Sync UART (in case the CI2311 chip's firmware was left in an unclean state):
        self.sync()
        # self.vinf(True)
    
    def sync(self):
        # Sync UART by writing 12 NOOP bytes:
        self.uart.write(bytearray([255] * 12))

    # `data` is expected to be 10 bytes in a bytearray,
    # with the first byte (element) containing the upper 2 bits, and then
    # the rest containing the remaining 72 bits.
    def set_raw_pov(self, data):
        start = time.ticks_ms()
        # if len(data) != 10: raise ValueError(f"Wrong byte count TO BE SENT: {len(data)}")
        b = data[0]
        # if (b & 0b11111100) != 0: raise ValueError(f"Bad leading byte: {b}")
        n = self.uart.write(bytearray([b | 0b100000_00]))
        n += self.uart.write(data[1:])
        # if n != 10: raise ValueError(f"Wrong byte count sent: {n}")
        self.uart.flush()
        # time.sleep_ms(50)
        r = self.uart.read(1)
        if r != b'V': raise ValueError(f"Unexpected response from CI2311: {r}")
        stop = time.ticks_ms()
        # raise ValueError(f"Delta: {time.ticks_diff(stop,start)}")

    def reg_write(self, payload):
        self.uart.write(bytearray(payload))
        r = self.uart.read(1)
        if r != b'R': raise ValueError(f"Unexpected response from CI2311: {r}")

    def vinf(self, vinf):
        self.reg_write([0b01001010 | vinf])

    def sky(self, color):
        self.reg_write([0, color])

    def floor(self, color):
        self.reg_write([1, color])

    def leak(self, value):
        self.reg_write([2, value])



pov = RayboxZeroUart()
reg = pov


"""
0000cccc --vvvvvv                       Reg: 4-bit command, 6-bit value
00000000 --bbggrr                       CMD_SKY     Set sky colour
00000001 --bbggrr                       CMD_FLOOR   Set floor colour
00000010 --tttttt                       CMD_LEAK    Set floor leak
00000100 --tttttt                       CMD_VSHIFT  Set texture V axis shift (texv addend)

0001cccc --vvvvvv --vvvvvv              Reg: 4-bit command, 12-bit value
00010011 --XXXXXX --YYYYYY              CMD_OTHER   Set 'other wall cell' position, X and Y

0010cccc vvvvvvvv vvvvvvvv              Reg: 4-bit command, 16-bit value
00100110 vvvvvvhh hhhhXXYY              CMD_MAPD    Set dividers, vertical, horizontal, vertical wall ID, horizontal wall ID

0011cccc vvvvvvvv vvvvvvvv vvvvvvvv     Reg: 4-bit command, 24-bit value
00110111 tttttttt tttttttt tttttttt     CMD_TEXADD0
00111000 tttttttt tttttttt tttttttt     CMD_TEXADD1
00111001 tttttttt tttttttt tttttttt     CMD_TEXADD2
00111010 tttttttt tttttttt tttttttt     CMD_TEXADD3

010ccccv                                Reg: 4-bit command, 1-bit value
0100101v                                CMD_VINF    Set (v=1) or clear (v=0) 'Infinite V mode'

100000pp pppppppp pppppppp pppppppp
         pppppppp pppppppp pppppppp
         pppppppp pppppppp pppppppp     74 bits for POV (vec SPI)

11------                                NO-OP

"""
