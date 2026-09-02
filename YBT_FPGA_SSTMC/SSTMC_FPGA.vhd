--------------------------------------------------------------------------------
-- 文件名    : SSTMC_FPGA.vhd
-- 模块名称  : SSTMC_FPGA（单元控制 FPGA 顶层）
-- 功能概述  : 本模块为 SSTMC 功率单元控制 FPGA 的行为级实现，包含：
--             1) 时钟/复位与 PLL 倍频（50 MHz -> 120 MHz）
--             2) 系统控制<->单元主控、单元主控<->单元接口 两路光纤通信
--             3) HB（半桥）与 DC（直流）双路 PWM 生成及桥臂驱动
--             4) 工作 DC 三相 PWM 与 BOOST 软启动 PWM
--             5) 三相电流均流 PI 控制（JLcon）
--             6) AMC1305/AMC1035 电压/温度采样
--             7) 故障检测、风扇、LED 指示及 PWM 保护
-- 主时钟    : CLKIN = 50 MHz
-- 内部高速时钟: sig_clkMHz = 120 MHz（由 sz_pll 产生）
-- 架构分区  : 0.LED | 1.复位+时钟 | 2.ZZ通信 | 3.ZC通信 | 4.均流PI
--             5.DC BOOST | 6.DC WORK | 7.HB/DC驱动 | 8.采样 | 9.硬件故障
--
-- sig_Cerr 故障字位定义（16bit）：
--   bit0  : ZC 光纤通信故障（接收停滞或帧完成超时）
--   bit1~4: 来自 ZC 接口侧故障子码
--   bit5  : 预留（固定 0）
--   bit6  : ZZ 光纤通信故障
--   bit7~9: 来自 ZC 接口侧故障子码
--   bit10 : 直流过压（P_GZSC，UdGY 持续 800*100us）
--   bit11 : 来自 ZC 接口侧故障
--   bit12 : 预留（风扇故障已停用，FFAN_FB1 改作 UART RX）
--   bit13 : 预留（固定 0）
--   bit14 : 预留（固定 0）
--   bit15 : 单元总故障（OR 汇总，见 BEGIN 组合逻辑）
--
-- sig_Dvft 设备故障字位定义（16bit）：
--   bit0~3 : 硬件 F_FLT1~4（当前赋值已注释，未生效）
--   bit4~6 : 来自 ZC 接口侧设备故障
--   bit7~11: AMC1035 五路温度过温（T4~T8，P_GZSC）
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
		-- 低电平有效，经 NumFI 滤波后写入 sig_Dvft（当前各故障位赋值已注释禁用）
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

		-- ======================== 调试 UART（原风扇接口复用） ========================
		FFAN_FB1				:	IN  STD_LOGIC;		-- UART RX（原风扇反馈）
		FFAN_PWM				:	OUT STD_LOGIC;		-- 风扇 PWM（已停用，固定为 0）
		FFAN_COM				:	OUT STD_LOGIC;		-- UART TX（原风扇公共端）

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

	-- ===================== BOOST 软启动 PWM 参数 =====================
	CONSTANT BS_MAXCNT	: INTEGER := 750;		-- 三角载波半周期：80kHz = 120MHz/2/750
	CONSTANT BS_MDUCNT	: INTEGER := 13653;		-- BOOST 调制常数（预留）
	CONSTANT D_AUTO_OFF_DELAY_CNT : INTEGER := 10000;	-- D关断延迟：10000/50MHz = 200us

	-- LLC PWM：开关频率 20~80 kHz → 120 MHz 时钟周期计数（period = 120M / (kHz*1000) = 120000/kHz）
	CONSTANT LLC_CLK_FREQ    : INTEGER := 120_000_000;
	CONSTANT LLC_F_MIN_KHZ   : INTEGER := 20;
	CONSTANT LLC_F_MAX_KHZ   : INTEGER := 80;
	CONSTANT LLC_PERIOD_MIN  : INTEGER := LLC_CLK_FREQ / (LLC_F_MAX_KHZ * 1000);	-- 1500 clk @80kHz
	CONSTANT LLC_PERIOD_MAX  : INTEGER := LLC_CLK_FREQ / (LLC_F_MIN_KHZ * 1000);	-- 6000 clk @20kHz
	CONSTANT LLC_PERIOD_SCALE  : INTEGER := LLC_CLK_FREQ / 1000;					-- 120000

	-- ===================== 死区/滤波/保护定时参数 =====================
	CONSTANT NumFI	:	INTEGER := 180;			-- 硬件故障滤波：180/50MHz = 3.6us
	CONSTANT NumHSQ	:	INTEGER := 192;			-- HB 死区：192/120MHz = 1.6us
	CONSTANT NumDSQ	:	INTEGER := 24;			-- DC 死区：24/120MHz = 200ns

	-- AMC1035 温度保护阈值（12bit 原始值）及确认时间
	CONSTANT T1safeACT  : INTEGER :=162;		-- T4/T5/T6 过温动作阈值
	CONSTANT T1safeRES  : INTEGER :=142;		-- T4/T5/T6 过温恢复阈值（滞回）
	CONSTANT T2safeACT  : INTEGER :=176;		-- T7/T8 过温动作阈值
	CONSTANT T2safeRES  : INTEGER :=156;		-- T7/T8 过温恢复阈值（滞回）
	CONSTANT TsafeTimer: INTEGER :=60000;		-- 过温确认：60000*100us = 6s

	-- ===================== 全局控制信号 =====================
	SIGNAL sig_RES		:  STD_LOGIC := '1';	-- 上电复位，高有效，约 1ms 后释放
	SIGNAL sig_clkMHz	:  STD_LOGIC := '0';	-- PLL 输出 120 MHz
	SIGNAL sig_clk20KHz	:  STD_LOGIC := '0';	-- 20 kHz，光纤通信位时钟
	SIGNAL sig_clk5Hz  	:  STD_LOGIC := '0';	-- 5 Hz，LED 慢闪节拍
	SIGNAL sig_ledres  	:  STD_LOGIC := '0';	-- LED 复位闪烁使能（上电约 5s）
	SIGNAL sig_Bs,sig_Dzgz,sig_OpenCLR,sig_OpenF:  STD_LOGIC := '0';
	SIGNAL led1_clk,led2_clk,led3_clk,led4_clk	:	STD_LOGIC := '0';

	COMPONENT sz_pll IS
		PORT (
			refclk   : IN  STD_LOGIC := 'X'; -- 参考时钟 50 MHz
			rst      : IN  STD_LOGIC := 'X'; -- 复位，高有效
			outclk_0 : OUT STD_LOGIC         -- 倍频输出 120 MHz
		);
	END COMPONENT sz_pll;

	-----------------------------------------------------系统-单元主控通信（ZZ）-----------------------------------------------------------
	CONSTANT zz_DELAY  :  INTEGER := 20;
	CONSTANT zz_dtIN   :  INTEGER := 54;		-- 下行帧宽：系统->单元主控
	CONSTANT zz_dtOUT  :  INTEGER := 51;		-- 上行帧宽：单元主控->系统
	SIGNAL sig_zzclk   :  STD_LOGIC := '0';
	SIGNAL sig_zzdtin  :  STD_LOGIC_VECTOR(zz_dtIN-1  DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zzdtout :  STD_LOGIC_VECTOR(zz_dtOUT-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zzFiberT:  STD_LOGIC := '0';		-- zz_t = NOT sig_zzFiberT
	SIGNAL sig_zzsinFt :  STD_LOGIC := '0';		-- ZZ 单次通信故障脉冲
	SIGNAL sig_zzFinish:  STD_LOGIC := '0';		-- ZZ 一帧收发完成
	SIGNAL sig_zzclk_r,sig_zzclk_edge		:	STD_LOGIC := '0';
	SIGNAL sig_zzFinish_r,sig_zzFinish_edge	:	STD_LOGIC := '0';
	SIGNAL sig_P15t,sig_P16t,sig_P17t,sig_P18t,sig_P19t	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_P23t,sig_Pt,sig_Idzl						:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_CLR,sig_HPwm,sig_Dpwm,sig_Dsoft			:	STD_LOGIC := '0';
	SIGNAL sig_I1O,sig_I2O,sig_I3O,sig_Cerr,sig_Dvft	:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_UhO,sig_UTh,sig_UBh						:	STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	-----------------------------------------------------系统-单元主控通信（ZZ）-----------------------------------------------------------

	---------------------------------------------------单元主控-单元接口通信（ZC）-----------------------------------------------------------
	CONSTANT zc_DELAY  :  INTEGER := 20;
	CONSTANT zc_dtIN   :  INTEGER := 43;		-- 下行帧宽：接口->单元主控
	CONSTANT zc_dtOUT  :  INTEGER := 21;		-- 上行帧宽：单元主控->接口
	SIGNAL sig_zcclk   :  STD_LOGIC := '0';
	SIGNAL sig_zcdtin  :  STD_LOGIC_VECTOR(zc_dtIN-1  DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zcdtout :  STD_LOGIC_VECTOR(zc_dtOUT-1 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_zcFiberT:  STD_LOGIC := '0';		-- zc_t = NOT sig_zcFiberT
	SIGNAL sig_zcsinFt :  STD_LOGIC := '0';		-- ZC 单次通信故障脉冲
	SIGNAL sig_zcFinish:  STD_LOGIC := '0';		-- ZC 一帧收发完成
	SIGNAL sig_zcclk_r,sig_zcclk_edge	:	STD_LOGIC := '0';
	SIGNAL sig_zcFinish_r,sig_zcFinish_edge	:	STD_LOGIC := '0';
	SIGNAL sig_T1O,sig_T2O,sig_T3O	:  STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_T1s,sig_T2s,sig_T3s	:  STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	---------------------------------------------------单元主控-单元接口通信（ZC）-----------------------------------------------------------
	------------------------------------------------------通信单元例化（TX_Comm）-------------------------------------------------------------

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
	------------------------------------------------------通信单元例化（TX_Comm）-------------------------------------------------------------

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

	SIGNAL CH1_fI,CH2_fI,CH3_fI:  INTEGER RANGE -500 TO 500 := 0;
	-------------------------------------------------------HB:PWM-----------------------------------------------------------
	SIGNAL sig_HPwma,sig_HPwmb,sig_HPwmDa,sig_HPwmDb	:	STD_LOGIC := '0';
	-------------------------------------------------------DC:PWM-----------------------------------------------------------
	SIGNAL sig_Dauto,sig_DPwm_new :	STD_LOGIC := '0';
	SIGNAL sig_Fauto:	INTEGER RANGE -32767 to 32767 := 0;
	SIGNAL sig_DCpwm14a,sig_DCpwm14b,sig_DCpwm14c 	:	STD_LOGIC := '0';
	SIGNAL sig_DCpwm14Da,sig_DCpwm14Db,sig_DCpwm14Dc:	STD_LOGIC := '0';
	SIGNAL sig_DBpwm14a,sig_DBpwm14b,sig_DBpwm14c 	:	STD_LOGIC := '0';
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

	-- LLC 全桥 PWM（llc_pwm_gen）接口
	SIGNAL sig_sr_en                              : STD_LOGIC := '0';  -- SR 使能占位，后续由用户接入
	SIGNAL w_llc_pwm_en                           : STD_LOGIC;
	SIGNAL w_llc_pwm_period_50                    : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL sig_P18t_r                             : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_P15t_sync_d0                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_P15t_sync_d1                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_llc_period_sync_d0                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_period_sync_d1                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_pwm_period                       : STD_LOGIC_VECTOR(12 DOWNTO 0);
	SIGNAL w_llc_pwm_duty                         : STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL w_llc_pwm1, w_llc_pwm2, w_llc_pwm3, w_llc_pwm4 : STD_LOGIC;
	SIGNAL w_llc_pwm5, w_llc_pwm6                 : STD_LOGIC;

	-- 调试 UART（FFAN_FB1=RX，FFAN_COM=TX，50 MHz / 115200 bps）
	CONSTANT C_UART_PARAM_COUNT : POSITIVE := 16;
	CONSTANT C_UART_DATA_WIDTH  : POSITIVE := 32;  -- VOFA+ RawData：每路 uint32 整数
	SIGNAL w_uart_mon_buf        : STD_LOGIC_VECTOR(C_UART_PARAM_COUNT * C_UART_DATA_WIDTH - 1 DOWNTO 0);
	SIGNAL w_uart_cmd_frame_vld  : STD_LOGIC;
	SIGNAL w_uart_cmd_frame_err  : STD_LOGIC;
	SIGNAL w_uart_cmd_start_addr : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL w_uart_cmd_length     : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL w_uart_cmd_data_wr_en : STD_LOGIC;
	SIGNAL w_uart_cmd_data_idx   : STD_LOGIC_VECTOR(7 DOWNTO 0);
	SIGNAL w_uart_cmd_data_word  : STD_LOGIC_VECTOR(15 DOWNTO 0);

	COMPONENT uart_debug_core
		GENERIC (
			CLK_FREQ       : POSITIVE := 50_000_000;
			UART_BPS       : POSITIVE := 115_200;
			PARAM_COUNT    : POSITIVE := 16;
			DATA_WIDTH     : POSITIVE := 32;
			MAX_DATA_WORDS : POSITIVE := 64
		);
		PORT (
			i_sys_clk        : IN  STD_LOGIC;
			i_sys_rst        : IN  STD_LOGIC;
			i_mon_buf        : IN  STD_LOGIC_VECTOR(PARAM_COUNT * DATA_WIDTH - 1 DOWNTO 0);
			o_uart_txd       : OUT STD_LOGIC;
			i_uart_rxd       : IN  STD_LOGIC;
			o_cmd_frame_vld  : OUT STD_LOGIC;
			o_cmd_frame_err  : OUT STD_LOGIC;
			o_cmd_start_addr : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			o_cmd_length     : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			o_cmd_data_wr_en : OUT STD_LOGIC;
			o_cmd_data_idx   : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
			o_cmd_data_word  : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
		);
	END COMPONENT;

	BEGIN

	sig_zzclk <= sig_clk20KHz;
	sig_zcclk <= sig_clk20KHz;
	sig_Dvft(13) <= '0';	sig_Dvft(14) <= '0';	sig_Cerr(5)  <= '0';	sig_Cerr(12) <= '0';	sig_Cerr(13) <= '0';	sig_Cerr(14) <= '0';
	sig_Cerr(15) <= (sig_Dzgz AND sig_OpenF) OR (sig_Cerr(0) AND sig_OpenF) OR sig_Cerr(6) OR sig_Cerr(10) OR sig_Dvft(0) OR sig_Dvft(1) OR sig_Dvft(2) OR sig_Dvft(3) OR sig_Dvft(7) OR sig_Dvft(8) OR sig_Dvft(9) OR sig_Dvft(10) OR sig_Dvft(11);
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
			sig_DCpwm14a_r <= w_llc_pwm1;
			IF ((w_llc_pwm1 = '1') AND (sig_DCpwm14a_r = '0')) THEN
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
	-- TrFAN: 三角波 PWM 风扇调速（已停用，引脚改接调试 UART）
--	TrFAN:PROCESS(sig_RES,FFAN_FB1,sig_Cerr(15),CLKIN)
--		VARIABLE updown1a :	STD_LOGIC := '0';
--		VARIABLE cnt1a	  :	INTEGER RANGE -16383 TO 16383 := 0;
--	BEGIN
--		IF (sig_RES = '1' OR FFAN_FB1 = '0' OR sig_Cerr(15) = '1') THEN
--			updown1a := '0';			cnt1a := 1000;
--			FFAN_PWM <= '0';			FFAN_COM <= '0';
--		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
--			IF (cnt1a >= 1000) THEN	updown1a := '0';
--			ELSIF (cnt1a <= 0) THEN	updown1a := '1';
--			END IF;
--			IF (updown1a = '1') THEN		cnt1a := cnt1a + 1;
--			ELSE						cnt1a := cnt1a - 1;
--			END IF;
--			IF (CONV_INTEGER(sig_P23t) <= cnt1a) THEN
--				FFAN_PWM <= '0';
--			ELSE
--				FFAN_PWM <= '1';
--			END IF;
--			FFAN_COM <= '1';
--		END IF;
--		sig_Cerr(12)<=NOT FFAN_FB1;
--	END PROCESS TrFAN;

	FFAN_PWM <= '0';

	-- 调试监测数据打包上行（16 路 × 32bit 整数，高 16 位补 0），打一拍打断宽总线组合路径
	P_UART_MON_BUF_REG : PROCESS(CLKIN)
	BEGIN
		IF RISING_EDGE(CLKIN) THEN
			w_uart_mon_buf <=
				x"0000" & sig_Cerr & x"0000" & sig_Dvft & x"0000" & sig_UTh & x"0000" & sig_UBh &
				x"0000" & sig_UhO & x"0000" & sig_T1O & x"0000" & sig_T2O & x"0000" & sig_T3O &
				x"0000" & sig_P15t & x"0000" & sig_P18t & x"0000" & sig_P23t & x"0000" & sig_Pt &
				x"0000" & sig_I1O & x"0000" & sig_I2O & x"0000" & sig_I3O & x"00000000";
		END IF;
	END PROCESS P_UART_MON_BUF_REG;

	P_UART_DEBUG : uart_debug_core
		GENERIC MAP (
			CLK_FREQ       => 50_000_000,
			UART_BPS       => 115_200,
			PARAM_COUNT    => C_UART_PARAM_COUNT,
			DATA_WIDTH     => C_UART_DATA_WIDTH,
			MAX_DATA_WORDS => 64
		)
		PORT MAP (
			i_sys_clk        => CLKIN,
			i_sys_rst        => sig_RES,
			i_mon_buf        => w_uart_mon_buf,
			o_uart_txd       => FFAN_COM,
			i_uart_rxd       => FFAN_FB1,
			o_cmd_frame_vld  => w_uart_cmd_frame_vld,
			o_cmd_frame_err  => w_uart_cmd_frame_err,
			o_cmd_start_addr => w_uart_cmd_start_addr,
			o_cmd_length     => w_uart_cmd_length,
			o_cmd_data_wr_en => w_uart_cmd_data_wr_en,
			o_cmd_data_idx   => w_uart_cmd_data_idx,
			o_cmd_data_word  => w_uart_cmd_data_word
		);
	-----------------------------------------------------1.复位+时钟-----------------------------------------------------------

	----------------------------------------------------2.系统-单元主控通信（ZZ）----------------------------------------------------------
	-- ZZ_sc: 20kHz 上升沿组帧上传；14 路子帧轮询（命令码 0001~1110）
	-- 帧头 bit50~46: 故障时 "01101"，正常时 "10110"
	-- 帧头 bit45~32: sig_Cerr(13:0) 故障状态
	-- 帧头 bit31~16: sig_UhO 高压侧电压
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
	-- ZZ_Error: 检测 zz_r 停滞 1ms 或 sig_zzFinish 超时 1ms，置 sig_Cerr(6)
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
	-- ZZ_COMM: TX_Comm 光纤收发 IP 例化（系统侧）
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
	-- ZZ_Decodeout: 解析下行命令与参数
	-- 命令码 var_DecdC0(9:5): 01001=清零, 10100=H关断, 11010=H_PWM
	-- 命令码 var_DecdC0(4:0): 10011=D启动, 10100=D关断, 11010=D_PWM(自动)
	ZZ_Decodeout:PROCESS(sig_RES, CLKIN)
		VARIABLE var_cntC,var_cnt2P 	:  INTEGER RANGE 0 TO 127 := 0;
		VARIABLE var_DecdC0,var_DecdC1	:  STD_LOGIC_VECTOR(9 DOWNTO 0) := (OTHERS => '0');
		VARIABLE var_Decd2P0,var_Decd2P1:  STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
		VARIABLE var_cnt_clk : INTEGER RANGE 0 TO 8191 := 0;
		VARIABLE var_Dstop_cnt     : INTEGER RANGE 0 TO D_AUTO_OFF_DELAY_CNT-1 := 0;
		VARIABLE var_Dstop_pending,var_Dstop_done : STD_LOGIC := '0';
	BEGIN
		IF (sig_RES = '1') THEN
			sig_zzFinish_r <= '0';			sig_zzFinish_edge <= '0';
			var_cntC   := 0;				var_DecdC0  := (OTHERS => '0');		var_DecdC1  := (OTHERS => '0');
			var_cnt2P  := 0;				var_Decd2P0 := (OTHERS => '0');		var_Decd2P1 := (OTHERS => '0');
			sig_CLR    <= '0';				sig_HPwm    <= '0';					sig_Dauto   <= '0';
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
							WHEN "01001" => sig_CLR <= '1'; sig_HPwm <= '0';
							WHEN "10100" => sig_CLR <= '0'; sig_HPwm <= '0';
							WHEN "11010" => sig_CLR <= '0'; sig_HPwm <= '1';
							WHEN OTHERS => NULL;
						END CASE;
						CASE var_DecdC0(4 DOWNTO 0) IS
							WHEN "10011" =>	IF (var_Dstop_pending = '0') THEN
												sig_DPwm_new <= '1';
											END IF;
							WHEN "10100" =>	sig_DPwm_new <= '0';
											IF (sig_Dauto = '1') AND (var_Dstop_pending = '0') AND (var_Dstop_done = '0') THEN
												var_Dstop_cnt := 0;		var_Dstop_pending := '1';
											END IF;
							WHEN "11010" =>	IF (var_Dstop_pending = '0') THEN
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
						WHEN "010" =>sig_P18t <= "000" & var_Decd2P0(12 DOWNTO 0);	-- LLC 开关频率(kHz)，20~80
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
	----------------------------------------------------2.系统-单元主控通信（ZZ）----------------------------------------------------------

	-------------------------------------------------3.单元主控-单元接口通信（ZC）---------------------------------------------------------
	-- ZC_sc: 20kHz 上升沿组帧；状态码 bit20~16:
	--   01001=CLR/OpenCLR, 10100=保护/默认, 11010=DPwm_new
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
	-- ZC_Error: 检测 zc_r 停滞或帧完成超时，置 sig_Cerr(0)
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
	-- ZC_COMM: TX_Comm 光纤收发 IP 例化（接口侧）
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
	-- ZC_Decodeout: 解析接口侧数据
	-- bit42~38: 01101=严重故障, 10110=正常
	-- bit37~35: 001/010/011=I1/I2/I3, 100=故障子码
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
	-------------------------------------------------3.单元主控-单元接口通信（ZC）---------------------------------------------------------

	----------------------------------------------------4.三相电流均流 PI（JLcon）-------------------------------------------------------
	-- 在 sig_zcclk 同步下执行 PI；Step 0~5 流水线
	-- ek = Ix - Idzl；uk = Kp*ek + Ki_accum/20000；输出 CHx_fI = uk/64（限幅 +/-500）
--	JLcon:PROCESS(sig_RES,CLKIN)
--		VARIABLE Step	:	INTEGER RANGE 0 TO 7 := 0;
--		VARIABLE CH1_ek,CH1_uk,CH2_ek,CH2_uk,CH3_ek,CH3_uk		:INTEGER RANGE -1073741823 TO 1073741823 := 0;
--		VARIABLE CH1_yk,CH1_yk1d,CH2_yk,CH2_yk1d,CH3_yk,CH3_yk1d:INTEGER RANGE -1073741823 TO 1073741823 := 0;
--	BEGIN
--		IF (sig_RES = '1') THEN
--			Step := 0;
--			CH1_ek   := 0;			CH1_uk   := 0;			CH1_yk   := 0;
--			CH1_yk1d := 0;			CH2_ek   := 0;			CH2_uk   := 0;
--			CH2_yk   := 0;			CH2_yk1d := 0;			CH3_ek   := 0;
--			CH3_uk   := 0;			CH3_yk   := 0;			CH3_yk1d := 0;
--			CH1_fI   <= 0;
--			CH2_fI   <= 0;
--			CH3_fI   <= 0;
--		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
--		    IF (sig_Fauto /= 1500) OR (sig_Bs = '1') OR (sig_CLR = '1') OR (sig_Dauto = '0') THEN
--				Step := 0;
--				CH1_ek   := 0;        CH2_ek   := 0;        CH3_ek   := 0;
--				CH1_uk   := 0;        CH2_uk   := 0;        CH3_uk   := 0;
--				CH1_yk   := 0;        CH1_yk1d := 0;        CH2_yk   := 0;
--				CH2_yk1d := 0;        CH3_yk   := 0;        CH3_yk1d := 0;
--				CH1_fI <= 0;        	CH2_fI <= 0;        CH3_fI <= 0;
--			ELSE
--				CASE Step IS
--					WHEN  0  =>	IF (sig_zcclk = '1') THEN
--									CH1_ek := CONV_INTEGER(sig_I1O)-CONV_INTEGER(sig_Idzl);
--									CH2_ek := CONV_INTEGER(sig_I2O)-CONV_INTEGER(sig_Idzl);
--									CH3_ek := CONV_INTEGER(sig_I3O)-CONV_INTEGER(sig_Idzl);
--									IF (CH1_ek >= 2047) THEN	CH1_ek := 2047;
--									ELSIF (CH1_ek < -2047) THEN	CH1_ek := -2047;
--									END IF;
--									IF (CH2_ek >= 2047) THEN	CH2_ek := 2047;
--									ELSIF (CH2_ek < -2047) THEN	CH2_ek := -2047;
--									END IF;
--									IF (CH3_ek >= 2047) THEN	CH3_ek := 2047;
--									ELSIF (CH3_ek < -2047) THEN	CH3_ek := -2047;
--									END IF;
--									Step := 1;
--								END IF;
--
--					WHEN  1  => CH1_yk := CH1_yk1d + CONV_INTEGER(sig_P17t)*CH1_ek;
--								CH2_yk := CH2_yk1d + CONV_INTEGER(sig_P17t)*CH2_ek;
--								CH3_yk := CH3_yk1d + CONV_INTEGER(sig_P17t)*CH3_ek;
--								IF (CH1_yk > 640000000) THEN 		CH1_yk := 640000000;
--								ELSIF (CH1_yk < -640000000) THEN	CH1_yk := -640000000;
--								END IF;
--								IF (CH2_yk > 640000000) THEN 		CH2_yk := 640000000;
--								ELSIF (CH2_yk < -640000000) THEN	CH2_yk := -640000000;
--								END IF;
--								IF (CH3_yk > 640000000) THEN 		CH3_yk := 640000000;
--								ELSIF (CH3_yk < -640000000) THEN	CH3_yk := -640000000;
--								END IF;
--								Step := 2;
--					WHEN  2  => Step := 3;
--					WHEN  3  => Step := 4;
--
--					WHEN  4  => CH1_uk := CONV_INTEGER(sig_P16t)*CH1_ek + CH1_yk/20000;	CH1_yk1d := CH1_yk;
--								CH2_uk := CONV_INTEGER(sig_P16t)*CH2_ek + CH2_yk/20000;	CH2_yk1d := CH2_yk;
--								CH3_uk := CONV_INTEGER(sig_P16t)*CH3_ek + CH3_yk/20000;	CH3_yk1d := CH3_yk;
--								IF (CH1_uk > 32000) THEN 		CH1_fI <= 500;
--								ELSIF (CH1_uk < -32000) THEN	CH1_fI <= -500;
--								ELSE 							CH1_fI <= CH1_uk/64;
--								END IF;
--								IF (CH2_uk > 32000) THEN 		CH2_fI <= 500;
--								ELSIF (CH2_uk < -32000) THEN	CH2_fI <= -500;
--								ELSE 							CH2_fI <= CH2_uk/64;
--								END IF;
--								IF (CH3_uk > 32000) THEN 		CH3_fI <= 500;
--								ELSIF (CH3_uk < -32000) THEN	CH3_fI <= -500;
--								ELSE 							CH3_fI <= CH3_uk/64;
--								END IF;
--								Step := 5;
--
--					WHEN  5  =>	IF (sig_zcclk = '0') THEN
--									Step := 0;
--								END IF;
--
--					WHEN OTHERS =>	NULL;
--				END CASE;
--			END IF;
--		END IF;
--	END PROCESS JLcon;
	----------------------------------------------------4.三相电流均流 PI（JLcon）-------------------------------------------------------

	----------------------------------------------------5.DC BOOST 软启动 PWM-----------------------------------------------------------
	-- BS_DC 状态机 Step 0~5:
	--   0: 等待 sig_Dauto=1，进入软启动
	--   1: var_Drive 1000->4900 爬升（每 64000 周期 +1，约 5s）
	--   2: 延时 1250 周期（25us@50M）后切工作 PWM
	--   3: sig_Fauto 750->1500 频率爬升
	--   4: 等待 50s 后 sig_OpenCLR=0, sig_OpenF=1
	--   5: 维持运行，sig_Dauto=0 时回 Step 0
--	BS_DC:PROCESS(sig_RES, CLKIN)
--		VARIABLE Step  		:	INTEGER RANGE 0 TO 7 := 0;
--		VARIABLE var_cnt	:	INTEGER RANGE 0 TO 67108863 := 0;
--		VARIABLE var_Drive  :	INTEGER RANGE 0 TO 8191 := 1000;
--	BEGIN
--		IF (sig_RES = '1') THEN
--			Step := 0;				var_cnt := 0;			var_Drive := 0;			Driveou1 <=0;
--			sig_Dsoft <= '0';		sig_Dpwm  <= '0';		sig_Fauto<= 750;
--			sig_OpenCLR <= '0';		sig_OpenF <= '0';
--		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
--			IF (sig_Bs = '1') OR (sig_CLR = '1') OR (sig_Dauto = '0') THEN
--				Step := 0;			var_cnt := 0;			var_Drive := 0;			Driveou1 <= 0;
--				sig_Dsoft <= '0';	sig_Dpwm  <= '0';		sig_Fauto <= 750;
--				sig_OpenCLR <= '0';
--			ELSE
--				CASE Step IS
--					WHEN 0	=>	IF (sig_Dauto = '1') THEN
--									var_cnt := 0;		sig_Dsoft <= '1';		sig_Dpwm <= '0';		Step := 1;		var_Drive := 1000;
--								END IF;
--					WHEN 1	=>	var_cnt := var_cnt + 1;
--								IF  (var_cnt >= 64000) THEN
--									var_cnt := 0;
--									IF (var_Drive <= 4900) THEN
--										var_Drive := var_Drive + 1;
--									ELSE				sig_Dsoft <= '0';		sig_Dpwm <= '0';		Step := 2;
--									END IF;
--								END IF;
--					WHEN 2	=>	var_cnt := var_cnt + 1;
--								IF (var_cnt >= 1250) THEN
--									var_cnt := 0;		sig_Dsoft <= '0';		sig_Dpwm <= '1';		Step := 3;		sig_Fauto<= 750;
--								END IF;
--					WHEN 3	=>	var_cnt := var_cnt + 1;
--								IF (var_cnt >= 200000) THEN
--									var_cnt := 0;
--									IF (sig_Fauto = 1499) THEN
--										sig_Fauto   <= 1500;	Step := 4;
--										sig_OpenCLR <= '1';		sig_OpenF   <= '0';
--									ELSE
--										sig_Fauto <= sig_Fauto + 1;
--									END IF;
--								END IF;
--					WHEN 4	=>	var_cnt := var_cnt + 1;
--								IF (var_cnt >= 50000000) THEN
--									var_cnt := 0;		Step := 5;
--									sig_OpenCLR <= '0';	sig_OpenF <= '1';
--								END IF;
--					WHEN 5	=>	IF (sig_Dauto = '0') THEN
--									var_cnt := 0;		sig_Dsoft <= '0';		sig_Dpwm <= '0';		Step := 0;
--								END IF;
--					WHEN OTHERS => NULL;
--				END CASE;
--			END IF;
--		Driveou1 <= (var_Drive * 307) / 4096;
--		END IF;
--	END PROCESS BS_DC;
------------------------------------------------------------------------------------------------------------------------------
	-- BS_PWM: 三相 80kHz 三角载波，Driveou1 控制 BOOST 占空比
--	BS_PWM:PROCESS(sig_RES,sig_clkMHz)
--		VARIABLE updown1a,updown2a,updown3a	:	STD_LOGIC := '0';
--		VARIABLE var_cnt1,var_cnt2,var_cnt3	:	INTEGER RANGE -32767 TO 32767 := 0;
--	BEGIN
--		IF (sig_RES = '1') THEN
--			updown1a := '0';			updown2a := '1';			updown3a := '0';
--			var_cnt1 := BS_MAXCNT;		var_cnt2 := BS_MAXCNT/3;	var_cnt3 := BS_MAXCNT/3;
--			sig_DBpwm14a<= '0';			sig_DBpwm14b<= '0';			sig_DBpwm14c<= '0';
--			sig_DBpwm23a<= '0';			sig_DBpwm23b<= '0';			sig_DBpwm23c<= '0';
--		ELSIF (sig_clkMHz'EVENT AND sig_clkMHz = '1') THEN
--			IF (var_cnt1 >= BS_MAXCNT) THEN	updown1a := '0';
--			ELSIF (var_cnt1 <= 0) THEN	updown1a := '1';
--			END IF;
--			IF (updown1a = '1') THEN	var_cnt1 := var_cnt1 + 1;
--			ELSE						var_cnt1 := var_cnt1 - 1;
--			END IF;
--
--			IF (var_cnt2 >= BS_MAXCNT) THEN	updown2a := '0';
--			ELSIF (var_cnt2 <= 0) THEN	updown2a := '1';
--			END IF;
--			IF (updown2a = '1') THEN	var_cnt2 := var_cnt2 + 1;
--			ELSE						var_cnt2 := var_cnt2 - 1;
--			END IF;
--
--			IF (var_cnt3 >= BS_MAXCNT) THEN	updown3a := '0';
--			ELSIF (var_cnt3 <= 0) THEN	updown3a := '1';
--			END IF;
--			IF (updown3a = '1') THEN	var_cnt3 := var_cnt3 + 1;
--			ELSE						var_cnt3 := var_cnt3 - 1;
--			END IF;
--
--			IF ( Driveou1 >= var_cnt1 ) 			THEN sig_DBpwm14a <= '1';	ELSE sig_DBpwm14a <= '0';	END IF;
--			IF ( var_cnt1 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23a <= '1';	ELSE sig_DBpwm23a <= '0';	END IF;
--
--			IF ( Driveou1 >= var_cnt2 ) 			THEN sig_DBpwm14b <= '1';	ELSE sig_DBpwm14b <= '0';	END IF;
--			IF ( var_cnt2 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23b <= '1';	ELSE sig_DBpwm23b <= '0';	END IF;
--
--			IF ( Driveou1 >= var_cnt3 ) 			THEN sig_DBpwm14c <= '1';	ELSE sig_DBpwm14c <= '0';	END IF;
--			IF ( var_cnt3 >= (BS_MAXCNT-Driveou1) ) THEN sig_DBpwm23c <= '1'; 	ELSE sig_DBpwm23c <= '0';	END IF;
--		END IF;
--	END PROCESS BS_PWM;
	----------------------------------------------------5.DC BOOST 软启动 PWM-----------------------------------------------------------

	----------------------------------------------------6.DC WORK PWM（三相三角载波）---------------------------------------------------
	-- CALC_NEW_MAX: 计算下一周期峰值 = P15t + Fauto - CHx_fI，限幅 750~2000
--	CALC_NEW_MAX : PROCESS(sig_RES, CLKIN)
--		VARIABLE var_new_a : INTEGER;
--		VARIABLE var_new_b : INTEGER;
--		VARIABLE var_new_c : INTEGER;
--	BEGIN
--		IF sig_RES = '1' THEN
--			new_max_a <= 750;
--			new_max_b <= 750;
--			new_max_c <= 750;
--
--		ELSIF RISING_EDGE(CLKIN) THEN
--
--			var_new_a := CONV_INTEGER(sig_P15t) + sig_Fauto - CH1_fI;
--			var_new_b := CONV_INTEGER(sig_P15t) + sig_Fauto - CH2_fI;
--			var_new_c := CONV_INTEGER(sig_P15t) + sig_Fauto - CH3_fI;
--
--			IF var_new_a < 750 THEN
--				new_max_a <= 750;
--			ELSIF var_new_a > 2000 THEN
--				new_max_a <= 2000;
--			ELSE
--				new_max_a <= var_new_a;
--			END IF;
--
--			IF var_new_b < 750 THEN
--				new_max_b <= 750;
--			ELSIF var_new_b > 2000 THEN
--				new_max_b <= 2000;
--			ELSE
--				new_max_b <= var_new_b;
--			END IF;
--
--			IF var_new_c < 750 THEN
--				new_max_c <= 750;
--			ELSIF var_new_c > 2000 THEN
--				new_max_c <= 2000;
--			ELSE
--				new_max_c <= var_new_c;
--			END IF;
--
--		END IF;
--	END PROCESS CALC_NEW_MAX;
--
--	-- UPDATE_THRESHOLD: 在三角波峰/谷点更新 max/half，避免周期内跳变
--	UPDATE_THRESHOLD : PROCESS(sig_RES, sig_clkMHz)
--	BEGIN
--		IF sig_RES = '1' THEN
--			max_a   <= 750;		half_a  <= 375;
--			max_b   <= 750;		half_b  <= 375;
--			max_c   <= 750;		half_c  <= 375;
--		ELSIF RISING_EDGE(sig_clkMHz) THEN
--			IF cnt_a <= 0 OR cnt_a >= max_a THEN
--				max_a <= new_max_a;
--				half_a <= new_max_a / 2;
--			END IF;
--
--			IF cnt_b <= 0 OR cnt_b >= max_b THEN
--				max_b <= new_max_b;
--				half_b <= new_max_b / 2;
--			END IF;
--
--			IF cnt_c <= 0 OR cnt_c >= max_c THEN
--				max_c <= new_max_c;
--				half_c <= new_max_c / 2;
--			END IF;
--
--		END IF;
--	END PROCESS UPDATE_THRESHOLD;
--
--	-- PHASE_PROC: 120MHz 三相独立三角载波；cnt>=half 时 PWM 高；B/C 相初始相位 215/270
--	PHASE_PROC : PROCESS(sig_RES,sig_clkMHz)
--	BEGIN
--		IF sig_RES = '1'	THEN
--			up_a <= '0';			cnt_a <= 750;			sig_DCpwm14a <= '0';		sig_zca <= '0';
--			up_b <= '1';			cnt_b <= 215;			sig_DCpwm14b <= '0';		sig_zcb <= '0';
--			up_c <= '0';			cnt_c <= 270;			sig_DCpwm14c <= '0';		sig_zcc <= '0';
--		ELSIF RISING_EDGE(sig_clkMHz) THEN
--			IF cnt_a <= 1 		THEN
--				up_a <= '1';	cnt_a <= 0;
--			ELSIF cnt_a >= max_a - 1 THEN
--				up_a <= '0';	cnt_a <= max_a;
--			END IF;
--			IF up_a = '1' 		THEN
--				cnt_a <= cnt_a + 1;
--			ELSE
--				cnt_a <= cnt_a - 1;
--			END IF;
--
--			IF cnt_b <= 1 		THEN
--				up_b <= '1';	cnt_b <= 0;
--			ELSIF cnt_b >= max_b -1 THEN
--				up_b <= '0';	cnt_b <= max_b;
--			END IF;
--			IF up_b = '1' 		THEN
--				cnt_b <= cnt_b + 1;
--			ELSE
--				cnt_b <= cnt_b - 1;
--			END IF;
--
--			IF cnt_c <= 1 		THEN
--				up_c <= '1';	cnt_c <= 0;
--			ELSIF cnt_c >= max_c -1  THEN
--				up_c <= '0';	cnt_c <= max_c;
--			END IF;
--			IF up_c = '1' 		THEN
--				cnt_c <= cnt_c + 1;
--			ELSE
--				cnt_c <= cnt_c - 1;
--			END IF;
--
--			IF cnt_a >= half_a    THEN
--				sig_DCpwm14a <= '1';
--				sig_zca <= '1';
--			ELSE
--				sig_DCpwm14a <= '0';
--				sig_zca <= '0';
--			END IF;
--			IF cnt_b >= half_b    THEN
--				sig_DCpwm14b <= '1';
--				sig_zcb <= '1';
--			ELSE
--				sig_DCpwm14b <= '0';
--				sig_zcb <= '0';
--			END IF;
--			IF cnt_c >= half_c    THEN
--				sig_DCpwm14c <= '1';
--				sig_zcc <= '1';
--			ELSE
--				sig_DCpwm14c <= '0';
--				sig_zcc <= '0';
--			END IF;
--
--		END IF;
--	END PROCESS PHASE_PROC;
	-----------------------------------------------------6.DC WORK PWM（三相三角载波）------------------------------------------------

	-----------------------------------------------------7.HB/DC 桥臂 PWM 驱动---------------------------------------------------------
	----------------------------------------------------------HB 半桥---------------------------------------------------------------
	-- SqHBPWM: HB 死区 NumHSQ=192@120MHz=1.6us，延迟 sig_HPwma/b 至 sig_HPwmDa/Db
	SqHBPWM:PROCESS(sig_RES, sig_clkMHz)
		VARIABLE var_cnta,var_cntb : INTEGER RANGE 0 TO 255 := 0;
	BEGIN
		IF (sig_RES = '1') THEN
			var_cnta := 0;			var_cntb := 0;
			sig_HPwmDa <= '0';		sig_HPwmDb <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (sig_HPwma = sig_HPwmDa) THEN   --sig_HPwma 原始PWM sig_HPwmDa 延时PWM (当电平相同)
				var_cnta := 0;
			ELSIF (var_cnta >= NumHSQ) THEN    --经过死区时间（允许跟随）
				var_cnta := 0;				
				sig_HPwmDa <= sig_HPwma;
			ELSE                               --累加计数值
				var_cnta := var_cnta + 1;
			END IF;
			IF (sig_HPwmb = sig_HPwmDb) THEN
				var_cntb := 0;
			ELSIF (var_cntb >= NumHSQ) THEN
				var_cntb := 0;				
				sig_HPwmDb <= sig_HPwmB;
			ELSE
				var_cntb := var_cntb + 1;
			END IF;
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
	-- SqDCPWM: DC 死区 NumDSQ=24@120MHz=200ns
--	SqDCPWM:PROCESS(sig_RES, sig_clkMHz)
--		VARIABLE var_cnta,var_cntb,var_cntc : INTEGER RANGE 0 TO 255 := 0;
--	BEGIN
--		IF (sig_RES = '1') THEN
--			var_cnta := 0;				var_cntb := 0;				var_cntc := 0;
--			sig_DCpwm14Da <= '0';		sig_DCpwm14Db <= '0';		sig_DCpwm14Dc <= '0';
--		ELSIF RISING_EDGE(sig_clkMHz) THEN
--			IF (sig_DCpwm14a = sig_DCpwm14Da) THEN
--				var_cnta := 0;
--			ELSIF (var_cnta >= NumDSQ) THEN
--				var_cnta := 0;				
--				sig_DCpwm14Da <= sig_DCpwm14a;
--			ELSE
--				var_cnta := var_cnta + 1;
--			END IF;
--
--			IF (sig_DCpwm14b = sig_DCpwm14Db) THEN
--				var_cntb := 0;
--			ELSIF (var_cntb >= NumDSQ) THEN
--				var_cntb := 0;				
--				sig_DCpwm14Db <= sig_DCpwm14b;
--			ELSE
--				var_cntb := var_cntb + 1;
--			END IF;
--
--			IF (sig_DCpwm14c = sig_DCpwm14Dc) THEN
--				var_cntc := 0;
--			ELSIF (var_cntc >= NumDSQ) THEN
--				var_cntc := 0;				
--				sig_DCpwm14Dc <= sig_DCpwm14c;
--			ELSE
--				var_cntc := var_cntc + 1;
--			END IF;
--		END IF;
--	END PROCESS SqDCPWM;
--------------------------------------------------------------------------------------------------------------------------------
--	FLOE_DRV <= '0';
--	-- PWM_DCbs: sig_Dpwm=工作模式桥臂驱动；sig_Dsoft=BOOST 软启动模式
--	PWM_DCbs:PROCESS(sig_RES, sig_clkMHz)
--	BEGIN
--		IF (sig_RES = '1') THEN
--			sig_Dvft(12) <= '0';
--			FL1S1_DRV <= '0';			FL1S2_DRV <= '0';
--			FL2S1_DRV <= '0';			FL2S2_DRV <= '0';
--			FL3S1_DRV <= '0';			FL3S2_DRV <= '0';
--		ELSIF RISING_EDGE(sig_clkMHz) THEN
--			IF (sig_CLR = '1') THEN
--				sig_Dvft(12) <= '0';
--				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
--				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
--				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
--			ELSIF (sig_Bs = '1') THEN
--				sig_Dvft(12) <= '0';
--				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
--				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
--				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
--			ELSIF (sig_Dpwm = '1') THEN
--				sig_Dvft(12) <= '1';
--				FL1S1_DRV <= sig_DCpwm14a AND sig_DCpwm14Da;				
--				FL1S2_DRV <= NOT (sig_DCpwm14a OR sig_DCpwm14Da);
--				FL2S1_DRV <= sig_DCpwm14b AND sig_DCpwm14Db;				
--				FL2S2_DRV <= NOT (sig_DCpwm14b OR sig_DCpwm14Db);
--				FL3S1_DRV <= sig_DCpwm14c AND sig_DCpwm14Dc;				
--				FL3S2_DRV <= NOT (sig_DCpwm14c OR sig_DCpwm14Dc);
--			ELSIF (sig_Dsoft = '1') THEN
--				sig_Dvft(12) <= '1';
--				FL1S1_DRV <= sig_DBpwm14a;				
--				FL1S2_DRV <= sig_DBpwm23a;
--				FL2S1_DRV <= sig_DBpwm14b;				
--				FL2S2_DRV <= sig_DBpwm23b;
--				FL3S1_DRV <= sig_DBpwm14c;				
--				FL3S2_DRV <= sig_DBpwm23c;
--			ELSE
--				sig_Dvft(12) <= '0';
--				FL1S1_DRV <= '0';		FL1S2_DRV <= '0';
--				FL2S1_DRV <= '0';		FL2S2_DRV <= '0';
--				FL3S1_DRV <= '0';		FL3S2_DRV <= '0';
--			END IF;
--		END IF;
--	END PROCESS PWM_DCbs;
--	zc_a<=sig_zca;
--	zc_b<=sig_zcb;
--	zc_c<=sig_zcc;
	----------------------------------------------------------DC 桥臂（LLC PWM）---------------------------------------------------------------
	-- 占空比：sig_P15t(9:0)；频率：sig_P18t 为 kHz（20~80），period = 120000 / kHz
	-- 系统经 ZZ Pt 子帧 type=010 写入 sig_P18t；未给定(0)时默认 80kHz
	-- P_LLC_FREQ：50 MHz 进程，仅在 sig_P18t 变化时重算周期，消除组合除法器
	P_LLC_FREQ : PROCESS(sig_RES, CLKIN)
		VARIABLE v_freq_khz : INTEGER RANGE 0 TO 8191;
		VARIABLE v_period   : INTEGER RANGE 0 TO 8191;
	BEGIN
		IF (sig_RES = '1') THEN
			sig_P18t_r          <= (OTHERS => '0');
			w_llc_pwm_period_50 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
		ELSIF (RISING_EDGE(CLKIN)) THEN
			IF (sig_P18t /= sig_P18t_r) THEN
				sig_P18t_r <= sig_P18t;
				v_freq_khz := CONV_INTEGER(sig_P18t);
				IF (v_freq_khz < LLC_F_MIN_KHZ) THEN
					IF (v_freq_khz = 0) THEN
						v_freq_khz := LLC_F_MAX_KHZ;
					ELSE
						v_freq_khz := LLC_F_MIN_KHZ;
					END IF;
				ELSIF (v_freq_khz > LLC_F_MAX_KHZ) THEN
					v_freq_khz := LLC_F_MAX_KHZ;
				END IF;
				v_period := LLC_PERIOD_SCALE / v_freq_khz;
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
			sig_P15t_sync_d0     <= (OTHERS => '0');
			sig_P15t_sync_d1     <= (OTHERS => '0');
			w_llc_period_sync_d0 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
			w_llc_period_sync_d1 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
		ELSIF (RISING_EDGE(sig_clkMHz)) THEN
			sig_P15t_sync_d0     <= sig_P15t;
			sig_P15t_sync_d1     <= sig_P15t_sync_d0;
			w_llc_period_sync_d0 <= w_llc_pwm_period_50;
			w_llc_period_sync_d1 <= w_llc_period_sync_d0;
		END IF;
	END PROCESS P_PWM_CMD_SYNC;

	w_llc_pwm_duty   <= sig_P15t_sync_d1(9 DOWNTO 0);
	w_llc_pwm_period <= w_llc_period_sync_d1;
	w_llc_pwm_en     <= '1' WHEN (sig_Dauto = '1' AND sig_CLR = '0' AND sig_Bs = '0') ELSE '0';

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
		IF (sig_RES = '1') THEN
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
	-- P_GZSC: 100us 节拍（2500*50M）；UdGY 持续 800 次置 sig_Cerr(10)
	-- T4~T6 用 T1safeACT/RES；T7/T8 用 T2safeACT/RES；持续 TsafeTimer 次置 sig_Dvft(7~11)
	--在50M/100us节拍下、确认直流过压 确认5路温度过高
	P_GZSC:PROCESS(sig_RES, sig_CLR, CLKIN)
		VARIABLE var_cnt_clk    : INTEGER RANGE 0 TO 4095 := 0;     --生成本进程的采样节拍
		VARIABLE var_GYcnt      : INTEGER RANGE 0 TO 4095 := 0;     --过压信号的持续计数
		VARIABLE var_T4cnt,var_T5cnt,var_T6cnt,var_T7cnt,var_T8cnt : INTEGER RANGE 0 TO 65535 := 0;  --5路温度的超限计数
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1') THEN
			var_cnt_clk := 0;		var_GYcnt := 0;
			var_T4cnt := 0;			var_T5cnt := 0;			var_T6cnt := 0;			var_T7cnt := 0;			var_T8cnt := 0;
			sig_Cerr(10) <= '0';	sig_Dvft(11 DOWNTO 7) <= "00000";
		ELSIF (RISING_EDGE(CLKIN)) THEN      
			var_cnt_clk := var_cnt_clk + 1;
			IF (var_cnt_clk = 2500) THEN     --50us执行一次过压与过温判断
				var_cnt_clk := 0;
				IF (sig_UdGY = '1') THEN
					IF (var_GYcnt >= 800) THEN      --过压确认40ms
					sig_Cerr(10) <= '1';
					ELSE var_GYcnt := var_GYcnt + 1; END IF;
				ELSE
					var_GYcnt := 0;
				END IF;

				IF(CONV_INTEGER(sig_T4O)>T1safeACT) THEN    --超过安全值且超过温度限值即满足要求
					IF(var_T4cnt>=TsafeTimer) THEN
						sig_Dvft(7) <= '1';
					ELSE
						var_T4cnt:=var_T4cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T4O)<T1safeRES) THEN
					var_T4cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T5O)>T1safeACT) THEN
					IF(var_T5cnt>=TsafeTimer) THEN
						sig_Dvft(8) <= '1';
					ELSE
						var_T5cnt:=var_T5cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T5O)<T1safeRES) THEN
					var_T5cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T6O)>T1safeACT) THEN
					IF(var_T6cnt>=TsafeTimer) THEN
						sig_Dvft(9) <= '1';
					ELSE
						var_T6cnt:=var_T6cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T6O)<T1safeRES) THEN
					var_T6cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T7O)>T2safeACT) THEN
					IF(var_T7cnt>=TsafeTimer) THEN
						sig_Dvft(10) <= '1';
					ELSE
						var_T7cnt:=var_T7cnt+1;
					END IF;
				ELSIF(CONV_INTEGER(sig_T7O)<T2safeRES) THEN
					var_T7cnt:=0;
				END IF;
				IF(CONV_INTEGER(sig_T8O)>T2safeACT) THEN
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
	-------------------------------------------------8.直流电压/温度采样与保护-----------------------------------------------------------

	-----------------------------------------------------9.硬件故障输入滤波-----------------------------------------------------------
	-- Dv_Ft: F_FLT1~4 低电平持续 NumFI(3.6us) 后置 sig_Dvft(0~3)（当前赋值已注释）
	Dv_Ft:PROCESS(sig_RES,sig_CLR,CLKIN)
		VARIABLE var_1cnt,var_2cnt,var_3cnt,var_4cnt:INTEGER RANGE 0 TO 511 := 0;   --滤波计数器
	BEGIN
		IF (sig_RES = '1' OR sig_CLR = '1') THEN
			var_1cnt    := 0;			var_2cnt    := 0;			var_3cnt    := 0;			var_4cnt    := 0;
			sig_Dvft(0) <= '0';			sig_Dvft(1) <= '0';			sig_Dvft(2) <= '0';			sig_Dvft(3) <= '0';
		ELSIF (CLKIN'EVENT AND CLKIN = '1') THEN
			IF (F_FLT1 = '0') THEN
				IF (var_1cnt >= NumFI) THEN
					--sig_Dvft(0) <= '1';
				ELSE
					var_1cnt := var_1cnt + 1;
				END IF;
			ELSE
				var_1cnt := 0;
			END IF;
			IF (F_FLT2 = '0') THEN
				IF (var_2cnt >= NumFI) THEN
					--sig_Dvft(1) <= '1';
				ELSE
					var_2cnt := var_2cnt + 1;
				END IF;
			ELSE
				var_2cnt := 0;
			END IF;
			IF (F_FLT3 = '0') THEN
				IF (var_3cnt >= NumFI) THEN
					--sig_Dvft(2) <= '1';
				ELSE
					var_3cnt := var_3cnt + 1;
				END IF;
			ELSE
				var_3cnt := 0;
			END IF;
			IF (F_FLT4 = '0') THEN
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
	-----------------------------------------------------9.硬件故障输入滤波-----------------------------------------------------------

END BEHAV;
