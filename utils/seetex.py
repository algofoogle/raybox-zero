# This script converts a raw raybox-zero textures binary to a PNG,
# expecting the source binary to be in 2xbgr format, which is:
# 8 bits per pixel (only 6 used): 2 "planes" of XBGR, i.e. bit packing (MSB to LSB) is: -BGR-bgr

from PIL import Image
import argparse
import os

def luma_2b_to_8b(value):
    """Convert a 2-bit value to 8-bit by repeating the bits."""
    return (value << 6) | (value << 4) | (value << 2) | value

def decode_2xbgr(byte):
    """Decode a single byte in 2xbgr (xbgrXBGR) format into 8-bit R, G, B."""
    r_2bit = ((byte << 1) & 0b10) | ((byte >> 4) & 0b01)
    g_2bit = ((byte << 0) & 0b10) | ((byte >> 5) & 0b01)
    b_2bit = ((byte >> 1) & 0b10) | ((byte >> 6) & 0b01)
    
    r = luma_2b_to_8b(r_2bit)
    g = luma_2b_to_8b(g_2bit)
    b = luma_2b_to_8b(b_2bit)
    return (r, g, b)

def convert_file_to_png(input_path, output_path):
    if not os.path.exists(input_path):
        print(f"Error: input file '{input_path}' does not exist.")
        return

    with open(input_path, 'rb') as f:
        data = f.read()

    width = 64
    total_pixels = len(data)
    height = total_pixels // width

    if total_pixels % width != 0:
        print("Warning: input data does not align to 64 pixels per row. Truncating extra bytes.")
        data = data[:width * height]

    # Decode pixels
    pixels = [decode_2xbgr(b) for b in data]

    # Trim white-only rows from the bottom
    while height > 0:
        row_start = (height - 1) * width
        row = pixels[row_start:row_start + width]
        if all(pixel == (255, 255, 255) for pixel in row):
            height -= 1
        else:
            break

    if height == 0:
        print("Image is fully white or empty. No output generated.")
        return

    image = Image.new("RGB", (width, height))
    image.putdata(pixels[:width * height])
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    image.save(output_path)
    print(f"Saved PNG to {output_path} ({width}x{height})")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert a raw 2xbgr binary file (64px wide) to a trimmed 24-bit PNG image."
    )
    parser.add_argument("input", help="Input binary file in 2xbgr format")
    parser.add_argument("output", help="Output PNG file path")
    args = parser.parse_args()

    convert_file_to_png(args.input, args.output)
