#include <defs.h>
#include <stub.h>
#include <uart.h>

void configure_io()
{
    //  ======= set each IO to the desired configuration =============

    //  GPIO 0 is turned off to prevent toggling the debug pin.
    //  For debug, make this an output and drive it externally to ground.
    reg_mprj_io_0  = GPIO_MODE_MGMT_STD_ANALOG;

    // Changing configuration for IO[4:1] will interfere with programming flash.
    // If you change them, you may need to hold reset while powering up the board
    // and initiating flash to keep the process configuring these IO from their
    // default values.
    reg_mprj_io_1  = GPIO_MODE_MGMT_STD_OUTPUT;         // SDO
    reg_mprj_io_2  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;   // SDI
    reg_mprj_io_3  = GPIO_MODE_MGMT_STD_INPUT_PULLUP;   // CSB: PULLUP avoids floating.
    reg_mprj_io_4  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;   // SCK

    reg_mprj_io_5  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;   // UART Rx
    reg_mprj_io_6  = GPIO_MODE_MGMT_STD_OUTPUT;         // UART Tx
    reg_mprj_io_7  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;   // IRQ

    // Raybox-zero pins:
    reg_mprj_io_11 = GPIO_MODE_USER_STD_INPUT_PULLUP;   // i_clk: PULLUP avoids floating.
    reg_mprj_io_12 = GPIO_MODE_USER_STD_OUTPUT;         // o_hsync
    reg_mprj_io_13 = GPIO_MODE_USER_STD_OUTPUT;         // o_vsync
    reg_mprj_io_14 = GPIO_MODE_USER_STD_OUTPUT;         // o_tex_csb
    reg_mprj_io_15 = GPIO_MODE_USER_STD_OUTPUT;         // o_tex_sclk
    reg_mprj_io_16 = GPIO_MODE_USER_STD_BIDIRECTIONAL;  // i_tex_in[0] (In) / o_tex_out0 (Out)
    reg_mprj_io_17 = GPIO_MODE_USER_STD_OUTPUT;         // o_gpout[0]
    reg_mprj_io_18 = GPIO_MODE_USER_STD_OUTPUT;         // o_gpout[1]
    reg_mprj_io_19 = GPIO_MODE_USER_STD_OUTPUT;         // o_gpout[2]
    reg_mprj_io_20 = GPIO_MODE_USER_STD_OUTPUT;         // o_gpout[3]
    reg_mprj_io_31 = GPIO_MODE_USER_STD_INPUT_NOPULL;   // i_tex_in[1]   (shared)
    reg_mprj_io_32 = GPIO_MODE_USER_STD_INPUT_NOPULL;   // i_tex_in[2]   (shared)
    reg_mprj_io_34 = GPIO_MODE_USER_STD_INPUT_NOPULL;   // i_tex_in[3]   (shared)
    reg_mprj_io_35 = GPIO_MODE_USER_STD_INPUT_NOPULL;   // i_spare_1     (shared)

    // Otherwise unused pins assigned by this firmware for testing:
    reg_mprj_io_36 = GPIO_MODE_MGMT_STD_OUTPUT;
    reg_mprj_io_37 = GPIO_MODE_MGMT_STD_OUTPUT;

    // Other projects; set all to be inputs under management control:
    // Pins that have analog connections in the chip:
    reg_mprj_io_8  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_9  = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_10 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_21 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_22 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_23 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_24 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_25 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    reg_mprj_io_26 = GPIO_MODE_MGMT_STD_INPUT_NOPULL;
    // Digital pins we can repurpose for other inputs in this test;
    // make them pullups so they can be grounded to assert inputs:
    reg_mprj_io_27 = GPIO_MODE_MGMT_STD_INPUT_PULLUP;
    reg_mprj_io_28 = GPIO_MODE_MGMT_STD_INPUT_PULLUP;
    reg_mprj_io_29 = GPIO_MODE_MGMT_STD_INPUT_PULLUP;
    reg_mprj_io_30 = GPIO_MODE_MGMT_STD_INPUT_PULLUP;
    reg_mprj_io_33 = GPIO_MODE_MGMT_STD_INPUT_PULLUP;

    // Initiate the serial transfer to configure IO
    reg_mprj_xfer = 1;
    while (reg_mprj_xfer == 1);
}

