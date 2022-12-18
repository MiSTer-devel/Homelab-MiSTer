module Homelab (
	input               CLK,
	input               RESET,
	input               CHR64,
	output              HSYNC,
	output              VSYNC,
	output reg          HBLANK,
	output              VBLANK,
	output              VIDEO,
	output reg [1:0]    AUDIO,
	input               CASS_IN,
	output              htp_playing,
	input      [2:0]    HTP_FUNC,

	input               KEY_STROBE,
	input               KEY_PRESSED,
	input      [7:0]    KEY_CODE, // PS2 keycode

	// DMA bus
	input     [15:0]    DL_ADDR,
	input      [7:0]    DL_DATA,
	input               DL_WE,
	input      [7:0]    DL_INDEX,
	input               DL_DOWNLOAD,

	input               MACHINE
);


// clock enables
reg cen6, cen3;
reg [1:0] cnt;
always @(posedge CLK) begin
	cnt <= cnt + 1'd1;
	cen6 <= cnt[0];
	cen3 <= cnt == 0;
end

//////////////////////////////////////////////////////////////////

// video circuit
reg  [8:0] hcnt;
wire       hblank = hcnt[8];
wire       hsync = hblank & hcnt[4] & hcnt[5] & ~hcnt[6];
assign     HSYNC = ~hsync;

reg  [8:0] vcnt;
wire       vblank = vcnt[8];
wire       vsync = vblank & ~vcnt[5] & vcnt[4] & vcnt[3];
assign     VSYNC = ~vsync;
assign     VBLANK = vblank;

always @(posedge CLK) begin : COUNTERS
	if (cen6) begin
		hcnt <= hcnt + 1'd1;
		if (hcnt == 383) hcnt <= 0;
		if (hcnt == 303) begin // next cycle is hsync
			vcnt <= vcnt + 1'd1;
			if (vcnt == 319) vcnt <= 0;
		end
	end
end

