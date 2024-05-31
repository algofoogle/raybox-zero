import png
import argparse
from itertools import chain

# Walls I like are: 0,1,14,15,84,85,106,107
# Overall good parameters:
#   py .\texy.py ..\assets\allwolfwalls.png -s 0,1,14,15,84,85,106,107 -m 1.4 -b 20 -f 2bgrx -p 1048576 walls.bin
# Another good set:
#   py texy.py ..\assets\allwolfwalls.png walls.bin -m 1.4 -b 20 -f 2bgrx -p 1048576 -s 78,79,66,67,46,47,50,51,0,1,2,3,52,53,14,15,16,17,8,9,12,13,32,33,38,39,22,23,44,45,86,87,88,89,98,99,100,101

parser = argparse.ArgumentParser(
    description='Converts PNG images for use as raybox-zero textures'
)
parser.add_argument('infile')
parser.add_argument('outfile')
parser.add_argument('-s', '--select', type=str, help='Takes a comma-separated list of wall indices (first is 0) and only includes those specified')
parser.add_argument('-b', '--bias', type=int, default=0, help='Add (or subtract) a given bias on each colour channel')
parser.add_argument('-m', '--multiplier', type=float, default=1.0, help='Adjust contrast using a multiplier')
parser.add_argument('-f', '--format', type=str, default='2xbgr', choices=['mono', 'bgrx2222', '2xbgr'], help='Desired target format')
parser.add_argument('-p', '--pad', type=int, default=0, help='Pad the file out to the specified size, using 0xFF filler')
args = parser.parse_args()
if args.select is not None:
    args.select = [int(s.strip()) for s in args.select.split(',')]
if args.infile is None:
    raise Exception(f"No input PNG file specified")

src = png.Reader(filename=args.infile)
loaded = src.asRGB8()
(width, height, data) = loaded[0:3]

# Get number of texture rows and columns,
# and make sure width and height are multiples of 64:
(cols,cr) = divmod(width, 64)
(rows,rr) = divmod(height, 64)
total_walls = cols*rows
# Validation...
e = []
if cr != 0: e.append(f"Width {width} is not a multiple of 64")
if rr != 0: e.append(f"Height {height} is not a multiple of 64")
if total_walls%2 != 0: e.append(f"Wall count {total_walls} is not even")
if len(e) > 0: raise Exception('; '.join(e))
print(f"{cols} columns, {rows} rows")

# Extract all actual pixel data:
data = list(data)

preview_rows = []

def b8_b2(v):
    return 3 if v >=213 else (2 if v >= 128 else (1 if v >= 42 else 0))

def b2_b8(v):
    return [0,85,170,255][v]

outfile = open(args.outfile, 'wb')
written_bytes = 0

