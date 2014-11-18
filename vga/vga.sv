// vga.sv
// 20 October 2011 Karl_Wang & David_Harris@hmc.edu
// VGA driver with character generator

module vga(input  logic       clk, sdi, sck,
			  output logic       vgaclk,						// 25 MHz VGA clock
			  output logic       hsync, vsync, sync_b,	// to monitor & DAC
			  output logic [7:0] r, g, b);					// to video DAC
 
  logic [9:0] x, y;
  logic [7:0] r_int, g_int, b_int;
	
  // Use a PLL to create the 25.175 MHz VGA pixel clock 
  // 25.175 Mhz clk period = 39.772 ns
  // Screen is 800 clocks wide by 525 tall, but only 640 x 480 used for display
  // HSync = 1/(39.772 ns * 800) = 31.470 KHz
  // Vsync = 31.474 KHz / 525 = 59.94 Hz (~60 Hz refresh rate)
  pll	vgapll(.inclk0(clk),	.c0(vgaclk)); 
  
  pll	pll_inst (
	.areset ( areset_sig ),
	.inclk0 ( inclk0_sig ),
	.c0 ( c0_sig ),
	.locked ( locked_sig )
  );

  // generate monitor timing signals
  vgaController vgaCont(vgaclk, hsync, vsync, sync_b,  
                        r_int, g_int, b_int, r, g, b, x, y);
	
  // user-defined module to determine pixel color
  videoGen videoGen(x, y, sdi, sck, r_int, g_int, b_int);
endmodule

module vgaController #(parameter HMAX   = 10'd800,
                                 VMAX   = 10'd525, 
											HSTART = 10'd152,
											WIDTH  = 10'd640,
											VSTART = 10'd37,
											HEIGHT = 10'd480)
						  (input  logic       vgaclk, 
                     output logic       hsync, vsync, sync_b,
							input  logic [7:0] r_int, g_int, b_int,
							output logic [7:0] r, g, b,
							output logic [9:0] x, y);

  logic [9:0] hcnt, vcnt;
  logic       oldhsync;
  logic       valid;
  
  // counters for horizontal and vertical positions
  always @(posedge vgaclk) begin
    if (hcnt >= HMAX) hcnt = 0;
    else hcnt++;
	 if (hsync & ~oldhsync) begin // start of hsync; advance to next row
	   if (vcnt >= VMAX) vcnt = 0;
      else vcnt++;
    end
    oldhsync = hsync;
  end
  
  // compute sync signals (active low)
  assign hsync = ~(hcnt >= 10'd8 & hcnt < 10'd104); // horizontal sync
  assign vsync = ~(vcnt >= 2 & vcnt < 4); // vertical sync
  assign sync_b = hsync | vsync;

  // determine x and y positions
  assign x = hcnt - HSTART;
  assign y = vcnt - VSTART;
  
  // force outputs to black when outside the legal display area
  assign valid = (hcnt >= HSTART & hcnt < HSTART+WIDTH &
                  vcnt >= VSTART & vcnt < VSTART+HEIGHT);
  assign {r,g,b} = valid ? {r_int,g_int,b_int} : 24'b0;
endmodule

