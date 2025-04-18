#NOTE: Running this inside a VSCode Integrated Terminal seems to slow it down a bit.
# On Windows, which is my host normally, I run it directly in a Windows Terminal and it seems
# to perform well.

import pygame
import time
import os
import math
import argparse
from raybox_controller import RayboxZeroControllerTTSDK1, RayboxZeroControllerTTSDK2, RayboxZeroControllerCI2311

# Main input functions:
# - WASD keys move
# - Mouse left/right motion rotates
# - Left/right keyboard arrows rotate also (as do Q/E)
# - Mouse left button 'shoots' (just a visual effect)

# Numpad:
#     9: sky_color++
#     7: sky_color--
#     3: floor_color++
#     1: floor_color--

# Mousewheel:
#     Mousewheel scales the 'facing' vector, which basically
#     has the effect of adjusting "FOV", otherwise described
#     as telephoto/wide-angle zooming.
#
#     Modifiers (can use any combo):
#         - CTRL: x2 
#         - SHIFT: x4
#         - ALT: x8
#
#     If you hold one of the following keyboard number row keys,
#     the mousewheel action instead adjusts a different parameter:
#         - 1: sky colour
#         - 2: floor color
#         - 3: 'leak' register (displacing floor height)

# Other:
#     ESC: Quit
#     M or F12: Toggle mouse capture
#     F11: Toggle system pause
#     R: Reset game state
#     `: Toggle vectors debug overlay

parser = argparse.ArgumentParser(add_help=False, description='Runs a raybox-zero "game", controlling target rendering hardware.')
parser.add_argument('device',           type=str,               choices=['ttsdk1', 'ttsdk2', 'ci2311'], help='Target rendering device/ASIC')
parser.add_argument('-d', '--debug',    action='store_true',                                            help='Print debug info for each update')
parser.add_argument('-r', '--rotate',   type=int, default=270,  choices=[0,90,180,270],                 help='Clockwise screen rotation in degrees')
parser.add_argument('-w', '--width',    type=int, default=1000,                                         help='Main window width')
parser.add_argument('-h', '--height',   type=int, default=700,                                          help='Main window height')
parser.add_argument('-m', '--map-size', type=str, default='32x32',                                      help='Map size (COLSxROWS)')
parser.add_argument('-p', '--player-size', type=float, default=0.55,                                    help='Set player size (for collisions)')
parser.add_argument('-n', '--no-clip',  action='store_true',                                            help='Disable clipping (collisions)')
parser.add_argument('-g', '--gen-tex',  action='store_true',                                            help='Textures are generated instead of SPI-loaded')
parser.add_argument('-f', '--flash-delta', type=int, default=0,                                         help='SPI texture base address delta for flash effects (0 to disable)')
parser.add_argument('--help', action='help', help='Show this help message and exit')
args = parser.parse_args()

if args.device == 'ttsdk1':
    TARGET_DEVICE = RayboxZeroControllerTTSDK1
elif args.device == 'ttsdk2':
    TARGET_DEVICE = RayboxZeroControllerTTSDK2
elif args.device == 'ci2311':
    TARGET_DEVICE = RayboxZeroControllerCI2311

print(f"Target raybox-zero device controller: {TARGET_DEVICE.__name__}")

# Natural-feeling behaviour of controls depends on VGA screen orientation:
if args.rotate == 0:
    ROTATE_MOUSE = True
    FLIPPED = False
elif args.rotate == 90:
    ROTATE_MOUSE = False
    FLIPPED = True
elif args.rotate == 180:
    ROTATE_MOUSE = True
    FLIPPED = True
elif args.rotate == 270:
    ROTATE_MOUSE = False
    FLIPPED = False
# ROTATE_MOUSE        = False # If True, use mouse Y (up/down) instead of X.
# FLIPPED             = True  # If True, assume monitor is rotated clockwise rather than CCW.

GEN_TEX             = args.gen_tex

RBZ_MAP_COLS, RBZ_MAP_ROWS = map(int, args.map_size.split('x'))
#NOTE: In the TT04 version of raybox-zero, MAP_W/HBITS were both set to 4, so cols/rows should be 16x16 for TT04.
# Versions since then are (so far) all 32x32.

# This is the size of the game map window that we display on the PC:
SCREEN_W            = args.width
SCREEN_H            = args.height
WINDOW_TITLE        = 'raybox_game'

