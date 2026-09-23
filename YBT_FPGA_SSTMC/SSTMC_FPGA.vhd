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
-- 架构分区  : 0.LED | 1.复位+时钟+delay | 2.ZZ通信 | 3.ZC通信 | 7.HB/DC驱动 | 8.采样 | 9.故障滤波
--
-- sig_Cerr 故障字位定义（16bit）：
--   bit0  : ZC 光纤通信故障（接收停滞或帧完成超时）
--   bit1~4: 来自 ZC 接口侧故障子码
--   bit5  : 预留（固定 0）
--   bit6  : ZZ 光纤通信故障
--   bit7~9: 来自 ZC 接口侧故障子码
--   bit10 : 直流过压（fault_prot，滤波后 UTh+UBh 滞回后持续 40*1ms）
--   bit11 : 来自 ZC 接口侧故障
--   bit12 : 预留（FFAN_FB1 暂作 TZ，原风扇反馈位停用）
--   bit13 : LLC PWM TZ（FFAN_FB1 低/下降沿锁存，仅复位可清）
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
		FFAN_FB1				:	IN  STD_LOGIC;		-- 暂作 LLC TZ：默认高，低/下降沿锁存关断（仅复位清）
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
	CONSTANT LLC_PERIOD_50KHZ  : INTEGER := LLC_CLK_FREQ / 50_000;	-- 2400：f≤50k → period≥此
	CONSTANT LLC_PERIOD_52KHZ  : INTEGER := LLC_CLK_FREQ / 52_000;	-- 2307：f>52k → period≤此
	CONSTANT LLC_DUTY_FULL     : INTEGER := 1023;					-- 占空比满码
	CONSTANT LLC_PERIOD_SCALE  : INTEGER := LLC_CLK_FREQ / LLC_F_UNIT_HZ;					-- 12000000
	CONSTANT LLC_DIV_DVD_W     : INTEGER := 24;	-- 12_000_000 需 24 位
	CONSTANT LLC_DIV_DVS_W     : INTEGER := 13;	-- 频率给定限幅后 2000~8000
	CONSTANT C_LLC_DIVIDEND    : STD_LOGIC_VECTOR(LLC_DIV_DVD_W - 1 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_SCALE, LLC_DIV_DVD_W);

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
	-----------------------------------------------------直流电压/温度采样（AMC1305/AMC1035）----------------------------------------------

	SIGNAL sig_HPwma,sig_HPwmb,sig_HPwmDa,sig_HPwmDb	:	STD_LOGIC := '0';
	SIGNAL sig_Dauto,sig_DPwm_new :	STD_LOGIC := '0';
	SIGNAL sig_HPwma_r,sig_llc_pwm1_r : STD_LOGIC := '0';
	SIGNAL sig_HPwma_edge,sig_llc_pwm1_edge : STD_LOGIC := '0';

	-- LLC 全桥 PWM（llc_pwm_gen）接口
	SIGNAL sig_sr_en                              : STD_LOGIC := '0';  -- SR 使能（预留）
	SIGNAL sig_llc_duty_lim                       : STD_LOGIC_VECTOR(15 DOWNTO 0);	-- 限幅后占空比 0~1023
	SIGNAL w_llc_en_cmd                           : STD_LOGIC;  -- LLC 使能命令（不含 TZ 关断）
	SIGNAL w_llc_pwm_en                           : STD_LOGIC;
	SIGNAL w_llc_tz_lat_120                       : STD_LOGIC := '0';
	SIGNAL w_llc_tz_lat_50                        : STD_LOGIC := '0';
	SIGNAL w_llc_pwm_period_50                    : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL sig_llc_freq_r                         : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_llc_div_start                        : STD_LOGIC := '0';
	SIGNAL w_llc_div_divisor                      : STD_LOGIC_VECTOR(LLC_DIV_DVS_W - 1 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_F_MAX, LLC_DIV_DVS_W);
	SIGNAL w_llc_div_quot                         : STD_LOGIC_VECTOR(LLC_DIV_DVD_W - 1 DOWNTO 0);
	SIGNAL w_llc_div_done                         : STD_LOGIC;
	SIGNAL w_llc_div_busy                         : STD_LOGIC;
	SIGNAL sig_Duty_sync_d0                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL sig_Duty_sync_d1                       : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_llc_period_sync_d0                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_period_sync_d1                   : STD_LOGIC_VECTOR(12 DOWNTO 0) := CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
	SIGNAL w_llc_pwm_period                       : STD_LOGIC_VECTOR(12 DOWNTO 0);
	SIGNAL w_llc_pwm_duty                         : STD_LOGIC_VECTOR(9 DOWNTO 0);
	SIGNAL w_llc_pwm1, w_llc_pwm2, w_llc_pwm3, w_llc_pwm4 : STD_LOGIC;
	SIGNAL w_llc_pwm5, w_llc_pwm6                 : STD_LOGIC;

	-- delay_core 公共时基（50 MHz）：1us/1ms/1s 脉冲 → fault_prot 等
	SIGNAL w_delay_1us : STD_LOGIC;
	SIGNAL w_delay_1ms : STD_LOGIC;
	SIGNAL w_delay_1s  : STD_LOGIC;

	-- filter_core（50 MHz）：电压帧完成→高速；1 ms 计数→低速（温度）；输出暂不外供
	SIGNAL w_amc1305_valid              : STD_LOGIC := '0';
	SIGNAL w_filt_v_tog                 : STD_LOGIC := '0';
	SIGNAL w_filt_v_tog_d0              : STD_LOGIC := '0';
	SIGNAL w_filt_v_tog_d1              : STD_LOGIC := '0';
	SIGNAL w_filt_v_tog_d2              : STD_LOGIC := '0';
	SIGNAL w_filt_hs_pulse              : STD_LOGIC := '0';
	SIGNAL w_filt_ls_pulse              : STD_LOGIC := '0';
	SIGNAL w_filt_ls_cnt                : INTEGER RANGE 0 TO 49999 := 0;
	SIGNAL w_filt_uth_d0                : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_uth_d1                : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_ubh_d0                : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_ubh_d1                : STD_LOGIC_VECTOR(15 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t4_d0                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t4_d1                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t5_d0                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t5_d1                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t6_d0                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t6_d1                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t7_d0                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t7_d1                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t8_d0                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_t8_d1                 : STD_LOGIC_VECTOR(11 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_bus_pos_i             : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_bus_neg_i             : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_temp1_i               : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_temp2_i               : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_temp3_i               : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_temp4_i               : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_temp5_i               : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0) := (OTHERS => '0');
	SIGNAL w_filt_hs_bus_pos            : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_hs_bus_neg            : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_bus_pos            : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_bus_neg            : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_temp1              : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_temp2              : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_temp3              : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_temp4              : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);
	SIGNAL w_filt_ls_temp5              : IEEE.NUMERIC_STD.SIGNED(31 DOWNTO 0);

	-- 暂不外供：保留综合结果，便于 SignalTap
	ATTRIBUTE keep : BOOLEAN;
	ATTRIBUTE keep OF w_filt_hs_bus_pos : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_hs_bus_neg : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_bus_pos : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_bus_neg : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_temp1   : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_temp2   : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_temp3   : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_temp4   : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_filt_ls_temp5   : SIGNAL IS TRUE;

	-- bus_balance_pi：50 MHz；使能=满占空+ f≤50k 后第 2 个 1ms；清除见过程
	SIGNAL w_bal_phase_q : IEEE.NUMERIC_STD.SIGNED(15 DOWNTO 0);
	SIGNAL w_bal_err     : IEEE.NUMERIC_STD.SIGNED(15 DOWNTO 0);
	SIGNAL w_bal_enable  : STD_LOGIC := '0';
	SIGNAL w_bal_clear   : STD_LOGIC := '0';
	ATTRIBUTE keep OF w_bal_phase_q : SIGNAL IS TRUE;
	ATTRIBUTE keep OF w_bal_err     : SIGNAL IS TRUE;

	BEGIN

	sig_Dvft(13) <= '0';	sig_Dvft(14) <= '0';	sig_Cerr(5)  <= '0';	sig_Cerr(12) <= '0';	sig_Cerr(14) <= '0';
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
	-- TrFAN: 三角波 PWM 风扇调速（占空比由 sig_P23t 给定）。FFAN_FB1 暂作 LLC TZ，不参与风扇启停
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

	-- delay_core：50 MHz 公共时基；供 fault_prot 等模块统一计时
	U_DELAY_CORE : entity work.delay_core
		GENERIC MAP (
			CLK_FREQ => 50_000_000
		)
		PORT MAP (
			i_sys_clk   => CLKIN,
			i_sys_rst   => sig_RES,
			o_delay_1us => w_delay_1us,
			o_delay_1ms => w_delay_1ms,
			o_delay_1s  => w_delay_1s
		);
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
			-- 上行电压/本地温度用滤波后量（高速母线、低速温度）
			i_uth      => STD_LOGIC_VECTOR(w_filt_hs_bus_pos(15 DOWNTO 0)),
			i_ubh      => STD_LOGIC_VECTOR(w_filt_hs_bus_neg(15 DOWNTO 0)),
			i_i1o      => sig_I1O,
			i_i2o      => sig_I2O,
			i_i3o      => sig_I3O,
			i_t1s      => sig_T1s,
			i_t2s      => sig_T2s,
			i_t3s      => sig_T3s,
			i_t4o      => STD_LOGIC_VECTOR(w_filt_ls_temp1(11 DOWNTO 0)),
			i_t5o      => STD_LOGIC_VECTOR(w_filt_ls_temp2(11 DOWNTO 0)),
			i_t6o      => STD_LOGIC_VECTOR(w_filt_ls_temp3(11 DOWNTO 0)),
			i_t7o      => STD_LOGIC_VECTOR(w_filt_ls_temp4(11 DOWNTO 0)),
			i_t8o      => STD_LOGIC_VECTOR(w_filt_ls_temp5(11 DOWNTO 0)),
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
	-- LLC 使能命令（光纤）；TZ 锁存后强制关断，仅复位可恢复
	w_llc_en_cmd <= '1' WHEN (sig_Dauto = '1' AND sig_CLR = '0' AND sig_Bs = '0') ELSE '0';
	w_llc_pwm_en <= '0' WHEN (w_llc_tz_lat_50 = '1') ELSE w_llc_en_cmd;

	-- TZ：FFAN_FB1；使能后前 2 个 PWM 脉冲屏蔽；120M/50M 各自锁存电平（仅复位清）
	U_LLC_TZ : entity work.llc_tz_prot
		GENERIC MAP (
			BLANK_PULSES => 2
		)
		PORT MAP (
			i_sys_clk_120 => sig_clkMHz,
			i_sys_rst     => sig_RES,
			i_tz_in       => FFAN_FB1,
			i_pwm_en_cmd  => w_llc_en_cmd,
			i_pwm_pulse   => w_llc_pwm1,
			i_sys_clk_50  => CLKIN,
			o_tz_lat_120  => w_llc_tz_lat_120,
			o_tz_lat_50   => w_llc_tz_lat_50
		);
	sig_Cerr(13) <= w_llc_tz_lat_50;

	-- 频率 sig_P15t 单位 10Hz。0 或 >8000 按 80kHz，<2000 按 20kHz。
	-- 除法在 U_LLC_PERIOD_DIV；给定变了且模块空闲时启动，o_done 后把商写入周期。
	P_LLC_FREQ : PROCESS(sig_RES, CLKIN)
		VARIABLE v_freq_cmd : INTEGER RANGE 0 TO 8191;
	BEGIN
		IF (sig_RES = '1') THEN
			sig_llc_freq_r      <= (OTHERS => '0');
			w_llc_pwm_period_50 <= CONV_STD_LOGIC_VECTOR(LLC_PERIOD_MIN, 13);
			w_llc_div_start     <= '0';
			w_llc_div_divisor   <= CONV_STD_LOGIC_VECTOR(LLC_F_MAX, LLC_DIV_DVS_W);
		ELSIF (RISING_EDGE(CLKIN)) THEN
			w_llc_div_start <= '0';

			IF (w_llc_div_done = '1') THEN
				w_llc_pwm_period_50 <= w_llc_div_quot(12 DOWNTO 0);
			END IF;

			IF (sig_P15t /= sig_llc_freq_r) AND (w_llc_div_busy = '0') AND (w_llc_div_start = '0') THEN
				sig_llc_freq_r <= sig_P15t;
				v_freq_cmd := CONV_INTEGER(sig_P15t);
				IF (v_freq_cmd = 0) OR (v_freq_cmd > LLC_F_MAX) THEN
					v_freq_cmd := LLC_F_MAX;
				ELSIF (v_freq_cmd < LLC_F_MIN) THEN
					v_freq_cmd := LLC_F_MIN;
				END IF;
				w_llc_div_divisor <= CONV_STD_LOGIC_VECTOR(v_freq_cmd, LLC_DIV_DVS_W);
				w_llc_div_start   <= '1';
			END IF;
		END IF;
	END PROCESS P_LLC_FREQ;

	-- 24 位 / 13 位，50 MHz 下 24 拍完成；被除数固定为 12_000_000
	U_LLC_PERIOD_DIV : entity work.unsigned_division
		GENERIC MAP (
			WIDTH_DVD => LLC_DIV_DVD_W,
			WIDTH_DVS => LLC_DIV_DVS_W
		)
		PORT MAP (
			i_sys_clk   => CLKIN,
			i_sys_rst   => sig_RES,
			i_start     => w_llc_div_start,
			i_dividend  => C_LLC_DIVIDEND,
			i_divisor   => w_llc_div_divisor,
			o_quotient  => w_llc_div_quot,
			o_remainder => OPEN,
			o_done      => w_llc_div_done,
			o_busy      => w_llc_div_busy,
			o_div_zero  => OPEN
		);

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
			-- 均压：i_phase_clk = (o_phase_q×period)>>14，与 bus_balance 同极性直连
			-- +：1 超前 4；-：1 滞后 4（示波器 TBPHS；台架反了只改 err 或此处取反一次）
			i_phase_clk  => (others => '0'),
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

	-- PWM_DCbs：sig_Dauto 发波；sig_CLR/sig_Bs/TZ 关断（无软启动/均流）
	-- TZ 锁存进异步复位支路，尽快把驱动拉低
	PWM_DCbs : PROCESS(sig_RES, sig_Bs, w_llc_tz_lat_120, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1' OR sig_Bs = '1' OR w_llc_tz_lat_120 = '1') THEN
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
	-- U_AMC1305: 双路 AMC1305 Sinc3，输出 UTh/UBh/UhO；过压标志固定为 0
	U_AMC1305 : entity work.amc1305_16bit_controller
		port map (
			i_sys_clk   => sig_clkMHz,
			i_sys_rst   => sig_RES,
			o_amc1_sclk => UAD1_CLK,
			o_amc2_sclk => UAD2_CLK,
			i_amc1_dout => UAD1_DAT,
			i_amc2_dout => UAD2_DAT,
			o_data_ch1  => sig_UTh,
			o_data_ch2  => sig_UBh,
			o_data_sum  => sig_UhO,
			o_udgy      => sig_UdGY,
			o_valid     => w_amc1305_valid
		);
------------------------------------------------------------------------------------------------------------------------------
	-- U_AMC1035: 五路 AMC1035 Sinc3 温度采样，SCLK 10 MHz
	U_AMC1035 : entity work.amc1035_5ch_controller
		port map (
			i_sys_clk   => CLKIN,
			i_sys_rst   => sig_RES,
			o_amc1_sclk => F_T1CLK,
			o_amc2_sclk => F_T2CLK,
			o_amc3_sclk => F_T3CLK,
			o_amc4_sclk => F_T4CLK,
			o_amc5_sclk => F_T5CLK,
			i_amc1_dout => F_T1OUT,
			i_amc2_dout => F_T2OUT,
			i_amc3_dout => F_T3OUT,
			i_amc4_dout => F_T4OUT,
			i_amc5_dout => F_T5OUT,
			o_data_ch1  => sig_T4O,
			o_data_ch2  => sig_T5O,
			o_data_ch3  => sig_T6O,
			o_data_ch4  => sig_T7O,
			o_data_ch5  => sig_T8O,
			o_valid     => OPEN
		);
------------------------------------------------------------------------------------------------------------------------------
	-- 电压完成：120 M → toggle；50 M 域还原单脉冲，避免 1 拍 120 M 脉冲漏采
	P_FILT_V_TOG : PROCESS(sig_RES, sig_clkMHz)
	BEGIN
		IF (sig_RES = '1') THEN
			w_filt_v_tog <= '0';
		ELSIF RISING_EDGE(sig_clkMHz) THEN
			IF (w_amc1305_valid = '1') THEN
				w_filt_v_tog <= NOT w_filt_v_tog;
			END IF;
		END IF;
	END PROCESS P_FILT_V_TOG;

	-- 50 M：同步母线/温度；HS=电压帧；LS=1 ms 计数（温度与低速母线）
	P_FILT_TRIG : PROCESS(sig_RES, CLKIN)
	BEGIN
		IF (sig_RES = '1') THEN
			w_filt_v_tog_d0  <= '0';
			w_filt_v_tog_d1  <= '0';
			w_filt_v_tog_d2  <= '0';
			w_filt_hs_pulse  <= '0';
			w_filt_ls_pulse  <= '0';
			w_filt_ls_cnt    <= 0;
			w_filt_uth_d0    <= (OTHERS => '0');
			w_filt_uth_d1    <= (OTHERS => '0');
			w_filt_ubh_d0    <= (OTHERS => '0');
			w_filt_ubh_d1    <= (OTHERS => '0');
			w_filt_t4_d0     <= (OTHERS => '0');
			w_filt_t4_d1     <= (OTHERS => '0');
			w_filt_t5_d0     <= (OTHERS => '0');
			w_filt_t5_d1     <= (OTHERS => '0');
			w_filt_t6_d0     <= (OTHERS => '0');
			w_filt_t6_d1     <= (OTHERS => '0');
			w_filt_t7_d0     <= (OTHERS => '0');
			w_filt_t7_d1     <= (OTHERS => '0');
			w_filt_t8_d0     <= (OTHERS => '0');
			w_filt_t8_d1     <= (OTHERS => '0');
			w_filt_bus_pos_i <= (OTHERS => '0');
			w_filt_bus_neg_i <= (OTHERS => '0');
			w_filt_temp1_i   <= (OTHERS => '0');
			w_filt_temp2_i   <= (OTHERS => '0');
			w_filt_temp3_i   <= (OTHERS => '0');
			w_filt_temp4_i   <= (OTHERS => '0');
			w_filt_temp5_i   <= (OTHERS => '0');
		ELSIF RISING_EDGE(CLKIN) THEN
			w_filt_v_tog_d0 <= w_filt_v_tog;
			w_filt_v_tog_d1 <= w_filt_v_tog_d0;
			w_filt_v_tog_d2 <= w_filt_v_tog_d1;
			w_filt_hs_pulse <= w_filt_v_tog_d1 XOR w_filt_v_tog_d2;

			w_filt_uth_d0 <= sig_UTh;
			w_filt_uth_d1 <= w_filt_uth_d0;
			w_filt_ubh_d0 <= sig_UBh;
			w_filt_ubh_d1 <= w_filt_ubh_d0;
			w_filt_t4_d0  <= sig_T4O;
			w_filt_t4_d1  <= w_filt_t4_d0;
			w_filt_t5_d0  <= sig_T5O;
			w_filt_t5_d1  <= w_filt_t5_d0;
			w_filt_t6_d0  <= sig_T6O;
			w_filt_t6_d1  <= w_filt_t6_d0;
			w_filt_t7_d0  <= sig_T7O;
			w_filt_t7_d1  <= w_filt_t7_d0;
			w_filt_t8_d0  <= sig_T8O;
			w_filt_t8_d1  <= w_filt_t8_d0;

			w_filt_bus_pos_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_uth_d1), 32);
			w_filt_bus_neg_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_ubh_d1), 32);
			w_filt_temp1_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_t4_d1), 32);
			w_filt_temp2_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_t5_d1), 32);
			w_filt_temp3_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_t6_d1), 32);
			w_filt_temp4_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_t7_d1), 32);
			w_filt_temp5_i <= IEEE.NUMERIC_STD.RESIZE(
				IEEE.NUMERIC_STD.SIGNED(w_filt_t8_d1), 32);

			-- 50 MHz / 50000 = 1 kHz，与 filter_core LS_FS 对齐
			IF (w_filt_ls_cnt = 49999) THEN
				w_filt_ls_cnt   <= 0;
				w_filt_ls_pulse <= '1';
			ELSE
				w_filt_ls_cnt   <= w_filt_ls_cnt + 1;
				w_filt_ls_pulse <= '0';
			END IF;
		END IF;
	END PROCESS P_FILT_TRIG;

	-- 高速母线 → ZZ 上行 + fault_prot；低速温度 → ZZ 上行 + fault_prot；LS 母线暂不外供
	U_FILTER_CORE : entity work.filter_core
		GENERIC MAP (
			CLK_FREQ => 50_000_000,
			HS_FS    => 78125,
			HS_WC_HZ => 800,
			LS_FS    => 1000,
			LS_WC_HZ => 100
		)
		PORT MAP (
			i_sys_clk         => CLKIN,
			i_sys_rst         => sig_RES,
			i_hs_sample_pulse => w_filt_hs_pulse,
			i_ls_sample_pulse => w_filt_ls_pulse,
			i_bus_pos         => w_filt_bus_pos_i,
			i_bus_neg         => w_filt_bus_neg_i,
			i_temp1           => w_filt_temp1_i,
			i_temp2           => w_filt_temp2_i,
			i_temp3           => w_filt_temp3_i,
			i_temp4           => w_filt_temp4_i,
			i_temp5           => w_filt_temp5_i,
			o_hs_bus_pos      => w_filt_hs_bus_pos,
			o_hs_bus_neg      => w_filt_hs_bus_neg,
			o_ls_bus_pos      => w_filt_ls_bus_pos,
			o_ls_bus_neg      => w_filt_ls_bus_neg,
			o_ls_temp1        => w_filt_ls_temp1,
			o_ls_temp2        => w_filt_ls_temp2,
			o_ls_temp3        => w_filt_ls_temp3,
			o_ls_temp4        => w_filt_ls_temp4,
			o_ls_temp5        => w_filt_ls_temp5
		);

	-- 均压使能/清除（50 MHz）：
	--   使能条件：LLC 使能 ∧ 占空比满 ∧ f≤50kHz → 用 1ms 节拍计数，满占空第 2 个 1ms 后开始
	--             之后每个 1ms 脉冲一次 i_enable
	--   清除条件：LLC 未使能 ∨ 占空比=0 ∨ f>52kHz ∨ TZ → i_clear，计数器清零
	P_BAL_EN : PROCESS(sig_RES, CLKIN)
		VARIABLE v_period : INTEGER;
		VARIABLE v_duty   : INTEGER;
		VARIABLE v_cnt    : INTEGER RANGE 0 TO 3 := 0;
		VARIABLE v_run    : STD_LOGIC := '0';
		VARIABLE v_arm    : BOOLEAN;
		VARIABLE v_abort  : BOOLEAN;
	BEGIN
		IF (sig_RES = '1') THEN
			v_cnt        := 0;
			v_run        := '0';
			w_bal_enable <= '0';
			w_bal_clear  <= '1';
		ELSIF RISING_EDGE(CLKIN) THEN
			-- 13 位无符号周期（1500~6000）。CONV_INTEGER 按有符号看，bit12=1 会变成负数。
			v_period := IEEE.NUMERIC_STD.to_integer(IEEE.NUMERIC_STD.unsigned(w_llc_pwm_period_50));
			v_duty   := CONV_INTEGER(sig_llc_duty_lim);
			v_abort  := (w_llc_pwm_en = '0') OR (v_duty = 0) OR (v_period <= LLC_PERIOD_52KHZ)
			            OR (w_llc_tz_lat_50 = '1');
			v_arm    := (w_llc_pwm_en = '1') AND (v_duty >= LLC_DUTY_FULL) AND (v_period >= LLC_PERIOD_50KHZ);

			w_bal_enable <= '0';

			IF v_abort THEN
				v_cnt        := 0;
				v_run        := '0';
				w_bal_clear  <= '1';
			ELSE
				w_bal_clear <= '0';
				IF v_arm THEN
					IF (w_delay_1ms = '1') THEN
						IF (v_run = '0') THEN
							IF (v_cnt < 2) THEN
								v_cnt := v_cnt + 1;
							END IF;
							IF (v_cnt >= 2) THEN
								v_run := '1';
							END IF;
						END IF;
						IF (v_run = '1') THEN
							-- w_bal_enable <= '1';
							   w_bal_enable <= '0';
						END IF;
					END IF;
				ELSE
					-- 未满占空/未到 ≤50k：停计但不清积分（直至 abort）
					v_cnt := 0;
				END IF;
			END IF;
		END IF;
	END PROCESS P_BAL_EN;

	-- 均压 PI：高速滤波母线（低 16bit 码）
	U_BUS_BALANCE : entity work.bus_balance_pi
		PORT MAP (
			i_sys_clk  => CLKIN,
			i_sys_rst  => sig_RES,
			i_enable   => w_bal_enable,
			i_clear    => w_bal_clear,
			i_bus_pos  => w_filt_hs_bus_pos(15 DOWNTO 0),
			i_bus_neg  => w_filt_hs_bus_neg(15 DOWNTO 0),
			i_kp       => (OTHERS => '0'),
			i_ki       => (OTHERS => '0'),
			o_phase_q  => w_bal_phase_q,
			o_err      => w_bal_err
		);
