`timescale 1ns/10ps
module DT(
	input 			clk, 
	input			reset,
	output	reg		done ,
	output	reg		sti_rd ,
	output	reg 	[9:0]	sti_addr ,
	input		[15:0]	sti_di,
	output	reg		res_wr ,
	output	reg		res_rd ,
	output	reg 	[13:0]	res_addr ,
	output	reg 	[7:0]	res_do,
	input		[7:0]	res_di,
	output  reg fwpass_finish
	);

reg[3:0] current_state;
reg[3:0] next_state;
// counter - 讀取[15:0]的sti_di
reg[3:0] counter;
reg[5:0] min;

parameter INIT = 4'd0;
// 寫ROM進去RAM
parameter READ_ROM_I = 4'd1;
parameter READ_ROM = 4'd2;
// FOWARD運算
parameter FORWARD_R = 4'd3;
parameter FORWARD = 4'd4;
parameter FORWARD_W = 4'd5;
parameter FORWARD_FINISH = 4'd6;
// BACKWARD運算
parameter BACKWARD = 4'd7;

always@(posedge clk or negedge reset)
begin
	if(!reset) current_state <= INIT;
	else current_state <= next_state;
end 


// 先下值再拉enable
always@(*)
begin
	case(current_state)
	INIT:
	begin
		next_state = READ_ROM_I;
	end
	READ_ROM_I:
	begin
		next_state = READ_ROM;
	end
	// 跑 [15:0] counter，跑完了就回去READ_ROM_I檢查
	READ_ROM:
	begin
		if(counter == 4'd15) 
		begin 
			if(res_addr == 14'd16383) next_state = FORWARD_R;
			else next_state = READ_ROM_I; 
		end
        else next_state = READ_ROM;
	end

    FORWARD_R:
	begin
		if(res_addr == 14'd16254) next_state = FORWARD_FINISH;
		// 如果是1的話才要做，0的話不能做這樣會出錯
        else if(res_di == 8'd1) next_state = FORWARD;
		else next_state = FORWARD_R;
	end

    FORWARD:
    begin
		if(counter == 14'd5) next_state = FORWARD_W;
        else next_state = FORWARD;
	end

    FORWARD_W:
    begin
		next_state = FORWARD_R;
	end

	FORWARD_FINISH:
	begin
		next_state = BACKWARD;
	end

	BACKWARD:
	begin
		next_state = BACKWARD;
	end

	default: next_state = INIT;
	endcase
end

// sti_rd - enable ROM_R
always@(posedge clk or negedge reset)
begin 
	if(!reset)	sti_rd <= 1'd0;
	else if(next_state == READ_ROM_I) sti_rd <= 1'd1;
	else sti_rd <= 1'd0;
end

// sti_addr - ROM address
always@(posedge clk or negedge reset)
begin
	if(!reset) sti_addr <= 10'd0;
	else if(current_state == READ_ROM_I || current_state == FORWARD_R) sti_addr <= sti_addr + 1'd1;
	else sti_addr <= sti_addr;
end 

// res_addr - RAM address
always@(posedge clk or negedge reset)
begin
	if(!reset) res_addr <= 14'd16383;
	else if(next_state == FORWARD_R && res_addr == 14'd16383) res_addr <= 14'd128;
	else if(next_state == READ_ROM ) res_addr <= res_addr + 1'd1;
	else if(next_state == FORWARD_R) res_addr <= res_addr + 1'd1;
    else if(next_state == FORWARD)
    begin
        case(counter)
        4'd0:res_addr <= res_addr - 14'd129;
        4'd1:res_addr <= res_addr + 14'd1;
        4'd2:res_addr <= res_addr + 14'd1;
        4'd3:res_addr <= res_addr + 14'd126;
        4'd4:res_addr <= res_addr + 14'd1;
		default: res_addr <= res_addr;
        endcase
    end
	// else if(current_state == FORWARD_FINISH) res_addr <= 14'd16254;
	else if(current_state == BACKWARD || current_state == FORWARD_FINISH ) 
	begin
		case(counter)
        4'd0:res_addr <= res_addr + 14'd129;
        4'd1:res_addr <= res_addr - 14'd1;
        4'd2:res_addr <= res_addr - 14'd1;
        4'd3:res_addr <= res_addr - 14'd126;
        4'd4:res_addr <= res_addr - 14'd1;
		4'd7:res_addr <= res_addr - 14'd1;
		default: res_addr <= res_addr;
        endcase
	end
	else res_addr <= res_addr;
end 

// counter - count for ROM data
always@(posedge clk or negedge reset)
begin 
	if(!reset) counter <= 4'd15;
	else if(next_state == READ_ROM) counter <= counter - 1'd1;
	else if(next_state == READ_ROM_I) counter <= 4'd15;
	// !!current_state可能還是3
    else if(next_state == FORWARD) counter <= counter + 1'd1;
	else if(next_state == BACKWARD && counter != 4'd7) counter <= counter + 1'd1;
	else counter <= 4'd0;
end

// res_rd - enable RAM -> DT 
always@(posedge clk or negedge reset)
begin 
	if(!reset) res_rd <= 1'd0;
	// 如果下一步是讀取相關的話就要打開
	else if(next_state == FORWARD_R || next_state == FORWARD || next_state == BACKWARD) res_rd <= 1'd1;
	else res_rd <= 1'd0;
end  

// res_wr - enable ROM -> DT 
always@(posedge clk or negedge reset)
begin 
	if(!reset) res_wr <= 1'd0;
	else if(next_state == READ_ROM || next_state == FORWARD_W) res_wr <= 1'd1;
	else if(current_state == BACKWARD && counter == 4'd6) res_wr <= 1'd1;
	else res_wr <= 1'd0;
end

// res_do - DT -> RAM
always@(posedge clk or negedge reset)
begin 
	if(!reset) res_do <= 8'd0;
	else if(next_state == READ_ROM || current_state == READ_ROM) res_do <= sti_di[counter];
	else if(next_state == FORWARD_W) res_do<= min + 8'd1;
	else if(next_state == BACKWARD) res_do <= min;
	else res_do <= 8'd0;
end

// min - record minumum pixel
always@(posedge clk or negedge reset)
begin 
	if(!reset) min <= 6'd0;
	else if(current_state == FORWARD) 
    begin
        if(counter == 4'd1) min <= res_di;
        else if(res_di < min) min <= res_di;
    end
	else if(next_state == BACKWARD)
	begin 
		if(counter == 4'd1) min <= res_di + 1;
		else if(counter != 4'd5)
			begin
				if(res_di + 1 < min) min <= res_di + 1;
			end
		else 
			begin
				if(res_di < min) min <= res_di;
			end
	end
	else min <= 8'd0;
end

// fwpass_finish 
always@(posedge clk or negedge reset)
begin 
	if(!reset) fwpass_finish <= 1'd0;
	else if(next_state == FORWARD_FINISH) fwpass_finish <= 1'd1;
	else fwpass_finish <= 1'd0;
end

// Done
always@(posedge clk or negedge reset)
begin
	if(!reset) done <= 1'd0;
	else if(next_state == BACKWARD && res_addr == 14'd128) done <= 1'd1;
	else done <= 1'd0;
end

endmodule
