--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   fiber_link_watchdog.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   光纤链路看门狗：接收电平停滞或帧完成超时则锁存通信故障。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--modifier          :
--Modify Date       :
--Modify Record     :   从 ZZ/ZC 输入模块抽出公共故障检测
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fiber_link_watchdog is
    generic (
        CLK_FREQ : positive := 50_000_000  -- 系统时钟频率，单位 Hz
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_clr     : in  std_logic;  -- 同步清故障，高有效

        -- PHY
        i_fiber_r : in  std_logic;  -- 光纤接收电平
        i_finish  : in  std_logic;  -- 一帧收发完成

        -- Status
        o_cerr    : out std_logic   -- 通信故障锁存
    );
end entity fiber_link_watchdog;

architecture rtl of fiber_link_watchdog is

    constant LINK_TIMEOUT_CNT : positive := CLK_FREQ / 1_000;  -- 链路超时 1 ms
    constant CNT_WIDTH        : positive := 16;

    signal r_fiber_d  : std_logic := '0';
    signal r_cnt_r    : unsigned(CNT_WIDTH - 1 downto 0) := (others => '0');
    signal r_cnt_f    : unsigned(CNT_WIDTH - 1 downto 0) := (others => '0');
    signal r_fiber_ft : std_logic := '0';
    signal r_comm_ft  : std_logic := '0';
    signal r_cerr     : std_logic := '0';

begin

    o_cerr <= r_cerr;

    -- ===================== 链路超时锁存 =====================
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_fiber_d  <= '0';
            r_cnt_r    <= (others => '0');
            r_cnt_f    <= (others => '0');
            r_fiber_ft <= '0';
            r_comm_ft  <= '0';
            r_cerr     <= '0';
        elsif rising_edge(i_sys_clk) then
            if i_clr = '1' then
                r_fiber_d  <= '0';
                r_cnt_r    <= (others => '0');
                r_cnt_f    <= (others => '0');
                r_fiber_ft <= '0';
                r_comm_ft  <= '0';
                r_cerr     <= '0';
            else
                if i_fiber_r = r_fiber_d then
                    if r_cnt_r = LINK_TIMEOUT_CNT then
                        r_fiber_ft <= '1';
                    else
                        r_cnt_r <= r_cnt_r + 1;
                    end if;
                else
                    r_cnt_r   <= (others => '0');
                    r_fiber_d <= i_fiber_r;
                end if;

                if i_finish = '0' then
                    if r_cnt_f = LINK_TIMEOUT_CNT then
                        r_comm_ft <= '1';
                    else
                        r_cnt_f <= r_cnt_f + 1;
                    end if;
                else
                    r_cnt_f <= (others => '0');
                end if;

                r_cerr <= r_fiber_ft or r_comm_ft;
            end if;
        end if;
    end process;

end architecture rtl;
