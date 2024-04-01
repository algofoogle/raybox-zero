# Optional delay between SPI edges:
def zzz():
    time.sleep_ms(1) # Comment out if you don't want/need it.

#              px:            py:            fx:        fy:        vx:        vy:
#              XXXXXXxxxxxxxxxYYYYYYyyyyyyyyySXxxxxxxxxxSYyyyyyyyyySXxxxxxxxxxSYyyyyyyyyy
pov_payload = '00110100011011100011111011011000000111101110000001000001111111000000011110'
#                  13.107422       7.855469  +0.119141  -0.992188  +0.496094  +0.058594

pov_payload = '00101110000100100001110001101111010011111110100011100001011100111101001111'
#                  11.517578       3.552734  -0.689453  -0.722656  +0.361328  -0.345703

pov_payload = '00111010000111000101101111111100100011011110010101100001101010100010001101'
#                  14.527344      11.498047  +0.552734  -0.832031  +0.416016  +0.275391

pov_payload = '00011011010010000100101111111000111111111000000000000000000000000100000000'
#                   6.820312       9.496094  +0.998047   0.000000   0.000000  +0.500000

SCLK=0  # ui_in[0]: sclk
MOSI=1  # ui_in[1]: mosi
CSb=2   # ui_in[2]: ss_n

# Start with /CS disabled...
gpio.ui[CSb].out(1)
# ...and SCLK low:
gpio.ui[SCLK].out(0)

zzz()

# Now assert /CS...
gpio.ui[CSb].out(0)

# ...and clock out each bit of the payload:
for b in pov_payload:
    zzz()
    # Present the bit on MOSI:
    gpio.ui[MOSI].out(int(b))
    # Clock it...
    zzz()
    gpio.ui[SCLK].out(1)
    zzz()
    gpio.ui[SCLK].out(0)

zzz()

# We're done; de-assert /CS:
gpio.ui[CSb].out(1)
