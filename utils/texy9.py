import png
import argparse
import random
from itertools import chain

# --- Config and CLI args ---
parser = argparse.ArgumentParser(description='Converts PNG tiles to binary and preview format.')
parser.add_argument('--unsharp-mask', action='store_true', help='Apply unsharp mask before processing')
parser.add_argument('--unsharp-amount', type=float, default=1.5, help='Unsharp mask strength')
parser.add_argument('--unsharp-radius', type=int, default=1, help='Unsharp mask blur radius')
parser.add_argument('--flatten-uniform', action='store_true', help='Disable dithering for uniform tiles')
parser.add_argument('--flatten-epsilon', type=int, default=4, help='RGB channel epsilon for tile uniformity')
parser.add_argument('-r', '--rotate', type=int, default=90, choices=[0,90,180,270], help='Clockwise rotation angle')
parser.add_argument('-f', '--format', type=str, default='2xbgr', choices=['mono', 'bgrx2222', '2xbgr'], help='Output pixel format')
parser.add_argument('-q', '--quantize', type=str, default='threshold', help='Quantization method to use (threshold, ordered2x2, ordered4x4, fs, atkinson, random)')
parser.add_argument('infile')
parser.add_argument('outfile')
parser.add_argument('-s', '--select', type=str, help='Comma-separated tile indices (0-based)')
parser.add_argument('-b', '--bias', type=int, default=0, help='Colour bias to add')
parser.add_argument('-m', '--multiplier', type=float, default=1.0, help='Colour contrast multiplier')
parser.add_argument('-p', '--pad', type=int, default=0, help='Pad output binary to this size')
args = parser.parse_args()

quantize_map = {}
if args.select:
    parsed = []
    for s in args.select.split(','):
        s = s.strip()
        if s[-1].isalpha():
            index = int(s[:-1])
            code = s[-1]
            qmap = {'t': 'threshold', 'f': 'fs', 'd': 'ordered2x2', 'D': 'ordered4x4', 'a': 'atkinson', 'r': 'random', 's': 'stucki'}
            quantize_map[index] = qmap.get(code, args.quantize)
            parsed.append(index)
        else:
            parsed.append(int(s))
    args.select = parsed

# --- Utilities ---
def apply_unsharp_mask(tile, amount=1.5, radius=1):
    def clamp(v): return max(0, min(255, v))

    # Create blurred version
    blurred = [[[0, 0, 0] for _ in range(64)] for _ in range(64)]
    for y in range(64):
        for x in range(64):
            total = [0, 0, 0]
            count = 0
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 64 and 0 <= ny < 64:
                        for c in range(3):
                            total[c] += tile[ny][nx][c]
                        count += 1
            for c in range(3):
                blurred[y][x][c] = total[c] // count

    # Apply unsharp mask: result = original + amount * (original - blurred)
    sharpened = [[[0, 0, 0] for _ in range(64)] for _ in range(64)]
    for y in range(64):
        for x in range(64):
            for c in range(3):
                o = tile[y][x][c]
                b = blurred[y][x][c]
                v = clamp(int(o + amount * (o - b)))
                sharpened[y][x][c] = v
    return sharpened
def b8_b2_threshold(v):
    return 3 if v >= 213 else 2 if v >= 128 else 1 if v >= 42 else 0

def b2_b8(v):
    return [0, 85, 170, 255][v]

FONT = {
    '0': ['111','101','101','101','111'], '1': ['010','110','010','010','111'],
    '2': ['111','001','111','100','111'], '3': ['111','001','111','001','111'],
    '4': ['101','101','111','001','001'], '5': ['111','100','111','001','111'],
    '6': ['111','100','111','101','111'], '7': ['111','001','001','001','001'],
    '8': ['111','101','111','101','111'], '9': ['111','101','111','001','111'],
    'a': ['111','101','111','101','101'], 'b': ['110','101','110','101','110'],
    'c': ['111','100','100','100','111'], 'd': ['110','101','101','101','110'],
    'e': ['111','100','111','100','111'], 'f': ['111','100','111','100','100']
}