always @(posedge CLK) begin : BLANK
	if (CHR64 | cen6) begin
		if (hcnt[1:0] == 2'b11 & (CHR64 | hcnt[2])) HBLANK <= hblank;
	end
end

wire        vs_n;
wire [10:0] video_addr = vs_n ? {vcnt[7:3], hcnt[7:2]} : cpu_addr[10:0];

reg   [7:0] vram[2048];
wire [10:0] vram_addr = CHR64 ? video_addr : {1'b0, video_addr[10:1]};
wire        vram_we = ~vs_n & ~wr_n;
reg   [7:0] vram_dout;

always @(posedge CLK) begin : VRAM
	if (vram_we) vram[vram_addr] <= cpu_dout;
	vram_dout <= vram[vram_addr];
end

reg   [7:0] chrrom[2048];
initial begin
	$readmemh("../bios/char.hex", chrrom);
end
always @(posedge CLK) begin
	if(DL_DOWNLOAD && DL_INDEX == 8'h2 && DL_ADDR[15:12] == 4'h0) chrrom[DL_ADDR[11:0]] <= DL_DATA;
end

reg   [7:0] chrrom_dout;
wire [10:0] chrrom_addr = {vcnt[2:0], vram_dout};
always @(posedge CLK) begin : CHRROM
	chrrom_dout <= chrrom[chrrom_addr];
end

reg   [7:0] video_sr;
assign      VIDEO = video_sr[7];

always @(posedge CLK) begin : VIDEOSHIFTER
	if (CHR64 | cen6) begin
		if (hcnt[1:0] == 2'b11 & (CHR64 | hcnt[2]) & vs_n & ~vblank & ~hblank) video_sr <= chrrom_dout;
		else video_sr <= {video_sr[6:0], 1'b0};
	end
end

//////////////////////////////////////////////////////////////////

// cpu
wire        int_n = ~vblank;
wire [15:0] cpu_addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        iorq_n;
wire        mreq_n;
wire        rfsh_n;
wire        rd_n;
wire        wr_n;

`ifdef VERILATOR
tv80s T80 (
	.reset_n(~RESET),
	.clk(CLK),
	//.cen(cen3),
	.wait_n(1'b1),
	.int_n(int_n),
	.nmi_n(1'b1),
	.busrq_n(1'b1),
	.m1_n(),
	.rfsh_n(rfsh_n),
	.mreq_n(mreq_n),
	.iorq_n(iorq_n),
	.rd_n(rd_n),
	.wr_n(wr_n),
	.A(cpu_addr),
	.di(cpu_din),
	.dout(cpu_dout)
);
`else
T80s T80 (
	.RESET_n(~RESET),
	.CLK(CLK),
	.CEN(cen3),
	.WAIT_n(~HTP_DOWNLOAD), //PAUSE CPU while we load HTP into ram

	.INT_n(1'b1),
	.NMI_n(1'b1),

	.BUSRQ_n(1'b1),
	.M1_n(),
	.RFSH_n(rfsh_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.A(cpu_addr),
	.DI(cpu_din),
	.DO(cpu_dout)
);
`endif

//////////////////////////////////////////////////////////////////

reg   [7:0] rom3[16384];
initial begin
	$readmemh("../bios/homelab3.hex", rom3);
	//$readmemh("../bios/homelab4.hex", rom3);	
end
reg   [7:0] rom4[16384];
initial begin
	$readmemh("../bios/homelab4.hex", rom4);
	//$readmemh("../bios/homelab4.hex", rom3);	
end
reg   [7:0] rom_dout;
always @(posedge CLK) begin : ROM
	rom_dout <= MACHINE==0 ? rom3[cpu_addr[13:0]] : rom4[cpu_addr[13:0]];
end


//////////////////////////////////////////////////////////////////

reg   [7:0] ram_dout;
wire        ram_we;


`ifdef VERILATOR
dpram #(.addr_width_g(16)) dpram
(
	.clock(CLK),
	.address_a(cpu_addr),
	.wren_a(ram_we),
	.data_a(cpu_dout),
	.q_a(ram_dout),

	.wren_b(DL_INDEX==8'h1 ? DL_WE : 0),
	.address_b(DL_INDEX==8'h1 ? DL_ADDR+'hfb0 : 'hfb0),
	.data_b(DL_INDEX==8'h1 ? DL_DATA : 0),
	.q_b()
);
`else

spram #(16, 8) ram
(
	.clock(CLK),
	.address(HTP_DOWNLOAD ? HTP_ADDR : cpu_addr),
	.wren(HTP_DOWNLOAD ? HTP_WE : ram_we),
	.data(HTP_DOWNLOAD ? DL_DATA : cpu_dout),
	.q(ram_dout)
);

spram #(16, 8) HTP2WAV
(
	.clock(CLK),
	.address((DL_DOWNLOAD && DL_INDEX == 8'h1) ? DL_ADDR: HT_ADDR),
	.wren((DL_DOWNLOAD && DL_INDEX == 8'h1) ? DL_WE : 1'b0),
	.data((DL_DOWNLOAD && DL_INDEX == 8'h1) ? DL_DATA : 8'h0),
	.q(HT_DATA)
);

`endif

//////////////////////////////////////////////////////////////////

// HTP Loading - Parse through HTP and if not a basic file, load into ram
//               If it's a basic program, user will have to use the LOAD command to load the program
reg        old_DL,HTP_DOWNLOAD,old_DL_ADDR;
reg        htp_ctr;
reg        HTP_WE;           // Write HTP Data to RAM
reg [15:0] HTP_ADDR;         // Calculated RAM address to store HTP data
reg [15:0] htp_data_offset;  // DL_ADDR of beginning of HTP data (after header)
reg [15:0] htp_start_addr;
reg [15:0] htp_length;
reg  [2:0] state;

reg [15:0] HT_ADDR;          // Address for HTP2WAV converter
reg  [7:0] HT_DATA;          // Data    for HTP2WAV converter
reg [15:0] HTP_SIZE;         // Size of HTP file loaded


parameter
  IDLE      = 3'h0,
  FIND_NAME = 3'h1,
  FIND_PTRS = 3'h2,
  START_ADDR= 3'h3,
  HTR_SIZE  = 3'h4,
  READ      = 3'h5;

always @(posedge CLK) begin
	old_DL_ADDR <= DL_ADDR[0];
	if(DL_INDEX == 8'h1 && DL_DOWNLOAD) HTP_SIZE <= DL_ADDR;

	if(RESET) begin
		state           <= IDLE;
	end
	else begin
		case (state)
			IDLE: begin
				old_DL <= DL_DOWNLOAD && DL_INDEX == 8'h1 && DL_ADDR == 16'h0000;
				if (~old_DL && (DL_DOWNLOAD && DL_INDEX == 8'h1 && DL_ADDR == 16'h0000)) begin  //Beginning of HTP Download
					htp_start_addr  <= 16'h0000;
					htp_length      <= 16'h0000;
					htp_data_offset <= 16'h0000;
					HTP_WE          <= 1'b0;
					HTP_ADDR        <= 16'h0000;
					state           <= FIND_NAME;
				end
				else begin
					HTP_DOWNLOAD  <= 1'b0;
					HTP_WE        <= 1'b0;
				end
			 end
				
			FIND_NAME: begin
				if(DL_DATA != 8'h00) state <= FIND_PTRS;
			end

			FIND_PTRS: begin
				htp_ctr <= 1'b0;
				if(DL_DATA == 8'h00) state <= START_ADDR;
			end
			
			START_ADDR: begin
				if(old_DL_ADDR != DL_ADDR[0]) begin
					if(htp_ctr == 1'b0) begin
						htp_start_addr[7:0]  <= DL_DATA;
						htp_ctr <= 1'b1;
					end
					else begin
						htp_start_addr[15:8] <= DL_DATA;
						htp_ctr <= 1'b0;
						state   <= HTR_SIZE;
					end
				end
			end
			
			HTR_SIZE: begin
				if(htp_start_addr == 16'h4016) state <= IDLE; //  If this a basic program (starting address of x4016), then don't bother continuing as it needs to be "loaded" via command line.
				else begin
					if(old_DL_ADDR != DL_ADDR[0]) begin
						if(htp_ctr == 1'b0) begin
							htp_length[7:0]  <= DL_DATA;
							htp_ctr <= 1'b1;
						end
						else begin
							htp_length[15:8] <= DL_DATA;
							htp_ctr <= 1'b0;
							htp_data_offset  <= DL_ADDR + 1'b1;
							HTP_DOWNLOAD  <= 1'b1;
							state   <= READ;
						end
					end
				end
			end
			
			READ: begin
				HTP_WE <= 1'b0; //DL_WE;
				if(old_DL_ADDR != DL_ADDR[0]) begin
					if(htp_length >= 16'h0000) begin
						HTP_ADDR <= htp_start_addr + (DL_ADDR - htp_data_offset);
						if(htp_length == 16'h0000) begin
							state <= IDLE;
						end
						else htp_length <= htp_length - 1'b1;
						HTP_WE <= 1'b1;
					end
//					else state <= IDLE;
				end
			end
			
		endcase
	end
end

// LOAD HTP file into buffer so user can "LOAD" from command line
reg old_play,old_stop,old_rewind,old_read_tape;
reg  [7:0] htp_byte   ;  //Current HTP Byte from buffer
reg  [3:0] htp_byte_ptr; //Which bit of htp_byte are we processing
reg [12:0] htp_pattern;  //Signal pattern to playback for each bit  0="1111111111100", 1="111100111100", read from right to left
reg  [3:0] htp_pat_ptr;  //Position in pattern we are currently processing
reg  [1:0] h2w_state;    //State machine for H2W
reg  [3:0] h2w_pulse_cnt; // How many reads from system
wire       h2w_tape_bit,playing;
reg [15:0] htc_timeout;  //Time between READ pulses, if after a certain amount of lapsed time, stop playback

assign h2w_tape_bit = htp_pattern[0];
parameter
  H2W_IDLE         = 3'h0,
  H2W_READ_BYTE    = 3'h1,
  H2W_GET_NEXT_BIT = 3'h2,
  H2W_READ         = 3'h3;

//always @(posedge CLK12) begin
always @(posedge CLK) begin
	old_play   <= HTP_FUNC[0];
	old_stop   <= HTP_FUNC[1];
	old_rewind <= HTP_FUNC[2];
	old_read_tape <= (cpu_addr==16'hE883 && ~rd_n);

	if(RESET || (~old_rewind && HTP_FUNC[2]) || (DL_DOWNLOAD && DL_INDEX == 8'h1)) begin
		h2w_state    <= H2W_IDLE;
		HT_ADDR      <= 16'h0000;
		htp_byte     <= 8'h00;
		htp_byte_ptr <= 4'h0;
		htp_pattern  <= 13'h0;
		htp_pat_ptr  <= 4'h0;
		playing      <= 1'b0;
	end
	else begin
		if(~old_stop && HTP_FUNC[1]) begin
			htp_pattern  <= 13'h0;
			htp_pat_ptr  <= 4'h0;
			htp_byte_ptr <= 4'h0;
			htp_byte     <= 8'h0;
			h2w_state    <= H2W_IDLE;
		end

		case (h2w_state)
			H2W_IDLE: begin
            playing <= 1'b0;
				if (~old_play && HTP_FUNC[0]) begin  //Beginning of HTP Download
					if(HTP_SIZE!=16'h0000 && HT_ADDR != HTP_SIZE) begin
						playing <= 1'b1;
						h2w_state <= H2W_READ_BYTE;
					end
				end
			end
			
			H2W_READ_BYTE: begin
//				htp_playing <= 1'b1;
				if(HT_ADDR != (HTP_SIZE + 1'b1)) begin
					htp_byte <= HT_DATA;
					htp_byte_ptr <= 0;
					HT_ADDR <= HT_ADDR + 1'b1;
					h2w_state <= H2W_GET_NEXT_BIT;
				end
				else h2w_state <= H2W_IDLE;
			end
			
			H2W_GET_NEXT_BIT: begin
				if(htp_byte_ptr == 4'h8) h2w_state <= H2W_READ_BYTE;
				else begin
					if(htp_byte[7]) begin
						htp_pattern <= 13'hF3C;
						htp_pat_ptr <= 4'd1;
					end
					else begin
						htp_pattern <= 13'h1FFC;
						htp_pat_ptr <= 4'h0;
					end
					htp_byte <= htp_byte << 1;
					htp_byte_ptr <= htp_byte_ptr + 1'b1;
					htc_timeout <= 16'h0000;
					h2w_state <= H2W_READ;
				end
			end
			
			H2W_READ: begin
				if(htc_timeout == 16'd8192) begin
					h2w_pulse_cnt <= 4'h0;
					h2w_state <= H2W_IDLE;
				end
				else begin
					if(htp_pat_ptr == 4'd13) h2w_state <= H2W_GET_NEXT_BIT;
					else begin
						if(old_read_tape && ~(cpu_addr==16'hE883 && ~rd_n)) begin
							if(h2w_pulse_cnt == 4'd11) begin
								htc_timeout <= 16'h0000;
								h2w_pulse_cnt <= 4'h0;
								htp_pat_ptr <= htp_pat_ptr + 1'b1;
								htp_pattern <= htp_pattern >> 1;
							end
							else h2w_pulse_cnt <= h2w_pulse_cnt + 1'b1;
						end
						else htc_timeout <= htc_timeout + 1'b1;
					end
				end
			end
		endcase
	end
end

assign htp_playing = playing;

reg   [7:0] adec[32];
initial begin
	// 16K ROM/48K RAM
	adec[0] = 8'hBF;  //0000 - 07FF
	adec[1] = 8'hBF;  //0800 - 0FFF
	adec[2] = 8'hDF;  //1000 - 17FF
	adec[3] = 8'hDF;  //1800 - 1FFF
	adec[4] = 8'hEF;  //2000 - 27FF
	adec[5] = 8'hEF;  //2800 - 2FFF
	adec[6] = 8'hF7;  //3000 - 37FF
	adec[7] = 8'hF7;  //3800 - 3FFF
	adec[8] = 8'hFD;  //4000 - 47FF
	adec[9] = 8'hFD;  //4800 - 4FFF
	adec[10] = 8'hFD; //5000 - 57FF
	adec[11] = 8'hFD; //5800 - 5FFF
	adec[12] = 8'hFD; //6000 - 67FF
	adec[13] = 8'hFD; //6800 - 6FFF
	adec[14] = 8'hFD; //7000 - 77FF
	adec[15] = 8'hFD; //7800 - 7FFF
	adec[16] = 8'hFD; //8000 - 87FF
	adec[17] = 8'hFD; //8800 - 8FFF
	adec[18] = 8'hFD; //9000 - 97FF
	adec[19] = 8'hFD; //9800 - 9FFF
	adec[20] = 8'hFD; //A000 - A7FF
	adec[21] = 8'hFD; //A800 - AFFF
	adec[22] = 8'hFD; //B000 - B7FF
	adec[23] = 8'hFD; //B800 - BFFF
	adec[24] = 8'hFD; //C000 - C7FF
	adec[25] = 8'hFD; //C800 - CFFF
	adec[26] = 8'hFD; //D000 - D7FF
	adec[27] = 8'hFD; //D800 - DFFF
	adec[28] = 8'hFD; //E000 - E7FF
	adec[29] = 8'h7F; //E800 - EFFF
	adec[30] = 8'hFD; //F000 - F7FF
	adec[31] = 8'hFE; //F800 - FFFF
end

wire  [7:0] adec_q = (~mreq_n & rfsh_n) ? adec[cpu_addr[15:11]] : 8'hFF;
assign cpu_din = ~&adec_q[6:3] ? rom_dout :
                  ~adec_q[1]   ? ram_dout :
                  ~adec_q[0]   ? mem_banking ? vram_dout : ram_dout:
                  ~adec_q[7]   ? mem_banking ? cpu_addr[7:0]==8'h83 ? h2w_state != H2W_IDLE ? h2w_tape_bit : CASS_IN : {4'hF, cpu_addr[4] ? 4'hF : key_matrix[cpu_addr[3:0]]} : ram_dout :
                  8'h00;
assign ram_we = ~wr_n && (~adec_q[1] || ((adec_q[0] == 1'b0 || adec_q[7] == 1'b0) && mem_banking == 1'b0));
assign vs_n = ~(adec_q[0] == 1'b0 && mem_banking);

//MEM Banking
reg mem_banking;

always @(posedge CLK) begin
	if (RESET) mem_banking <= 1'b0;
	else begin
		if (cpu_addr[7:0] == 8'h7F && ~wr_n && ~iorq_n) mem_banking <= 1'b0;
		if (cpu_addr[7:0] == 8'hFF && ~wr_n && ~iorq_n) mem_banking <= 1'b1;
	end
end

always @(posedge CLK) begin : BEEP
	reg ks_old;
	ks_old <= adec_q[7];
	if (~ks_old & adec_q[7]) AUDIO[1] <= cpu_addr[7];
end

//Tape audio
assign AUDIO[0] = h2w_state != H2W_IDLE ? h2w_tape_bit : CASS_IN;

reg  [3:0] key_matrix[16];

always @(posedge CLK) begin : KEYBOARD
	if(RESET) begin
		integer i;
		for (i=0;i<16;i=i+1) begin
			key_matrix[i] <= 4'hF;
		end
	end else begin
		key_matrix[2][0] <= int_n;
		key_matrix[3][0] <= h2w_state != H2W_IDLE ? h2w_tape_bit : CASS_IN;
		if (KEY_STROBE) begin
			case (KEY_CODE)
				8'h72: key_matrix[0][0] <= ~KEY_PRESSED; //down
				8'h75: key_matrix[0][1] <= ~KEY_PRESSED; //up
				8'h74: key_matrix[0][2] <= ~KEY_PRESSED; //right
				8'h6B: key_matrix[0][3] <= ~KEY_PRESSED; //left
				8'h29: key_matrix[1][0] <= ~KEY_PRESSED; //space
				8'h5A: key_matrix[1][1] <= ~KEY_PRESSED; //CR
				8'h12: key_matrix[2][1] <= ~KEY_PRESSED; //lshift
				8'h59: key_matrix[2][2] <= ~KEY_PRESSED; //rshift
				8'h11: key_matrix[2][3] <= ~KEY_PRESSED; //alt
				8'h06: key_matrix[3][1] <= ~KEY_PRESSED; //F2
				8'h05: key_matrix[3][2] <= ~KEY_PRESSED; //F1
				8'h45: key_matrix[4][0] <= ~KEY_PRESSED; //0
				8'h16: key_matrix[4][1] <= ~KEY_PRESSED; //1
				8'h1E: key_matrix[4][2] <= ~KEY_PRESSED; //2
				8'h26: key_matrix[4][3] <= ~KEY_PRESSED; //3
				8'h25: key_matrix[5][0] <= ~KEY_PRESSED; //4
				8'h2E: key_matrix[5][1] <= ~KEY_PRESSED; //5
				8'h36: key_matrix[5][2] <= ~KEY_PRESSED; //6
				8'h3D: key_matrix[5][3] <= ~KEY_PRESSED; //7
				8'h3E: key_matrix[6][0] <= ~KEY_PRESSED; //8
				8'h46: key_matrix[6][1] <= ~KEY_PRESSED; //9
				8'h54: key_matrix[6][2] <= ~KEY_PRESSED; //:
				8'h5B: key_matrix[6][3] <= ~KEY_PRESSED; //;
				8'h41: key_matrix[7][0] <= ~KEY_PRESSED; //,
				8'h5D: key_matrix[7][1] <= ~KEY_PRESSED; //=
				8'h49: key_matrix[7][2] <= ~KEY_PRESSED; //.
				8'h4A: key_matrix[7][3] <= ~KEY_PRESSED; //?
				8'h0E: key_matrix[8][0] <= ~KEY_PRESSED; //Promt
				8'h1C: key_matrix[8][1] <= ~KEY_PRESSED; //A
				8'h52: key_matrix[8][2] <= ~KEY_PRESSED; //Á
				8'h32: key_matrix[8][3] <= ~KEY_PRESSED; //B
				8'h21: key_matrix[9][0] <= ~KEY_PRESSED; //C
				8'h23: key_matrix[9][1] <= ~KEY_PRESSED; //D
				8'h24: key_matrix[9][2] <= ~KEY_PRESSED; //E
				8'h4C: key_matrix[9][3] <= ~KEY_PRESSED; //É
				8'h2B: key_matrix[10][0] <= ~KEY_PRESSED; //F
				8'h34: key_matrix[10][1] <= ~KEY_PRESSED; //G
				8'h33: key_matrix[10][2] <= ~KEY_PRESSED; //H
				8'h43: key_matrix[10][3] <= ~KEY_PRESSED; //I
				8'h3B: key_matrix[11][0] <= ~KEY_PRESSED; //J
				8'h42: key_matrix[11][1] <= ~KEY_PRESSED; //K
				8'h4B: key_matrix[11][2] <= ~KEY_PRESSED; //L
				8'h3A: key_matrix[11][3] <= ~KEY_PRESSED; //M
				8'h31: key_matrix[12][0] <= ~KEY_PRESSED; //N
				8'h44: key_matrix[12][1] <= ~KEY_PRESSED; //O
				8'h0B: key_matrix[12][2] <= ~KEY_PRESSED; //Ó
				8'h83: key_matrix[12][3] <= ~KEY_PRESSED; //Ö
				8'h4D: key_matrix[13][0] <= ~KEY_PRESSED; //P
				8'h15: key_matrix[13][1] <= ~KEY_PRESSED; //Q
				8'h2D: key_matrix[13][2] <= ~KEY_PRESSED; //R
				8'h1B: key_matrix[13][3] <= ~KEY_PRESSED; //S
				8'h2C: key_matrix[14][0] <= ~KEY_PRESSED; //T
				8'h3C: key_matrix[14][1] <= ~KEY_PRESSED; //U
				8'h4E: key_matrix[14][2] <= ~KEY_PRESSED; //Ü
				8'h2A: key_matrix[14][3] <= ~KEY_PRESSED; //V
				8'h1D: key_matrix[15][0] <= ~KEY_PRESSED; //W
				8'h22: key_matrix[15][1] <= ~KEY_PRESSED; //X
				8'h35: key_matrix[15][2] <= ~KEY_PRESSED; //Y
				8'h1A: key_matrix[15][3] <= ~KEY_PRESSED; //Z
			endcase
		end
	end
end

endmodule
