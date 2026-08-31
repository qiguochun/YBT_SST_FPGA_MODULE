LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_arith.ALL;
USE IEEE.STD_LOGIC_signed.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY SSTMC_FPGA IS
	PORT(
		CLKIN				:	IN 	STD_LOGIC;			--50MHZ
		
		zz_r,zc_r			:	IN  STD_LOGIC;
		zz_t,zc_t			:	OUT STD_LOGIC;
		zc_a,zc_b,zc_c		:	OUT STD_LOGIC;
		
		UAD1_CLK,UAD2_CLK	:	OUT STD_LOGIC;
		UAD1_DAT,UAD2_DAT	:	IN 	STD_LOGIC;
		
		F_FLT1,F_FLT2		:	IN 	STD_LOGIC;
		F_FLT3,F_FLT4		:	IN 	STD_LOGIC;
		
		FHOE_DRV  			:	OUT STD_LOGIC;
		FHRDY_12,FHRDY_34 	:	OUT STD_LOGIC;
		FHS1_DRV,FHS2_DRV 	:	OUT STD_LOGIC;		--PHB_ATop,PHB_ABot 
		FHS3_DRV,FHS4_DRV 	:	OUT STD_LOGIC;		--PHB_BTop,PHB_BBot
	
		FLOE_DRV  			:	OUT STD_LOGIC;		
		FL1S1_DRV,FL1S2_DRV :	OUT STD_LOGIC;
		FL2S1_DRV,FL2S2_DRV :	OUT STD_LOGIC;
		FL3S1_DRV,FL3S2_DRV :	OUT STD_LOGIC;
		
		FFAN_FB1			:	IN STD_LOGIC;
		FFAN_PWM,FFAN_COM	:	OUT STD_LOGIC;

		F_T1CLK,F_T2CLK,F_T3CLK,F_T4CLK,F_T5CLK	:	OUT STD_LOGIC;
		F_T1OUT,F_T2OUT,F_T3OUT,F_T4OUT,F_T5OUT	:	IN 	STD_LOGIC;
		
		F_LED1,F_LED2,F_LED3,F_LED4				:	OUT STD_LOGIC	--LED1:系统-单元主控通迅指示;LED2:单元主控-单元从控通迅指示;LED3:亮=重故障指示,闪烁=H-PWM工作指示;LED4:D-PWM工作指示		
	);
END SSTMC_FPGA;