def render_marker_line(index, row):
    marker = [[0, 0, 0] for _ in range(32)]
    dec, hexval = str(index), format(index, 'x')
    text = dec if row // 8 == 0 else hexval if row // 8 == 1 else ''
    col = 32 - (len(text) * 4)
    y = row % 8
    for char in text:
        glyph = FONT.get(char.lower())
        if glyph and y < len(glyph):
            for x, pixel in enumerate(glyph[y]):
                if pixel == '1' and 0 <= col + x < 32:
                    marker[col + x] = [255, 255, 255]
        col += 4
    return list(chain(*marker))

# --- Load image ---
reader = png.Reader(filename=args.infile)
width, height, pixels, _ = reader.asRGB8()
data = list(pixels)
cols, remx = divmod(width, 64)
rows, remy = divmod(height, 64)
if remx or remy:
    raise Exception("Image dimensions must be divisible by 64")
total_tiles = cols * rows
selected = args.select or list(range(total_tiles))

# --- Output setup ---
out = open(args.outfile, 'wb')
preview_rows = []
written = 0

# --- Tile processing ---
def build_dither_mask(tile, epsilon):
    mask = [[False for _ in range(64)] for _ in range(64)]
    for y in range(64):
        for x in range(64):
            cx = min(63, max(0, x))
            cy = min(63, max(0, y))
            r0, g0, b0 = tile[cy][cx]
            diffs = []
            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    nx = min(63, max(0, cx + dx))
                    ny = min(63, max(0, cy + dy))
                    r1, g1, b1 = tile[ny][nx]
                    diff = abs(r0 - r1) + abs(g0 - g1) + abs(b0 - b1)
                    diffs.append(diff)
            avg_diff = sum(diffs) / len(diffs)
            mask[y][x] = avg_diff > epsilon
    return mask
def tile_is_uniform(tile, epsilon):
    ref = tile[0][0]
    for row in tile:
        for px in row:
            if any(abs(a - b) > epsilon for a, b in zip(px, ref)):
                return False
    return True