void delay(const int d)
{
    /* Configure timer for a single-shot countdown */
	reg_timer0_config = 0;
	reg_timer0_data = d;
    reg_timer0_config = 1;

    // Loop, waiting for value to reach zero
    reg_timer0_update = 1;  // latch current value
    while (reg_timer0_value > 0) {
        reg_timer0_update = 1;
    }
}


// Blinks the LED via `gpio`. IO36 follows, IO37 is inverted.
// Period is ~2x blink_delay
void blink(const int blink_delay)
{
    reg_gpio_out = 1;   // LED OFF
    // reg_mprj_datah = 0x00000010; // IO37=0, IO36=1
    // reg_mprj_datal = 0x00000000;

    delay(blink_delay);

    reg_gpio_out = 0;   // LED ON
    // reg_mprj_datah = 0x00000020; // IO37=1, IO36=0
    // reg_mprj_datal = 0x00000000;

    delay(blink_delay);
}


typedef union {
    struct __attribute__((packed)) {
        uint64_t reset_lock             : 2;
        uint64_t vec_csb                : 1;
        uint64_t vec_sclk               : 1;
        uint64_t vec_mosi               : 1;
        uint64_t gpout0_sel             : 6;
        uint64_t debug_vec_overlay      : 1;
        uint64_t reg_csb                : 1;
        uint64_t reg_sclk               : 1;
        uint64_t reg_mosi               : 1;
        uint64_t gpout1_sel             : 6;
        uint64_t gpout2_sel             : 6;
        uint64_t debug_trace_overlay    : 1;
        uint64_t gpout3_sel             : 6;
        uint64_t debug_map_overlay      : 1;
        uint64_t gpout4_sel             : 6;
        uint64_t gpout5_sel             : 6;
        uint64_t inc_py                 : 1;
        uint64_t inc_px                 : 1;
        uint64_t gen_tex                : 1;
        uint64_t reg_outs_enb           : 1;
        uint64_t _unused                : 13; // Padding.
    } f;
    struct {
        uint32_t la2;
        uint32_t la3;
    } w;
} rbz_control_t;

#define update_rbz(     p)             { reg_la2_data=(p).w.la2; reg_la3_data=(p).w.la3; }
#define spi_init(       spi, la)       { (la).f.spi##_csb=1;   (la).f.spi##_sclk=0;                            update_rbz(la); (la).f.spi##_csb=0;                      update_rbz(la); }
#define spi_send_bit(   spi, la, bit)  {                       (la).f.spi##_sclk=0; (la).f.spi##_mosi=(bit);   update_rbz(la);                     (la).f.spi##_sclk=1; update_rbz(la); }
#define spi_stop(       spi, la)       { (la).f.spi##_csb=0;   (la).f.spi##_sclk=0;                            update_rbz(la); (la).f.spi##_csb=1;                      update_rbz(la); }

void reg_spi_send_stream(rbz_control_t* pla, uint32_t data, int count)
{
    data <<= 32-count;
    while (count-->0) {
        spi_send_bit(reg, *pla, (data & 0x80000000)>>31 );
        data <<= 1;
    }
}

void vec_spi_send_stream(rbz_control_t* pla, uint32_t data, int count)
{
    data <<= 32-count;
    while (count-->0) {
        spi_send_bit(vec, *pla, (data & 0x80000000)>>31 );
        data <<= 1;
    }
}


void reg_spi_send_command(rbz_control_t* pla, uint32_t command, uint32_t data, int data_len)
{
    spi_init(reg, *pla);
    reg_spi_send_stream(pla, command, 4);
    reg_spi_send_stream(pla, data, data_len);
    spi_stop(reg, *pla);
}






