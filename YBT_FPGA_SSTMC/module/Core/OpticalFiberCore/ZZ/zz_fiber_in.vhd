--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zz_fiber_in.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   ZZ 光纤输入：解析主控 FPGA 下行命令，并检测链路故障。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   收齐边沿当拍解析；故障检测复用 fiber_link_watchdog
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zz_fiber_in is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        DT_IN    : positive := 70           -- 下行帧宽：系统 -> 单元主控
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_led_res : in  std_logic;  -- LED 复位闪烁节拍

        -- PHY Receive
        i_fiber_r : in  std_logic;                            -- 系统侧光纤接收
        i_dt_in   : in  std_logic_vector(DT_IN - 1 downto 0); -- 下行原始帧
        i_finish  : in  std_logic;                            -- 一帧收发完成

        -- Downlink Decoded
        o_clr      : out std_logic;
        o_hpwm     : out std_logic;
        o_dauto    : out std_logic;
        o_dpwm_new : out std_logic;
        o_hpwma    : out std_logic;
        o_hpwmb    : out std_logic;
        o_idzl     : out std_logic_vector(15 downto 0);
        o_p15t     : out std_logic_vector(15 downto 0);
        o_p16t     : out std_logic_vector(15 downto 0);
        o_p17t     : out std_logic_vector(15 downto 0);
        o_p18t     : out std_logic_vector(15 downto 0);
        o_p19t     : out std_logic_vector(15 downto 0);
        o_p23t     : out std_logic_vector(15 downto 0);
        o_pt       : out std_logic_vector(15 downto 0);         --发送至从控下行帧原样透传
        o_duty     : out std_logic_vector(15 downto 0);

        -- Status
        o_cerr6 : out std_logic;  -- ZZ 光纤通信故障
        o_led   : out std_logic   -- F_LED1 通信心跳
    );
end entity zz_fiber_in;

architecture rtl of zz_fiber_in is

    constant D_AUTO_OFF_DELAY_CNT : positive := CLK_FREQ / 5_000;  -- D 关断延迟 200 us

    constant DUTY_MAX          : natural := 1023;  -- LLC 占空比上限
    constant CMD_CONFIRM_CNT   : natural := 5;     -- 命令连续相同计数到达值（共 6 帧）
    constant PARAM_CONFIRM_CNT : natural := 4;     -- 复用参数连续相同帧数
    constant LED_TOGGLE_FRAME  : natural := 5000;  -- LED 翻转间隔（帧）

    constant CMD_H_CLR : std_logic_vector(4 downto 0) := "01001";
    constant CMD_H_OFF : std_logic_vector(4 downto 0) := "10100";
    constant CMD_H_PWM : std_logic_vector(4 downto 0) := "11010";

    constant CMD_D_START : std_logic_vector(4 downto 0) := "10011";
    constant CMD_D_OFF   : std_logic_vector(4 downto 0) := "10100";
    constant CMD_D_AUTO  : std_logic_vector(4 downto 0) := "11010";

    constant PARAM_CH_P16 : std_logic_vector(2 downto 0) := "000";
    constant PARAM_CH_P17 : std_logic_vector(2 downto 0) := "001";
    constant PARAM_CH_P18 : std_logic_vector(2 downto 0) := "010";
    constant PARAM_CH_P19 : std_logic_vector(2 downto 0) := "011";
    constant PARAM_CH_P23 : std_logic_vector(2 downto 0) := "111";

    signal r_finish_d : std_logic := '0';
    signal r_clr      : std_logic := '0';
    signal r_hpwm     : std_logic := '0';
    signal r_dauto    : std_logic := '0';
    signal r_dpwm_new : std_logic := '0';
    signal r_hpwma    : std_logic := '0';
    signal r_hpwmb    : std_logic := '0';
    signal r_idzl     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p15t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p16t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p17t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p18t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p19t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_p23t     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_pt       : std_logic_vector(15 downto 0) := (others => '0');
    signal r_duty     : std_logic_vector(15 downto 0) := (others => '0');
    signal r_led_clk  : std_logic := '0';
    signal r_led      : std_logic := '0';