------------------------------------------------------------------------------------------------------------------------------
	-------------------------------------------------8.直流电压/温度采样与保护-----------------------------------------------------------

	-----------------------------------------------------9.滤波与故障确认（fault_prot）-------------------------------------------------
	U_FAULT_PROT : entity work.fault_prot
		PORT MAP (
			i_sys_clk    => CLKIN,
			i_sys_rst    => sig_RES,
			i_clr        => sig_CLR,
			i_delay_1us  => w_delay_1us,
			i_delay_1ms  => w_delay_1ms,
			i_delay_1s   => w_delay_1s,
			i_uth        => w_filt_hs_bus_pos,
			i_ubh        => w_filt_hs_bus_neg,
			i_t4         => w_filt_ls_temp1,
			i_t5         => w_filt_ls_temp2,
			i_t6         => w_filt_ls_temp3,
			i_t7         => w_filt_ls_temp4,
			i_t8         => w_filt_ls_temp5,
			i_flt1       => F_FLT1,
			i_flt2       => F_FLT2,
			i_flt3       => F_FLT3,
			i_flt4       => F_FLT4,
			o_dc_ov      => sig_Cerr(10),
			o_dvft_ot    => sig_Dvft(11 DOWNTO 7),
			o_dvft_hw    => sig_Dvft(3 DOWNTO 0),
			o_bus_imbal  => open   -- 压差故障暂不上报、不外用
		);
	-----------------------------------------------------9.滤波与故障确认（fault_prot）-------------------------------------------------

END BEHAV;