ARCHITECTURE BEHAV OF SSTMC_FPGA IS

	CONSTANT BS_MAXCNT	: INTEGER := 750;		--80KHz=120MHz/2/750
	CONSTANT BS_MDUCNT	: INTEGER := 13653;
	CONSTANT D_AUTO_OFF_DELAY_CNT : INTEGER := 10000;

	CONSTANT NumFI	:	INTEGER := 180;			--180/50MHz=3.6uS	
	CONSTANT NumHSQ	:	INTEGER := 192;			--HB死区:192/120MHz,1.6us
	CONSTANT NumDSQ	:	INTEGER := 24;			--DC原边死区:24/120MHz=200ns
	
	CONSTANT T1safeACT  : INTEGER :=162;
	CONSTANT T1safeRES  : INTEGER :=142;
	CONSTANT T2safeACT  : INTEGER :=176;
	CONSTANT T2safeRES  : INTEGER :=156;
	CONSTANT TsafeTimer: INTEGER :=60000;
	
	SIGNAL sig_RES		:  STD_LOGIC := '1';
	SIGNAL sig_clkMHz	:  STD_LOGIC := '0';
	SIGNAL sig_clk20KHz	:  STD_LOGIC := '0';
	SIGNAL sig_clk5Hz  	:  STD_LOGIC := '0';
	SIGNAL sig_ledres  	:  STD_LOGIC := '0';
	SIGNAL sig_Bs,sig_Dzgz,sig_OpenCLR,sig_OpenF:  STD_LOGIC := '0';
	SIGNAL led1_clk,led2_clk,led3_clk,led4_clk	:	STD_LOGIC := '0';

	COMPONENT sz_pll IS
		PORT (
			refclk   : IN  STD_LOGIC := 'X'; -- clk
			rst      : IN  STD_LOGIC := 'X'; -- reset
			outclk_0 : OUT STD_LOGIC         -- clk
		);
	END COMPONENT sz_pll;

	-----------------------------------------------------系统-单元主控通迅-----------------------------------------------------------
	CONSTANT zz_DELAY  :  INTEGER := 20;
	CONSTANT zz_dtIN   :  INTEGER := 54;		--单元主控制器接收数据				
	CONSTANT zz_dtOUT  :  INTEGER := 51;		--单元主控制器上传数据
	SIGNAL sig_zzclk   :  STD_LOGIC := '0';
	SIGNAL sig_zzdtin  :  STD_LOGIC_VECTOR(zz_dtIN-1  DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zzdtout :  STD_LOGIC_VECTOR(zz_dtOUT-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zzFiberT:  STD_LOGIC := '0';		--zz_t= not sig_zzFiberT
	SIGNAL sig_zzsinFt :  STD_LOGIC := '0';		--ZZ单次通迅故障
	SIGNAL sig_zzFinish:  STD_LOGIC := '0';		--通讯完成
	SIGNAL sig_zzclk_r,sig_zzclk_edge		:	STD_LOGIC := '0';
	SIGNAL sig_zzFinish_r,sig_zzFinish_edge	:	STD_LOGIC := '0';	
	SIGNAL sig_P15t,sig_P16t,sig_P17t,sig_P18t,sig_P19t	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');	------数据命令------
	SIGNAL sig_P23t,sig_Pt,sig_Idzl						:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_CLR,sig_HPwm,sig_Dpwm,sig_Dsoft			:	STD_LOGIC := '0';
	SIGNAL sig_I1O,sig_I2O,sig_I3O,sig_Cerr,sig_Dvft	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_UhO,sig_UTh,sig_UBh						:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	-----------------------------------------------------系统-单元主控通迅-----------------------------------------------------------

	---------------------------------------------------单元主控-单元从控通迅-----------------------------------------------------------
	CONSTANT zc_DELAY  :  INTEGER := 20;
	CONSTANT zc_dtIN   :  INTEGER := 43;		--单元主控制器接收数据				
	CONSTANT zc_dtOUT  :  INTEGER := 21;		--单元主控制器下发数据
	SIGNAL sig_zcclk   :  STD_LOGIC := '0';
	SIGNAL sig_zcdtin  :  STD_LOGIC_VECTOR(zc_dtIN-1  DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zcdtout :  STD_LOGIC_VECTOR(zc_dtOUT-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zcFiberT:  STD_LOGIC := '0';		--zc_t= not sig_zcFiberT
	SIGNAL sig_zcsinFt :  STD_LOGIC := '0';		--Zc单次通迅故障
	SIGNAL sig_zcFinish:  STD_LOGIC := '0';		--通讯完成
	SIGNAL sig_zcclk_r,sig_zcclk_edge	:	STD_LOGIC := '0';
	SIGNAL sig_zcFinish_r,sig_zcFinish_edge	:	STD_LOGIC := '0';	
	SIGNAL sig_T1O,sig_T2O,sig_T3O	:  STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');	------数据命令--------sig_UdO
	SIGNAL sig_T1s,sig_T2s,sig_T3s	:  STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	---------------------------------------------------单元主控-单元从控通迅-----------------------------------------------------------
	------------------------------------------------------通迅元件例化模块-------------------------------------------------------------
	COMPONENT TX_Comm
		GENERIC ( DELAY : INTEGER := 20; DtinN : INTEGER := 41; DtOUT : INTEGER := 51 );
		PORT
		(
			RESET		:	 IN STD_LOGIC;
			CLK			:	 IN STD_LOGIC;
			TXclk		:	 IN STD_LOGIC;
			FiberR		:	 IN STD_LOGIC;
			TXdtIn		:	 OUT STD_LOGIC_VECTOR(dtinn-1 DOWNTO 0);
			TXdtOut		:	 IN STD_LOGIC_VECTOR(dtout-1 DOWNTO 0);
			FiberT		:	 OUT STD_LOGIC;
			TXSinFt		:	 OUT STD_LOGIC;
			TXFinish	:	 OUT STD_LOGIC );
	END COMPONENT;
	------------------------------------------------------通迅元件例化模块-------------------------------------------------------------

	-----------------------------------------------------直流电压/温度测量--------------------------------------------------------------
	SIGNAL sig_UdGY		:	STD_LOGIC := '0';
	SIGNAL sig_T4O,sig_T5O,sig_T6O,sig_T7O,sig_T8O	:  STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	COMPONENT AMC1305_16bit_Controller
		PORT
		(
			RESET			:	 IN STD_LOGIC;
			CLK_120MHZ		:	 IN STD_LOGIC;
			AMC1_SCLK		:	 OUT STD_LOGIC;
			AMC2_SCLK		:	 OUT STD_LOGIC;
			AMC1_DOUT		:	 IN STD_LOGIC;
			AMC2_DOUT		:	 IN STD_LOGIC;
			DATA_16BIT1		:	 OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			DATA_16BIT2		:	 OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			DATA_16BIT3		:	 OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
			OUT_UdGY		:	 OUT STD_LOGIC	);
	END COMPONENT;

	COMPONENT AMC1035_5CH_Controller
		PORT
		(
			RESET		:	 IN STD_LOGIC;
			CLK_50MHZ	:	 IN STD_LOGIC;
			AMC_SCLK1	:	 OUT STD_LOGIC;
			AMC_SCLK2	:	 OUT STD_LOGIC;
			AMC_SCLK3	:	 OUT STD_LOGIC;
			AMC_SCLK4	:	 OUT STD_LOGIC;
			AMC_SCLK5	:	 OUT STD_LOGIC;
			AMC_DOUT1	:	 IN STD_LOGIC;
			AMC_DOUT2	:	 IN STD_LOGIC;
			AMC_DOUT3	:	 IN STD_LOGIC;
			AMC_DOUT4	:	 IN STD_LOGIC;
			AMC_DOUT5	:	 IN STD_LOGIC;
			DATA_CH1	:	 OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
			DATA_CH2	:	 OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
			DATA_CH3	:	 OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
			DATA_CH4	:	 OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
			DATA_CH5	:	 OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
			OUT_VALID	:	 OUT STD_LOGIC	);
	END COMPONENT;
	-----------------------------------------------------直流电压/温度测量--------------------------------------------------------------

	SIGNAL CH1_fI,CH2_fI,CH3_fI:  INTEGER RANGE -500 TO 500 := 0;
	-------------------------------------------------------HB:PWM-----------------------------------------------------------
	SIGNAL sig_HPwma,sig_HPwmb,sig_HPwmDa,sig_HPwmDb	:	STD_LOGIC := '0';	--HB,'1'=导通,'0'=关断
	-------------------------------------------------------DC:PWM-----------------------------------------------------------
	SIGNAL sig_Dauto,sig_DPwm_new :	STD_LOGIC := '0';
	SIGNAL sig_Fauto:	INTEGER RANGE -32767 to 32767 := 0;
	SIGNAL sig_DCpwm14a,sig_DCpwm14b,sig_DCpwm14c 	:	STD_LOGIC := '0';		--DC WORK
	SIGNAL sig_DCpwm14Da,sig_DCpwm14Db,sig_DCpwm14Dc:	STD_LOGIC := '0';	
	SIGNAL sig_DBpwm14a,sig_DBpwm14b,sig_DBpwm14c 	:	STD_LOGIC := '0';		--DC BOOST
	SIGNAL sig_DBpwm23a,sig_DBpwm23b,sig_DBpwm23c 	:	STD_LOGIC := '0';
	SIGNAL Driveou1	:	INTEGER RANGE -32767 to 32767 := 75;
	
	
	SIGNAL sig_HPwma_r,sig_DCpwm14a_r			:	STD_LOGIC := '0';
	SIGNAL sig_HPwma_edge,sig_DCpwm14a_edge		:	STD_LOGIC := '0';
	
	SIGNAL up_a,up_b,up_c          		: STD_LOGIC;
	SIGNAL cnt_a,cnt_b,cnt_c       		: INTEGER RANGE -32767 TO 32767;
	SIGNAL max_a,max_b,max_c       		: INTEGER RANGE -32767 TO 32767;
	SIGNAL new_max_a,new_max_b,new_max_c: INTEGER RANGE -32767 TO 32767;
	SIGNAL half_a,half_b,half_c     	: INTEGER RANGE -32767 TO 32767;
	SIGNAL sig_zca,sig_zcb,sig_zcc 					:	STD_LOGIC := '0';

	BEGIN

	sig_zzclk <= sig_clk20KHz;		
	sig_zcclk <= sig_clk20KHz;
	sig_Dvft(13) <= '0';	sig_Dvft(14) <= '0';	sig_Cerr(5)  <= '0';	sig_Cerr(13) <= '0';	sig_Cerr(14) <= '0';
	sig_Cerr(15) <= (sig_Dzgz AND sig_OpenF) OR (sig_Cerr(0) AND sig_OpenF) OR sig_Cerr(6) OR sig_Cerr(10) OR sig_Dvft(0) OR sig_Dvft(1) OR sig_Dvft(2) OR sig_Dvft(3) OR sig_Dvft(7) OR sig_Dvft(8) OR sig_Dvft(9) OR sig_Dvft(10) OR sig_Dvft(11);	--单元总故障
	sig_Bs  <= sig_RES OR sig_Cerr(15);						--总闭锁

	-------------------------------------------------------0.LED-----------------------------------------------------------
	P_LEDRES:PROCESS(CLKIN)		--sig_RES
		VARIABLE	var_cnt		:	INTEGER RANGE 0 TO 268435455 := 0;
		VARIABLE	var_ledres	:	STD_LOGIC := '0';
	BEGIN
		IF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (var_cnt >= 250000000) THEN
				var_ledres := '0';
			ELSE
				var_cnt := var_cnt + 1;			
				var_ledres := '1';	
			END IF;
			sig_ledres <= sig_clk5Hz AND var_ledres; 
		END IF;
	END PROCESS P_LEDRES;
	------------------------------------------------------------------------------------------------------------------------------
	P_Hled:PROCESS(CLKIN)
		VARIABLE var_cnt : INTEGER RANGE 0 to 2047 := 0;
	BEGIN
		IF (RISING_EDGE(CLKIN)) THEN
			sig_HPwma_r <= sig_HPwma;
			IF ((sig_HPwma = '1') AND (sig_HPwma_r = '0')) THEN
				sig_HPwma_edge <= '1';
			ELSE
				sig_HPwma_edge <= '0';
			END IF;
			IF (sig_Dvft(15) = '0') THEN
				var_cnt := 0;
				led3_clk <= '0';
			ELSIF (sig_HPwma_edge = '1') THEN
				IF (var_cnt >= 1200) THEN
					var_cnt := 1;
					led3_clk <= NOT(led3_clk);
				ELSE
					var_cnt := var_cnt + 1;
				END IF;
			END IF;
			F_LED3 <= (NOT (led3_clk XOR sig_ledres)) AND (NOT sig_Bs);
		END IF;
	END PROCESS P_Hled;
	------------------------------------------------------------------------------------------------------------------------------
	P_Dled:PROCESS(CLKIN)
		VARIABLE var_cnt : INTEGER RANGE 0 TO 16383 := 0;
	BEGIN
		IF (RISING_EDGE(CLKIN)) THEN
			sig_DCpwm14a_r <= sig_DCpwm14a;
			IF ((sig_DCpwm14a = '1') AND (sig_DCpwm14a_r = '0')) THEN
				sig_DCpwm14a_edge <= '1';
			ELSE
				sig_DCpwm14a_edge <= '0';
			END IF;
			IF ((sig_Cerr(13) = '0') AND (sig_Dvft(12) = '0')) THEN
				var_cnt := 0;
				led4_clk <= '0';
			ELSIF (sig_DCpwm14a_edge = '1') THEN
				IF (var_cnt >= 10000) THEN
					var_cnt := 1;
					led4_clk <= NOT(led4_clk);
				ELSE
					var_cnt := var_cnt + 1;
				END IF;
			END IF;
			--F_LED4 <= NOT ((led4_clk XOR sig_ledres) OR (sig_clk5Hz AND sig_CLR));
			F_LED4<=(NOT ( (led4_clk XOR sig_ledres) OR (sig_clk5Hz AND sig_CLR))) AND (NOT sig_zzsinFt) AND (NOT sig_zcsinFt);
		END IF;
	END PROCESS P_Dled;
	-------------------------------------------------------0.LED-----------------------------------------------------------

	
	-----------------------------------------------------1.复位+时钟-----------------------------------------------------------
	P_reset:PROCESS(CLKIN)		--sig_RES
		VARIABLE var_cnt:INTEGER RANGE 0 TO 65535 := 0;
	BEGIN
		IF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (var_cnt >= 49999) THEN
				sig_RES <= '0';
			ELSE
				var_cnt := var_cnt + 1;
				sig_RES <= '1';	
			END IF;
		END IF;
	END PROCESS P_reset;
	------------------------------------------------------------------------------------------------------------------------------
	P_PLL:sz_pll PORT MAP(
		refclk   =>	CLKIN,
		rst      =>	sig_RES,
		outclk_0 =>	sig_clkMHz	);
	------------------------------------------------------------------------------------------------------------------------------
	P_CLK20KHZ:PROCESS(CLKIN)
		VARIABLE  var_cnt : INTEGER RANGE 0 TO 4095 := 0;
	BEGIN
		IF (CLKIN'EVENT AND CLKIN = '1' ) THEN
			var_cnt := var_cnt + 1;
			CASE var_cnt IS 
				WHEN 1    => sig_clk20KHz <= '1';
				WHEN 1251 => sig_clk20KHz <= '0'; 	
				WHEN 2500 => var_cnt :=  0;
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
	END PROCESS P_CLK20KHZ;
	------------------------------------------------------------------------------------------------------------------------------
	P_CLK5HZ:PROCESS(CLKIN)
		VARIABLE  var_cnt : INTEGER RANGE 0 TO 16777215 := 0;
	BEGIN
		IF (CLKIN'EVENT AND CLKIN = '1' ) THEN
			var_cnt := var_cnt + 1;
			CASE var_cnt IS 
				WHEN 1        => sig_clk5Hz <=	'1';
				WHEN  5000001 => sig_clk5Hz <=	'0';
				WHEN 10000000 => var_cnt :=	0;
				WHEN OTHERS => NULL;
			END CASE;
		END IF;
	END PROCESS P_CLK5HZ;
	------------------------------------------------------------------------------------------------------------------------------
	TrFAN:PROCESS(sig_RES,FFAN_FB1,sig_Cerr(15),CLKIN)
		VARIABLE updown1a :	STD_LOGIC := '0';
		VARIABLE cnt1a	  :	INTEGER RANGE -16383 TO 16383 := 0;
	BEGIN
		IF (sig_RES = '1' OR FFAN_FB1 = '0' OR sig_Cerr(15) = '1') THEN
			updown1a := '0';			cnt1a := 1000;			
			FFAN_PWM <= '0';			FFAN_COM <= '0';		
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (cnt1a >= 1000) THEN	updown1a := '0';
			ELSIF (cnt1a <= 0) THEN	updown1a := '1';
			END IF;		
			IF (updown1a = '1') THEN		cnt1a := cnt1a + 1;									
			ELSE						cnt1a := cnt1a - 1;
			END IF;
			IF (CONV_INTEGER(sig_P23t) <= cnt1a) THEN
				FFAN_PWM <= '0';
			ELSE 
				FFAN_PWM <= '1';
			END IF;
			FFAN_COM <= '1';			
		END IF;	
		sig_Cerr(12)<=NOT FFAN_FB1;
	END PROCESS TrFAN;
	-----------------------------------------------------1.复位+时钟-----------------------------------------------------------

	----------------------------------------------------2.系统-单元主控通迅----------------------------------------------------------
	ZZ_sc:PROCESS(sig_RES, CLKIN)
		VARIABLE var_cnt : INTEGER RANGE 0 TO 15 := 0; 
	BEGIN
		IF (sig_RES = '1') THEN
			var_cnt := 0;				sig_zzdtout <= (OTHERS => '0');		
			sig_zzclk_r <= '0';			sig_zzclk_edge <= '0';
		ELSIF (RISING_EDGE(CLKIN)) THEN
			sig_zzclk_r <= sig_zzclk;
			IF ((sig_zzclk = '1') AND (sig_zzclk_r = '0')) THEN
				sig_zzclk_edge <= '1';
			ELSE
				sig_zzclk_edge <= '0';
			END IF;
			IF (sig_zzclk_edge = '1') THEN        
				IF (sig_Cerr(15) = '1') THEN	
					sig_zzdtout(50 DOWNTO 46) <= "01101";
				ELSE
					sig_zzdtout(50 DOWNTO 46) <= "10110";
				END IF;
				sig_zzdtout(45 DOWNTO 32) <= sig_Cerr(13 DOWNTO 0);
				sig_zzdtout(31 DOWNTO 16) <= sig_UhO;
				var_cnt := var_cnt + 1;
				CASE var_cnt IS
					WHEN 1  => sig_zzdtout(15 DOWNTO 0) <= "0001" & sig_I1O(15 DOWNTO 4);
					WHEN 2  => sig_zzdtout(15 DOWNTO 0) <= "0010" & sig_I2O(15 DOWNTO 4);
					WHEN 3  => sig_zzdtout(15 DOWNTO 0) <= "0011" & sig_I3O(15 DOWNTO 4);
					WHEN 4  => sig_zzdtout(15 DOWNTO 0) <= "0100" & sig_Dvft(11 DOWNTO 0);
					WHEN 5  => sig_zzdtout(15 DOWNTO 0) <= "0101" & sig_UTh(15 DOWNTO 4);	
					WHEN 6  => sig_zzdtout(15 DOWNTO 0) <= "0110" & sig_UBh(15 DOWNTO 4);
					WHEN 7  => sig_zzdtout(15 DOWNTO 0) <= "0111" & sig_T1s;
					WHEN 8  => sig_zzdtout(15 DOWNTO 0) <= "1000" & sig_T2s;
					WHEN 9  => sig_zzdtout(15 DOWNTO 0) <= "1001" & sig_T3s;
					WHEN 10 => sig_zzdtout(15 DOWNTO 0) <= "1010" & sig_T4O;
					WHEN 11 => sig_zzdtout(15 DOWNTO 0) <= "1011" & sig_T5O;
					WHEN 12 => sig_zzdtout(15 DOWNTO 0) <= "1100" & sig_T6O;
					WHEN 13 => sig_zzdtout(15 DOWNTO 0) <= "1101" & sig_T7O;
					WHEN 14 => sig_zzdtout(15 DOWNTO 0) <= "1110" & sig_T8O;
							 var_cnt := 0;
					WHEN OTHERS => NULL;
				END CASE;		
			END IF;
		END IF;
	END PROCESS ZZ_sc;
------------------------------------------------------------------------------------------------------------------------------
	ZZ_Error:PROCESS(sig_RES,sig_CLR,CLKIN)
		VARIABLE var_clkR :  STD_LOGIC := '0';
		VARIABLE var_cntR,var_cntF :  INTEGER RANGE 0 TO 65535 := 0;
		VARIABLE var_zzRFt,var_zzcommFt   :  STD_LOGIC := '0';	
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1') THEN
			var_clkR := '0';			var_cntR    := 0;			var_zzRFt   := '0';
			var_cntF := 0;				var_zzcommFt:= '0';			sig_Cerr(6) <= '0';		
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN 
			IF (zz_r = var_clkR) THEN						
				IF (var_cntR = 50000) THEN
					var_zzRFt := '1';
				ELSE
					var_cntR := var_cntR + 1;
				END IF;
			ELSE
				var_cntR := 0;
				var_clkR := zz_r;
			END IF;
			IF (sig_zzFinish = '0') THEN
				IF (var_cntF = 50000) THEN
					var_zzcommFt := '1';
				ELSE
					var_cntF := var_cntF + 1;	
				END IF;
			ELSE
				var_cntF := 0;
			END IF;
			sig_Cerr(6) <= var_zzRFt OR var_zzcommFt;	
		END IF;  
	END PROCESS ZZ_Error;
------------------------------------------------------------------------------------------------------------------------------
	ZZ_COMM: TX_Comm
	GENERIC MAP(
		DELAY   => zz_DELAY,
		DtinN   => zz_dtIN,
		DtOUT   => zz_dtOUT)
	PORT MAP(
		RESET    => sig_RES,
		CLK      => CLKIN,
		TXclk    => sig_clk20KHz,
		FiberR   => zz_r,
		TXdtIn   => sig_zzdtin,
		TXdtOut  => sig_zzdtout,
		FiberT   => sig_zzFiberT,
		TXSinFt  => sig_zzsinFt,
		TXFinish => sig_zzFinish  );
	zz_t <= NOT sig_zzFiberT;
------------------------------------------------------------------------------------------------------------------------------
	ZZ_Decodeout:PROCESS(sig_RES, CLKIN)
		VARIABLE var_cntC,var_cnt2P 	:  INTEGER RANGE 0 TO 127 := 0;--var_cnt1P
		VARIABLE var_DecdC0,var_DecdC1	:  STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');
		--VARIABLE var_Decd1P0,var_Decd1P1:  STD_LOGIC_VECTOR(12 DOWNTO 0) := (OTHERS => '0');	
		VARIABLE var_Decd2P0,var_Decd2P1:  STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
		VARIABLE var_cnt_clk : INTEGER RANGE 0 TO 8191 := 0;
		VARIABLE var_Dstop_cnt     : INTEGER RANGE 0 TO D_AUTO_OFF_DELAY_CNT-1 := 0;
		VARIABLE var_Dstop_pending,var_Dstop_done : STD_LOGIC := '0';
	BEGIN
		IF (sig_RES = '1') THEN
			sig_zzFinish_r <= '0';			sig_zzFinish_edge <= '0';
			var_cntC   := 0;				var_DecdC0  := (OTHERS => '0');		var_DecdC1  := (OTHERS => '0');
			--var_cnt1P  := 0;				var_Decd1P0 := (OTHERS => '0');		var_Decd1P1 := (OTHERS => '0');
			var_cnt2P  := 0;				var_Decd2P0 := (OTHERS => '0');		var_Decd2P1 := (OTHERS => '0');
			sig_CLR    <= '0';				sig_HPwm    <= '0';					sig_Dauto   <= '0';			--sig_Dpwm<='0';	sig_Dsoft<='0';
			sig_P15t   <= (OTHERS => '0');	sig_P16t    <= (OTHERS => '0');		sig_P17t    <= (OTHERS => '0');
			sig_P18t   <= (OTHERS => '0');	sig_P19t    <= (OTHERS => '0');		sig_P23t    <= (OTHERS => '0');
			sig_HPwma  <= '0';				sig_HPwmb   <= '0';					sig_DPwm_new<= '0';			
			var_cnt_clk:= 0;				led1_clk    <= '1';	
			var_Dstop_cnt := 0;				var_Dstop_pending := '0';			var_Dstop_done := '0';
			sig_Pt    <= (OTHERS => '0');	sig_Idzl	<= (OTHERS => '0');				
		ELSIF (RISING_EDGE(CLKIN)) THEN
			IF (var_Dstop_pending = '1') THEN
				IF (var_Dstop_cnt = D_AUTO_OFF_DELAY_CNT-1) THEN
					sig_Dauto <= '0';				var_Dstop_cnt := 0;
					var_Dstop_pending := '0';		var_Dstop_done := '1';
				ELSE
					var_Dstop_cnt := var_Dstop_cnt + 1;
				END IF;
			END IF;
			
			sig_zzFinish_r <= sig_zzFinish;
			IF ((sig_zzFinish = '1') AND (sig_zzFinish_r = '0')) THEN
				sig_zzFinish_edge <= '1';
			ELSE
				sig_zzFinish_edge <= '0';
			END IF;

			IF (sig_zzFinish_edge = '1') THEN
				var_DecdC1 := sig_zzdtin(53 DOWNTO 44);
				IF (var_DecdC1 = var_DecdC0) THEN						
					IF (var_cntC = 5) THEN				
						CASE var_DecdC0(9 DOWNTO 5) IS 
							WHEN "01001" => sig_CLR <= '1'; sig_HPwm <= '0';		--清故障
							WHEN "10100" => sig_CLR <= '0'; sig_HPwm <= '0';		--H闭锁
							WHEN "11010" => sig_CLR <= '0'; sig_HPwm <= '1';		--H_PWM
							WHEN OTHERS => NULL;
						END CASE;
						CASE var_DecdC0(4 DOWNTO 0) IS
							WHEN "10011" =>	IF (var_Dstop_pending = '0') THEN		--D软启
												sig_DPwm_new <= '1';
											END IF;
							WHEN "10100" =>	sig_DPwm_new <= '0';					--D闭锁
											IF (sig_Dauto = '1') AND (var_Dstop_pending = '0') AND (var_Dstop_done = '0') THEN
												var_Dstop_cnt := 0;		var_Dstop_pending := '1';
											END IF;
							WHEN "11010" =>	IF (var_Dstop_pending = '0') THEN		--D_PWM
												sig_Dauto <= '1';		sig_DPwm_new <= '0';		var_Dstop_done := '0';
											END IF;
							WHEN OTHERS =>	NULL;
						END CASE;				
					ELSE
						var_cntC := var_cntC + 1;
					END IF;
				ELSE
					var_cntC   := 0;
					var_DecdC0 := var_DecdC1;
				END IF;

				sig_HPwma <= sig_zzdtin(43);
				sig_HPwmb <= sig_zzdtin(42);
				
				sig_Idzl <= sig_zzdtin(41 DOWNTO 29) & "000";				
				sig_P15t <="000" & sig_zzdtin(28 DOWNTO 16);
					
				var_Decd2P1 := sig_zzdtin(15 DOWNTO 0);
				IF var_Decd2P1 = var_Decd2P0 THEN
					IF var_cnt2P < 4 THEN
						var_cnt2P := var_cnt2P + 1;
					END IF;
				ELSE
					var_Decd2P0 := var_Decd2P1;
					var_cnt2P   := 1;
				END IF;
				IF var_cnt2P = 4 THEN
					sig_Pt <= var_Decd2P0;
					CASE var_Decd2P0(15 DOWNTO 13) IS
						WHEN "000" =>sig_P16t <= "000" & var_Decd2P0(12 DOWNTO 0);
						WHEN "001" =>sig_P17t <= "000" & var_Decd2P0(12 DOWNTO 0);
						WHEN "010" =>sig_P18t <= "000" & var_Decd2P0(12 DOWNTO 0);
						WHEN "011" =>sig_P19t <= "000" & var_Decd2P0(12 DOWNTO 0);
						WHEN "111" =>sig_P23t <= "000" & var_Decd2P0(12 DOWNTO 0);
						WHEN OTHERS =>NULL;
					END CASE;
					var_cnt2P := 5;
				END IF;		
			
				IF (var_cnt_clk >= 5000) THEN
					var_cnt_clk := 1;
					led1_clk <= NOT(led1_clk);
				ELSE
					var_cnt_clk := var_cnt_clk + 1;
				END IF;
			
			END IF;
			F_LED1 <= led1_clk XOR sig_ledres;
		END IF;
	END PROCESS ZZ_Decodeout;
	----------------------------------------------------2.系统-单元主控通迅----------------------------------------------------------

	-------------------------------------------------3.单元主控-单元从控通迅---------------------------------------------------------
	ZC_sc:PROCESS(sig_RES, CLKIN)
	BEGIN
		IF (sig_RES = '1') THEN
			sig_zcclk_r <= '0';
			sig_zcclk_edge <= '0';		sig_zcdtout <= (OTHERS => '0');
		ELSIF (RISING_EDGE(CLKIN)) THEN
			sig_zcclk_r <= sig_zcclk;
			IF ((sig_zcclk = '1') AND (sig_zcclk_r = '0')) THEN
				sig_zcclk_edge <= '1';
			ELSE
				sig_zcclk_edge <= '0';
			END IF;
			IF (sig_zcclk_edge = '1') THEN
				IF (sig_CLR = '1' OR sig_OpenCLR = '1') THEN	
					sig_zcdtout(20 DOWNTO 16) <= "01001";
				ELSIF(sig_Bs='1')			THEN	sig_zcdtout(20 DOWNTO 16)<= "10100";
				ELSIF(sig_DPwm_new='1')   	THEN	sig_zcdtout(20 DOWNTO 16)<="11010";
				ELSE								sig_zcdtout(20 DOWNTO 16) <= "10100";				
				END IF;
				sig_zcdtout(15 DOWNTO 0) <= sig_Pt;
			END IF;
		END IF;
	END PROCESS ZC_sc;
------------------------------------------------------------------------------------------------------------------------------
	ZC_Error:PROCESS(sig_RES,sig_CLR,sig_OpenCLR,CLKIN)
		VARIABLE var_clkR :  STD_LOGIC := '0';
		VARIABLE var_cntR,var_cntF	:  INTEGER RANGE 0 TO 65535 := 0; 
		VARIABLE var_zcRFt,var_zccommFt	:	STD_LOGIC := '0';
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1' OR  sig_OpenCLR = '1') THEN
			var_clkR := '0';		var_cntR := 0;				var_zcRFt := '0';
			var_cntF := 0;			var_zccommFt := '0';		sig_Cerr(0) <= '0';		
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN 
			IF (zc_r = var_clkR) THEN						
				IF (var_cntR = 50000) THEN
					var_zcRFt := '1';
				ELSE
					var_cntR := var_cntR + 1;
				END IF;
			ELSE
				var_cntR := 0;
				var_clkR := zc_r;
			END IF;
			IF (sig_zcFinish = '0') THEN
				IF (var_cntF = 50000) THEN
					var_zccommFt := '1';
				ELSE
					var_cntF := var_cntF + 1;	
				END IF;
			ELSE
				var_cntF := 0;
			END IF;
			sig_Cerr(0) <= var_zcRFt OR var_zccommFt;
		END IF;  
	END PROCESS ZC_Error;
------------------------------------------------------------------------------------------------------------------------------
	ZC_COMM: TX_Comm
	GENERIC MAP(
		DELAY   => zc_DELAY,
		DtinN   => zc_dtIN,
		DtOUT   => zc_dtOUT)
	PORT MAP(
		RESET    => sig_RES,
		CLK      => CLKIN,
		TXclk    => sig_clk20KHz,
		FiberR   => zc_r,
		TXdtIn   => sig_zcdtin,
		TXdtOut  => sig_zcdtout,
		FiberT   => sig_zcFiberT,
		TXSinFt  => sig_zcsinFt,
		TXFinish => sig_zcFinish
	);		
	zc_t <= NOT sig_zcFiberT;
------------------------------------------------------------------------------------------------------------------------------
	ZC_Decodeout:PROCESS(sig_RES,sig_Cerr(0),CLKIN)
		VARIABLE var_cnt : INTEGER RANGE 0 TO 8191 := 0;
	BEGIN
		IF (sig_RES = '1' OR  sig_Cerr(0)='1') THEN
			sig_zcFinish_r <= '0';			sig_zcFinish_edge <= '0';
			sig_Dzgz <= '0';		
			sig_I1O <= (OTHERS => '0');		sig_I2O <= (OTHERS => '0');		sig_I3O <= (OTHERS => '0');
			sig_T1O <= (OTHERS => '0');		sig_T2O <= (OTHERS => '0');		sig_T3O <= (OTHERS => '0');		
			sig_Cerr(4 DOWNTO 1) <= (OTHERS => '0');						sig_Cerr(9 DOWNTO 7) <= (OTHERS => '0');		
			sig_Cerr(11) <= '0';											sig_Dvft(6 DOWNTO 4) <= (OTHERS => '0');			
			var_cnt := 0;					led2_clk <= '0';
			sig_T1s	<= (OTHERS => '0');		sig_T2s	<= (OTHERS => '0');		sig_T3s	<= (OTHERS => '0');
		ELSIF (RISING_EDGE(CLKIN)) THEN
			sig_zcFinish_r <= sig_zcFinish;
			IF ((sig_zcFinish = '1') AND (sig_zcFinish_r = '0')) THEN
				sig_zcFinish_edge <= '1';
			ELSE
				sig_zcFinish_edge <= '0';
			END IF;

			IF (sig_zcFinish_edge = '1') THEN
				CASE sig_zcdtin(42 DOWNTO 38) IS
					WHEN "01101" => sig_Dzgz <= '1';
					WHEN "10110" => sig_Dzgz <= '0';
					WHEN OTHERS  => NULL;
				END CASE;
			
				CASE sig_zcdtin(37 DOWNTO 35) IS
					WHEN "001" => sig_I1O <= sig_zcdtin(34 DOWNTO 19);
					WHEN "010" => sig_I2O <= sig_zcdtin(34 DOWNTO 19);
					WHEN "011" => sig_I3O <= sig_zcdtin(34 DOWNTO 19);
					WHEN OTHERS => NULL;
				END CASE;
			
				CASE sig_zcdtin(18 DOWNTO 16) IS
					WHEN "001" => sig_T1O <= sig_zcdtin(15 DOWNTO 0);
					WHEN "010" => sig_T2O <= sig_zcdtin(15 DOWNTO 0);
					WHEN "011" => sig_T3O <= sig_zcdtin(15 DOWNTO 0);
					WHEN "100" => sig_Cerr(4 DOWNTO 1)  <= sig_zcdtin(4 DOWNTO 1);
								  sig_Cerr(9 DOWNTO 7)  <= sig_zcdtin(9 DOWNTO 7);
								  sig_Cerr(11)          <= sig_zcdtin(11);	
								  sig_Dvft(6 DOWNTO 4)  <= sig_zcdtin(14 DOWNTO 12);
					WHEN OTHERS => NULL;
				END CASE;

				IF (var_cnt >= 5000) THEN
					var_cnt := 1;
					led2_clk <= NOT(led2_clk);
				ELSE
					var_cnt := var_cnt + 1;
				END IF;
				
				sig_T1s <= CONV_STD_LOGIC_VECTOR((CONV_INTEGER(sig_T1O)*225-18118)/16384,12);
				sig_T2s <= CONV_STD_LOGIC_VECTOR((CONV_INTEGER(sig_T2O)*225-18118)/16384,12);
				sig_T3s <= CONV_STD_LOGIC_VECTOR((CONV_INTEGER(sig_T3O)*225-18118)/16384,12);			
			END IF;
			F_LED2 <= led2_clk XOR sig_ledres;
		END IF;
	END PROCESS ZC_Decodeout;
	-------------------------------------------------3.单元主控-单元从控通迅---------------------------------------------------------

	----------------------------------------------------4.输出均流控制---------------------------------------------------------------
	JLcon:PROCESS(sig_RES,CLKIN)
		VARIABLE Step	:	INTEGER RANGE 0 TO 7 := 0;
		VARIABLE CH1_ek,CH1_uk,CH2_ek,CH2_uk,CH3_ek,CH3_uk		:INTEGER RANGE -1073741823 TO 1073741823 := 0;
		VARIABLE CH1_yk,CH1_yk1d,CH2_yk,CH2_yk1d,CH3_yk,CH3_yk1d:INTEGER RANGE -1073741823 TO 1073741823 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			Step := 0;			
			CH1_ek   := 0;			CH1_uk   := 0;			CH1_yk   := 0;
			CH1_yk1d := 0;			CH2_ek   := 0;			CH2_uk   := 0;
			CH2_yk   := 0;			CH2_yk1d := 0;			CH3_ek   := 0;
			CH3_uk   := 0;			CH3_yk   := 0;			CH3_yk1d := 0;		
			CH1_fI   <= 0;
			CH2_fI   <= 0;
			CH3_fI   <= 0;
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
		    IF (sig_Fauto /= 1500) OR (sig_Bs = '1') OR (sig_CLR = '1') OR (sig_Dauto = '0') THEN
				Step := 0;
				CH1_ek   := 0;        CH2_ek   := 0;        CH3_ek   := 0;
				CH1_uk   := 0;        CH2_uk   := 0;        CH3_uk   := 0;
				CH1_yk   := 0;        CH1_yk1d := 0;        CH2_yk   := 0;
				CH2_yk1d := 0;        CH3_yk   := 0;        CH3_yk1d := 0;
				CH1_fI <= 0;        	CH2_fI <= 0;        CH3_fI <= 0;
			ELSE
				CASE Step IS
					WHEN  0  =>	IF (sig_zcclk = '1') THEN
									-- CH1_ek := (2*CONV_INTEGER(sig_I1O)-CONV_INTEGER(sig_I2O)-CONV_INTEGER(sig_I3O))/3;
									-- CH2_ek := (2*CONV_INTEGER(sig_I2O)-CONV_INTEGER(sig_I1O)-CONV_INTEGER(sig_I3O))/3;
									-- CH3_ek := (2*CONV_INTEGER(sig_I3O)-CONV_INTEGER(sig_I1O)-CONV_INTEGER(sig_I2O))/3;
									CH1_ek := CONV_INTEGER(sig_I1O)-CONV_INTEGER(sig_Idzl);
									CH2_ek := CONV_INTEGER(sig_I2O)-CONV_INTEGER(sig_Idzl);
									CH3_ek := CONV_INTEGER(sig_I3O)-CONV_INTEGER(sig_Idzl);										
									IF (CH1_ek >= 2047) THEN	CH1_ek := 2047;
									ELSIF (CH1_ek < -2047) THEN	CH1_ek := -2047;
									END IF;
									IF (CH2_ek >= 2047) THEN	CH2_ek := 2047;
									ELSIF (CH2_ek < -2047) THEN	CH2_ek := -2047;
									END IF;
									IF (CH3_ek >= 2047) THEN	CH3_ek := 2047;
									ELSIF (CH3_ek < -2047) THEN	CH3_ek := -2047;
									END IF;
									Step := 1;
								END IF;
				
					WHEN  1  => CH1_yk := CH1_yk1d + CONV_INTEGER(sig_P17t)*CH1_ek;
								CH2_yk := CH2_yk1d + CONV_INTEGER(sig_P17t)*CH2_ek;
								CH3_yk := CH3_yk1d + CONV_INTEGER(sig_P17t)*CH3_ek;
								IF (CH1_yk > 640000000) THEN 		CH1_yk := 640000000;
								ELSIF (CH1_yk < -640000000) THEN	CH1_yk := -640000000;
								END IF;
								IF (CH2_yk > 640000000) THEN 		CH2_yk := 640000000;
								ELSIF (CH2_yk < -640000000) THEN	CH2_yk := -640000000;
								END IF;
								IF (CH3_yk > 640000000) THEN 		CH3_yk := 640000000;
								ELSIF (CH3_yk < -640000000) THEN	CH3_yk := -640000000;
								END IF;
								Step := 2;
					WHEN  2  => Step := 3; 
					WHEN  3  => Step := 4; 
							
					WHEN  4  => CH1_uk := CONV_INTEGER(sig_P16t)*CH1_ek + CH1_yk/20000;	CH1_yk1d := CH1_yk;
								CH2_uk := CONV_INTEGER(sig_P16t)*CH2_ek + CH2_yk/20000;	CH2_yk1d := CH2_yk;
								CH3_uk := CONV_INTEGER(sig_P16t)*CH3_ek + CH3_yk/20000;	CH3_yk1d := CH3_yk;
								IF (CH1_uk > 32000) THEN 		CH1_fI <= 500;
								ELSIF (CH1_uk < -32000) THEN	CH1_fI <= -500;
								ELSE 							CH1_fI <= CH1_uk/64;
								END IF;
								IF (CH2_uk > 32000) THEN 		CH2_fI <= 500;
								ELSIF (CH2_uk < -32000) THEN	CH2_fI <= -500;
								ELSE 							CH2_fI <= CH2_uk/64;
								END IF;
								IF (CH3_uk > 32000) THEN 		CH3_fI <= 500;
								ELSIF (CH3_uk < -32000) THEN	CH3_fI <= -500;
								ELSE 							CH3_fI <= CH3_uk/64;
								END IF;
								Step := 5;
							
					WHEN  5  =>	IF (sig_zcclk = '0') THEN
									Step := 0;
								END IF;
								
					WHEN OTHERS =>	NULL;
				END CASE;
			END IF;
		END IF;	
	END PROCESS JLcon;
	----------------------------------------------------4.输出均流控制---------------------------------------------------------------

	
	----------------------------------------------------5.DC BOOST PWM---------------------------------------------------------------
	BS_DC:PROCESS(sig_RES, CLKIN)	
		VARIABLE Step  		:	INTEGER RANGE 0 TO 7 := 0;
		VARIABLE var_cnt	:	INTEGER RANGE 0 TO 67108863 := 0;
		VARIABLE var_Drive  :	INTEGER RANGE 0 TO 8191 := 1000;
	BEGIN
		IF (sig_RES = '1') THEN
			Step := 0;				var_cnt := 0;			var_Drive := 0;			Driveou1 <=0;
			sig_Dsoft <= '0';		sig_Dpwm  <= '0';		sig_Fauto<= 750;		
			sig_OpenCLR <= '0';		sig_OpenF <= '0';						
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (sig_Bs = '1') OR (sig_CLR = '1') OR (sig_Dauto = '0') THEN
				Step := 0;			var_cnt := 0;			var_Drive := 0;			Driveou1 <= 0;
				sig_Dsoft <= '0';	sig_Dpwm  <= '0';		sig_Fauto <= 750;
				sig_OpenCLR <= '0';	--sig_OpenF <= '0';
			ELSE
				CASE Step IS
					WHEN 0	=>	IF (sig_Dauto = '1') THEN	
									var_cnt := 0;		sig_Dsoft <= '1';		sig_Dpwm <= '0';		Step := 1;		var_Drive := 1000;
								END IF;
					WHEN 1	=>	var_cnt := var_cnt + 1;
								IF  (var_cnt >= 64000) THEN		--5s=(4900-1000)*64000/50000000
									var_cnt := 0;	
									IF (var_Drive <= 4900) THEN
										var_Drive := var_Drive + 1;
									ELSE				sig_Dsoft <= '0';		sig_Dpwm <= '0';		Step := 2;									
									END IF;
								END IF;
					WHEN 2	=>	var_cnt := var_cnt + 1;
								IF (var_cnt >= 1250) THEN		--25us
									var_cnt := 0;		sig_Dsoft <= '0';		sig_Dpwm <= '1';		Step := 3;		sig_Fauto<= 750;
								END IF;						
					WHEN 3	=>	var_cnt := var_cnt + 1;				
								IF (var_cnt >= 200000) THEN
									var_cnt := 0;		
									-- sig_Fauto <= sig_Fauto + 1;
									-- IF (sig_Fauto >= 1499) THEN
										-- Step := 4;
										-- sig_OpenCLR <= '1';
									-- END IF;
									IF (sig_Fauto = 1499) THEN
										sig_Fauto   <= 1500;	Step := 4;
										sig_OpenCLR <= '1';		sig_OpenF   <= '0';										
									ELSE
										sig_Fauto <= sig_Fauto + 1;
									END IF;
								END IF;
					WHEN 4	=>	var_cnt := var_cnt + 1;				
								IF (var_cnt >= 50000000) THEN
									var_cnt := 0;		Step := 5;
									sig_OpenCLR <= '0';	sig_OpenF <= '1';
								END IF;								
					WHEN 5	=>	IF (sig_Dauto = '0') THEN			
									var_cnt := 0;		sig_Dsoft <= '0';		sig_Dpwm <= '0';		Step := 0;						
								END IF;			
					WHEN OTHERS => NULL;
				END CASE;
			END IF;
		Driveou1 <= (var_Drive * 307) / 4096;
		END IF;
	END PROCESS BS_DC;	
------------------------------------------------------------------------------------------------------------------------------	
	BS_PWM:PROCESS(sig_RES,sig_clkMHz)
		VARIABLE updown1a,updown2a,updown3a	:	STD_LOGIC := '0';
		VARIABLE var_cnt1,var_cnt2,var_cnt3	:	INTEGER RANGE -32767 TO 32767 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			updown1a := '0';			updown2a := '1';			updown3a := '0';				
			var_cnt1 := BS_MAXCNT;		var_cnt2 := BS_MAXCNT/3;	var_cnt3 := BS_MAXCNT/3;
			sig_DBpwm14a<= '0';			sig_DBpwm14b<= '0';			sig_DBpwm14c<= '0';
			sig_DBpwm23a<= '0';			sig_DBpwm23b<= '0';			sig_DBpwm23c<= '0';
		ELSIF (sig_clkMHz'EVENT AND sig_clkMHz = '1') THEN
			IF (var_cnt1 >= BS_MAXCNT) THEN	updown1a := '0';			--1
			ELSIF (var_cnt1 <= 0) THEN	updown1a := '1';
			END IF;		
			IF (updown1a = '1') THEN	var_cnt1 := var_cnt1 + 1;									
			ELSE						var_cnt1 := var_cnt1 - 1;
			END IF;
 		
			IF (var_cnt2 >= BS_MAXCNT) THEN	updown2a := '0';			--2
			ELSIF (var_cnt2 <= 0) THEN	updown2a := '1';
			END IF;		
			IF (updown2a = '1') THEN	var_cnt2 := var_cnt2 + 1;									
			ELSE						var_cnt2 := var_cnt2 - 1;
			END IF;
		
			IF (var_cnt3 >= BS_MAXCNT) THEN	updown3a := '0';			--3
			ELSIF (var_cnt3 <= 0) THEN	updown3a := '1';
			END IF;		
			IF (updown3a = '1') THEN	var_cnt3 := var_cnt3 + 1;									
			ELSE						var_cnt3 := var_cnt3 - 1;
			END IF; 			

			IF ( Driveou1 >= var_cnt1 ) 			THEN sig_DBpwm14a <= '1';	ELSE sig_DBpwm14a <= '0';	END IF;		--1				
			IF ( var_cnt1 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23a <= '1';	ELSE sig_DBpwm23a <= '0';	END IF;
		
			IF ( Driveou1 >= var_cnt2 ) 			THEN sig_DBpwm14b <= '1';	ELSE sig_DBpwm14b <= '0';	END IF;		--2
			IF ( var_cnt2 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23b <= '1';	ELSE sig_DBpwm23b <= '0';	END IF;
		
			IF ( Driveou1 >= var_cnt3 ) 			THEN sig_DBpwm14c <= '1';	ELSE sig_DBpwm14c <= '0';	END IF;		--3
			IF ( var_cnt3 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23c <= '1'; 	ELSE sig_DBpwm23c <= '0';	END IF;		
		END IF;		
	END PROCESS BS_PWM;
	----------------------------------------------------5.DC BOOST PWM---------------------------------------------------------------

	----------------------------------------------------6.DC WORK PWM---------------------------------------------------------------
	CALC_NEW_MAX : PROCESS(sig_RES, CLKIN)
		VARIABLE var_new_a : INTEGER;
		VARIABLE var_new_b : INTEGER;
		VARIABLE var_new_c : INTEGER;
	BEGIN
		IF sig_RES = '1' THEN
			new_max_a <= 750;
			new_max_b <= 750;
			new_max_c <= 750;

		ELSIF RISING_EDGE(CLKIN) THEN

			-- 计算三相新的PWM周期计数值
			var_new_a := CONV_INTEGER(sig_P15t) + sig_Fauto - CH1_fI;
			var_new_b := CONV_INTEGER(sig_P15t) + sig_Fauto - CH2_fI;
			var_new_c := CONV_INTEGER(sig_P15t) + sig_Fauto - CH3_fI;

			-- A相限幅：750～2000
			IF var_new_a < 750 THEN
				new_max_a <= 750;
			ELSIF var_new_a > 2000 THEN
				new_max_a <= 2000;
			ELSE
				new_max_a <= var_new_a;
			END IF;

			-- B相限幅：750～2000
			IF var_new_b < 750 THEN
				new_max_b <= 750;
			ELSIF var_new_b > 2000 THEN
				new_max_b <= 2000;
			ELSE
				new_max_b <= var_new_b;
			END IF;

			-- C相限幅：750～2000
			IF var_new_c < 750 THEN
				new_max_c <= 750;
			ELSIF var_new_c > 2000 THEN
				new_max_c <= 2000;
			ELSE
				new_max_c <= var_new_c;
			END IF;

		END IF;
	END PROCESS CALC_NEW_MAX;
	
	UPDATE_THRESHOLD : PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF sig_RES = '1' THEN
			max_a   <= 750;		half_a  <= 375;
			max_b   <= 750;		half_b  <= 375;
			max_c   <= 750;		half_c  <= 375;			
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF cnt_a <= 0 OR cnt_a >= max_a THEN
				max_a <= new_max_a;
				half_a <= new_max_a / 2;
			END IF;
			
			IF cnt_b <= 0 OR cnt_b >= max_b THEN
				max_b <= new_max_b;
				half_b <= new_max_b / 2;
			END IF;
			
			IF cnt_c <= 0 OR cnt_c >= max_c THEN
				max_c <= new_max_c;
				half_c <= new_max_c / 2;
			END IF;
			
		END IF;
	END PROCESS UPDATE_THRESHOLD;
	
	PHASE_PROC : PROCESS(sig_RES,sig_clkMHz)
	BEGIN
		IF sig_RES = '1'	THEN
			up_a <= '0';			cnt_a <= 750;			sig_DCpwm14a <= '0';		sig_zca <= '0';
			up_b <= '1';			cnt_b <= 215;			sig_DCpwm14b <= '0';		sig_zcb <= '0';
			up_c <= '0';			cnt_c <= 270;			sig_DCpwm14c <= '0';		sig_zcc <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF cnt_a <= 1 		THEN	--1	
				up_a <= '1';	cnt_a <= 0;
			ELSIF cnt_a >= max_a - 1 THEN
				up_a <= '0';	cnt_a <= max_a;
			END IF;
			IF up_a = '1' 		THEN					
				cnt_a <= cnt_a + 1;
			ELSE
				cnt_a <= cnt_a - 1;
			END IF;

			IF cnt_b <= 1 		THEN	--2	
				up_b <= '1';	cnt_b <= 0;
			ELSIF cnt_b >= max_b -1 THEN
				up_b <= '0';	cnt_b <= max_b;
			END IF;			
			IF up_b = '1' 		THEN			
				cnt_b <= cnt_b + 1;
			ELSE
				cnt_b <= cnt_b - 1;
			END IF;
			
			IF cnt_c <= 1 		THEN	--3	
				up_c <= '1';	cnt_c <= 0;
			ELSIF cnt_c >= max_c -1  THEN
				up_c <= '0';	cnt_c <= max_c;
			END IF;			
			IF up_c = '1' 		THEN			
				cnt_c <= cnt_c + 1;
			ELSE
				cnt_c <= cnt_c - 1;
			END IF;
			
			IF cnt_a >= half_a    THEN	--1
				sig_DCpwm14a <= '1';
				sig_zca <= '1';
			ELSE
				sig_DCpwm14a <= '0';
				sig_zca <= '0';				
			END IF;
			IF cnt_b >= half_b    THEN	--2
				sig_DCpwm14b <= '1';
				sig_zcb <= '1';				
			ELSE
				sig_DCpwm14b <= '0';
				sig_zcb <= '0';				
			END IF;
			IF cnt_c >= half_c    THEN	--3
				sig_DCpwm14c <= '1';
				sig_zcc <= '1';				
			ELSE
				sig_DCpwm14c <= '0';
				sig_zcc <= '0';								
			END IF;
			
		END IF;
	END PROCESS PHASE_PROC;
	-----------------------------------------------------6.DC WORK PWM---------------------------------------------------------------

	-----------------------------------------------------7.HB/DC：PWM死区------------------------------------------------------------
	----------------------------------------------------------HB------------------------------------------------------------------
	SqHBPWM:PROCESS(sig_RES, sig_clkMHz)
		VARIABLE var_cnta,var_cntb : INTEGER RANGE 0 TO 255 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			var_cnta := 0;			var_cntb := 0;
			sig_HPwmDa <= '0';		sig_HPwmDb <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (sig_HPwma = sig_HPwmDa) THEN
				var_cnta := 0;
			ELSIF (var_cnta >= NumHSQ) THEN
				var_cnta := 0;				sig_HPwmDa <= sig_HPwma;
			ELSE
				var_cnta := var_cnta + 1;
			END IF;
			IF (sig_HPwmb = sig_HPwmDb) THEN
				var_cntb := 0;
			ELSIF (var_cntb >= NumHSQ) THEN
				var_cntb := 0;				sig_HPwmDb <= sig_HPwmB;
			ELSE
				var_cntb := var_cntb + 1;
			END IF;
		END IF;
	END PROCESS SqHBPWM;
------------------------------------------------------------------------------------------------------------------------------	
	FHOE_DRV <= '0';
	PWM_HBbs:PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1') THEN
			sig_Dvft(15) <= '0';
			FHRDY_12 <= '0';			FHRDY_34 <= '0';
			FHS1_DRV <= '0';			FHS2_DRV <= '0';
			FHS3_DRV <= '0';			FHS4_DRV <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (sig_CLR = '1') THEN
				sig_Dvft(15) <= '0';
				FHRDY_12 <= '1';		FHRDY_34 <= '1';			
				FHS1_DRV <= '0';		FHS2_DRV <= '0';
				FHS3_DRV <= '0';		FHS4_DRV <= '0';
			ELSIF (sig_Bs = '1') THEN
				sig_Dvft(15) <= '0';
				FHRDY_12 <= '0';		FHRDY_34 <= '0';
				FHS1_DRV <= '0';		FHS2_DRV <= '0';
				FHS3_DRV <= '0';		FHS4_DRV <= '0';
			ELSIF (sig_HPwm = '1') THEN
				sig_Dvft(15) <= '1';
				FHRDY_12 <= '1';		FHRDY_34 <= '1';
				FHS1_DRV <= sig_HPwma AND sig_HPwmDa;				FHS2_DRV <= NOT (sig_HPwma OR sig_HPwmDa);
				FHS3_DRV <= sig_HPwmb AND sig_HPwmDb;				FHS4_DRV <= NOT (sig_HPwmb OR sig_HPwmDb);
			ELSE
				sig_Dvft(15) <= '0';
				FHRDY_12 <= '0';		FHRDY_34 <= '0';
				FHS1_DRV <= '0';		FHS2_DRV <= '0';
				FHS3_DRV <= '0';		FHS4_DRV <= '0';
			END IF;
		END IF;
	END PROCESS PWM_HBbs;
	----------------------------------------------------------HB------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------	
	SqDCPWM:PROCESS(sig_RES, sig_clkMHz)
		VARIABLE var_cnta,var_cntb,var_cntc : INTEGER RANGE 0 TO 255 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			var_cnta := 0;				var_cntb := 0;				var_cntc := 0;
			sig_DCpwm14Da <= '0';		sig_DCpwm14Db <= '0';		sig_DCpwm14Dc <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (sig_DCpwm14a = sig_DCpwm14Da) THEN
				var_cnta := 0;
			ELSIF (var_cnta >= NumDSQ) THEN
				var_cnta := 0;				sig_DCpwm14Da <= sig_DCpwm14a;
			ELSE
				var_cnta := var_cnta + 1;
			END IF;

			IF (sig_DCpwm14b = sig_DCpwm14Db) THEN
				var_cntb := 0;
			ELSIF (var_cntb >= NumDSQ) THEN
				var_cntb := 0;				sig_DCpwm14Db <= sig_DCpwm14b;
			ELSE
				var_cntb := var_cntb + 1;
			END IF;

			IF (sig_DCpwm14c = sig_DCpwm14Dc) THEN
				var_cntc := 0;
			ELSIF (var_cntc >= NumDSQ) THEN
				var_cntc := 0;				sig_DCpwm14Dc <= sig_DCpwm14c;
			ELSE
				var_cntc := var_cntc + 1;
			END IF;
		END IF;
	END PROCESS SqDCPWM;
------------------------------------------------------------------------------------------------------------------------------	
	FLOE_DRV <= '0';
	PWM_DCbs:PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1') THEN
			sig_Dvft(12) <= '0';
			FL1S1_DRV <= '0';			FL1S2_DRV <= '0';
			FL2S1_DRV <= '0';			FL2S2_DRV <= '0';
			FL3S1_DRV <= '0';			FL3S2_DRV <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (sig_CLR = '1') THEN
				sig_Dvft(12) <= '0';
				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
			ELSIF (sig_Bs = '1') THEN
				sig_Dvft(12) <= '0';
				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
			ELSIF (sig_Dpwm = '1') THEN
				sig_Dvft(12) <= '1';	
				FL1S1_DRV <= sig_DCpwm14a AND sig_DCpwm14Da;				FL1S2_DRV <= NOT (sig_DCpwm14a OR sig_DCpwm14Da);
				FL2S1_DRV <= sig_DCpwm14b AND sig_DCpwm14Db;				FL2S2_DRV <= NOT (sig_DCpwm14b OR sig_DCpwm14Db);
				FL3S1_DRV <= sig_DCpwm14c AND sig_DCpwm14Dc;				FL3S2_DRV <= NOT (sig_DCpwm14c OR sig_DCpwm14Dc);
			ELSIF (sig_Dsoft = '1') THEN
				sig_Dvft(12) <= '1';
				FL1S1_DRV <= sig_DBpwm14a;				FL1S2_DRV <= sig_DBpwm23a;
				FL2S1_DRV <= sig_DBpwm14b;				FL2S2_DRV <= sig_DBpwm23b;
				FL3S1_DRV <= sig_DBpwm14c;				FL3S2_DRV <= sig_DBpwm23c;
			ELSE
				sig_Dvft(12) <= '0';
				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
			END IF;
		END IF;
	END PROCESS PWM_DCbs;		
	zc_a<=sig_zca;
	zc_b<=sig_zcb;
	zc_c<=sig_zcc;
	----------------------------------------------------------DC------------------------------------------------------------------
	-----------------------------------------------------7.HB/DC：PWM死区------------------------------------------------------------

	-------------------------------------------------8.直流电压/温度测量-----------------------------------------------------------
	P_AMC1305:AMC1305_16bit_Controller	PORT MAP(
		RESET		 => sig_RES,
		CLK_120MHZ	 => sig_clkMHz,		
		AMC1_SCLK	 => UAD1_CLK,
		AMC2_SCLK	 => UAD2_CLK,
		AMC1_DOUT	 => UAD1_DAT,
		AMC2_DOUT	 => UAD2_DAT,
		DATA_16BIT1	 => sig_UTh,
		DATA_16BIT2	 => sig_UBh,
		DATA_16BIT3	 => sig_UhO,
		OUT_UdGY	 => sig_UdGY );	
------------------------------------------------------------------------------------------------------------------------------	
	P_AMC1035:AMC1035_5CH_Controller	PORT MAP(
		RESET		 => sig_RES,
		CLK_50MHZ	 => CLKIN,
		AMC_SCLK1	 => F_T1CLK,
		AMC_SCLK2	 => F_T2CLK,
		AMC_SCLK3	 => F_T3CLK,
		AMC_SCLK4	 => F_T4CLK,
		AMC_SCLK5	 => F_T5CLK,
		AMC_DOUT1	 => F_T1OUT,
		AMC_DOUT2	 => F_T2OUT,
		AMC_DOUT3	 => F_T3OUT,
		AMC_DOUT4	 => F_T4OUT,
		AMC_DOUT5	 => F_T5OUT,
		DATA_CH1	 => sig_T4O,
		DATA_CH2	 => sig_T5O,
		DATA_CH3	 => sig_T6O,
		DATA_CH4	 => sig_T7O,
		DATA_CH5	 => sig_T8O	);
------------------------------------------------------------------------------------------------------------------------------
	P_GZSC:PROCESS(sig_RES, sig_CLR, CLKIN)
		VARIABLE var_cnt_clk    : INTEGER RANGE 0 TO 4095 := 0;
		VARIABLE var_GYcnt      : INTEGER RANGE 0 TO 4095 := 0;
		VARIABLE var_T4cnt,var_T5cnt,var_T6cnt,var_T7cnt,var_T8cnt : INTEGER RANGE 0 TO 65535 := 0;
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1') THEN
			var_cnt_clk := 0;		var_GYcnt := 0;
			var_T4cnt := 0;			var_T5cnt := 0;			var_T6cnt := 0;			var_T7cnt := 0;			var_T8cnt := 0;
			sig_Cerr(10) <= '0';	sig_Dvft(11 DOWNTO 7) <= "00000";
		ELSIF (RISING_EDGE(CLKIN)) THEN
			var_cnt_clk := var_cnt_clk + 1;
			IF (var_cnt_clk = 2500) THEN
				var_cnt_clk := 0;
				IF (sig_UdGY = '1') THEN
					IF (var_GYcnt >= 800) THEN  sig_Cerr(10) <= '1';
					ELSE var_GYcnt := var_GYcnt + 1; END IF;
				ELSE
					var_GYcnt := 0;
				END IF;
				
				IF(CONV_INTEGER(sig_T4O)>T1safeACT) THEN			-------------------4----------------------------------						
					IF(var_T4cnt>=TsafeTimer) THEN
						sig_Dvft(7) <= '1';
					ELSE
						var_T4cnt:=var_T4cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T4O)<T1safeRES) THEN
					var_T4cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T5O)>T1safeACT) THEN			-------------------5----------------------------------						
					IF(var_T5cnt>=TsafeTimer) THEN
						sig_Dvft(8) <= '1';
					ELSE
						var_T5cnt:=var_T5cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T5O)<T1safeRES) THEN
					var_T5cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T6O)>T1safeACT) THEN			-------------------6----------------------------------						
					IF(var_T6cnt>=TsafeTimer) THEN
						sig_Dvft(9) <= '1';
					ELSE
						var_T6cnt:=var_T6cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T6O)<T1safeRES) THEN
					var_T6cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T7O)>T2safeACT) THEN			-------------------7----------------------------------						
					IF(var_T7cnt>=TsafeTimer) THEN
						sig_Dvft(10) <= '1';
					ELSE
						var_T7cnt:=var_T7cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T7O)<T2safeRES) THEN
					var_T7cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T8O)>T2safeACT) THEN			-------------------8----------------------------------						
					IF(var_T8cnt>=TsafeTimer) THEN
						sig_Dvft(11) <= '1';
					ELSE
						var_T8cnt:=var_T8cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T8O)<T2safeRES) THEN
					var_T8cnt:=0;
				END IF;				
			END IF;
		END IF;
	END PROCESS P_GZSC;
	-------------------------------------------------8.直流电压/温度测量-----------------------------------------------------------

	-----------------------------------------------------9.器件故障-------------------------------------------------------------
	Dv_Ft:PROCESS(sig_RES,sig_CLR,CLKIN)
		VARIABLE var_1cnt,var_2cnt,var_3cnt,var_4cnt:INTEGER RANGE 0 TO 511 := 0; 
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1') THEN
			var_1cnt    := 0;			var_2cnt    := 0;			var_3cnt    := 0;			var_4cnt    := 0;		
			sig_Dvft(0) <= '0';			sig_Dvft(1) <= '0';			sig_Dvft(2) <= '0';			sig_Dvft(3) <= '0';
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (F_FLT1 = '0') THEN			-------------------1----------------------------------
				IF (var_1cnt >= NumFI) THEN
					--sig_Dvft(0) <= '1';
				ELSE
					var_1cnt := var_1cnt + 1;
				END IF;
			ELSE
				var_1cnt := 0;			
			END IF;
			IF (F_FLT2 = '0') THEN			-------------------2----------------------------------
				IF (var_2cnt >= NumFI) THEN
					--sig_Dvft(1) <= '1';
				ELSE
					var_2cnt := var_2cnt + 1;
				END IF;
			ELSE
				var_2cnt := 0;			
			END IF;	
			IF (F_FLT3 = '0') THEN			-------------------3----------------------------------
				IF (var_3cnt >= NumFI) THEN
					--sig_Dvft(2) <= '1';
				ELSE
					var_3cnt := var_3cnt + 1;
				END IF;
			ELSE
				var_3cnt := 0;			
			END IF; 	
			IF (F_FLT4 = '0') THEN			-------------------4----------------------------------
				IF (var_4cnt >= NumFI) THEN
					--sig_Dvft(3) <= '1';
				ELSE
					var_4cnt := var_4cnt + 1;
				END IF;
			ELSE
				var_4cnt := 0;			
			END IF;		
		END IF;
	END PROCESS Dv_Ft;
	-----------------------------------------------------9.器件故障-------------------------------------------------------------

END BEHAV;