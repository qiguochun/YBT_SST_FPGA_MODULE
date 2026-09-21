--------------------------------------------------------------------------------
-- 文件名    : SSTMC_FPGA.vhd
-- 模块名称  : SSTMC_FPGA（单元控制 FPGA 顶层）
-- 功能概述  : 本模块为 SSTMC 功率单元控制 FPGA 的行为级实现，包含：
--             1) 时钟/复位与 PLL 倍频（50 MHz -> 120 MHz）
--             2) 系统控制<->单元主控、单元主控<->单元接口 两路光纤通信
--             3) HB 半桥死区驱动与 LLC 全桥 PWM
--             4) AMC1305/AMC1035 电压/温度采样
--             5) 故障确认、风扇、LED 指示及 PWM 保护
-- 主时钟    : CLKIN = 50 MHz
-- 内部高速时钟: sig_clkMHz = 120 MHz（由 sz_pll 产生）
-- 架构分区  : 0.LED | 1.复位+时钟 | 2.ZZ通信 | 3.ZC通信 | 7.HB/DC驱动 | 8.采样 | 9.故障滤波
--
-- sig_Cerr 故障字位定义（16bit）：
--   bit0  : ZC 光纤通信故障（接收停滞或帧完成超时）
--   bit1~4: 来自 ZC 接口侧故障子码
--   bit5  : 预留（固定 0）
--   bit6  : ZZ 光纤通信故障
--   bit7~9: 来自 ZC 接口侧故障子码
--   bit10 : 直流过压（fault_prot，UdGY 持续 800*50us）
--   bit11 : 来自 ZC 接口侧故障
--   bit12 : 风扇反馈故障（FFAN_FB1 低有效）
--   bit13 : 预留（固定 0）
--   bit14 : 预留（固定 0）
--   bit15 : 单元总故障（OR 汇总，见 BEGIN 组合逻辑）
--
-- sig_Dvft 设备故障字位定义（16bit）：
--   bit0~3 : 硬件 F_FLT1~4（当前赋值已注释，未生效）
--   bit4~6 : 来自 ZC 接口侧设备故障
--   bit7~11: AMC1035 五路温度过温（T4~T8，fault_prot）
--   bit12  : DC PWM 运行标志（工作/软启动时置 1）
--   bit13~14: 预留（固定 0）
--   bit15  : HB PWM 运行标志
--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_arith.ALL;
USE IEEE.STD_LOGIC_signed.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY SSTMC_FPGA IS
	PORT(
		-- ======================== 系统时钟 ========================
		CLKIN				:	IN 	STD_LOGIC;			-- 外部主时钟输入，50 MHz

		-- ======================== 光纤通信接口 ========================
		-- zz_* : 系统控制 <-> 单元主控 通信链路
		zz_r					:	IN  STD_LOGIC;		-- 系统侧光纤接收（RX）
		zz_t					:	OUT STD_LOGIC;		-- 系统侧光纤发送（TX），取反后输出
		-- zc_* : 单元主控 <-> 单元接口 通信链路
		zc_r					:	IN  STD_LOGIC;		-- 接口侧光纤接收（RX）
		zc_t					:	OUT STD_LOGIC;		-- 接口侧光纤发送（TX），取反后输出
		zc_a,zc_b,zc_c			:	OUT STD_LOGIC;		-- 三相 DC PWM 相位参考，输出至接口

		-- ======================== AMC1305 电压采样（SPI） ========================
		UAD1_CLK,UAD2_CLK		:	OUT STD_LOGIC;		-- AMC1305 采样时钟 SCLK
		UAD1_DAT,UAD2_DAT		:	IN 	STD_LOGIC;		-- AMC1305 串行数据 DOUT

		-- ======================== 硬件故障输入（低电平有效） ========================
		-- 低电平有效，经 fault_prot 滤波后写入 sig_Dvft（当前各故障位赋值已注释禁用）
		F_FLT1,F_FLT2			:	IN 	STD_LOGIC;		-- 硬件故障输入 1、2
		F_FLT3,F_FLT4			:	IN 	STD_LOGIC;		-- 硬件故障输入 3、4

		-- ======================== HB（半桥）桥臂驱动 ========================
		FHOE_DRV  				:	OUT STD_LOGIC;		-- HB 使能输出（本设计固定为 '0'）
		FHRDY_12,FHRDY_34 		:	OUT STD_LOGIC;		-- HB 桥臂 1/2、3/4 就绪信号
		FHS1_DRV,FHS2_DRV 		:	OUT STD_LOGIC;		-- HB-A 上桥/下桥驱动（PHB_ATop/PHB_ABot）
		FHS3_DRV,FHS4_DRV 		:	OUT STD_LOGIC;		-- HB-B 上桥/下桥驱动（PHB_BTop/PHB_BBot）

		-- ======================== DC（直流）桥臂驱动 ========================
		FLOE_DRV  				:	OUT STD_LOGIC;		-- DC 使能输出（本设计固定为 '0'）
		FL1S1_DRV,FL1S2_DRV 	:	OUT STD_LOGIC;		-- DC 相 1 上桥/下桥驱动
		FL2S1_DRV,FL2S2_DRV 	:	OUT STD_LOGIC;		-- DC 相 2 上桥/下桥驱动
		FL3S1_DRV,FL3S2_DRV 	:	OUT STD_LOGIC;		-- DC 相 3 上桥/下桥驱动

		-- ======================== 风扇接口 ========================
		FFAN_FB1				:	IN  STD_LOGIC;		-- 风扇反馈（低=故障）
		FFAN_PWM				:	OUT STD_LOGIC;		-- 风扇 PWM
		FFAN_COM				:	OUT STD_LOGIC;		-- 风扇公共端/使能

		-- ======================== AMC1035 温度采样（5 通道 SPI） ========================
		F_T1CLK,F_T2CLK,F_T3CLK,F_T4CLK,F_T5CLK	:	OUT STD_LOGIC;	-- 5 路 AMC1035 SCLK
		F_T1OUT,F_T2OUT,F_T3OUT,F_T4OUT,F_T5OUT	:	IN 	STD_LOGIC;	-- 5 路 AMC1035 DOUT

		-- ======================== 状态 LED 指示 ========================
		-- LED1: 系统<->单元主控通信心跳（通信正常时闪烁）
		-- LED2: 单元主控<->单元接口通信心跳
		-- LED3: 常亮=HB 桥故障；闪烁=H-PWM 运行指示
		-- LED4: D-PWM 运行指示（闪烁）；通信单次故障时熄灭
		F_LED1,F_LED2,F_LED3,F_LED4				:	OUT STD_LOGIC
	);