for idx, tile_id in enumerate(selected):
    tile_quant = quantize_map.get(tile_id, args.quantize)
    use_dither = True
    row, col = divmod(tile_id, cols)

    x0, y0 = col * 64, row * 64

    # Extract tile and rotate:
    tile_orig = [[[0, 0, 0] for _ in range(64)] for _ in range(64)]
    for y in range(64):
        for x in range(64):
            px = data[y0 + y][(x0 + x)*3:(x0 + x)*3+3]
            # Rotations are in clockwise degrees.
            if args.rotate == 0:
                tx, ty = x, y
            elif args.rotate == 90:
                tx, ty = 63-y, x
                # tile_orig[x][63 - y] = px # Default.
            elif args.rotate == 180:
                tx, ty = 63-x, 63-y
            elif args.rotate == 270:
                tx, ty = y, 63-x
            else:
                raise Exception(f"Invalid rotation [{args.rotate}]; must be one of: 0, 90, 180, 270")
            tile_orig[ty][tx] = px

    if args.unsharp_mask:
        tile = apply_unsharp_mask(tile_orig, amount=args.unsharp_amount, radius=args.unsharp_radius)
    else:
        tile = tile_orig
    if args.flatten_uniform and tile_is_uniform(tile, args.flatten_epsilon):
      tile_quant = 'threshold'
      use_dither = False

    if args.flatten_uniform:
      region_mask = build_dither_mask(tile, args.flatten_epsilon)
    else:
      region_mask = [[True for _ in range(64)] for _ in range(64)]

    tile_original = []
    tile_adjusted = []
    tile_lossy = []
    encoded = []

    errbuf = [[[0, 0, 0] for _ in range(64)] for _ in range(64)] if tile_quant in ['fs', 'atkinson', 'stucki', 'sierra'] else None

    for y in range(64):
        row_o = []
        row_a = []
        row_q = []
        for x in range(64):
            r, g, b = tile[y][x]
            row_o.append([r, g, b])
            r = min(255, max(0, int((r - 128) * args.multiplier) + 128 + args.bias))
            g = min(255, max(0, int((g - 128) * args.multiplier) + 128 + args.bias))
            b = min(255, max(0, int((b - 128) * args.multiplier) + 128 + args.bias))
            row_a.append([r, g, b])

            use_dither_here = region_mask[y][x]

            if not use_dither_here:
                r2, g2, b2 = map(b8_b2_threshold, (r, g, b))

            elif tile_quant == 'random':
                r2, g2, b2 = [b8_b2_threshold(v + random.randint(-21, 21)) for v in (r, g, b)]
            elif tile_quant.startswith('ordered'):
                matrix = [[0]]
                if tile_quant == 'ordered2x2':
                    matrix = [[0, 2], [3, 1]]
                elif tile_quant == 'ordered4x4':
                    matrix = [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]
                dim = len(matrix)
                def dither(val, x, y):
                    bias = matrix[y % dim][x % dim] / (dim * dim)
                    level = int(val / 256.0 * 4 + bias)
                    return min(3, max(0, level))
                r2, g2, b2 = dither(r,x,y), dither(g,x,y), dither(b,x,y)
            elif tile_quant in ['fs', 'atkinson', 'stucki', 'sierra']:
                r += errbuf[y][x][0]
                g += errbuf[y][x][1]
                b += errbuf[y][x][2]
                r = min(255, max(0, r))
                g = min(255, max(0, g))
                b = min(255, max(0, b))
                r2, g2, b2 = map(b8_b2_threshold, (r, g, b))
                rq, gq, bq = map(b2_b8, (r2, g2, b2))
                err = [r - rq, g - gq, b - bq]
                if tile_quant == 'fs':
                    for dx, dy, w in [(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)]:
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] * w // 16
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] * w // 16
                elif tile_quant == 'atkinson':
                    for dx, dy in [(1,0), (2,0), (-1,1), (0,1), (1,1), (0,2)]:
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] // 8
                elif tile_quant == 'stucki':
                    for dx, dy, w in [
                        (1, 0, 8), (2, 0, 4),
                        (-2, 1, 2), (-1, 1, 4), (0, 1, 8), (1, 1, 4), (2, 1, 2),
                        (-2, 2, 1), (-1, 2, 2), (0, 2, 4), (1, 2, 2), (2, 2, 1)
                    ]:
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] * w // 42
                elif tile_quant == 'sierra':
                    for dx, dy, w in [
                        (1, 0, 5), (2, 0, 3),
                        (-2, 1, 2), (-1, 1, 4), (0, 1, 5), (1, 1, 4), (2, 1, 2),
                        (-1, 2, 2), (0, 2, 3), (1, 2, 2)
                    ]:
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] * w // 32
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 64 and 0 <= ny < 64:
                            for c in range(3):
                                errbuf[ny][nx][c] += err[c] // 8
            else:
                # Default fallback quantization method
                r2, g2, b2 = map(b8_b2_threshold, (r, g, b))

            row_q.append([b2_b8(r2), b2_b8(g2), b2_b8(b2)])

            if args.format == '2xbgr':
                byte = (
                    ((b2 & 1) << 6) | ((g2 & 1) << 5) | ((r2 & 1) << 4) |
                    ((b2 & 2) << 1) | ((g2 & 2)     ) | ((r2 & 2) >> 1)
                )
            elif args.format == 'bgrx2222':
                byte = (b2 << 6) | (g2 << 4) | (r2 << 2)
            elif args.format == 'mono':
                avg = (r + g + b) // 3
                byte = 1 if avg > 127 else 0
            encoded.append(byte)

        tile_original.append(row_o)  # unmodified
        tile_adjusted.append(row_a)
        tile_lossy.append(row_q)

    out.write(bytes(encoded))
    written += len(encoded)

    for y in range(64):
        marker = render_marker_line(tile_id, y)
        row_rotated_original = list(chain.from_iterable(tile_orig[x][63 - y] for x in range(64)))
        row_rotated_adjusted = list(chain.from_iterable(tile_adjusted[x][63 - y] for x in range(64)))
        row_rotated_lossy = list(chain.from_iterable(tile_lossy[x][63 - y] for x in range(64)))
        preview_rows.append(row_rotated_original + row_rotated_adjusted + row_rotated_lossy + marker)

# --- Write preview PNG ---
with open("preview.png", 'wb') as pf:
    writer = png.Writer(width=64*3 + 32, height=len(selected)*64, bitdepth=8, greyscale=False)
    writer.write(pf, preview_rows)

if args.pad > written:
    out.write(bytes([255] * (args.pad - written)))
out.close()
