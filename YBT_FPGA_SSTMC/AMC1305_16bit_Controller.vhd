LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.all;
USE IEEE.STD_LOGIC_arith.all;
USE IEEE.STD_LOGIC_signed.all;
USE IEEE.NUMERIC_STD.all;

ENTITY AMC1305_16bit_Controller IS
    PORT(
        RESET		: IN  STD_LOGIC;
        CLK_120MHZ	: IN  STD_LOGIC;		
        AMC1_SCLK	: OUT STD_LOGIC;
        AMC2_SCLK	: OUT STD_LOGIC;		
        AMC1_DOUT	: IN  STD_LOGIC;
        AMC2_DOUT	: IN  STD_LOGIC;		
        DATA_16BIT1	: OUT STD_LOGIC_VECTOR(15 downto 0);
        DATA_16BIT2	: OUT STD_LOGIC_VECTOR(15 downto 0);
        DATA_16BIT3	: OUT STD_LOGIC_VECTOR(15 downto 0);
		OUT_UdGY	: OUT STD_LOGIC
        --OUT_VALID	: OUT STD_LOGIC
    );
END AMC1305_16bit_Controller;

ARCHITECTURE BEHAV OF AMC1305_16bit_Controller IS

CONSTANT OSR_VAL      : INTEGER := 20000;
CONSTANT NUMD	:	INTEGER	:= 20;
CONSTANT NUMW	:	INTEGER	:= 11; 

SIGNAL clk_div_cnt	    : INTEGER RANGE 0 TO 15;
SIGNAL sclk_internal    : STD_LOGIC := '0';

SIGNAL CH1_dout_sync1   : STD_LOGIC := '0';
SIGNAL CH1_dout_sync2   : STD_LOGIC := '0';

SIGNAL CH2_dout_sync1   : STD_LOGIC := '0';
SIGNAL CH2_dout_sync2   : STD_LOGIC := '0';

SIGNAL osr_cnt		    : INTEGER range -131071 to 131071 := 0; 

SIGNAL CH1_H_level_cnt   : INTEGER range -131071 to 131071 := 0;
SIGNAL CH1_data_OUT_reg  : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');

SIGNAL CH2_H_level_cnt   : INTEGER range -131071 to 131071 := 0;
SIGNAL CH2_data_OUT_reg  : STD_LOGIC_VECTOR(15 downto 0) := (others => '0');

SIGNAL DATA_VALID	: STD_LOGIC:= '0';
SIGNAL sig_UdGY	    : STD_LOGIC:= '0';

--------------------------- COMPONENT ---------------------------
SIGNAL CLKram	    : STD_LOGIC := '0';
SIGNAL Weram	    : STD_LOGIC := '0';
SIGNAL addrUdt	    : STD_LOGIC_VECTOR(NUMW-1 downTO 0) := (OTHERS=>'0');
SIGNAL CH1_FFndt, CH1_FFodt : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS=>'0');
SIGNAL CH2_FFndt, CH2_FFodt : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS=>'0');