END SSTMC_FPGA;

ARCHITECTURE BEHAV OF SSTMC_FPGA IS

	-- LLC PWM：开关频率 20~80 kHz；给定单位 10Hz（2000~8000），period = 12_000_000 / 给定值
	CONSTANT LLC_CLK_FREQ      : INTEGER := 120_000_000;
	CONSTANT LLC_F_UNIT_HZ     : INTEGER := 10;		-- 频率给定单位：10 Hz
	CONSTANT LLC_F_MIN         : INTEGER := 2000;	-- 20 kHz = 2000×10Hz
	CONSTANT LLC_F_MAX         : INTEGER := 8000;	-- 80 kHz = 8000×10Hz
	CONSTANT LLC_PERIOD_MIN    : INTEGER := LLC_CLK_FREQ / (LLC_F_MAX * LLC_F_UNIT_HZ);	-- 1500 clk @80kHz
	CONSTANT LLC_PERIOD_MAX    : INTEGER := LLC_CLK_FREQ / (LLC_F_MIN * LLC_F_UNIT_HZ);	-- 6000 clk @20kHz
	CONSTANT LLC_PERIOD_SCALE  : INTEGER := LLC_CLK_FREQ / LLC_F_UNIT_HZ;					-- 12000000

	-- ===================== 死区定时参数 =====================
	CONSTANT NumHSQ	:	INTEGER := 192;			-- HB 死区：192/120MHz = 1.6us

	-- ===================== 全局控制信号 =====================
	SIGNAL sig_RES		:  STD_LOGIC := '1';	-- 上电复位，高有效，约 1ms 后释放
	SIGNAL sig_clkMHz	:  STD_LOGIC := '0';	-- PLL 输出 120 MHz
	SIGNAL sig_clk20KHz	:  STD_LOGIC := '0';	-- 20 kHz，光纤通信位时钟
	SIGNAL sig_clk5Hz  	:  STD_LOGIC := '0';	-- 5 Hz，LED 慢闪节拍
	SIGNAL sig_ledres  	:  STD_LOGIC := '0';	-- LED 复位闪烁使能（上电约 5s）
	SIGNAL sig_Bs,sig_Dzgz :  STD_LOGIC := '0';
	SIGNAL led3_clk,led4_clk	:	STD_LOGIC := '0';

	COMPONENT sz_pll IS
		PORT (
			refclk   : IN  STD_LOGIC := 'X'; -- 参考时钟 50 MHz
			rst      : IN  STD_LOGIC := 'X'; -- 复位，高有效
			outclk_0 : OUT STD_LOGIC         -- 倍频输出 120 MHz
		);
	END COMPONENT sz_pll;

	-----------------------------------------------------系统-单元主控通信（ZZ）-----------------------------------------------------------
	-- 组帧/解析已拆至 zz_fiber_out.vhd / zz_fiber_in.vhd，由 zz_fiber_core 封装
	SIGNAL sig_zzsinFt :  STD_LOGIC := '0';		-- ZZ 单次通信故障脉冲
	SIGNAL sig_P15t,sig_P16t,sig_P17t,sig_P18t,sig_P19t	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_P23t,sig_Pt,sig_Idzl,sig_Duty			:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_CLR,sig_HPwm : STD_LOGIC := '0';
	SIGNAL sig_I1O,sig_I2O,sig_I3O,sig_Cerr,sig_Dvft	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_UhO,sig_UTh,sig_UBh						:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	-----------------------------------------------------系统-单元主控通信（ZZ）-----------------------------------------------------------

	---------------------------------------------------单元主控-单元接口通信（ZC）-----------------------------------------------------------
	-- 组帧/解析已拆至 zc_fiber_out.vhd / zc_fiber_in.vhd，由 zc_fiber_core 封装
	SIGNAL sig_zcsinFt :  STD_LOGIC := '0';		-- ZC 单次通信故障脉冲
	SIGNAL sig_T1s,sig_T2s,sig_T3s	:  STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	---------------------------------------------------单元主控-单元接口通信（ZC）-----------------------------------------------------------

	-----------------------------------------------------直流电压/温度采样（AMC1305/AMC1035）----------------------------------------------
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
	-----------------------------------------------------直流电压/温度采样（AMC1305/AMC1035）----------------------------------------------

	SIGNAL sig_HPwma,sig_HPwmb,sig_HPwmDa,sig_HPwmDb	:	STD_LOGIC := '0';
	SIGNAL sig_Dauto,sig_DPwm_new :	STD_LOGIC := '0';
	SIGNAL sig_HPwma_r,sig_llc_pwm1_r : STD_LOGIC := '0';
	SIGNAL sig_HPwma_edge,sig_llc_pwm1_edge : STD_LOGIC := '0';

	-- LLC 全桥 PWM（llc_pwm_gen）接口
	SIGNAL sig_sr_en                              : STD_LOGIC := '0';  -- SR 使能（预留）
	SIGNAL sig_llc_duty_lim                       : STD_LOGIC_VECTOR(15 DOWNTO 0);	-- 限幅后占空比 0~1023
	SIGNAL w_llc_pwm_en                           : STD_LOGIC;
	SIGNAL w_llc_pwm_period_50                    : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL sig_llc_freq_r                         : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_Duty_sync_d0                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_Duty_sync_d1                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_llc_period_sync_d0                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_period_sync_d1                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_pwm_period                       : STD_LOGIC_VECTOR(12 DOWNTO 0);
	SIGNAL w_llc_pwm_duty                         : STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL w_llc_pwm1, w_llc_pwm2, w_llc_pwm3, w_llc_pwm4 : STD_LOGIC;
	SIGNAL w_llc_pwm5, w_llc_pwm6                 : STD_LOGIC;

	BEGIN

	sig_Dvft(13) <= '0';	sig_Dvft(14) <= '0';	sig_Cerr(5)  <= '0';	sig_Cerr(13) <= '0';	sig_Cerr(14) <= '0';
	sig_Cerr(15) <= sig_Cerr(6) OR sig_Cerr(10) OR sig_Dvft(0) OR sig_Dvft(1) OR sig_Dvft(2) OR sig_Dvft(3) OR sig_Dvft(7) OR sig_Dvft(8) OR sig_Dvft(9) OR sig_Dvft(10) OR sig_Dvft(11);
	sig_Bs  <= sig_RES OR sig_Cerr(15);

	-------------------------------------------------------0.LED 状态指示-----------------------------------------------------------
	-- P_LEDRES: 上电后 5s 内 sig_ledres 与 5Hz 时钟相与，产生复位闪烁节拍
	P_LEDRES:PROCESS(CLKIN)
		VARIABLE	var_cnt		:	INTEGER RANGE 0 TO 268435455 := 0;
		VARIABLE	var_ledres	:	STD_LOGIC := '0';
	BEGIN
		IF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (var_cnt >= 250000000) THEN		-- 250M/50M = 5s
				var_ledres := '0';
			ELSE
				var_cnt := var_cnt + 1;
				var_ledres := '1';
			END IF;
			sig_ledres <= sig_clk5Hz AND var_ledres;
		END IF;
	END PROCESS P_LEDRES;
	------------------------------------------------------------------------------------------------------------------------------
	-- P_Hled: LED3 指示 HB PWM 运行；sig_Dvft(15)=0 时熄灭；总保护 sig_Bs 时强制灭
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
				IF (var_cnt >= 1200) THEN		-- 1200/50M = 24us 分频
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
	-- P_Dled: LED4 指示 DC PWM；通信单次故障 sig_zzsinFt/sig_zcsinFt 时强制灭
	P_Dled:PROCESS(CLKIN)
		VARIABLE var_cnt : INTEGER RANGE 0 TO 16383 := 0;
	BEGIN
		IF (RISING_EDGE(CLKIN)) THEN
			sig_llc_pwm1_r <= w_llc_pwm1;
			IF ((w_llc_pwm1 = '1') AND (sig_llc_pwm1_r = '0')) THEN
				sig_llc_pwm1_edge <= '1';
			ELSE
				sig_llc_pwm1_edge <= '0';
			END IF;
			IF ((sig_Cerr(13) = '0') AND (sig_Dvft(12) = '0')) THEN
				var_cnt := 0;
				led4_clk <= '0';
			ELSIF (sig_llc_pwm1_edge = '1') THEN
				IF (var_cnt >= 10000) THEN
					var_cnt := 1;
					led4_clk <= NOT(led4_clk);
				ELSE
					var_cnt := var_cnt + 1;
				END IF;
			END IF;
			F_LED4<=(NOT ( (led4_clk XOR sig_ledres) OR (sig_clk5Hz AND sig_CLR))) AND (NOT sig_zzsinFt) AND (NOT sig_zcsinFt);
		END IF;
	END PROCESS P_Dled;
	-------------------------------------------------------0.LED 状态指示-----------------------------------------------------------

	-----------------------------------------------------1.复位+时钟-----------------------------------------------------------
	-- P_reset: 上电后约 1ms 复位释放（49999+1 个 50MHz 周期）
	P_reset:PROCESS(CLKIN)
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
	-- P_CLK20KHZ: 20kHz = 50MHz/2500，占空比 50%（高 1250 周期）
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
	-- P_CLK5HZ: 5Hz = 50MHz/10M，周期 0.2s
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
	sig_Cerr(12) <= NOT FFAN_FB1;
	-- TrFAN: 三角波 PWM 风扇调速（占空比由 sig_P23t 给定）。故障只上报，不在这里停风扇
	TrFAN:PROCESS(sig_RES, CLKIN)
		VARIABLE updown1a :	STD_LOGIC := '0';
		VARIABLE cnt1a	  :	INTEGER RANGE -16383 TO 16383 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			updown1a := '0';			cnt1a := 1000;
			FFAN_PWM <= '0';			FFAN_COM <= '0';
		ELSIF RISING_EDGE(CLKIN) THEN
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
	END PROCESS TrFAN;
	-----------------------------------------------------1.复位+时钟-----------------------------------------------------------

	----------------------------------------------------2.系统-单元主控通信（ZZ）----------------------------------------------------------
	U_ZZ_FIBER : entity work.zz_fiber_core
		GENERIC MAP (
			DELAY  => 20,
			DT_IN  => 70,
			DT_OUT => 51
		)
		PORT MAP (
			i_sys_clk  => CLKIN,
			i_sys_rst  => sig_RES,
			i_tx_clk   => sig_clk20KHz,
			i_led_res  => sig_ledres,
			i_fiber_r  => zz_r,
			o_fiber_t  => zz_t,
			i_cerr     => sig_Cerr,
			i_dvft     => sig_Dvft(11 DOWNTO 0),
			i_uho      => sig_UhO,
			i_uth      => sig_UTh,
			i_ubh      => sig_UBh,
			i_i1o      => sig_I1O,
			i_i2o      => sig_I2O,
			i_i3o      => sig_I3O,
			i_t1s      => sig_T1s,
			i_t2s      => sig_T2s,
			i_t3s      => sig_T3s,
			i_t4o      => sig_T4O,
			i_t5o      => sig_T5O,
			i_t6o      => sig_T6O,
			i_t7o      => sig_T7O,
			i_t8o      => sig_T8O,
			o_clr      => sig_CLR,
			o_hpwm     => sig_HPwm,
			o_dauto    => sig_Dauto,
			o_dpwm_new => sig_DPwm_new,
			o_hpwma    => sig_HPwma,
			o_hpwmb    => sig_HPwmb,
			o_idzl     => sig_Idzl,
			o_p15t     => sig_P15t,
			o_p16t     => sig_P16t,
			o_p17t     => sig_P17t,
			o_p18t     => sig_P18t,
			o_p19t     => sig_P19t,
			o_p23t     => sig_P23t,
			o_pt       => sig_Pt,
			o_duty     => sig_Duty,
			o_cerr6    => sig_Cerr(6),
			o_sin_ft   => sig_zzsinFt,
			o_dt_in    => open,
			o_led      => F_LED1
		);
	----------------------------------------------------2.系统-单元主控通信（ZZ）----------------------------------------------------------

	-------------------------------------------------3.单元主控-单元接口通信（ZC）---------------------------------------------------------
	U_ZC_FIBER : entity work.zc_fiber_core
		GENERIC MAP (
			DELAY  => 20,
			DT_IN  => 43,
			DT_OUT => 21
		)
		PORT MAP (
			i_sys_clk  => CLKIN,
			i_sys_rst  => sig_RES,
			i_tx_clk   => sig_clk20KHz,
			i_led_res  => sig_ledres,
			i_clr      => sig_CLR,
			i_bs       => sig_Bs,
			i_dpwm_new => sig_DPwm_new,
			i_pt       => sig_Pt,
			i_fiber_r  => zc_r,
			o_fiber_t  => zc_t,
			o_i1o      => sig_I1O,
			o_i2o      => sig_I2O,
			o_i3o      => sig_I3O,
			o_t1s      => sig_T1s,
			o_t2s      => sig_T2s,
			o_t3s      => sig_T3s,
			o_dzgz     => sig_Dzgz,
			o_cerr0    => sig_Cerr(0),
			o_cerr_1_4 => sig_Cerr(4 DOWNTO 1),
			o_cerr_7_9 => sig_Cerr(9 DOWNTO 7),
			o_cerr11   => sig_Cerr(11),
			o_dvft_4_6 => sig_Dvft(6 DOWNTO 4),
			o_sin_ft   => sig_zcsinFt,
			o_led      => F_LED2
		);
	-------------------------------------------------3.单元主控-单元接口通信（ZC）---------------------------------------------------------

	-----------------------------------------------------7.HB/DC 桥臂 PWM 驱动---------------------------------------------------------
	----------------------------------------------------------HB 半桥---------------------------------------------------------------
	-- SqHBPWM: HB 死区 NumHSQ=192@120MHz=1.6us，延迟 sig_HPwma/b 至 sig_HPwmDa/Db
	SqHBPWM:PROCESS(sig_RES, sig_clkMHz)
		VARIABLE var_cnta,var_cntb : INTEGER RANGE 0 TO 255 := 0;

		PROCEDURE p_dead(
			SIGNAL i_pwm : IN STD_LOGIC;
			VARIABLE v_cnt : INOUT INTEGER;
			SIGNAL o_dly : INOUT STD_LOGIC
		) IS
		BEGIN
			IF (i_pwm = o_dly) THEN
				v_cnt := 0;
			ELSIF (v_cnt >= NumHSQ) THEN
				v_cnt := 0;
				o_dly <= i_pwm;
			ELSE
				v_cnt := v_cnt + 1;
			END IF;
		END PROCEDURE p_dead;
	BEGIN
		IF (sig_RES = '1') THEN
			var_cnta := 0;			var_cntb := 0;
			sig_HPwmDa <= '0';		sig_HPwmDb <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			p_dead(sig_HPwma, var_cnta, sig_HPwmDa);
			p_dead(sig_HPwmb, var_cntb, sig_HPwmDb);
		END IF;
	END PROCESS SqHBPWM;
