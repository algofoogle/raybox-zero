# raybox_controller.py
#
# This is Python 3.x code that runs on a host PC to send commands/data to raybox-zero (RBZ).
#
# It's an API abstracting any specific RBZ "peripheral", i.e. a hardware device that controls
# an RBZ chip... typically this is the Tiny Tapeout demo board's RP2040,
# or Anton's RP2040 test board, or any Pi Pico.
# 
# Essentially, raybox_game imports this and uses it as an abstraction for talking to whichever
# version of the RBZ chip and wrapper hardware is being used.
# 
# This code:
# 1. Identifies and connects to the RBZ peripheral (RP2040 running MicroPython) via USB-serial.
# 2. Preloads the target with the MicroPython code in raybox_peripheral(_*).py
# 3. Configures RBZ chip (for TT, selects/configures the project; for CI2311, starts clock).
# 4. Uses the MicroPython REPL in "raw mode" to send update commands for raybox-zero.
# NOTE: Step 3 is a little blurred at the moment; depending on the specific target peripheral,
# sometimes this init is done in raybox_controller, sometimes in raybox_peripheral(_*).

import time
import sys
import serial
import serial.tools.list_ports
import os
from pathlib import Path

# These files contain the MicroPython code that gets pushed to a respective version of the
PATH_TO_RAYBOX_PERIPHERAL_CODE          = './raybox_peripheral.py'
PATH_TO_RAYBOX_PERIPHERAL_CI2311_CODE   = './raybox_peripheral_ci2311.py'

CLOCK_SPEED = 25_000_000  # Clock for design. 25.175MHz is 'typical' VGA clock, at 59.94fps
MACHINE_FREQ = 225_000_000 # RP2040 clock. This should be an integer multiple (2+) of CLOCK_SPEED.

DEBUG = False

# Represents a serial connection to a MicroPython device:
class MicroPythonInterface:
    def __init__(self):
        # List COM ports:
        print("Available COM ports:")
        ports = sorted(serial.tools.list_ports.comports())
        if len(ports) == 0:
            print("NONE! Aborting.")
            sys.exit(1)
        for port, desc, hwid in ports:
            print(f"{port}: {desc} - {hwid}")
        # Check whether a port is a Raspberry Pi device
        self.port = None
        for port in ports:
            if port.vid == 0x2E8A:
                self.port = port.device
                print(f"Found RP port: {port.hwid}")
                break
        if self.port is None:
            # Get last port, to use as default:
            port = ports[-1]
            self.port = port.device
            print(f"Using the last port by default: {port.hwid}")
        print(f"*** NOTE: If you need to use a specific port, edit {self.__class__.__name__} in {__file__}")
        #NOTE: baudrate doesn't really make any difference for USB CDC serial devices,
        # though there is one value (1200) that is a signal to the RP2040 to reset itself.
        self.conn = serial.Serial(port=self.port, baudrate=9600)
        self.conn.timeout = 10.0
        self.conn.write_timeout = 10.0
        # self.write = self.conn.write

    def write(self, *data):
        for p in data:
            w = bytes(p, 'utf-8') if type(p) is str else p
            self.conn.write(w)

    # Await a read of any of a few possible binary strings.
    # If a match is found, a tuple is returned comprising the match, and the data preceeding it.
    # If a timeout occurs before a match is found, then the actual received data is returned.
    def await_bytes(self, mark, timeout=5.0, exception=None):
        data = b''
        if type(mark) is not list: mark = [mark]
        old_timeout = self.conn.timeout
        start_time = time.time()
        try:
            self.conn.timeout = timeout
            while True:
                if time.time() - start_time > timeout:
                    # Timeout while streaming data, waiting for end...
                    break
                # Read one byte at a time until we get the string we want:
                r = self.conn.read()
                if len(r) == 0: break
                data += r
                for m in mark:
                    n = -len(m)
                    if data[n:] == m: return (m, data[:n])
            # breakpoint()
            print(f'WARNING: Timeout waiting for {mark}. Read buffer is {len(data)} byte(s)')
            if exception is not None: raise exception
            return None
        finally:
            self.conn.timeout = old_timeout

    def exit_raw_mode(self):
        self.write(b'\x02') # Send CTRL+B
        r = self.await_bytes(b'>>> ')
        if type(r) is not tuple:
            raise Exception(f'Expected >>> prompt but got: {r}')
    
    def enter_raw_mode(self):
        self.exit_raw_mode()
        self.write(b'\x01') # Send CTRL+A
        r = self.await_bytes([
            b'\nraw REPL; CTRL-B to exit\n>',
            b'\r\nraw REPL; CTRL-B to exit\r\n>'
        ])
        if type(r) is not tuple:
            raise Exception(f'Expected raw REPL welcome but got: {r}')

    def raw_exec(self, data, decode_response='utf-8'):
        self.write(data, b'\x04')
        # Expect acknowledgement of CTRL+D:
        self.await_bytes(b'OK', exception=Exception('Did not receive OK'))
        # Expect first EOT to mark start of response:
        out = self.await_bytes(b'\x04', exception=Exception('Did not receive first EOT'))
        # Wait until the next EOT to mark the end of the response:
        r = self.await_bytes(b'\x04>')
        if type(r) is not tuple:
            raise Exception(f'Expected 2nd EOT and > prompt but got: {r}')
        if len(r[1]) != 0:
            raise Exception(f'Got unexpected response to [{data}] from raw_exec: {r[1]}')
        if decode_response is None:
            return out[1]
        else:
            return out[1].decode(decode_response)
    
    def exec(self, data):
        return self.raw_exec(data, 'ascii').strip()


