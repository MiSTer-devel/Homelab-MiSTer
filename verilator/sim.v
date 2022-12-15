`timescale 1ns/1ns
// top end ff for verilator

module top(

   input clk_48 /*verilator public_flat*/,
   input clk_12 /*verilator public_flat*/,   
   input reset,

   output [7:0] VGA_R/*verilator public_flat*/,
   output [7:0] VGA_G/*verilator public_flat*/,
   output [7:0] VGA_B/*verilator public_flat*/,
   
   output VGA_HS,
   output VGA_VS,
   output VGA_HB,
   output VGA_VB,

   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,
   
   input        ioctl_download,
   input        ioctl_upload,
   input        ioctl_wr,
   input [24:0] ioctl_addr,
   input [7:0]  ioctl_dout,
   input [7:0]  ioctl_din,   
   input [7:0]  ioctl_index,
   output  reg  ioctl_wait=1'b0,

   input [10:0] ps2_key   
);

   // Core inputs/outputs
   wire       pause;
   wire [7:0] audio;
   wire [8:0] rgb;
   wire [3:0] led/*verilator public_flat*/;

   // MAP OUTPUTS
   assign AUDIO_L = {audio,audio};
   assign AUDIO_R = AUDIO_L;

reg ce_pix;
assign ce_pix = 1'b1;

wire         chr64 = 1;

wire        video;
wire        audio;
wire        hs, vs;
wire        hb, vb;
wire        blankn = ~(hb | vb);

assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_HB = hb;
assign VGA_VB = vb;

assign VGA_R = (video && blankn) ? 'hFF : 'h00;
assign VGA_G = (video && blankn) ? 'hFF : 'h00;
assign VGA_B = (video && blankn) ? 'hFF : 'h00;

reg key_strobe = old_keystb ^ ps2_key[10];
reg old_keystb = 0;
always @(posedge clk_48) old_keystb <= ps2_key[10];

wire       pressed = ps2_key[9];
wire [7:0] code    = ps2_key[7:0];

Homelab Homelab (
	.RESET(reset),
	.CLK12(clk_12),
	.CHR64(chr64),
	.HSYNC(hs),
	.VSYNC(vs),
	.HBLANK(hb),
	.VBLANK(vb),
	.VIDEO(video),
	.AUDIO(audio),
	.CASS_IN(UART_RX),

	.KEY_STROBE(key_strobe),  // key_strobe
	.KEY_PRESSED(pressed),
	.KEY_CODE(code),

	.DL_CLK(clk_12),   // clk_48
	.DL_ADDR(ioctl_addr[15:0]),
	.DL_DATA(ioctl_dout),
	.DL_WE(ioctl_wr),
	.DL_INDEX(ioctl_index)   
);

endmodule