------------------------------------------------------------------------------------------------------------------------------
	FHOE_DRV <= '0';     --HB总使能固定拉低
	-- PWM_HBbs: 上桥=PWM AND 延迟PWM；下桥=NOT(PWM OR 延迟PWM)，互锁防直通
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
				FHS1_DRV <= sig_HPwma AND sig_HPwmDa;				
				FHS2_DRV <= NOT (sig_HPwma OR sig_HPwmDa);
				FHS3_DRV <= sig_HPwmb AND sig_HPwmDb;				
				FHS4_DRV <= NOT (sig_HPwmb OR sig_HPwmDb);
			ELSE
				sig_Dvft(15) <= '0';
				FHRDY_12 <= '0';		FHRDY_34 <= '0';
				FHS1_DRV <= '0';		FHS2_DRV <= '0';
				FHS3_DRV <= '0';		FHS4_DRV <= '0';
			END IF;
		END IF;
	END PROCESS PWM_HBbs;
	----------------------------------------------------------HB 半桥---------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------
	----------------------------------------------------------DC 桥臂（LLC PWM）---------------------------------------------------------------
	-- 频率 sig_P15t、占空比 sig_Duty、使能 sig_Dauto（光纤下行）
	sig_llc_duty_lim <= CONV_STD_LOGIC_VECTOR(1023, 16) WHEN (CONV_INTEGER(sig_Duty) > 1023)
	                    ELSE sig_Duty;
	w_llc_pwm_en     <= '1' WHEN (sig_Dauto = '1' AND sig_CLR = '0' AND sig_Bs = '0') ELSE '0';

	-- 占空比：sig_Duty(9:0)；频率：sig_P15t 单位10Hz（2000~8000），period = 12000000 / 给定值
	-- 未给定频率(0)时默认 80kHz（给定值 8000）
	-- P_LLC_FREQ：50 MHz 进程，仅在频率变化时重算周期，消除组合除法器
	P_LLC_FREQ : PROCESS(sig_RES, CLKIN)
		VARIABLE v_freq_cmd : INTEGER RANGE 0 TO 8191;
		VARIABLE v_period   : INTEGER RANGE 0 TO 8191;
	BEGIN
		IF (sig_RES = '1') THEN
			sig_llc_freq_r      <= (OTHERS => '0');
			w_llc_pwm_period_50 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
		ELSIF (RISING_EDGE(CLKIN)) THEN
			IF (sig_P15t /= sig_llc_freq_r) THEN
				sig_llc_freq_r <= sig_P15t;
				v_freq_cmd := CONV_INTEGER(sig_P15t);
				IF (v_freq_cmd < LLC_F_MIN) THEN
					IF (v_freq_cmd = 0) THEN
						v_freq_cmd := LLC_F_MAX;
					ELSE
						v_freq_cmd := LLC_F_MIN;
					END IF;
				ELSIF (v_freq_cmd > LLC_F_MAX) THEN
					v_freq_cmd := LLC_F_MAX;
				END IF;
				v_period := LLC_PERIOD_SCALE / v_freq_cmd;
				IF (v_period < LLC_PERIOD_MIN) THEN
					v_period := LLC_PERIOD_MIN;
				ELSIF (v_period > LLC_PERIOD_MAX) THEN
					v_period := LLC_PERIOD_MAX;
				END IF;
				w_llc_pwm_period_50 <= CONV_STD_LOGIC_VECTOR(v_period, 13);
			END IF;
		END IF;
	END PROCESS P_LLC_FREQ;

	-- P_PWM_CMD_SYNC：通信域(50M) -> PWM域(120M) 双拍同步后再送 llc_pwm_gen
	P_PWM_CMD_SYNC : PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1') THEN
			sig_Duty_sync_d0     <= (OTHERS => '0');
			sig_Duty_sync_d1     <= (OTHERS => '0');
			w_llc_period_sync_d0 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
			w_llc_period_sync_d1 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
		ELSIF (RISING_EDGE(sig_clkMHz)) THEN
			sig_Duty_sync_d0     <= sig_llc_duty_lim;
			sig_Duty_sync_d1     <= sig_Duty_sync_d0;
			w_llc_period_sync_d0 <= w_llc_pwm_period_50;
			w_llc_period_sync_d1 <= w_llc_period_sync_d0;
		END IF;
	END PROCESS P_PWM_CMD_SYNC;

	w_llc_pwm_duty   <= sig_Duty_sync_d1(9 DOWNTO 0);
	w_llc_pwm_period <= w_llc_period_sync_d1;

	U_LLC_PWM_GEN : entity work.llc_pwm_gen
		GENERIC MAP (
			CLK_FREQ => 120_000_000
		)
		PORT MAP (
			i_sys_clk    => sig_clkMHz,
			i_sys_rst    => sig_RES,
			i_pwm_en     => w_llc_pwm_en,
			i_pwm_period => w_llc_pwm_period,
			i_pwm_duty   => w_llc_pwm_duty,
			i_sr_en      => sig_sr_en,
			o_pwm1       => w_llc_pwm1,
			o_pwm2       => w_llc_pwm2,
			o_pwm3       => w_llc_pwm3,
			o_pwm4       => w_llc_pwm4,
			o_pwm5       => w_llc_pwm5,
			o_pwm6       => w_llc_pwm6,
			o_pwm7       => open,
			o_pwm8       => open
		);

	FLOE_DRV <= '0';
	zc_a     <= '0';
	zc_b     <= '0';
	zc_c     <= '0';

	-- PWM_DCbs：sig_Dauto 发波；sig_CLR/sig_Bs 关断（无软启动/均流）
	PWM_DCbs : PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1' or sig_Bs = '1') THEN
			sig_Dvft(12) <= '0';
			FL1S1_DRV    <= '0';
			FL1S2_DRV    <= '0';
			FL2S1_DRV    <= '0';
			FL2S2_DRV    <= '0';
			FL3S1_DRV    <= '0';
			FL3S2_DRV    <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (w_llc_pwm_en = '1') THEN
				sig_Dvft(12) <= '1';
				FL1S1_DRV    <= w_llc_pwm1;
				FL1S2_DRV    <= w_llc_pwm2;
				FL2S1_DRV    <= w_llc_pwm3;
				FL2S2_DRV    <= w_llc_pwm4;
				FL3S1_DRV    <= w_llc_pwm5;
				FL3S2_DRV    <= w_llc_pwm6;
			ELSE
				sig_Dvft(12) <= '0';
				FL1S1_DRV    <= '0';
				FL1S2_DRV    <= '0';
				FL2S1_DRV    <= '0';
				FL2S2_DRV    <= '0';
				FL3S1_DRV    <= '0';
				FL3S2_DRV    <= '0';
			END IF;
		END IF;
	END PROCESS PWM_DCbs;
	----------------------------------------------------------DC 桥臂（LLC PWM）---------------------------------------------------------------
	-----------------------------------------------------7.HB/DC 桥臂 PWM 驱动---------------------------------------------------------

	-------------------------------------------------8.直流电压/温度采样与保护-----------------------------------------------------------
	-- P_AMC1305: 双路 AMC1305，输出 UTh/UBh/UhO 及过压标志 UdGY
	P_AMC1305:AMC1305_16bit_Controller	PORT MAP(
		RESET		 => sig_RES,          --上电复位
		CLK_120MHZ	 => sig_clkMHz,    --120Mhz
		AMC1_SCLK	 => UAD1_CLK,      --芯片串行时钟
		AMC2_SCLK	 => UAD2_CLK,
		AMC1_DOUT	 => UAD1_DAT,      --芯片数据输出
		AMC2_DOUT	 => UAD2_DAT,
		DATA_16BIT1	 => sig_UTh,       
		DATA_16BIT2	 => sig_UBh,
		DATA_16BIT3	 => sig_UhO,
		OUT_UdGY	 => sig_UdGY );       --过压标志
------------------------------------------------------------------------------------------------------------------------------
	-- P_AMC1035: 5 路 AMC1035 温度采样，50MHz 时钟
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
	-------------------------------------------------8.直流电压/温度采样与保护-----------------------------------------------------------

	-----------------------------------------------------9.滤波与故障确认（fault_prot）-------------------------------------------------
	U_FAULT_PROT : entity work.fault_prot
		PORT MAP (
			i_sys_clk  => CLKIN,
			i_sys_rst  => sig_RES,
			i_clr      => sig_CLR,
			i_udgy     => sig_UdGY,
			i_t4       => sig_T4O,
			i_t5       => sig_T5O,
			i_t6       => sig_T6O,
			i_t7       => sig_T7O,
			i_t8       => sig_T8O,
			i_flt1     => F_FLT1,
			i_flt2     => F_FLT2,
			i_flt3     => F_FLT3,
			i_flt4     => F_FLT4,
			o_cerr10   => sig_Cerr(10),
			o_dvft_ot  => sig_Dvft(11 DOWNTO 7),
			o_dvft_hw  => sig_Dvft(3 DOWNTO 0)
		);
	-----------------------------------------------------9.滤波与故障确认（fault_prot）-------------------------------------------------

END BEHAV;