# Process each wall that we want... user-specified, or all:
select_walls = args.select or range(0, total_walls)
actual_walls_extracted = []
print(f"Wall IDs to extract, in order: {list(select_walls)}")
for i in select_walls:
    if i >= total_walls:
        print(f"==> WARNING: SKIPPING wall ID {i} because it exceeds the maximum ({total_walls-1})")
        continue
    actual_walls_extracted.append(i)
    (wr,wc) = divmod(i, cols)
    (wx,wy) = (wc*64, wr*64)
    print(f"Wall {i:3d} is at  RC({wc:3d}, {wr:3d})  =>  XY({wx:5d}, {wy:5d})")
    # Process each *column* of pixel data.
    # For raybox-zero, it is packed bottom to top, left to right.
    for x in range(wx, wx+64):
        # Process each pixel of each column, from bottom to top:
        preview_slice_original = []
        preview_slice_adjusted = []
        preview_slice_lossy = []
        outfile_data = []
        for y in range(wy+63, wy-1, -1):
            bias = args.bias
            mul = args.multiplier
            r8 = data[y][x*3+0]
            g8 = data[y][x*3+1]
            b8 = data[y][x*3+2]
            preview_slice_original += [r8,g8,b8]
            r8 = int((float(r8)-128.0)*mul) + 128 + bias
            g8 = int((float(g8)-128.0)*mul) + 128 + bias
            b8 = int((float(b8)-128.0)*mul) + 128 + bias
            if r8 > 255: r8 = 255
            if g8 > 255: g8 = 255
            if b8 > 255: b8 = 255
            if r8 < 0: r8 = 0
            if g8 < 0: g8 = 0
            if b8 < 0: b8 = 0
            preview_slice_adjusted += [r8,g8,b8]

            if args.format == '2xbgr':
                # Each byte must be made up of this bit stream:
                # X,b[0],g[0],r[0], X,b[1],g[1],r[1]
                r2 = b8_b2(r8)
                g2 = b8_b2(g8)
                b2 = b8_b2(b8)
                # Now convert it BACK to an RGB888 equivalent for the preview...
                preview_slice_lossy += [ b2_b8(r2), b2_b8(g2), b2_b8(b2) ]
                # Now pack it:
                outfile_data.append(
                    ((0)        <<7) | # X
                    (((b2&1)>>0)<<6) | # B[1]
                    (((g2&1)>>0)<<5) | # G[1]
                    (((r2&1)>>0)<<4) | # R[1]
                    ((0)        <<3) | #
                    (((b2&2)>>1)<<2) | # B[0]
                    (((g2&2)>>1)<<1) | # G[0]
                    (((r2&2)>>1)<<0)   # R[0]
                )
            elif args.format == 'bgrx2222':
                # Convert RGB888 input data to our desired target format...
                r2 = b8_b2(r8)
                g2 = b8_b2(g8)
                b2 = b8_b2(b8)
                # # This is the simple 'shift' method:
                # r2 = r8 >> 6
                # g2 = g8 >> 6
                # b2 = b8 >> 6
                # preview_slice_lossy += [r2<<6, g2<<6, b2<<6]
                # Now convert it BACK to an RGB888 equivalent for the preview...
                preview_slice_lossy += [ b2_b8(r2), b2_b8(g2), b2_b8(b2) ]
                # Pack this pixel as an bgrx2222 byte:
                outfile_data.append( (b2<<6)|(g2<<4)|(r2<<2)|0 ) # 2 LSB not used.
            elif args.format == 'mono':
                # Average and threshold:
                m = 1 if ((r8+g8+b8)/3)>127 else 0
                # Now convert it BACK to an RGB equivalent for the preview...
                preview_slice_lossy += ([m*255]*3)
                # Pack this pixel as a single bit:
                outfile_data.append( m )
        wall_index_marker = list(chain.from_iterable([ [k]*3 for k in [255*int(j) for j in f"{i:08b}"] ]))
        # When a slice is done, write it to our output file:
        if args.format == 'bgrx2222' or args.format == '2xbgr':
            byte_list = outfile_data
        elif args.format == 'mono':
            byte_list = [int("".join(map(str, outfile_data[i:i+8])), 2) for i in range(0, len(outfile_data), 8)]
        outfile.write(bytes(byte_list))
        written_bytes += len(byte_list)

        preview_rows.append(preview_slice_original + preview_slice_adjusted + preview_slice_lossy + wall_index_marker)

# Create the preview file:
preview_file = open('preview.png', 'wb')
preview = png.Writer(
    width=64*3+8, height=len(actual_walls_extracted)*64, # Extra 8 is a binary marker for wall index.
    bitdepth=8, greyscale=False
)
preview.write(preview_file, preview_rows)
preview_file.close()
print(f"{len(select_walls)} wall(s) selected. {len(actual_walls_extracted)} actual wall(s) extracted: {actual_walls_extracted}")

if args.pad is not None and args.pad > written_bytes:
    outfile.write(bytes([255] * (args.pad-written_bytes)))
outfile.close()