module videoGen(input  logic [9:0] x, y,
					 input  logic sdi, sck,
           		 output logic [7:0] r_int, g_int, b_int);
	
  logic whiteKey, blackKey, whitePressedKey, blackPressedKey;
  logic inCursorRect, pixel;

  logic [9:0] xPos, yPos; //For tracking mouse
  
  logic [31:0] out; //Stores feedback from the SPI connection
  
  assign xPos = out[25:16]; //Because x was sent first
  assign yPos = out[9:0]; //Because y was sent second  
 
  spi_slave_receive_only mySPI(sck, sdi, out);
  
  rectGen cursorRect(x, y, xPos, yPos, xPos + 10'd12, yPos + 10'd8, inCursorRect);
  chargenrom2 myCursor(x-xPos, y-yPos, inCursorRect, pixel); 

  keyboard myBoard(x, y, xPos, yPos, whiteKey, blackKey, whitePressedKey, blackPressedKey);
  
  always_comb begin
		if(inCursorRect & pixel) begin
			{r_int, g_int, b_int} = {{8{1'b0}}, {8{pixel}}, {8{1'b0}}};
		end
		else begin
			{r_int, g_int, b_int} = {{8{(whiteKey  & ~blackKey) | blackPressedKey}}, {8{~blackKey & ~whitePressedKey}}, {8{~blackKey & ~whitePressedKey}}};
		end
  end
  
 /* rectGen cursorRect(x, y, xPos, yPos, xPos + 10'd12, yPos + 10'd8, inCursorRect);
  chargenrom2 myCursor(x-xPos, y-yPos, inCursorRect, pixel);  
  rectGen myRect(x, y, 10'd120, 10'd128, 10'd287, 10'd215, inLittleRect);
  rectGen myRect2(x, y, 10'd120, 10'd128, 10'd450, 10'd335, inBigRect);
  always_comb begin
	if(inCursorRect) begin
		{r_int, g_int, b_int} = {{8{1'b0}}, {8{pixel}}, {8{1'b0}}};
	end
	else if(inLittleRect) begin
		{r_int, g_int, b_int} = (y[3] == 1 & x[3] == 0) ? {24{1'b1}} : 
	                                           {16'h0000, {8{1'b1}}};
	end
	else if(inBigRect) begin
		{r_int, g_int, b_int} = (y[4]==0) ? {{8{1'b1}},16'h0000} : 
	                                           {24{1'b1}}; 
	end
	else begin
		{r_int, g_int, b_int} = {24'h0000};
	end
  end*/
endmodule