# Try to determine ideal map preview scale:
RBZ_MAP_SCALE       = min((SCREEN_W-50)//RBZ_MAP_COLS, (SCREEN_H-50)//RBZ_MAP_ROWS)

DEBUG               = args.debug # Print debug info for each update?
NO_CLIP             = args.no_clip # Disable collision detection?
PLAYER_SIZE         = args.player_size  # 0.6875 is same as Wolf3D? 0.55 fees right. <0.28 overflows. 0.25 shows interesting 'infinite' glitches.
ZOOM_PULSE_SCALER   = 1.5

FLASH_DELTA         = args.flash_delta

# Nanoseconds to milliseconds:
NSMS        = 1_000_000

# 8ms: Size of a "tick" (i.e. the time unit we want to schedule to) in nanoseconds.
# This really only needs to be less than 1 frame (~16.7ms), but I want to see if
# it's possible to schedule at least 2 updates per frame:
TICK        = 8_000_000

# Set working dir to wherever this script is located:
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Create our interface that talks to MicroPython on the TT04 demo board,
# for loading and controlling the raybox-zero project:
# raybox = RayboxZeroCI2311Controller() # RayboxZeroController()
raybox = TARGET_DEVICE(debug=DEBUG, gen_tex=GEN_TEX)

# Set up a Pygame window.
pygame.init()
pygame.display.set_caption(WINDOW_TITLE)
screen = pygame.display.set_mode((SCREEN_W,SCREEN_H))

# Load font:
font = pygame.font.Font("font-cousine/Cousine-Regular.ttf", 12)
info_text = font.render(
    "M: Capture/release mouse  F11: Pause  R: Reset  C: Toggle clipping",
    True,
    (255,255,0),
)

# Call capture_mouse(True) (or False) at least once to set its internal state.
# Then you can call capture_mouse() to toggle the capture state (which it will return after changing)
# or call it with an explicit True or False again.
def capture_mouse(capture: bool = None):
    if capture == True:
        capture_mouse.captured = True
        # Hide the mouse and capture it.
        pygame.mouse.set_visible(False)
        pygame.event.set_grab(True)
    elif capture == False:
        capture_mouse.captured = False
        pygame.mouse.set_visible(True)
        pygame.event.set_grab(False)
    else:
        # Toggle
        capture_mouse(not capture_mouse.captured)
    return capture_mouse.captured

capture_mouse(True)



# Used for calculating game time (in ns) relative to this moment:
TIME_ORIGIN = time.perf_counter_ns()

# General timestamp provider:
def ts() -> int:
    return time.perf_counter_ns()-TIME_ORIGIN

start = timer = ts()

running         = True
tick_counter    = 0     # No. of ticks that have elapsed since we started timing.
hit_counter     = 0     # No. of times we hit our timing target.
loop_counter    = 0     # No. of iterations of our loop since last timing hit.
event_counter   = 0
pause           = False

# Summary stuff;
min_loops       = None  # Min. no. of loop iterations that we managed to get within a tick.
max_loops       = 0
sum_loops       = 0
max_delta       = 0     # Target is 'TICK', but so long as it's less than TICK*1.5 we're probably OK.
sum_deltas      = 0     # Used to produce an average of time deltas.


# This holds the state of the game environment:
class RBZMap:
    FLASH_STEPS = [
        #   Bb Gg Rr  Flash-delta-mul
        (0b_11_11_11, 3),
        (0b_10_11_11, 3),
        (0b_01_11_11, 2),
        (0b_10_11_10, 2),
        (0b_10_11_01, 1),
        (0b_10_10_01, 1),
        (0b_10_01_01, 0),
        (0b_10_01_00, 0), # Final sky.
        (0b_10_00_00, 0),
        (0b_01_00_00, 0), # Final floor.
    ]
    def __init__(self, raybox): #: RayboxZeroController = None):
        self.raybox = raybox
        self.leak = 0
        self.vinf = False
        self.vshift = 0
        self.texadd0 = 0
        self.texadd1 = 0
        self.texadd2 = 0
        self.texadd3 = 0
        # Hack to ensure other_x/y pair exist in advance:
        self.__dict__['other_x'] = 0
        self.__dict__['other_y'] = 0
        self.other_x = 0
        self.other_y = 0
        self.__dict__['mapdx'] = 0
        self.__dict__['mapdy'] = 0
        self.__dict__['mapdxw'] = 0
        self.__dict__['mapdyw'] = 0
        self.mapdx = 0
        self.mapdy = 0
        self.mapdxw = 0
        self.mapdyw = 0
        self.gen_tex = GEN_TEX
        if FLIPPED:
            self.sky_color      = RBZMap.FLASH_STEPS[9][0] # 0b10_10_10
            self.floor_color    = RBZMap.FLASH_STEPS[7][0] # 0b01_01_01
        else:
            self.sky_color      = RBZMap.FLASH_STEPS[7][0] # 0b01_01_01
            self.floor_color    = RBZMap.FLASH_STEPS[9][0] # 0b10_10_10
        self.map_cols = RBZ_MAP_COLS
        self.map_rows = RBZ_MAP_ROWS
        self.map_width = float(self.map_cols)
        self.map_height = float(self.map_rows)
        self.screen_scale = RBZ_MAP_SCALE # Scaling of map units to screen units.
        #NOTE: The below are just used for centring, not for scaling:
        self.screen_width = float(SCREEN_W)
        self.screen_height = float(SCREEN_H)
        self.map_surface = None
        self.flash_step = 0
        # Initialise map to our bitwise pattern per:
        # https://github.com/algofoogle/raybox-zero/blob/main/src/rtl/map_rom.v
        self.map_data = [0] * (self.map_cols * self.map_rows)
        w = self.map_cols
        h = self.map_rows
        for y in range(h):
            for x in range(w):

                left_right_borders = (x == 0) | (x == (w - 1))
                top_bottom_borders = (y == 0) | (y == (h - 1))

                low_3_bits_match = ((y & 0b111)^0b111 == (x & 0b111))
                bit_3_of_y_and_x_are_zero = ((y & 0b1000) == 0) & ((x & 0b1000) == 0)

                expression1 = low_3_bits_match & bit_3_of_y_and_x_are_zero

                bitwise_ops = ((((y & 0b10) ^ ( (x & 0b100) >> 1)))>>1) ^ ((y & 1) & ((x >> 1) & 1))
                expression2 = bitwise_ops & ((y & 0b100)>>2) & ((x & 0b10)>>1)
                expression3 = ((y & 1)^1) & ((x & 1)^1)

                expression4 = (expression2 | expression3)
                bits_2_match = ((y & 0b100)>>2) ^ ~((x & 0b100)>>2)

                c = (
                    (left_right_borders) |
                    (top_bottom_borders) |
                    (expression1) |
                    (expression4 & bits_2_match)
                )

                b0 = 0b01 if c else 0b00

                f1 = (x>>3) & 1; f2 = (x>>2) & 1; f3 = (x>>1) & 1; f4 = x & 1
                a6 = (y>>3) & 1; b6 = (y>>2) & 1; c6 = (y>>1) & 1; d6 = y & 1
                d = 1 if (x==8 and y==10) else 0
                c = ((((f3^d6) & (f2^a6)) & (f4^b6)) & (f1^c6)) | d
                b1 = 0b10 if c else 0b00

                self.cell(x,y,b1|b0)
        self.generate_map_surface()

    # Make the environment appear to "flash":
    def env_flash(self, start=False):
        if FLIPPED:
            sky = self.raybox.set_floor
            floor = self.raybox.set_sky
        else:
            sky = self.raybox.set_sky
            floor = self.raybox.set_floor
        count = len(RBZMap.FLASH_STEPS)
        if start:
            self.flash_step = count
        elif self.flash_step > 0:
            self.flash_step -= 1
        if self.flash_step > 2:
            sky(RBZMap.FLASH_STEPS[count-self.flash_step][0])
        if self.flash_step > 0:
            flash_step = RBZMap.FLASH_STEPS[count-self.flash_step]
            floor(flash_step[0])
            self.raybox.call_peripheral_method('reg', 'texadd', 0, self.texadd0+flash_step[1]*FLASH_DELTA)
            self.raybox.call_peripheral_method('reg', 'texadd', 1, self.texadd0+flash_step[1]*FLASH_DELTA)
            self.raybox.call_peripheral_method('reg', 'texadd', 2, self.texadd0+flash_step[1]*FLASH_DELTA)
            self.raybox.call_peripheral_method('reg', 'texadd', 3, self.texadd0+flash_step[1]*FLASH_DELTA)
        return self.flash_step

    # Look up the colour we should render in the map preview, based on wall type:
    def cell_color_lut(self, color: int):
        lut = {
            0: (192,  0,  0),   # Red
            1: (190,190,150),   # Pale yellow
            2: (  0,  0,192),   # Blue
            3: (128,  0,192),   # Purple
        }
        return lut[color]

    # This gives us the properties:
    # - sky_color
    # - floor_color
    # - leak
    # - vshift
    # - vinf
    # - gen_tex
    # - texadd0..3
    # which automatically update their respective register values in our raybox peripheral:
    def __setattr__(self, name, value):
        if name in ['sky_color', 'floor_color', 'leak', 'vshift', 'other_x', 'other_y']:
            value %= 64 # Range is 0..63.
            self.__dict__[name] = value
            if name in ['other_x', 'other_y']:
                # print(f'other x/y:{self.other_x},{self.other_y}')
                self.raybox.call_peripheral_method('reg', 'other', self.other_x, self.other_y)
            else:
                self.raybox.call_peripheral_method('reg', name.split('_')[0], value)
        elif name in ['texadd0', 'texadd1', 'texadd2', 'texadd3']:
            value &= 0xFFFFFF # 24-bit address range.
            self.__dict__[name] = value
            self.raybox.call_peripheral_method('reg', 'texadd', int(name.split('texadd')[1]), value)
        elif name in ['mapdx', 'mapdy', 'mapdxw', 'mapdyw']:
            self.__dict__[name] = value
            # if name in ['mapdx', 'mapdy']:
            #     # Dividing wall coordinate:
            # else:
            #     # Dividing wall ID:
            self.raybox.call_peripheral_method('reg', 'mapd', self.mapdx, self.mapdy, self.mapdxw, self.mapdyw)
        elif name == 'vinf':
            v = self.__dict__[name] = not not value
            self.raybox.call_peripheral_method('reg', name.split('_')[0], v)
        elif name == 'gen_tex':
            v = self.__dict__[name] = not not value
            self.raybox.set_gen_tex(v)
            # print(f'value:{value} -- ui_in:{self.raybox.get_ui_in()}')
        elif name in ['other_x', 'other_y']:
            self.__dict__[name] = value

        else:
            super().__setattr__(name, value)

    # Reset the map preview:
    def reset(self):
        self.screen_scale = RBZ_MAP_SCALE
        self.generate_map_surface()

    # Handle map zoom adjustments:
    def zoom(self, scaler: float = None):
        if scaler is None:
            self.screen_scale = RBZ_MAP_SCALE
        else:
            self.screen_scale *= scaler
        self.generate_map_surface()

    # Generate a static image (i.e. Pygame 'surface') of the map:
    def generate_map_surface(self):
        ss = self.screen_scale
        mx = (self.map_cols)*ss
        my = (self.map_rows)*ss
        if FLIPPED:
            flipper = -1
            offset = mx-ss
        else:
            flipper = 1
            offset = 0
        surf = self.map_surface = pygame.Surface( (mx,my) )
        for y in range(self.map_rows):
            for x in range(self.map_cols):
                c = self.cell(x, y)
                if c is not None:
                    pygame.draw.rect(surf, self.cell_color_lut(c), pygame.rect.Rect(offset+x*ss*flipper,y*ss,ss,ss))

    # Convert map X/Y position to screen coordinates,
    # with the centre of the map (nominally 7.5,7.5) at the centre of the screen:
    def xy_screen(self, x: float, y: float):
        flipper = -1 if FLIPPED else 1
        ss = self.screen_scale
        mcx = (self.map_width) / 2.0
        mcy = (self.map_height) / 2.0
        return (
            int(self.screen_width/2.0 + flipper*ss*(x-mcx)),
            int(self.screen_height/2.0 + ss*(y-mcy)),
        )

    # Look up (and optionally set) the contents of a given map cell:
    def cell(self, x: int, y: int, set: int = None):
        #NOTE: Map data is stored as Y/X instead of X/Y:
        if set is None:
            if self.mapdx != 0 and x==self.mapdx:
                return 0
            if self.mapdy != 0 and y==self.mapdy:
                return 0
            if x==self.other_x and y==self.other_y:
                return 0 # This is the wall ID of the 'OTHER' block.
            c = self.map_data[x*self.map_rows + y]
            return None if c == 0 else c
        else:
            self.map_data[x*self.map_rows + y] = set
            return set
    
    # Retrieve the rectangle screen coordinates represenvation of a given map cell:
    def cell_screen_rect(self, x: int, y: int):
        (sx, sy) = self.xy_screen(float(x), float(y))
        ss = self.screen_scale
        return pygame.rect.Rect(sx, sy, ss, ss)

    # Draw the map_surface to the screen:
    def draw(self, screen: pygame.Surface):
        rect = self.map_surface.get_rect()
        rect.center = (self.screen_width/2.0,self.screen_height/2.0)
        screen.blit(self.map_surface, rect)


class Actor:
    def __init__(self, x: float, y: float, color = None, size = None):
        self.x = x
        self.y = y
        self.color = (255,0,255) if color is None else color
        self.size = 1.0 if size is None else size # Size in map units. Size of 1.0 means actor occupies exactly one 64x64 map cell.
        self.walk_rate = 30.0
        self.run_scaler = 5.0/3.0
        self.crawl_scaler = 1.0/6.0
    
    def render(self, map: RBZMap, screen):
        flipper = 1 # -1 if FLIPPED else 1
        s = map.screen_scale
        r = pygame.Rect(0, 0, s*self.size, s*self.size) # Body square.
        (cx,cy) = map.xy_screen(self.x * flipper, self.y) # Position.
        r.center = (cx, cy)
        pygame.draw.rect(screen, self.color, r) # Draw body square centred on position.
        # s = map.screen_scale #-1.0
        # pygame.draw.line(screen, (255,255,255), (cx,cy-s/2.0), (cx,cy+s/2.0))
        # pygame.draw.line(screen, (255,255,255), (cx-s/2.0,cy), (cx+s/2.0,cy))
        return (cx,cy)


class Player(Actor):
    def __init__(self, x: float, y: float, angle: float = 0.0):
        super().__init__(x, y, (220,0,180), PLAYER_SIZE) #48.0/64.0) # Wolf3D player seems to be 0.6875 units wide.
        self.initial_x = x
        self.initial_y = y
        self.initial_a = angle
        self.facing_scaler = 1.0
        self.vplane_scaler = 1.0
        self.zoom_is_pulsing = False
        self.reset()

    def __setattr__(self, name, value):
        if name in ['facing_scaler', 'vplane_scaler']:
            value = max(value, -2.0)        # Clamp; lower limit supported by raybox-zero is -2.0
            value = min(value,  2.0-2**-9)  # Clamp; upper limit is 1 bit short of 2.0
            self.__dict__[name] = value
        else:
            return super().__setattr__(name, value)

    def zoom_pulse(self, start=False):
        if start:
            self.zoom_is_pulsing = True
            self.facing_scaler /= ZOOM_PULSE_SCALER
        elif self.zoom_is_pulsing and self.facing_scaler < 0.999:
            self.facing_scaler *= 1.0+(1.0-self.facing_scaler)/2.0
            if self.facing_scaler >= 0.999:
                self.zoom_is_pulsing = False
                self.facing_scaler = 1.0
        else:
            self.zoom_is_pulsing = False

    # Magnitude of the 'facing' vector:
    def facing_mag(self):
        return 1.0*self.facing_scaler
    
    # Magnitude of the 'viewplane' vector:
    def vplane_mag(self):
        return 0.5*self.vplane_scaler
    
    def current_view_vectors(self):
        sina, cosa = math.sin(self.a), math.cos(self.a)
        fm, vm = self.facing_mag(), self.vplane_mag()
        return [
            self.x, self.y,
            sina * fm, cosa * fm,
            -cosa * vm, sina * vm
        ]
    
    # Reset player position/orientation (POV) to a known good value:
    def reset(self):
        self.x = self.initial_x
        self.y = self.initial_y
        self.a = self.initial_a
        self.facing_scaler = 1.0
        self.vplane_scaler = 1.0

    # Draw the player position and orientation overlaid on the on-screen map:
    def render(self, map: RBZMap, screen):
        flipper = -1 if FLIPPED else 1
        (cx,cy) = super().render(map, screen)
        _, _, fx, fy, vx, vy = self.current_view_vectors()
        fx *= flipper
        vx *= flipper
        s = map.screen_scale #-1.0
        fx *= s
        fy *= s
        vx *= s
        vy *= s
        pygame.draw.line(screen, (255,0,0), (cx,cy), (cx+fx,cy+fy)) # Draw facing line
        pygame.draw.line(screen, (255,0,0), (cx+fx-vx,cy+fy-vy), (cx+fx+vx,cy+fy+vy)) # Draw viewplane

    # Adjust the current player orientation by applying a rotational transformation:
    def rotate_vectors(self, a):
        self.a += a
        if self.a > 2.0*math.pi:
            self.a -= 2.0*math.pi
        elif self.a < 0:
            self.a += 2.0*math.pi

    # Recalculate vectors by applying user inputs, scaled by time since last update:
    def recalc_vectors(self, dir_keys, delta_time, mouse, shift_key, alt_key, clip_map: RBZMap = None):
        flipper = -1 if FLIPPED else 1
        mouse_rotate_speed = -0.002 # Mouse angular motion coefficient.
        move_quantum = 2.0**-9.0 # Smallest unit movement in fixed-point (Q#.9) format.
        rate = self.walk_rate
        if shift_key: rate *= self.run_scaler
        if alt_key: rate *= self.crawl_scaler
        player_walk_60hz = move_quantum * rate
        player_walk_1hz = player_walk_60hz*60.0
        step = (delta_time/1000.0)*player_walk_1hz
        # Calculate overall direction vector:
        mx = 0.0
        my = 0.0
        ma = 0.0 # Angular motion.

        #SMELL: Motion scaling is affected by the size of self.facing_mag() if done this way:
        _, _, fx, fy, _, _ = self.current_view_vectors()
        if dir_keys[KEY_NORTH]: mx += fx;           my += fy
        if dir_keys[KEY_SOUTH]: mx -= fx;           my -= fy
        if dir_keys[KEY_WEST ]: mx += fy * flipper; my -= fx * flipper
        if dir_keys[KEY_EAST ]: mx -= fy * flipper; my += fx * flipper

        # (Try to) apply motion to player position (collision detection considered),
        # normalising movement (so it doesn't exceed maximum when multiple keys are pressed):
        mag = math.sqrt(mx*mx + my*my)
        if mag != 0.0:
            player.move(step*mx/mag, step*my/mag, clip_map)

        # Keyboard rotation:
        if dir_keys[KEY_CCW  ]: ma -= delta_time/1000.0 * flipper
        if dir_keys[KEY_CW   ]: ma += delta_time/1000.0 * flipper
        # Mouse rotation:
        ma += mouse*mouse_rotate_speed
        player.rotate_vectors(ma*flipper)
        
    # Convert a given floating-point number to a fixed-point representation,
    # optionally returning the value as an integer or string of binary digits:
    def float_to_fixed(f, q: str = 'Q12.12', binary: bool = False) -> int:
        bits = 0
        if q == 'Q12.12':
            #SMELL: Hard-coded to assume Q12.12 for now, where MSB is sign bit.
            t = int(f * (2.0**12.0))  # Just shift it left by 12 bits (fractional part scale) and make it an integer...
            t &= 0x00FFFFFF # ...then return only the lower 24 bits.
            bits = 24
        elif q == 'UQ6.9':
            t = int(f * (2.0**9.0))
            t &= 0x00007FFF # 15 bits.
            bits = 15
        elif q == 'SQ2.9':
            t = int(f * (2.0**9.0))
            t &= 0x000007FF # 11 bits.
            bits = 11
        else:
            raise Exception(f"Unsupported fixed-point format: {q}")
        return bin(t)[2:].zfill(bits) if binary else t

    # Get the player vectors (or one of them) in fixed-point formats that
    # match the requirements of the raybox-zero "Vectors" SPI interface,
    # optionally as strings of binary digits instead of integers:
    def fixed(self, k: str = None, binary: bool = False):
        px, py, fx, fy, vx, vy = self.current_view_vectors()
        m = {
            'player_x': px,
            'player_y': py,
            'facing_x': fx,
            'facing_y': fy,
            'vplane_x': vx,
            'vplane_y': vy,
        }
        # Fixed-point formats used by raybox-zero:
        q = {
            'player_x': 'UQ6.9',
            'player_y': 'UQ6.9',
            'facing_x': 'SQ2.9',
            'facing_y': 'SQ2.9',
            'vplane_x': 'SQ2.9',
            'vplane_y': 'SQ2.9',
        }
        if k is None:
            return list(map(lambda v: Player.float_to_fixed(v[1], q[v[0]], binary), m.items()))
        else:
            return Player.float_to_fixed(m[k], q[k], binary)

    # Apply a motion vector to the player position, optionally using
    # collision detection (clipping):
    def move(self, x: float, y: float, clip_map: RBZMap = None):
        if clip_map is None:
            self.x += x
            self.y += y
        else:
            (self.x, self.y) = self.try_move(x, y, clip_map)

    # Determine new position by attempting to move on the vector (x,y)
    # while respecting collision detection. This is basically a reimplementation of:
    # https://dev.opera.com/articles/3d-games-with-canvas-and-raycasting-part-2/#collision-detection
    def try_move(self, x: float, y: float, map: RBZMap):
        r = self.size / 2.0
        r2 = r*r
        m = lambda x, y: map.cell(x, y) is not None # map.cell() returns 0 for the 'other' wall block, but None for an empty cell.
        # From:
        fx = self.x
        fy = self.y
        # To:
        tx = fx + x
        ty = fy + y
        if NO_CLIP:
            return (tx, ty)
        # Sanity check:
        #TODO: Put in clamping/wrapping to map dimensions.
        # Quantize to map cell coords:
        bx = int(tx)
        by = int(ty)
        if m(bx, by): return (fx, fy) # Player is trying to move completely into a blocking cell; stop the move completely.
        ct = m(bx+0, by-1) # Up 1 cell.
        cb = m(bx+0, by+1) # Down 1 cell.
        cl = m(bx-1, by+0) # Left 1 cell.
        cr = m(bx+1, by+0) # Right 1 cell.
        if (ct and ty  -by < r): ty = by   + r
        if (cb and by+1-ty < r): ty = by+1 - r
        if (cl and tx  -bx < r): tx = bx   + r
        if (cr and bx+1-tx < r): tx = bx+1 - r

        # is tile to the top-left a wall
        if m(bx - 1, by - 1) and not (ct and cl):
            dx = tx - bx
            dy = ty - by
            if dx * dx + dy * dy < r2:
                if dx * dx > dy * dy:
                    tx = bx + r
                else:
                    ty = by + r

        # is tile to the top-right a wall
        if m(bx + 1, by - 1) and not (ct and cr):
            dx = tx - (bx + 1)
            dy = ty - by
            if dx * dx + dy * dy < r2:
                if dx * dx > dy * dy:
                    tx = bx + 1 - r
                else:
                    ty = by + r

        # is tile to the bottom-left a wall
        if m(bx - 1, by + 1) and not (cb and cl):
            dx = tx - bx
            dy = ty - (by + 1)
            if dx * dx + dy * dy < r2:
                if dx * dx > dy * dy:
                    tx = bx + r
                else:
                    ty = by + 1 - r

        # is tile to the bottom-right a wall
        if m(bx + 1, by + 1) and not (cb and cr):
            dx = tx - (bx + 1)
            dy = ty - (by + 1)
            if dx * dx + dy * dy < r2:
                if dx * dx > dy * dy:
                    tx = bx + 1 - r
                else:
                    ty = by + 1 - r

        return (tx, ty)


misses = 0 # [] # Keeps track of updates where we missed our timing target.

# Create the player:
player = Player(11.5, 10.5)

# Create the environment:
game_map = RBZMap(raybox)

# Direction keys: QWEASD, hence W=1, A=3, S=4, D=5
dir_keys    = [False] * 6
KEY_CCW     = 0
KEY_CW      = 2
KEY_NORTH   = 1
KEY_WEST    = 3
KEY_SOUTH   = 4
KEY_EAST    = 5
dir_labels  = [*'QWEASD'] # Each array element is one character (i.e. one key label).

last_blit_time = last_time = pygame.time.get_ticks()

frame_count = 0

fps_text = None

other_x_tracking = 0
other_y_tracking = 0

mapdx_tracking = 0
mapdy_tracking = 0

while running:

    mouse_delta = pygame.mouse.get_rel()

    loop_counter += 1
    now = ts()
    delta = now-timer   # Time since last tick was registered.


    if delta >= TICK:
        # The way I've designed this currently, it will attempt to send rendering update control data
        # to Raybox every `TICK` nanoseconds.
        
        # OK, hit our scheduled target:
        # At the least, our target has elapsed... probably a little more.
        hit_counter += 1                            # Increment hit counter.
        if delta > max_delta: max_delta = delta     # Used for finding max_delta.
        sum_deltas += delta                         # Used for calculating average.
        ticks = int(delta/TICK)
        if ticks > 1: misses += 1 # misses.append(hit_counter)
        tick_counter += ticks                       # Count of what would be WHOLE ticks since start.
        timer += int(delta/TICK)*TICK               # Update timer to refer to what WOULD'VE been the start of this tick.

        # Get vectors as fixed-point hex values:
        vectors = player.fixed(binary=True)

        raybox.set_raw_pov(''.join(vectors))
        game_map.env_flash()
        player.zoom_pulse()

        # Render our preview window:
        screen.fill((40,80,120))
        game_map.draw(screen)
        player.render(game_map, screen)
        screen.blit(info_text, (0,0))
        # Draw WASD keys overlay:
        for n in range(6):
            if True: #n != 0 and n!= 2:
                pygame.draw.rect(
                    screen,
                    (0,255,0),
                    pygame.Rect( 20+(n%3)*32, 20+(n//3)*32, 30, 30),
                    0 if dir_keys[n] else 1, 4
                )
        # Display other data:
        # Vectors (decimal floating-point):
        px, py, fx, fy, vx, vy = player.current_view_vectors()
        text = font.render(
            f"player({px:15.6f}, {py:15.6f})  "+
            f"facing({fx:11.6f}, {fy:11.6f})  "+
            f"vplane({vx:11.6f}, {vy:11.6f})", True, (255,255,255))
        rect = text.get_rect()
        rect.bottomright = (SCREEN_W, SCREEN_H-rect.height)
        screen.blit(text, rect)
        
        # Vectors (hex fixed-point):
        text = font.render(
            f"player({vectors[0]}, {vectors[1]})  "+
            f"facing({vectors[2]}, {vectors[3]})  "+
            f"vplane({vectors[4]}, {vectors[5]})", True, (255,255,255))
        rect = text.get_rect()
        rect.bottomright = (SCREEN_W, SCREEN_H)
        screen.blit(text, rect)

        # Calculate FPS:
        if frame_count >= 10:
            time_delta = float(pygame.time.get_ticks()-last_fps_time)/1000.0
            fps = 10.0 / time_delta
            fps_text = font.render( f"FPS: {fps:6.1f}", True, (255,255,255) )
            frame_count = 0
        if fps_text is not None:
            rect = fps_text.get_rect()
            rect.topright = (SCREEN_W, 0)
            screen.blit(fps_text,rect)
        pygame.display.flip()
        if frame_count == 0:
            last_fps_time = pygame.time.get_ticks() # In ms.
        frame_count += 1

        if DEBUG:
            print(
                f"{ts()/NSMS:11.4f}: Hit {hit_counter:4} of {tick_counter:4} ticks at {timer/NSMS:11.4f}ms."
                f" Delta:{delta/NSMS:7.4f}ms. Loops:{loop_counter:5}",
            )
        if min_loops is None or loop_counter < min_loops: min_loops = loop_counter
        if loop_counter > max_loops: max_loops = loop_counter
        sum_loops += loop_counter
        loop_counter = 0  # Reset loop counter.

    mods = pygame.key.get_mods()
    shift_key   = mods & pygame.KMOD_SHIFT
    alt_key     = mods & pygame.KMOD_ALT
    ctrl_key    = mods & pygame.KMOD_CTRL

    # Get the state of all keys:
    keys = pygame.key.get_pressed()

    # Check for movement keys:
    dir_keys = list(map(lambda v: keys[v], [pygame.K_q, pygame.K_w, pygame.K_e, pygame.K_a, pygame.K_s, pygame.K_d]))
    dir_keys[KEY_CCW  ] |= keys[pygame.K_LEFT]
    dir_keys[KEY_CW   ] |= keys[pygame.K_RIGHT]
    dir_keys[KEY_NORTH] |= keys[pygame.K_UP]
    dir_keys[KEY_SOUTH] |= keys[pygame.K_DOWN]

    if pygame.mouse.get_pressed()[2]:
        dir_keys[KEY_NORTH] = True

    # Check if we've got any key KB/mouse/window events we have to process:
    for event in pygame.event.get():
        event_counter += 1
        if event.type == pygame.QUIT:
            print("Exiting: Pygame QUIT event")
            running = False
        elif event.type == pygame.MOUSEBUTTONDOWN:
            if event.button == 1 and not pause:
                game_map.env_flash(True)
                player.zoom_pulse(True)
        elif event.type == pygame.MOUSEWHEEL:
            texadd_mult = 1
            mult = 1.0
            add_speed = 1
            zoom_speed = 0.01
            # Modifier keys scale mousewheel movements:
            if ctrl_key:    mult *= 2; texadd_mult *= 262144    # 1 "variant"
            if shift_key:   mult *= 4; texadd_mult *= 8192      # 2 tiles (1 wall type)
            if alt_key:     mult *= 8; texadd_mult *= 64        # 1 line
            adjust_fov = True

            if keys[pygame.K_1]:
                # Change sky colour:
                adjust_fov = False
                if FLIPPED:
                    game_map.floor_color += event.y * add_speed * mult
                else:
                    game_map.sky_color += event.y * add_speed * mult
            if keys[pygame.K_2]:
                # Change floor colour:
                adjust_fov = False
                if FLIPPED:
                    game_map.sky_color += event.y * add_speed * mult
                else:
                    game_map.floor_color += event.y * add_speed * mult
            if keys[pygame.K_3]:
                # Change leak:
                adjust_fov = False
                game_map.leak += event.y * add_speed * mult
            if keys[pygame.K_4]:
                # Change texture VSHIFT:
                adjust_fov = False
                game_map.vshift += event.y * add_speed * mult
            
            # Handle each CMD_TEXADD#:
            if keys[pygame.K_6] or keys[pygame.K_0]:
                adjust_fov = False
                game_map.texadd3 += event.y * texadd_mult
            if keys[pygame.K_7] or keys[pygame.K_0]:
                adjust_fov = False
                game_map.texadd0 += event.y * texadd_mult
            if keys[pygame.K_8] or keys[pygame.K_0]:
                adjust_fov = False
                game_map.texadd1 += event.y * texadd_mult
            if keys[pygame.K_9] or keys[pygame.K_0]:
                adjust_fov = False
                game_map.texadd2 += event.y * texadd_mult

            if adjust_fov:
                player.facing_scaler *= 1.0 + event.y * zoom_speed * mult

        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                print("Exiting: ESC key pressed")
                if event.mod & pygame.KMOD_CTRL:
                    # CTRL+ESC, so activate inc_px/py when we exit.
                    raybox.enable_player_auto_increment(inc_px=True, inc_py=True)
                running = False
            elif event.key == pygame.K_c:
                NO_CLIP = not NO_CLIP
                print(f"Clipping: {"Disabled" if NO_CLIP else "Enabled"}")
            elif event.key == pygame.K_F11:
                pause = not pause
                if pause:
                    print("Pausing...")
                else:
                    print("Resuming from pause...")
            elif event.key == pygame.K_m or event.key == pygame.K_F12:
                print("Toggle mouse capture:", "captured" if capture_mouse() else "released")
            elif event.key == pygame.K_r:
                print("Reset game state")
                player.reset()
                game_map.reset()
            elif event.key == pygame.K_i:
                game_map.vinf = not game_map.vinf
                print(f"VINF: {game_map.vinf}")
            elif event.key == pygame.K_t:
                game_map.gen_tex = not game_map.gen_tex
                print(f"Texture source: {"Internally generated" if game_map.gen_tex else "External SPI"}")
            elif event.key == pygame.K_BACKQUOTE:
                r = raybox.toggle_debug()
                print(f"Turning Vectors DEBUG signal {'ON' if r else 'OFF'}")
            elif FLIPPED:
                if   event.key == pygame.K_KP_9: game_map.floor_color+= 1 # Increment floor colour.
                elif event.key == pygame.K_KP_7: game_map.floor_color-= 1 # Decrement floor colour.
                elif event.key == pygame.K_KP_3: game_map.sky_color  += 1 # Increment sky colour.
                elif event.key == pygame.K_KP_1: game_map.sky_color  -= 1 # Decrement sky colour.
            else:
                if   event.key == pygame.K_KP_9: game_map.sky_color  += 1 # Increment sky colour.
                elif event.key == pygame.K_KP_7: game_map.sky_color  -= 1 # Decrement sky colour.
                elif event.key == pygame.K_KP_3: game_map.floor_color+= 1 # Increment floor colour.
                elif event.key == pygame.K_KP_1: game_map.floor_color-= 1 # Decrement floor colour.

    # Update game state based on inputs and time elapsed:
    this_time = pygame.time.get_ticks()
    delta_time = this_time - last_time
    last_time = this_time
    if keys[pygame.K_o]:
        other_x_tracking = min(max(other_x_tracking-mouse_delta[0],0),(RBZ_MAP_COLS-1)*64)
        other_y_tracking = min(max(other_y_tracking+mouse_delta[1],0),(RBZ_MAP_ROWS-1)*64)
        game_map.other_x = other_x_tracking // 64
        game_map.other_y = other_y_tracking // 64
        game_map.generate_map_surface()
    elif keys[pygame.K_p]:
        mapdx_tracking = min(max(mapdx_tracking-mouse_delta[0],0),(RBZ_MAP_COLS-1)*64)
        mapdy_tracking = min(max(mapdy_tracking+mouse_delta[1],0),(RBZ_MAP_COLS-1)*64)
        game_map.mapdx = mapdx_tracking // 64
        game_map.mapdy = mapdy_tracking // 64
        game_map.generate_map_surface()
    else:
        mouse_move = mouse_delta[0] if not ROTATE_MOUSE else mouse_delta[1]

    if not pause:
        player.recalc_vectors(dir_keys, delta_time, mouse_move, shift_key, alt_key, game_map)



# Display stats:
print("---")
print(f"{ts()/NSMS:11.4f}: Hit {hit_counter:4} of {tick_counter:4} ticks at {timer/NSMS:11.4f}ms. Delta:{delta/NSMS:7.4f}ms. Total time:{(ts()-start)/NSMS:10.4f}")
#if len(misses) > 0:
if misses > 0:
    # print(len(misses), "misses", misses)
    print(misses, "misses")
print(f"Min loops: {min_loops:5}")
print(f"Max loops: {max_loops:5}")
print(f"Avg loops: {int(sum_loops/hit_counter):5}")
print(f"Max delta: {max_delta/NSMS:6.3f}ms")
print(f"Avg delta: {sum_deltas/hit_counter/NSMS:6.3f}ms")
print(f"Pygame events: {event_counter}")
