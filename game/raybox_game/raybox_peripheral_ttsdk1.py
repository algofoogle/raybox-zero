# This is MicroPython code that runs on the TT04 board's RP2040,
# to enable a host to communicate with raybox-zero running on the ASIC.
# See raybox-controller.py for the host PC side that sends us commands.
from machine import Pin, SoftSPI

# Raybox-Zero SPI interface, can talk to either of RBZ's SPI peripherals:
# - "vectors" (POV) and "registers" (REG)
class RBZSPI:
    SPI_BAUD = 500_000
    def __init__(self, tt, interface):
        self.tt = tt
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
        
    def enable(self):   self.csb(False)
    def disable(self):  self.csb(True)

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

    # Do an SPI transaction.
    # 'data' is one of:
    # - a string of binary digits, or an array thereof.
    # - an integer (in which case 'count' must be specified also; i.e. required bit count).
    # - an array of tuples; [0] is binary digit string or integer, [1] is required bit count.
    def send(self, data, count=None):
        self.disable() # Reset SPI.
        self.enable()
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
        self.disable()

class POV(RBZSPI):
    def __init__(self):         super().__init__(tt, 'pov')
    def set_raw_pov(self, pov): self.send(pov, 74)

class REG(RBZSPI):
    # Register names per
    # https://github.com/algofoogle/raybox-zero/blob/922aa8e901d1d3e54e35c5253b0a44d7b32f681f/src/rtl/spi_registers.v#L77
    CMD_SKY    = 0
    CMD_FLOOR  = 1
    CMD_LEAK   = 2

    def __init__(self):         super().__init__(tt, 'reg')

    def sky     (self, color):  self.send([ (self.CMD_SKY,  4), (color, 6) ]) # Set sky colour (6b data)
    def floor   (self, color):  self.send([ (self.CMD_FLOOR,4), (color, 6) ]) # Set floor colour (6b data)
    def leak    (self, texels): self.send([ (self.CMD_LEAK, 4), (texels,6) ]) # Set floor 'leak' (in texels; 6b data)

pov = POV()
reg = REG()
