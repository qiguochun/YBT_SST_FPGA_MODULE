--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_tz_prot.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   LLC Trip Zone（TZ）保护。
--                      i_tz_in 默认高；稳定低或下降沿锁存故障（仅复位可清）。
--                      触发后 o_tz_lat_* 保持高电平，不是脉冲。
--                      120M：屏蔽后快锁存，供驱动异步关断。
--                      50M：本域对 TZ 脚做电平/边沿检测并锁存（故障字/关使能）；
--                      开放检测时刻与 120M 对齐（同步 r_det_en），不再搬运 120M 锁存电平。
--                      自 LLC 使能命令有效起，先计 BLANK_PULSES 个 PWM 上升沿
--                      再开放检测（对应 git：第一次启动前两个脉冲屏蔽）。
--                      使能撤销则屏蔽计数清零，下次使能重新计脉冲。
--------------------------------------------------------------------------------
--Version           :   Rev 1.1
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   50M 改为本域电平/边沿锁存；与 120M 只同步 det_en
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

        o_tz_lat_120  : out std_logic;  -- 120M 锁存电平（触发后保持到复位）
        o_tz_lat_50   : out std_logic   -- 50M 锁存电平（触发后保持到复位）
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

    -- 50M：同步开放标志 + 本域采样 TZ
    signal r_det_50_d0   : std_logic := '0';
    signal r_det_en_50   : std_logic := '0';
    signal r_tz_50_d0    : std_logic := '1';
    signal r_tz_50_d1    : std_logic := '1';
    signal r_tz_lat_50   : std_logic := '0';

    signal w_pwm_rise    : std_logic;

begin

    o_tz_lat_120 <= r_tz_lat_120;
    o_tz_lat_50  <= r_tz_lat_50;

    w_pwm_rise <= r_pwm_d0 and (not r_pwm_d1);

    -- ===================== 120 M：同步 + 脉冲屏蔽 + 锁存（保持电平） =====================
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
                    if (r_blank_cnt + 1) >= BLANK_PULSES then
                        r_det_en <= '1';
                    end if;
                end if;
            end if;

            -- 稳定低，或同步后下降沿 → 锁存为高并保持到复位
            if r_det_en = '1' then
                if (r_tz_d1 = '0') or ((r_tz_d0 = '0') and (r_tz_d1 = '1')) then
                    r_tz_lat_120 <= '1';
                end if;
            end if;
        end if;
    end process;

    -- ===================== 50 M：本域电平/边沿锁存 =====================
    -- 不搬运 r_tz_lat_120；只同步“是否已过屏蔽”的 det_en（0→1 后基本保持）。
    -- 50M 直接采 TZ 脚：稳定低或下降沿 → 锁存高电平，保持到复位。
    process (i_sys_clk_50, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_det_50_d0  <= '0';
            r_det_en_50  <= '0';
            r_tz_50_d0   <= '1';
            r_tz_50_d1   <= '1';
            r_tz_lat_50  <= '0';
        elsif rising_edge(i_sys_clk_50) then
            r_det_50_d0 <= r_det_en;
            r_det_en_50 <= r_det_50_d0;

            r_tz_50_d0 <= i_tz_in;
            r_tz_50_d1 <= r_tz_50_d0;

            if r_det_en_50 = '1' then
                if (r_tz_50_d1 = '0') or ((r_tz_50_d0 = '0') and (r_tz_50_d1 = '1')) then
                    r_tz_lat_50 <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
