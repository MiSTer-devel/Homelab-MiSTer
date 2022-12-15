//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 0;
assign AUDIO_L = {2'b0,audio[1],2'b0,audio[0],10'b0};
assign AUDIO_R = {2'b0,audio[1],2'b0,audio[0],10'b0};
assign AUDIO_MIX = 0;

assign LED_USER = (ioctl_download && ioctl_index==1) | (adc_cassette_bit & tape_adc_act);
assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v" 
localparam CONF_STR = {
	"Homelab;;",
	"-;",
	"F1,HTP,Load Rom;",
	"T[10],Play;",
	"T[11],Stop;",
	"T[12],Rewind;",
`ifndef DISABLE_TURBO_LOADER
	"O[13],Turbo HTP Loading,Off,On;",
`endif
	"-;",
	"FC2,CHR,Load Alternate CHR;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],Screen mode,32 CH,64 CH;",
	"O[6:5],Screen Color,White,Green,Amber;",	
	"O[3],Machine,Homelab3,Homelab4;",		
	"-;",
	"R[0],Reset;",
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	//ioctl
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),

	.buttons(buttons),
	.status(status),
	.status_menumask({status[5]}),
	
	.ps2_key(ps2_key)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk12, clk120, clk_sys, pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.outclk_0(clk12),
	.outclk_1(clk120),
	.locked(pll_locked)	
);

// Turbo Loader - speeds up loading HTP files via the LOAD command by speeding up the processor to 120MHZ
`ifndef DISABLE_TURBO_LOADER
//  This is a quick and dirty way of switching the clock,
//  which normally can cause glitches but since it's only done
//  during tape loading, there isn't much to glitch on.
//  Does take forever to compile in Standard or Auto Fitting,
//  so if you don't care about this feature, or you are debugging
//  new features and want to compile faster, use the DISABLE_TURBO_LOADER
//  verilog macro to leave this feature out.  
wire turbo;
assign turbo = (status[13] && htp_playing);

assign clk_sys = turbo ? clk120 : clk12;

`else

assign clk_sys = clk12;

`endif


reg reset = 0;
always @(posedge clk_sys) begin
	reset <= status[0] | buttons[1] | mode_change | machine_change; // | ~rom_loaded;
end

wire mode_change = old_mode ^ status[2];
reg old_mode = 0;
always @(posedge clk_sys) old_mode <= status[2];

wire machine_change = old_machine ^ status[3];
reg old_machine = 0;
always @(posedge clk_sys) old_machine <= status[3];

//////////////////////////////////////////////////////////////////

wire machine = status[3];
wire htp_playing;

wire vblankn;
wire HBlank;
wire HSync;
wire VBlank;
wire VSync;
wire [7:0] video;

Homelab Homelab (
	.RESET(reset),
	.CLK(clk_sys),
	.CHR64(chr64),
	.HSYNC(HSync),
	.VSYNC(VSync),
	.HBLANK(HBlank),
	.VBLANK(VBlank),
	.VIDEO(video),
	.AUDIO(audio),
	.CASS_IN((adc_cassette_bit & tape_adc_act)),
	.htp_playing(htp_playing),
	.HTP_FUNC(status[12:10]),

	.KEY_STROBE(key_strobe),
	.KEY_PRESSED(key_pressed),
	.KEY_CODE(key_code),

	.DL_ADDR(ioctl_addr[15:0]),
	.DL_DATA(ioctl_data),
	.DL_WE(ioctl_wr),
	.DL_INDEX(ioctl_index),
	.DL_DOWNLOAD(ioctl_download),

	.MACHINE(machine)
);

// 512 x 256 x 50Hz
`ifndef DISABLE_TURBO_LOADER

assign CLK_VIDEO = clk120;
assign CE_PIXEL = turbo ? clk120 : clk12;

`else

assign CLK_VIDEO = clk12;
assign CE_PIXEL = 1'b1;

`endif

wire  chr64 = status[2];
wire  [1:0] audio;

assign vblankn = ~(HBlank | VBlank);
assign VGA_HS = HSync;
assign VGA_VS = VSync;
assign VGA_DE = vblankn;

wire key_strobe = old_keystb ^ ps2_key[10];
reg old_keystb = 0;
always @(posedge clk_sys) old_keystb <= ps2_key[10];

wire       key_pressed = ps2_key[9];
wire [7:0] key_code    = ps2_key[7:0];

/////////////////////// Video colour processing  //////////////////////////////

wire [1:0] disp_color = status[6:5];
logic [23:0] mono_colour;
logic [23:0] rgb_white;
logic [23:0] rgb_green;
logic [23:0] rgb_amber;

always_comb begin
	rgb_white <= (video && vblankn) ? 24'hffffff : 24'h000000;
	rgb_green <= (video && vblankn) ? 24'h00ff00 : 24'h000000;
	rgb_amber <= (video && vblankn) ? 24'hffbf00 : 24'h000000;
end

always_comb begin
    if(disp_color==2'b00) mono_colour = rgb_white;
    else if(disp_color==2'b01) mono_colour = rgb_green;
    else if(disp_color==2'b10) mono_colour= rgb_amber;
    else mono_colour = rgb_white;
end

assign VGA_R = mono_colour[23:16];
assign VGA_G = mono_colour[15:8];
assign VGA_B = mono_colour[7:0];

/////////////////////// ADC Module  //////////////////////////////


wire adc_cassette_bit, tape_adc_act;
ltc2308_tape ltc2308_tape
(
	.clk(CLK_50M),
	.ADC_BUS(ADC_BUS),
	.dout(adc_cassette_bit),
	.active(tape_adc_act)
);

endmodule