begin

    o_clr      <= r_clr;
    o_hpwm     <= r_hpwm;
    o_dauto    <= r_dauto;
    o_dpwm_new <= r_dpwm_new;
    o_hpwma    <= r_hpwma;
    o_hpwmb    <= r_hpwmb;
    o_idzl     <= r_idzl;
    o_p15t     <= r_p15t;
    o_p16t     <= r_p16t;
    o_p17t     <= r_p17t;
    o_p18t     <= r_p18t;
    o_p19t     <= r_p19t;
    o_p23t     <= r_p23t;
    o_pt       <= r_pt;
    o_duty     <= r_duty;
    o_led      <= r_led;

    U_WATCHDOG : entity work.fiber_link_watchdog
        generic map (
            CLK_FREQ => CLK_FREQ
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_clr     => r_clr,
            i_fiber_r => i_fiber_r,
            i_finish  => i_finish,
            o_cerr    => o_cerr6
        );

    -- ===================== 下行帧解析 =====================
    -- [69:54]占空比  [53:44]命令  [43:42]HB  [41:29]Idzl
    -- [28:16]P15t 频率(单位 10 Hz)  [15:0]复用参数
    process (i_sys_clk, i_sys_rst)
        variable v_cnt_c         : integer range 0 to 127 := 0;
        variable v_cnt_2p        : integer range 0 to 127 := 0;
        variable v_decd_c0       : std_logic_vector(9 downto 0) := (others => '0');
        variable v_decd_c1       : std_logic_vector(9 downto 0) := (others => '0');
        variable v_decd_2p0      : std_logic_vector(15 downto 0) := (others => '0');
        variable v_decd_2p1      : std_logic_vector(15 downto 0) := (others => '0');
        variable v_cnt_led       : integer range 0 to 8191 := 0;
        variable v_dstop_cnt     : integer range 0 to D_AUTO_OFF_DELAY_CNT - 1 := 0;
        variable v_dstop_pending : std_logic := '0';
        variable v_dstop_done    : std_logic := '0';
    begin
        if i_sys_rst = '1' then
            r_finish_d      <= '0';
            v_cnt_c         := 0;
            v_decd_c0       := (others => '0');
            v_decd_c1       := (others => '0');
            v_cnt_2p        := 0;
            v_decd_2p0      := (others => '0');
            v_decd_2p1      := (others => '0');
            r_clr           <= '0';
            r_hpwm          <= '0';
            r_dauto         <= '0';
            r_dpwm_new      <= '0';
            r_hpwma         <= '0';
            r_hpwmb         <= '0';
            r_idzl          <= (others => '0');
            r_p15t          <= (others => '0');
            r_p16t          <= (others => '0');
            r_p17t          <= (others => '0');
            r_p18t          <= (others => '0');
            r_p19t          <= (others => '0');
            r_p23t          <= (others => '0');
            r_pt            <= (others => '0');
            r_duty          <= (others => '0');
            v_cnt_led       := 0;
            r_led_clk       <= '1';
            v_dstop_cnt     := 0;
            v_dstop_pending := '0';
            v_dstop_done    := '0';
            r_led           <= '0';
        elsif rising_edge(i_sys_clk) then
            -- D 自动关断延迟：与命令解析同进程，保证 pending 当拍可见
            if v_dstop_pending = '1' then
                if v_dstop_cnt = D_AUTO_OFF_DELAY_CNT - 1 then
                    r_dauto         <= '0';
                    v_dstop_cnt     := 0;
                    v_dstop_pending := '0';
                    v_dstop_done    := '1';
                else
                    v_dstop_cnt := v_dstop_cnt + 1;
                end if;
            end if;

            if (i_finish = '1') and (r_finish_d = '0') then
                -- 1) 命令：连续 6 帧相同才更新 H/D 状态
                v_decd_c1 := i_dt_in(53 downto 44);
                if v_decd_c1 = v_decd_c0 then
                    if v_cnt_c = CMD_CONFIRM_CNT then
                        case v_decd_c0(9 downto 5) is
                            when CMD_H_CLR =>
                                r_clr  <= '1';
                                r_hpwm <= '0';
                            when CMD_H_OFF =>
                                r_clr  <= '0';
                                r_hpwm <= '0';
                            when CMD_H_PWM =>
                                r_clr  <= '0';
                                r_hpwm <= '1';
                            when others =>
                                null;
                        end case;

                        case v_decd_c0(4 downto 0) is
                            when CMD_D_START =>
                                if v_dstop_pending = '0' then
                                    r_dpwm_new <= '1';
                                end if;
                            when CMD_D_OFF =>
                                r_dpwm_new <= '0';
                                if (r_dauto = '1') and (v_dstop_pending = '0') and (v_dstop_done = '0') then
                                    v_dstop_cnt     := 0;
                                    v_dstop_pending := '1';
                                end if;
                            when CMD_D_AUTO =>
                                if v_dstop_pending = '0' then
                                    r_dauto      <= '1';
                                    r_dpwm_new   <= '0';
                                    v_dstop_done := '0';
                                end if;
                            when others =>
                                null;
                        end case;
                    else
                        v_cnt_c := v_cnt_c + 1;
                    end if;
                else
                    v_cnt_c   := 0;
                    v_decd_c0 := v_decd_c1;
                end if;

                -- 2) 每帧直更：HB / 电流指令 / 频率 / 占空比
                r_hpwma <= i_dt_in(43);
                r_hpwmb <= i_dt_in(42);
                r_idzl  <= i_dt_in(41 downto 29) & "000";
                r_p15t  <= "000" & i_dt_in(28 downto 16);

                if unsigned(i_dt_in(69 downto 54)) > DUTY_MAX then
                    r_duty <= std_logic_vector(to_unsigned(DUTY_MAX, 16));
                else
                    r_duty <= i_dt_in(69 downto 54);
                end if;

                -- 3) 复用参数：连续 4 帧相同才写入通道
                v_decd_2p1 := i_dt_in(15 downto 0);
                if v_decd_2p1 = v_decd_2p0 then
                    if v_cnt_2p < PARAM_CONFIRM_CNT then
                        v_cnt_2p := v_cnt_2p + 1;
                    end if;
                else
                    v_decd_2p0 := v_decd_2p1;
                    v_cnt_2p   := 1;
                end if;

                if v_cnt_2p = PARAM_CONFIRM_CNT then
                    r_pt <= v_decd_2p0;
                    case v_decd_2p0(15 downto 13) is
                        when PARAM_CH_P16 =>
                            r_p16t <= "000" & v_decd_2p0(12 downto 0);
                        when PARAM_CH_P17 =>
                            r_p17t <= "000" & v_decd_2p0(12 downto 0);
                        when PARAM_CH_P18 =>
                            r_p18t <= "000" & v_decd_2p0(12 downto 0);
                        when PARAM_CH_P19 =>
                            r_p19t <= "000" & v_decd_2p0(12 downto 0);
                        when PARAM_CH_P23 =>
                            r_p23t <= "000" & v_decd_2p0(12 downto 0);
                        when others =>
                            null;
                    end case;
                    v_cnt_2p := PARAM_CONFIRM_CNT + 1;
                end if;

                -- 4) 通信心跳
                if v_cnt_led >= LED_TOGGLE_FRAME then
                    v_cnt_led := 1;
                    r_led_clk <= not r_led_clk;
                else
                    v_cnt_led := v_cnt_led + 1;
                end if;
            end if;

            r_finish_d <= i_finish;
            r_led      <= r_led_clk xor i_led_res;
        end if;
    end process;

end architecture rtl;