COMPONENT RAM_16_2048
	PORT
	(
		aclr		: IN STD_LOGIC  := '0';
		address		: IN STD_LOGIC_VECTOR (NUMW-1 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		    : OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
	);
END COMPONENT;
-----------------------------------------------------------------

BEGIN

OUT_UdGY<=sig_UdGY;

PROCESS(RESET, CLK_120MHZ)
VARIABLE var_cnt : INTEGER RANGE 0 TO 15 := 0;
BEGIN
    IF RESET = '1' THEN
        var_cnt := 0;
        clk_div_cnt <= 0;
        sclk_internal <= '0';
    ELSIF rising_edge(CLK_120MHZ) THEN
        var_cnt := var_cnt + 1;
        CASE var_cnt IS 
            WHEN 1  => sclk_internal <= '1';
            WHEN 4  => sclk_internal <= '0';
            WHEN 6  => var_cnt := 0;
            WHEN OTHERS => NULL;
        END CASE;
    END IF;		
END PROCESS;

AMC1_SCLK <= sclk_internal;
AMC2_SCLK <= sclk_internal;

PROCESS(RESET, CLK_120MHZ)
BEGIN
    IF RESET = '1' THEN
        CH1_dout_sync1 <= '0';
        CH1_dout_sync2 <= '0';
    ELSIF rising_edge(CLK_120MHZ) THEN
        CH1_dout_sync1 <= AMC1_DOUT;
        CH1_dout_sync2 <= CH1_dout_sync1;
    END IF;
END PROCESS;

PROCESS(RESET, CLK_120MHZ)
BEGIN
    IF RESET = '1' THEN
        CH2_dout_sync1 <= '0';
        CH2_dout_sync2 <= '0';
    ELSIF rising_edge(CLK_120MHZ) THEN
        CH2_dout_sync1 <= AMC2_DOUT;
        CH2_dout_sync2 <= CH2_dout_sync1;
    END IF;
END PROCESS;

PROCESS(RESET, CLK_120MHZ)
BEGIN
    IF RESET = '1' THEN
        DATA_VALID <= '0';
        osr_cnt <= 0;				
        CH1_H_level_cnt <= 0;
        CH1_data_OUT_reg <= (others => '0');
        CH2_H_level_cnt <= 0;
        CH2_data_OUT_reg <= (others => '0');		
    ELSIF rising_edge(CLK_120MHZ) THEN
        DATA_VALID <= '0';
        IF clk_div_cnt = 0 AND sclk_internal = '0' THEN
            IF CH1_dout_sync2 = '1' THEN
                CH1_H_level_cnt <= CH1_H_level_cnt + 1;
            END IF;
            IF CH2_dout_sync2 = '1' THEN
                CH2_H_level_cnt <= CH2_H_level_cnt + 1;
            END IF;           

            osr_cnt <= osr_cnt + 1;            

            IF osr_cnt = OSR_VAL THEN
                CH1_data_OUT_reg <= CONV_STD_LOGIC_VECTOR(CH1_H_level_cnt - OSR_VAL/2, 16);
                CH2_data_OUT_reg <= CONV_STD_LOGIC_VECTOR(CH2_H_level_cnt - OSR_VAL/2, 16);
                DATA_VALID <= '1';
                osr_cnt <= 0;
                CH1_H_level_cnt <= 0;
                CH2_H_level_cnt <= 0;
            END IF;
        END IF;
    END IF;
END PROCESS;

P_Ulpf: PROCESS(RESET, CLK_120MHZ)
	VARIABLE CH1_var_rst   : INTEGER RANGE -65535 TO 65535 := 0;
	VARIABLE CH2_var_rst   : INTEGER RANGE -65535 TO 65535 := 0;
	VARIABLE add_rst       : INTEGER RANGE -65535 TO 65535 := 0;

	VARIABLE CH1_uadd      : INTEGER RANGE -127459327 TO 127459327 := 0;
	VARIABLE CH2_uadd      : INTEGER RANGE -127459327 TO 127459327 := 0;

	VARIABLE Index         : INTEGER RANGE 0 TO NUMD-1 := 0;
	VARIABLE Step          : INTEGER RANGE 0 TO 15 := 0;
BEGIN
	IF RESET = '1' THEN
		CLKram    <= '0';
		Weram   <= '0';
		addrUdt   <= (OTHERS => '0');			
		CH1_FFndt <= (OTHERS => '0');
		CH2_FFndt <= (OTHERS => '0');

		CH1_uadd := 0;
		CH2_uadd := 0;
		Index    := 0;
		Step     := 0;

		DATA_16BIT1 <= (OTHERS => '0');
		DATA_16BIT2 <= (OTHERS => '0');
		DATA_16BIT3 <= (OTHERS => '0');
		sig_UdGY    <= '0';
		--OUT_VALID   <= '0';

	ELSIF rising_edge(CLK_120MHZ) THEN
		CASE Step IS
			WHEN 0 =>
				IF DATA_VALID = '1' THEN
					Step     := 1;
					Weram  <= '0';
					--OUT_VALID <= '0';		
					addrUdt  <= CONV_STD_LOGIC_VECTOR(Index, NUMW);	
					CH1_FFndt <= CH1_data_OUT_reg;
					CH2_FFndt <= CH2_data_OUT_reg;
				END IF;	
						
			WHEN 1 => Step := 2;
			WHEN 2 => Step := 3; CLKram <= '1';
			WHEN 3 => Step := 4;
			WHEN 4 => Step := 5; CLKram <= '0';

			WHEN 5 =>
				Step := 6;
				CH1_uadd := CH1_uadd - CONV_INTEGER(CH1_FFodt) + CONV_INTEGER(CH1_FFndt);
				CH2_uadd := CH2_uadd - CONV_INTEGER(CH2_FFodt) + CONV_INTEGER(CH2_FFndt);
				Weram  <= '1';
																
			WHEN 6 => Step := 7;
			WHEN 7 =>
				Step := 8;
				CLKram <= '1';
				CH1_var_rst := (CH1_uadd + NUMD/2) / NUMD;
				CH2_var_rst := (CH2_uadd + NUMD/2) / NUMD;
				add_rst     := CH1_var_rst + CH2_var_rst;
						
			WHEN 8 =>
				Step := 9;
				IF CH1_var_rst >= 32767 THEN
					DATA_16BIT1 <= CONV_STD_LOGIC_VECTOR(32767, 16);
				ELSIF CH1_var_rst <= -32767 THEN
					DATA_16BIT1 <= CONV_STD_LOGIC_VECTOR(-32767, 16);
				ELSE
					DATA_16BIT1 <= CONV_STD_LOGIC_VECTOR(CH1_var_rst, 16);
				END IF;

				IF CH2_var_rst >= 32767 THEN
					DATA_16BIT2 <= CONV_STD_LOGIC_VECTOR(32767, 16);
				ELSIF CH2_var_rst <= -32767 THEN
					DATA_16BIT2 <= CONV_STD_LOGIC_VECTOR(-32767, 16);
				ELSE
					DATA_16BIT2 <= CONV_STD_LOGIC_VECTOR(CH2_var_rst, 16);
				END IF;

				IF add_rst >= 32767 THEN
					DATA_16BIT3 <= CONV_STD_LOGIC_VECTOR(32767, 16);
				ELSIF add_rst <= -32767 THEN
					DATA_16BIT3 <= CONV_STD_LOGIC_VECTOR(-32767, 16);
				ELSE
					DATA_16BIT3 <= CONV_STD_LOGIC_VECTOR(add_rst, 16);
				END IF;
				
				--DATA_16BIT3=1.2*N*Ud/R,R=7*510,
				-----------------------------------------------------------------------
				IF(sig_UdGY='1') THEN
					IF(add_rst<13132) THEN		--1680,11294/0.86
						sig_UdGY<='0';		
					END IF;
				ELSE
					IF(add_rst>13290) THEN		--1700,11429/0.86
						sig_UdGY<='1';		
					END IF;
				END IF;
				-----------------------------------------------------------------------
						
			WHEN 9 =>
				Step := 10;
				CLKram <= '0';
				--OUT_VALID <= '1';
				IF Index = NUMD-1 THEN
					Index := 0;
				ELSE
					Index := Index + 1;
				END IF;						
							
			WHEN 10 =>
				IF DATA_VALID = '0' THEN
					Step := 0;
				END IF;

			WHEN OTHERS => NULL;
		END CASE;
	END IF;	
END PROCESS P_Ulpf;

U_RAM_CH1 : RAM_16_2048 PORT map(
			aclr	  => RESET,
			address   => addrUdt,
			clock	  => CLKram,
			data	  => CH1_FFndt,
			wren	  => Weram,
			q		  => CH1_FFodt
);
			
U_RAM_CH2 : RAM_16_2048 PORT map(
			aclr	  => RESET,
			address   => addrUdt,
			clock	  => CLKram,
			data	  => CH2_FFndt,
			wren	  => Weram,
			q		  => CH2_FFodt
);		

END BEHAV;