# Represents a TT04 board running MicroPython:
class TT04(MicroPythonInterface):
    def __init__(self):
        super().__init__()
        # Send CTRL+C twice to stop any running program:
        self.write(b'\x03\x03')
        print('Entering raw mode...')
        self.enter_raw_mode()
        print('Testing raw mode: ', end='')
        print(self.raw_exec('print("It works!")', 'ascii').strip())
        print(f"tt object: {self.raw_exec('print(tt)', 'ascii').strip()}")

    def set_ui_in(self, state):
        self.raw_exec(f'tt.input_byte={state}')

    def set_ui_bit(self, bit, state):
        return self.exec(f'tt.in{bit}({state})')

    def toggle_ui_bit(self, bit):
        return int(self.raw_exec(f'tt.in{bit}.toggle();print(tt.in3())'))

    def select_project(self, project):
        r = self.exec(f'tt.shuttle.{project}.enable()')
        print(r)
        return r

    def set_clock_hz(self, hz):
        if hz == 0:
            r = self.exec('tt.clock_project_stop()')
        else:
            r = self.exec(f'tt.clock_project_PWM({int(hz)})')
        return r

    def reset_tt_pin_modes(self):
        return self.exec('tt.mode=RPMode.ASIC_RP_CONTROL')
    
    def reset_project(self):
        self.exec('tt.reset_project(True)')
        time.sleep(0.1)
        self.exec('tt.reset_project(False)')


# Represents raybox-zero on a TT04 board:
class RayboxZeroController(TT04):
    UI_SCLK     = 0
    UI_MOSI     = 1
    UI_CSB      = 2
    UI_DEBUG    = 3
    UI_INC_PX   = 4
    UI_INC_PY   = 5
    UI_REG      = 6

    def __init__(self):
        super().__init__()
        self.enter_raw_mode()
        print(self.reset_tt_pin_modes())
        self.set_ui_in(0b0000_1000)
        self.select_project('tt_um_algofoogle_raybox_zero')
        print(self.exec(f'machine.freq({int(MACHINE_FREQ)})'))
        print(self.set_clock_hz(CLOCK_SPEED))
        self.reset_project()
        peripheral_code_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            PATH_TO_RAYBOX_PERIPHERAL_CODE
        )
        remote_api_code = Path(peripheral_code_path).read_text()
        print(self.exec(remote_api_code))
        print(self.exec('print(repr(tt))'))
        print('RP2040 core clock:', self.exec('print(machine.freq())'))

    def debug(self, state):
        self.set_ui_bit(self.UI_DEBUG, state)

    def toggle_debug(self):
        return self.toggle_ui_bit(self.UI_DEBUG)

    def set_raw_pov(self, pov):
        return self.exec(f'pov.set_raw_pov({repr(pov)})')
    
    def call_peripheral_method(self, interface, method, data):
        return self.exec(f'{interface}.{method}({int(data)})')

    def set_sky(self, color):
        return self.call_peripheral_method('reg', 'sky', color)

    def set_floor(self, color):
        return self.call_peripheral_method('reg', 'floor', color)

    def set_leak(self, leak):
        return self.call_peripheral_method('reg', 'leak', leak)


# Represents Anton's RP2040 board (or probably any RP2040 board)
# sending commands via UART to firmware on a CI2311 raybox-zero chip.
class RayboxZeroCI2311Controller(MicroPythonInterface):
    def __init__(self):
        super().__init__()
        self.enter_raw_mode()
        peripheral_code_path = os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            PATH_TO_RAYBOX_PERIPHERAL_CI2311_CODE
        )
        remote_api_code = Path(peripheral_code_path).read_text()
        print(self.exec(remote_api_code))
        print('RP2040 core clock:', self.exec('print(machine.freq())'))

    def set_raw_pov(self, pov):
        #SMELL: Change pov to be an 8-byte binaryarray:
        # Make sure pov is left-padded to 80 bits:
        bin = '0' * (-len(pov) % 8) + pov
        # Convert this string of binary digits into a bytearray:
        ba = bytes([int(bin[i:i+8], 2) for i in range(0, len(bin), 8)])
        return self.exec(f'pov.set_raw_pov({repr(ba)})')
    
    def call_peripheral_method(self, interface, method, data):
        return self.exec(f'{interface}.{method}({int(data)})')

    def set_sky(self, color):
        return self.call_peripheral_method('reg', 'sky', color)

    def set_floor(self, color):
        return self.call_peripheral_method('reg', 'floor', color)

    def set_leak(self, leak):
        return self.call_peripheral_method('reg', 'leak', leak)