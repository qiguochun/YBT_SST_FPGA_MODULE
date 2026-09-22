--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   delay_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.04
--Description       :   公共时基节拍。仅使用一路 30 MHz 系统时钟，
--                      产生单周期 1 µs / 1 ms / 1 s 脉冲，供其他模块统一计时。
--                      µs 预触发打拍，
--                      ms/s 在上级脉冲上累加，禁止下游再自行分频。
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity delay_core is
    generic (
        CLK_FREQ : positive := 30_000_000  -- 系统时钟频率，单位 Hz（默认 30 MHz）
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;  -- 30 MHz 工作时钟
        i_sys_rst : in  std_logic;  -- 异步复位，高有效

        -- User Interface
        o_delay_1us : out std_logic;  -- 1 µs 单周期脉冲
        o_delay_1ms : out std_logic;  -- 1 ms 单周期脉冲
        o_delay_1s  : out std_logic   -- 1 s 单周期脉冲
    );
end entity delay_core;

architecture rtl of delay_core is

    -- 能表示 0 .. n-1 的位宽，即 ceil(log2(n))
    function f_clog2(n : positive) return natural is
        variable v_tmp : natural := n - 1;
        variable v_log : natural := 0;
    begin
        while v_tmp > 0 loop
            v_tmp := v_tmp / 2;
            v_log := v_log + 1;
        end loop;
        if v_log = 0 then
            return 1;
        end if;
        return v_log;
    end function;

    -- 1 µs = CLK_FREQ / 1e6 拍；须为整数 MHz 且 >= 2 MHz
    constant COUNT_1US : positive := CLK_FREQ / 1_000_000;
    constant COUNT_1MS : positive := 1000;  -- 1000 × 1 µs
    constant COUNT_1S  : positive := 1000;  -- 1000 × 1 ms

    constant US_CNT_W : natural := f_clog2(COUNT_1US);
    constant MS_CNT_W : natural := f_clog2(COUNT_1MS);
    constant S_CNT_W  : natural := f_clog2(COUNT_1S);

    signal r_cnt_us : unsigned(US_CNT_W - 1 downto 0) := (others => '0');
    signal r_cnt_ms : unsigned(MS_CNT_W - 1 downto 0) := (others => '0');
    signal r_cnt_s  : unsigned(S_CNT_W - 1 downto 0) := (others => '0');

    signal r_delay_1us : std_logic := '0';
    signal r_delay_1ms : std_logic := '0';
    signal r_delay_1s  : std_logic := '0';

    signal w_delay_1us_pre : std_logic;
    signal w_delay_1ms_pre : std_logic;

begin

    o_delay_1us <= r_delay_1us;
    o_delay_1ms <= r_delay_1ms;
    o_delay_1s  <= r_delay_1s;

    -- 提前 1 拍产生预触发，下一拍输出对齐计数回零
    w_delay_1us_pre <= '1' when r_cnt_us = COUNT_1US - 2 else '0';
    w_delay_1ms_pre <= '1' when (r_cnt_ms = COUNT_1MS - 1) and (w_delay_1us_pre = '1') else '0';

    -- ===================== 1 µs 计数与脉冲 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_cnt_us     <= (others => '0');
            r_delay_1us  <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_cnt_us = COUNT_1US - 1 then
                r_cnt_us <= (others => '0');
            else
                r_cnt_us <= r_cnt_us + 1;
            end if;
            r_delay_1us <= w_delay_1us_pre;
        end if;
    end process;

    -- ===================== 1 ms 计数与脉冲 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_cnt_ms    <= (others => '0');
            r_delay_1ms <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_delay_1us = '1' then
                if r_cnt_ms = COUNT_1MS - 1 then
                    r_cnt_ms <= (others => '0');
                else
                    r_cnt_ms <= r_cnt_ms + 1;
                end if;
            end if;
            r_delay_1ms <= w_delay_1ms_pre;
        end if;
    end process;

    -- ===================== 1 s 计数与脉冲 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_cnt_s    <= (others => '0');
            r_delay_1s <= '0';
        elsif rising_edge(i_sys_clk) then
            if r_delay_1ms = '1' then
                if r_cnt_s = COUNT_1S - 1 then
                    r_cnt_s <= (others => '0');
                else
                    r_cnt_s <= r_cnt_s + 1;
                end if;
            end if;

            if (r_cnt_s = COUNT_1S - 1) and (w_delay_1ms_pre = '1') then
                r_delay_1s <= '1';
            else
                r_delay_1s <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
