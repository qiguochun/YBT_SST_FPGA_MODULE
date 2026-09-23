--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_tz_prot.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   LLC Trip Zone（TZ）保护。
--                      i_tz_in 默认高；稳定低或下降沿锁存故障（仅复位可清）。
--                      自 LLC 使能命令有效起，先计 BLANK_PULSES 个 PWM 上升沿
--                      再开放检测（对应 git：第一次启动前两个脉冲屏蔽）。
--                      使能撤销则屏蔽计数清零，下次使能重新计脉冲。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   自顶层抽出独立模块；屏蔽改为使能后 N 个 PWM 脉冲
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity llc_tz_prot is
    generic (
        BLANK_PULSES : natural := 2  -- 使能后屏蔽脉冲数
    );
    port (
        -- 120 MHz 域（快速锁存 / 停波）
        i_sys_clk_120 : in  std_logic;
        i_sys_rst     : in  std_logic;  -- 异步复位，高有效
        i_tz_in       : in  std_logic;  -- TZ 脚，默认高；低/下降沿锁存
        i_pwm_en_cmd  : in  std_logic;  -- LLC 使能命令（不含 TZ 关断）
        i_pwm_pulse   : in  std_logic;  -- 用于屏蔽计数的 PWM（如 pwm1）

        -- 50 MHz 域（故障字 / 均压清除）
        i_sys_clk_50  : in  std_logic;

        o_tz_lat_120  : out std_logic;  -- 120M 锁存，供驱动异步关断
        o_tz_lat_50   : out std_logic   -- 50M 同步后锁存
    );
end entity llc_tz_prot;

architecture rtl of llc_tz_prot is

    signal r_tz_d0       : std_logic := '1';
    signal r_tz_d1       : std_logic := '1';
    signal r_en_d0       : std_logic := '0';
    signal r_en_d1       : std_logic := '0';
    signal r_pwm_d0      : std_logic := '0';
    signal r_pwm_d1      : std_logic := '0';
    signal r_blank_cnt   : integer range 0 to BLANK_PULSES := 0;
    signal r_det_en      : std_logic := '0';
    signal r_tz_lat_120  : std_logic := '0';

    signal r_tz_50_d0    : std_logic := '0';
    signal r_tz_lat_50   : std_logic := '0';

    signal w_pwm_rise    : std_logic;

begin

    o_tz_lat_120 <= r_tz_lat_120;
    o_tz_lat_50  <= r_tz_lat_50;

    w_pwm_rise <= r_pwm_d0 and (not r_pwm_d1);

    -- ===================== 120 M：同步 + 脉冲屏蔽 + 锁存 =====================
    process (i_sys_clk_120, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tz_d0      <= '1';
            r_tz_d1      <= '1';
            r_en_d0      <= '0';
            r_en_d1      <= '0';
            r_pwm_d0     <= '0';
            r_pwm_d1     <= '0';
            r_blank_cnt  <= 0;
            r_det_en     <= '0';
            r_tz_lat_120 <= '0';
        elsif rising_edge(i_sys_clk_120) then
            r_en_d0  <= i_pwm_en_cmd;
            r_en_d1  <= r_en_d0;
            r_pwm_d0 <= i_pwm_pulse;
            r_pwm_d1 <= r_pwm_d0;
            r_tz_d0  <= i_tz_in;
            r_tz_d1  <= r_tz_d0;

            if r_en_d1 = '0' then
                r_blank_cnt <= 0;
                r_det_en    <= '0';
            elsif r_det_en = '0' then
                if w_pwm_rise = '1' then
                    if r_blank_cnt < BLANK_PULSES then
                        r_blank_cnt <= r_blank_cnt + 1;
                    end if;
                    -- 变量下一式用更新后的意图：计满本拍即开放
                    if (r_blank_cnt + 1) >= BLANK_PULSES then
                        r_det_en <= '1';
                    end if;
                end if;
            end if;

            -- 稳定低，或同步后下降沿
            if r_det_en = '1' then
                if (r_tz_d1 = '0') or ((r_tz_d0 = '0') and (r_tz_d1 = '1')) then
                    r_tz_lat_120 <= '1';
                end if;
            end if;
        end if;
    end process;

    -- ===================== 50 M：双拍同步 =====================
    process (i_sys_clk_50, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_tz_50_d0  <= '0';
            r_tz_lat_50 <= '0';
        elsif rising_edge(i_sys_clk_50) then
            r_tz_50_d0  <= r_tz_lat_120;
            r_tz_lat_50 <= r_tz_50_d0;
        end if;
    end process;

end architecture rtl;
