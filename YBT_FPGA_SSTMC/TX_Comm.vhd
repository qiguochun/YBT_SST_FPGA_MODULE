LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY TX_Comm IS
GENERIC(
    DELAY    : INTEGER := 20;
    DtinN    : INTEGER := 41;
    DtOUT    : INTEGER := 51);
PORT(
    RESET    : IN  STD_LOGIC;
    CLK      : IN  STD_LOGIC;
    TXclk    : IN  STD_LOGIC;
    FiberR   : IN  STD_LOGIC;
    TXdtIn   : OUT STD_LOGIC_VECTOR(DtinN-1 DOWNTO 0);
    TXdtOut  : IN  STD_LOGIC_VECTOR(DtOUT-1 DOWNTO 0);
    FiberT   : OUT STD_LOGIC;
    TXSinFt  : OUT STD_LOGIC;
    TXFinish : OUT STD_LOGIC
);
END TX_Comm;

ARCHITECTURE BEHAV OF TX_Comm IS

    SIGNAL outstep     : INTEGER RANGE 0 TO 31 := 0;
    SIGNAL outcount    : INTEGER RANGE -DtOUT+1 TO DtOUT-1 := 0;
    SIGNAL outdelay    : INTEGER RANGE 0 TO DELAY-1 := 0;
    SIGNAL outdttemp   : STD_LOGIC_VECTOR(DtOUT-1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL evendo      : STD_LOGIC := '0';
    SIGNAL FiberT_reg  : STD_LOGIC := '0';

    SIGNAL instep      : INTEGER RANGE 0 TO 31 := 0;
    SIGNAL incount     : INTEGER RANGE 0 TO DtinN-1 := 0;
    SIGNAL indelay     : INTEGER RANGE 0 TO DELAY-1 := 0;
    SIGNAL indttemp    : STD_LOGIC_VECTOR(DtinN-1 DOWNTO 0) := (OTHERS=>'0');
    SIGNAL evendi      : STD_LOGIC := '0';
    SIGNAL TXSinFt_reg : STD_LOGIC := '0';
    SIGNAL TXFinish_reg: STD_LOGIC := '0';

    SIGNAL rx_r1       : STD_LOGIC := '0';
    SIGNAL rx_r2       : STD_LOGIC := '0';
    SIGNAL txclk_r     : STD_LOGIC := '0';

BEGIN

    FiberT   <= FiberT_reg;
    TXSinFt  <= TXSinFt_reg;
    TXFinish <= TXFinish_reg;

    PROCESS(CLK, RESET)
    BEGIN
        IF (RESET = '1') THEN
            rx_r1    <= '0';
            rx_r2    <= '0';
            txclk_r  <= '0';
        ELSIF (RISING_EDGE(CLK)) THEN
            rx_r1    <= FiberR;
            rx_r2    <= rx_r1;
            txclk_r  <= TXclk;
        END IF;
    END PROCESS;

    PROCESS(CLK, RESET)
    BEGIN
        IF (RESET = '1') THEN
            FiberT_reg  <= '0';
            outstep     <= 0;
            outcount    <= 0;
            outdelay    <= 0;
            outdttemp   <= (OTHERS=>'0');
            evendo      <= '0';
        ELSIF (RISING_EDGE(CLK)) THEN

            IF (outdelay < DELAY-1) THEN
                outdelay <= outdelay + 1;
            ELSE
                outdelay <= 0;
            END IF;

            CASE outstep IS
                WHEN 0  =>	IF (txclk_r = '1') 		THEN FiberT_reg<='1';  	outstep<=1;		outdelay<=0;	END IF;
				
				WHEN 1	=>	IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=2;		END IF;
                WHEN 2  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=3;		END IF;
                WHEN 3  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=4;		END IF;
                WHEN 4  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=5;		END IF;
                WHEN 5  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=6;		END IF;
                WHEN 6  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=7;		END IF;
                WHEN 7  =>  IF (outdelay=DELAY-1) 	THEN FiberT_reg<='0';	outstep<=8;		END IF;
                WHEN 8  =>  IF (outdelay=DELAY-1) 	THEN FiberT_reg<='1';	outstep<=9;		END IF;

                WHEN 9  =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';   outstep<=10;      
								outcount<=DtOUT-1;	outdttemp<=TXdtOut;		
								evendo<='0';                        
							END IF;

                WHEN 10 =>	IF (outdelay=DELAY-1) THEN
								IF (outcount >= 0) THEN
									FiberT_reg <= outdttemp(outcount);
									IF (outdttemp(outcount)='1') THEN
										evendo <= NOT evendo;
									END IF;
									outcount <= outcount - 1;
								ELSE
									FiberT_reg <= evendo;					outstep<=11;
								END IF;
							END IF;

                WHEN 11 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=12;	END IF;
                WHEN 12 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=13;	END IF;
                WHEN 13 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=14;	END IF;
                WHEN 14 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=15;	END IF;
                WHEN 15 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=16;	END IF;
                WHEN 16 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=17;	END IF;
                WHEN 17 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=18;	END IF;
                WHEN 18 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=19;	END IF;
                WHEN 19 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=20;	END IF;
                WHEN 20 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='1';	outstep<=21;	END IF;
                WHEN 21 =>  IF (outdelay=DELAY-1)	THEN FiberT_reg<='0';	outstep<=22;	END IF;

                WHEN 22 =>  IF (txclk_r = '0') THEN		                    outstep<=0;   	END IF;
                WHEN OTHERS => outstep<=0;
            END CASE;
        END IF;
    END PROCESS;

    PROCESS(CLK, RESET)
    BEGIN
        IF (RESET = '1') THEN
            TXdtIn       <= (OTHERS=>'0');
            TXSinFt_reg  <= '0';
            TXFinish_reg <= '0';
            instep       <= 0;
            incount      <= 0;
            indelay      <= 0;
            indttemp     <= (OTHERS=>'0');
            evendi       <= '0';
        ELSIF (RISING_EDGE(CLK)) THEN

            IF (indelay < DELAY-1) THEN
                indelay <= indelay + 1;
            ELSE
                indelay <= 0;
            END IF;

            CASE instep IS
                WHEN 0  => 	IF (rx_r2 = '1') THEN
								IF (indelay < DELAY/2) THEN
									indelay <= indelay + 1;
								ELSE
									instep  <= 1;
									indelay <= 0;
								END IF;
							ELSE
								indelay <= 0;
							END IF;

                WHEN 1  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='1') THEN instep<=2; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 2  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='0') THEN instep<=3; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 3  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='0') THEN instep<=4; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 4  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='1') THEN instep<=5; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 5  =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='0') THEN instep<=6; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 6  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='1') THEN instep<=7; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 7  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='0') THEN instep<=8; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;
                WHEN 8  =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='1') THEN instep<=9; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;

                WHEN 9  =>  IF (indelay=DELAY-1) THEN 
								IF (rx_r2='1') THEN									
									incount<=DtinN-1;	evendi<= '0';		instep<=10;									
								ELSE														
																							instep<=0;  TXSinFt_reg<='1'; 
								END IF;    
							END IF;

                WHEN 10 =>  IF (indelay=DELAY-1) THEN
								indttemp(incount) <= rx_r2;
								IF (rx_r2='1') THEN
									evendi <= NOT evendi;
								END IF;
								IF (incount>0) THEN
									incount <= incount - 1;
								ELSE
									instep <= 11;
								END IF;
							END IF;

                WHEN 11 =>  IF (indelay=DELAY-1) THEN IF (rx_r2=evendi)THEN instep<=12; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 12 =>  IF (indelay=DELAY-1) THEN 	IF (rx_r2='1') THEN instep<=13; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 13 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='0') THEN instep<=14; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 14 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='1') THEN instep<=15; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 15 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='1') THEN instep<=16; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 16 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='0') THEN instep<=17; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 17 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='1') THEN instep<=18; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 18 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='0') THEN instep<=19; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 19 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='0') THEN instep<=20; ELSE instep<=0; TXSinFt_reg<='1'; END IF;	END IF;
                WHEN 20 =>  IF (indelay=DELAY-1) THEN	IF (rx_r2='1') THEN instep<=21; ELSE instep<=0; TXSinFt_reg<='1'; END IF; 	END IF;

                WHEN 21 =>  IF (indelay=DELAY-1) THEN
								IF (rx_r2='1') THEN
									instep       <= 22;
									TXdtIn       <= indttemp;
									TXSinFt_reg  <= '0';
									TXFinish_reg <= '1';
								ELSE
									instep       <= 0;
									TXSinFt_reg  <= '1';
								END IF;
							END IF;

                WHEN 22 =>  IF (indelay=DELAY-1) THEN	
								instep    <= 0;
								TXFinish_reg  <= '0';
							END IF;

                WHEN OTHERS => instep <= 0;
            END CASE;
        END IF;
    END PROCESS;

END BEHAV;