module keyboard(input logic [9:0] x, y, xMouse, yMouse,
					output logic isWhite, isBlack, whiteIsRed, blackIsRed);
	
	logic [9:0]startX, startXB, startY, width, widthB, nextW, height, heightB;
	logic latentBlack; // Says that a black key is pressed somewhere (not necessarily at (x,y))
	
	assign startX = 10'd20;	
	assign startY = 10'd175;
	assign width = 10'd25;
	assign nextW = 10'd27;
	assign height = 10'd150;
	
	assign startXB = 10'd38;
	assign widthB = 10'd16;
	assign heightB = 10'd70;
	
	logic inMiddleC, inMiddleD, inMiddleE, inMiddleF, inMiddleG, inNextA, inNextB, inNextC, inNextD, inNextE, inNextF, inNextG;
	logic inThirdA, inThirdB, inThirdC, inThirdD, inThirdE, inThirdF, inThirdG, inLastA, inLastB, inLastC;
	logic tinMiddleC, tinMiddleD, tinMiddleE, tinMiddleF, tinMiddleG, tinNextA, tinNextB, tinNextC, tinNextD, tinNextE, tinNextF, tinNextG;
	logic tinThirdA, tinThirdB, tinThirdC, tinThirdD, tinThirdE, tinThirdF, tinThirdG, tinLastA, tinLastB, tinLastC;
	logic isMiddleC, isMiddleD, isMiddleE, isMiddleF, isMiddleG, isNextA, isNextB, isNextC, isNextD, isNextE, isNextF, isNextG;
	logic isThirdA, isThirdB, isThirdC, isThirdD, isThirdE, isThirdF, isThirdG, isLastA, isLastB, isLastC;
	
	logic inMiddleCS, inMiddleDS, inMiddleFS, inMiddleGS, inNextAS, inNextCS, inNextDS, inNextFS, inNextGS;
	logic inThirdAS, inThirdCS, inThirdDS, inThirdFS, inThirdGS, inLastAS, inLastCS;
	logic tinMiddleCS, tinMiddleDS, tinMiddleFS, tinMiddleGS, tinNextAS, tinNextCS, tinNextDS, tinNextFS, tinNextGS;
	logic tinThirdAS, tinThirdCS, tinThirdDS, tinThirdFS, tinThirdGS, tinLastAS, tinLastCS;
	logic isMiddleCS, isMiddleDS, isMiddleFS, isMiddleGS, isNextAS, isNextCS, isNextDS, isNextFS, isNextGS;
	logic isThirdAS, isThirdCS, isThirdDS, isThirdFS, isThirdGS, isLastAS, isLastCS;
	
	//Create all 22 white keys
	rectGenPlus middleC(x, y, xMouse, yMouse, 	startX ,						startY, startX + width, 					startY + height, inMiddleC, tinMiddleC, isMiddleC);
	rectGenPlus middleD(x, y, xMouse, yMouse, 	startX + 10'd1*nextW, 	startY, startX + 10'd1*nextW + width, 	startY + 10'd1*height, inMiddleD, tinMiddleD, isMiddleD);
	rectGenPlus middleE(x, y, xMouse, yMouse,  startX + 10'd2*nextW, 	startY, startX + 10'd2*nextW + width, 	startY + 10'd1*height, inMiddleE, tinMiddleE, isMiddleE);
	rectGenPlus middleF(x, y, xMouse, yMouse,  startX + 10'd3*nextW, 	startY, startX + 10'd3*nextW + width, 	startY + 10'd1*height, inMiddleF, tinMiddleF, isMiddleF);
	rectGenPlus middleG(x, y, xMouse, yMouse,  startX + 10'd4*nextW, 	startY, startX + 10'd4*nextW + width, 	startY + 10'd1*height, inMiddleG, tinMiddleG, isMiddleG);
	rectGenPlus nextA(x, y, xMouse, yMouse,  	startX + 10'd5*nextW, 	startY, startX + 10'd5*nextW + width, 	startY + 10'd1*height, inNextA, tinNextA, isNextA);
	rectGenPlus nextB(x, y, xMouse, yMouse,  	startX + 10'd6*nextW, 	startY, startX + 10'd6*nextW + width, 	startY + 10'd1*height, inNextB, tinNextB, isNextB);
	rectGenPlus nextC(x, y, xMouse, yMouse,  	startX + 10'd7*nextW, 	startY, startX + 10'd7*nextW + width, 	startY + 10'd1*height, inNextC, tinNextC, isNextC);
	rectGenPlus nextD(x, y, xMouse, yMouse,  	startX + 10'd8*nextW, 	startY, startX + 10'd8*nextW + width, 	startY + 10'd1*height, inNextD, tinNextD, isNextD);
	rectGenPlus nextE(x, y, xMouse, yMouse,  	startX + 10'd9*nextW, 	startY, startX + 10'd9*nextW + width, 	startY + 10'd1*height, inNextE, tinNextE, isNextE);
	rectGenPlus nextF(x, y, xMouse, yMouse,  	startX + 10'd10*nextW, 	startY, startX + 10'd10*nextW + width, startY + 10'd1*height, inNextF, tinNextF, isNextF);
	rectGenPlus nextG(x, y, xMouse, yMouse,  	startX + 10'd11*nextW, 	startY, startX + 10'd11*nextW + width, startY + 10'd1*height, inNextG, tinNextG, isNextG);
	rectGenPlus thirdA(x, y, xMouse, yMouse,  	startX + 10'd12*nextW,	startY, startX + 10'd12*nextW + width, startY + 10'd1*height, inThirdA, tinThirdA, isThirdA);
	rectGenPlus thirdB(x, y, xMouse, yMouse,  	startX + 10'd13*nextW, 	startY, startX + 10'd13*nextW + width, startY + 10'd1*height, inThirdB, tinThirdB, isThirdB);
	rectGenPlus thirdC(x, y, xMouse, yMouse,  	startX + 10'd14*nextW, 	startY, startX + 10'd14*nextW + width, startY + 10'd1*height, inThirdC, tinThirdC, isThirdC);
	rectGenPlus thirdD(x, y, xMouse, yMouse,  	startX + 10'd15*nextW, 	startY, startX + 10'd15*nextW + width, startY + 10'd1*height, inThirdD, tinThirdD, isThirdD);
	rectGenPlus thirdE(x, y, xMouse, yMouse,  	startX + 10'd16*nextW, 	startY, startX + 10'd16*nextW + width, startY + 10'd1*height, inThirdE, tinThirdE, isThirdE);
	rectGenPlus thirdF(x, y, xMouse, yMouse,  	startX + 10'd17*nextW, 	startY, startX + 10'd17*nextW + width, startY + 10'd1*height, inThirdF, tinThirdF, isThirdF);
	rectGenPlus thirdG(x, y, xMouse, yMouse,  	startX + 10'd18*nextW, 	startY, startX + 10'd18*nextW + width, startY + 10'd1*height, inThirdG, tinThirdG, isThirdG);
	rectGenPlus lastA(x, y, xMouse, yMouse, 	startX + 10'd19*nextW, 	startY, startX + 10'd19*nextW + width, startY + 10'd1*height, inLastA, tinLastA, isLastA);
	rectGenPlus lastB(x, y, xMouse, yMouse,  	startX + 10'd20*nextW, 	startY, startX + 10'd20*nextW + width, startY + 10'd1*height, inLastB, tinLastB, isLastB);
	rectGenPlus lastC(x, y, xMouse, yMouse,  	startX + 10'd21*nextW, 	startY, startX + 10'd21*nextW + width, startY + 10'd1*height, inLastC, tinLastC, isLastC);

	//Now 16 Black keys
	rectGenPlus middleCS(x, y, xMouse, yMouse, 	startXB,						startY, startXB + widthB, 						startY + heightB, 		inMiddleCS, tinMiddleCS, isMiddleCS);
	rectGenPlus middleDS(x, y, xMouse, yMouse, 	startXB + 10'd1*nextW, 	startY, startXB + 10'd1*nextW + widthB, 	startY + 10'd1*heightB, inMiddleDS, tinMiddleDS, isMiddleDS);
	rectGenPlus middleFS(x, y, xMouse, yMouse,  	startXB + 10'd3*nextW, 	startY, startXB + 10'd3*nextW + widthB, 	startY + 10'd1*heightB, inMiddleFS, tinMiddleFS, isMiddleFS);
	rectGenPlus middleGS(x, y, xMouse, yMouse,  	startXB + 10'd4*nextW, 	startY, startXB + 10'd4*nextW + widthB, 	startY + 10'd1*heightB, inMiddleGS, tinMiddleGS, isMiddleGS);
	rectGenPlus nextAS(x, y, xMouse, yMouse,  		startXB + 10'd5*nextW, 	startY, startXB + 10'd5*nextW + widthB, 	startY + 10'd1*heightB, inNextAS, 	tinNextAS, isNextAS);
	rectGenPlus nextCS(x, y, xMouse, yMouse,  		startXB + 10'd7*nextW, 	startY, startXB + 10'd7*nextW + widthB, 	startY + 10'd1*heightB, inNextCS, 	tinNextCS, isNextCS);
	rectGenPlus nextDS(x, y, xMouse, yMouse,  		startXB + 10'd8*nextW, 	startY, startXB + 10'd8*nextW + widthB, 	startY + 10'd1*heightB, inNextDS, 	tinNextDS, isNextDS);
	rectGenPlus nextFS(x, y, xMouse, yMouse,  		startXB + 10'd10*nextW, startY, startXB + 10'd10*nextW + widthB, 	startY + 10'd1*heightB, inNextFS, 	tinNextFS, isNextFS);
	rectGenPlus nextGS(x, y, xMouse, yMouse,  		startXB + 10'd11*nextW, startY, startXB + 10'd11*nextW + widthB, 	startY + 10'd1*heightB, inNextGS, 	tinNextGS, isNextGS);
	rectGenPlus thirdAS(x, y, xMouse, yMouse,  	startXB + 10'd12*nextW,	startY, startXB + 10'd12*nextW + widthB, 	startY + 10'd1*heightB, inThirdAS, 	tinThirdAS, isThirdAS);
	rectGenPlus thirdCS(x, y, xMouse, yMouse,  	startXB + 10'd14*nextW, startY, startXB + 10'd14*nextW + widthB, 	startY + 10'd1*heightB, inThirdCS, 	tinThirdCS, isThirdCS);
	rectGenPlus thirdDS(x, y, xMouse, yMouse,  	startXB + 10'd15*nextW, startY, startXB + 10'd15*nextW + widthB, 	startY + 10'd1*heightB, inThirdDS, 	tinThirdDS, isThirdDS);
	rectGenPlus thirdFS(x, y, xMouse, yMouse,  	startXB + 10'd17*nextW, startY, startXB + 10'd17*nextW + widthB, 	startY + 10'd1*heightB, inThirdFS, 	tinThirdFS, isThirdFS);
	rectGenPlus thirdGS(x, y, xMouse, yMouse,  	startXB + 10'd18*nextW, startY, startXB + 10'd18*nextW + widthB, 	startY + 10'd1*heightB, inThirdGS, 	tinThirdGS, isThirdGS);
	rectGenPlus lastAS(x, y, xMouse, yMouse, 		startXB + 10'd19*nextW, startY, startXB + 10'd19*nextW + widthB, 	startY + 10'd1*heightB, inLastAS, 	tinLastAS, isLastAS);
	rectGenPlus lastCS(x, y, xMouse, yMouse,  		startXB + 10'd21*nextW, startY, startXB + 10'd21*nextW + widthB, 	startY + 10'd1*heightB, inLastCS, 	tinLastCS, isLastCS);
	
	assign isWhite = inMiddleC | inMiddleD | inMiddleE | inMiddleF | inMiddleG | inNextA | inNextB | inNextC | inNextD | inNextE | inNextF | inNextG | inThirdA | inThirdB | inThirdC | inThirdD | inThirdE | inThirdF | inThirdG | inLastA | inLastB | inLastC;
	assign isBlack = inMiddleCS | inMiddleDS | inMiddleFS | inMiddleGS | inNextAS | inNextCS | inNextDS | inNextFS | inNextGS | inThirdAS | inThirdCS | inThirdDS | inThirdFS | inThirdGS | inLastAS | inLastCS;
	
	assign latentBlack = tinMiddleCS | tinMiddleDS | tinMiddleFS | tinMiddleGS | tinNextAS | tinNextCS | tinNextDS | tinNextFS | tinNextGS | tinThirdAS | tinThirdCS | tinThirdDS | tinThirdFS | tinThirdGS | tinLastAS | tinLastCS;
	
	assign blackIsRed = isMiddleCS | isMiddleDS | isMiddleFS | isMiddleGS | isNextAS | isNextCS | isNextDS | isNextFS | isNextGS | isThirdAS | isThirdCS | isThirdDS | isThirdFS | isThirdGS | isLastAS | isLastCS;
	assign whiteIsRed = ~latentBlack & (isMiddleC | isMiddleD | isMiddleE | isMiddleF | isMiddleG | isNextA | isNextB | isNextC | isNextD | isNextE | isNextF | isNextG | isThirdA | isThirdB | isThirdC | isThirdD | isThirdE | isThirdF | isThirdG | isLastA | isLastB | isLastC);
endmodule
	
module rectGenPlus(input logic[9:0] x, y, xtarget, ytarget, left, top, right, bot,
				output logic inrect, targetInRect, withTarget);
				
	assign targetInRect = (xtarget >= left & xtarget < right & ytarget >= top & ytarget < bot);
	assign inrect = (x >= left & x < right & y >= top & y < bot);
	assign withTarget = targetInRect & inrect;

endmodule

module rectGen(input logic[9:0] x, y, left, top, right, bot,
				output logic inrect);
	
	assign inrect = (x >= left & x < right & y >= top & y < bot);

endmodule

module chargenrom2(input  logic [9:0] xoff, yoff,
						input logic validPoint,
						output logic       pixel);
						
  logic [11:0] charrom2[7:0]; // character generator ROM
  logic [11:0] line;            // a line read from the ROM
  // initialize ROM with characters from text file 
  initial 
	 $readmemb("charrom2.txt", charrom2);
  always_comb begin
	  if (validPoint)
	  begin
		  // index into ROM to find line of character
		  line = {charrom2[yoff]}; 
		  // reverse order of bits
		  pixel = line[10'd11-xoff];
	  end else begin
		line = 7'b0;
		pixel = 1'b0;
	  end
  end
endmodule


module chargenrom(input  logic [7:0] ch,
                  input  logic [2:0] xoff, yoff,
						output logic       pixel);
						
  logic [5:0] charrom[2047:0]; // character generator ROM
  logic [7:0] line;            // a line read from the ROM
  
  // initialize ROM with characters from text file 
  initial 
	 $readmemb("charrom.txt", charrom);
	 
  // index into ROM to find line of character
  assign line = {charrom[yoff+{ch, 3'b000}]}; 
  // reverse order of bits
  assign pixel = line[3'd7-xoff];
endmodule

// If the slave only need to received data from the master
// Slave reduces to a simple shift register given by following HDL: 
module spi_slave_receive_only(input logic sck, //from master
							input logic sdi, //from master 
							output logic[31:0] q); // data received
  logic [4:0] counter;
  logic [31:0] shiftRegister;
  
  always_ff @(posedge sck) begin
	 counter <= counter + 5'b1;
    if (counter == 5'b0)
		q <= shiftRegister;
	 else begin
      shiftRegister <={shiftRegister[30:0], sdi}; //shift register
	 end
  end
endmodule