void main()
{
    // See:
    // https://web.open-source-silicon.dev/t/10118431/zzz
    // Set pad's DM value to 110 (fast rise/fall):
    reg_gpio_mode1 = 1; // Sets upper 2 bits of pad's DM value.
    reg_gpio_mode0 = 0; // Sets lower bit of pad's DM value.
    reg_gpio_ien = 1;   // IEb=1 (input disabled)
    reg_gpio_oe = 1;    // OE=1 (output ENabled)

    configure_io();

    // // Use DLL instead of direct xclk:
    // reg_hkspi_pll_divider = 5;          // Multiply xclk (10MHz) by 5 to get 50MHz.
    // reg_hkspi_pll_source  = 0b100010;   // 100=div-4 (12.5MHz), 010=div-2 (25MHz)
    // reg_hkspi_pll_ena     = 0b01;       // Select DLL output, enable DLL/DCO
    // reg_hkspi_pll_bypass  = 0b0;        // Disable DLL bypass.
    // reg_clk_out_dest      = 0b110;      // IO15=user_clock2, IO14=wb_clk_i

    // Configure LA[115:64] as outputs from SoC, but note that this config is from
    // the perspective of the UPW, so we configure these as INPUTS:
    reg_la2_oenb = reg_la2_iena = 0xffffffff; // Set 64..95 to UPW inputs.
    reg_la3_oenb = reg_la3_iena = 0x000fffff; // Set 96..115 to UPW inputs too.

    // const int blink_delay = 10000000;

    rbz_control_t la;

    uint32_t la2, la3;

    la.f.debug_map_overlay      = 0;    // Turn OFF map overlay.
    la.f.debug_trace_overlay    = 0;    // Turn OFF trace overlay.
    la.f.debug_vec_overlay      = 1;    // Turn on vectors overlay.
    la.f.gen_tex                = 0;    // Disable generated textures; use external SPI texture memory.
    la.f.gpout0_sel             = 30;   // Select rgb[22] for gpout0 (B0)
    la.f.gpout1_sel             = 31;   // Select rgb[23] for gpout1 (B1)
    la.f.gpout2_sel             = 0;    // Default for gpout2 (R0)
    la.f.gpout3_sel             = 0;    // Default for gpout3 (R1)
    la.f.gpout4_sel             = 0;    // (Unused)
    la.f.gpout5_sel             = 0;    // (Unused)
    la.f.inc_px                 = 0;    // Turn OFF Player X incrementing.
    la.f.inc_py                 = 0;    // Turn OFF Player Y incrementing.
    la.f.reg_csb                = 1;    // Disable 'registers' SPI
    la.f.reg_sclk               = 0;    // 
    la.f.reg_mosi               = 0;    // 
    la.f.reg_outs_enb           = 0;    // Enable (ENb, active low) registered outputs instead of direct.
    la.f.reset_lock             = 0b00; // Start with reset lock engaged.
    la.f.vec_csb                = 1;    // Disable 'vectors' SPI
    la.f.vec_sclk               = 0;    // 
    la.f.vec_mosi               = 0;    // 

    update_rbz(la);

    // Wait 1000 clock cycles before releasing reset:
    for (int i=0; i<3; ++i) {
        la.f.reset_lock = 0b00; // Reset.
        update_rbz(la);
        delay(1000);
        la.f.reset_lock = 0b01; // 2 bits just need to differ in order to release reset lock.
        update_rbz(la);
        delay(1000);
    }

    // // Use reg_ SPI interface to set floor colour to full yellow:
    // reg_spi_send_command(&la, 1, 0b000011, 6);

    spi_init(vec, la);
    vec_spi_send_stream(&la, 0b00110100000011000100101010001000, 32);
    vec_spi_send_stream(&la, 0b10011111011001110000000110010000, 32);
    vec_spi_send_stream(&la, 0b0010011111, 10);
    spi_stop(vec, la);

    int counter = 0;

    reg_uart_enable = 1;

    // Loop, waiting for value to reach zero
    reg_timer0_update = 1;  // latch current value
    while (reg_timer0_value > 0) {
        reg_timer0_update = 1;
    }

    const int timer_delay = 1222333;
    int c;
    int control_state = 0;

    // Configure timer for one-shot countdowns:
	reg_timer0_config = 0;
	reg_timer0_data = timer_delay;
    reg_timer0_config = 1;
    reg_timer0_update = 1; // Latch current value.

    while (1) {
        // Control LAs according to available input pins:
        // 27 maps to reset:                // When the input is low, the design is in reset.
        la.f.reset_lock         = (0 == (reg_mprj_datal & (1<<27))) ? 0b00 : 0b01;
        // 28 maps to debug_vec_overlay     // when the input is low, vectors overlay is enabled.
        la.f.debug_vec_overlay  = (0 == (reg_mprj_datal & (1<<28))) ?    1 :    0;
        // 29 maps to gen_tex:              // When the input is low, generated textures are used instead of SPI textures.
        la.f.gen_tex            = (0 == (reg_mprj_datal & (1<<29))) ?    1 :    0;
        // 30 maps to reg_outs_enb:         // When the input is low, we have UNregistered outputs.
        la.f.reg_outs_enb       = (0 == (reg_mprj_datal & (1<<30))) ?    1 :    0;
        // 33 maps to inc_px/py:            // When the input is low, player X/Y incrementing is enabled.
        la.f.inc_px=la.f.inc_py = (0 == (reg_mprj_datah & (1<< 1))) ?    1 :    0;

        update_rbz(la);

        if (0 == reg_timer0_value) {
            // Timer expired.
            ++counter;
            if (0 == (counter & 0b11)) {
                // Blink gpio LED briefly:
                reg_gpio_out = 0;
                // print("Hello, World! 0x"); print_hex(counter>>2, 4); print("\n");
            }
            else {
                // Turn off gpio LED:
                reg_gpio_out = 1;
            }
            // Reset the timer:
            reg_timer0_config = 0;
            reg_timer0_data = timer_delay;
            reg_timer0_config = 1;
            reg_timer0_update = 1; // Latch current value.
        }
        else {
            // Timer is still running:
            reg_timer0_update = 1;
        }

        // See if there's an incoming character:
        if (!uart_rxempty_read()) {
            c = reg_uart_data;
            uart_ev_pending_write(UART_EV_RX);
            switch (control_state) {
                case 0:
                    // Start a new command.
                    switch (c>>6) {
                        case 0b00:
                            // Upper 2 bits are 00: Typical reg commands...
                            spi_init(reg, la);
                            reg_spi_send_stream(&la, c, 4); // Send 4 LSB (the command).
                            switch (c>>4) {
                                case 0:
                                    // Reg command in 4 LSBs of this byte, and 6-bit value in next byte LSBs.
                                    // This includes:
                                    // CMD_SKY    = 0   Set sky colour (6b data)
                                    // CMD_FLOOR  = 1   Set floor colour (6b data)
                                    // CMD_LEAK   = 2   Set floor 'leak' (in texels; 6b data)
                                    // CMD_VSHIFT = 4   Set texture V axis shift (texv addend)
                                    control_state = 12;
                                    break;
                                case 1:
                                    // 2x6-bit value (12 bits):
                                    // CMD_OTHER  = 3   Set 'other wall cell' position: X and Y, both 6b each, for a total of 12b.
                                    control_state = 11;
                                    break;
                                case 2:
                                    // Reg command with 2 bytes; currently just:
                                    // CMD_MAPD   = 6   Set mapdx,mapdy, mapdxw,mapdyw.
                                    control_state = 14; // Ends up being 2x8-bit (16-bit)
                                    break;
                                case 3:
                                    // Reg command with 3 bytes; i.e. one of:
                                    // CMD_TEXADD0= 7
                                    // CMD_TEXADD1= 8
                                    // CMD_TEXADD2= 9
                                    // CMD_TEXADD3=10
                                    control_state = 13; // Ends up being 3x8-bit (24-bit)
                                    break;
                            }
                            break;
                        case 0b01:
                            // Upper 2 bits are 00: Command with 1-bit value (010ccccv).
                            spi_init(reg, la);
                            reg_spi_send_stream(&la, c, 5);
                            spi_stop(reg, la);
                            break;
                        case 0b10:
                            // Upper 2 bits are 10: POV stream.
                            control_state = 1;
                            spi_init(vec, la);
                            // 2 LSB are the top MSB of the POV stream.
                            vec_spi_send_stream(&la, c, 2);
                            break;
                        case 0b11:
                            // Uper 2 bits are 11: NOOP
                            break;
                    }
                    break;
                case 1:
                case 2:
                case 3:
                case 4:
                case 5:
                case 6:
                case 7:
                case 8:
                case 9:
                    // Stream of (remaining) 72 reg bits:
                    vec_spi_send_stream(&la, c, 8);
                    ++control_state;
                    break;
                // case 10 falls thru to 'if' statement below.
                case 11:
                case 12:
                    // Stream of 6 or 12 bits reg:
                    reg_spi_send_stream(&la, c, 6);
                    control_state = 16;
                    break;
                case 13:
                case 14:
                case 15:
                    // Stream of 8, 16, or 24 reg bits:
                    reg_spi_send_stream(&la, c, 8);
                    ++control_state;
                    break;
                // case 16 falls thru to 'if' statement below.
            }
            if (10==control_state) {
                // POV stream end.
                spi_stop(vec, la);
                control_state = 0;
                print("V");
            }
            else if (16==control_state) {
                // REG stream end.
                spi_stop(reg, la);
                control_state = 0;
                print("R");
            }
        }

    }
}

