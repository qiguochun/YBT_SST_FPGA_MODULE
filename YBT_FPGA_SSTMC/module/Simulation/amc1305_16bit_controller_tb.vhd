--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   amc1305_16bit_controller_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   amc1305_16bit_controller 模块级仿真。
--                      全 0 / 全 1 比特流核对 ±10000 定标与求和。
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity amc1305_16bit_controller_tb is
end entity amc1305_16bit_controller_tb;

architecture sim of amc1305_16bit_controller_tb is

    constant CLK_PERIOD : time := 8.333 ns;  -- 120 MHz
    constant CODE_FS    : integer := 10000;
    constant TOL        : integer := 2;      -- 允许 1~2 LSB 截断误差

    -- 3 帧暖机+有效：每帧 256 OSR × 6 clk，再留余量
    constant FRAME_CLKS : integer := 256 * 6;
    constant WAIT_CLKS  : integer := FRAME_CLKS * 4 + 200;

    signal i_sys_clk   : std_logic := '0';
    signal i_sys_rst   : std_logic := '1';
    signal i_amc1_dout : std_logic := '0';
    signal i_amc2_dout : std_logic := '0';
    signal o_amc1_sclk : std_logic;
    signal o_amc2_sclk : std_logic;
    signal o_data_ch1  : std_logic_vector(15 downto 0);
    signal o_data_ch2  : std_logic_vector(15 downto 0);
    signal o_data_sum  : std_logic_vector(15 downto 0);
    signal o_udgy      : std_logic;

    signal test_pass : natural := 0;
    signal test_fail : natural := 0;
    signal sim_done  : boolean := false;

    procedure p_check(
        name     : in string;
        got      : in integer;
        expect   : in integer;
        pass_cnt : inout natural;
        fail_cnt : inout natural
    ) is
    begin
        if abs(got - expect) <= TOL then
            pass_cnt := pass_cnt + 1;
            report "[PASS] " & name & " got=" & integer'image(got) &
                   " expect=" & integer'image(expect);
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] " & name & " got=" & integer'image(got) &
                   " expect=" & integer'image(expect) severity error;
        end if;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.amc1305_16bit_controller
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            o_amc1_sclk => o_amc1_sclk,
            o_amc2_sclk => o_amc2_sclk,
            i_amc1_dout => i_amc1_dout,
            i_amc2_dout => i_amc2_dout,
            o_data_ch1  => o_data_ch1,
            o_data_ch2  => o_data_ch2,
            o_data_sum  => o_data_sum,
            o_udgy      => o_udgy
        );

    p_stim : process
        variable v_pass : natural := 0;
        variable v_fail : natural := 0;
        variable v_ch1  : integer;
        variable v_ch2  : integer;
        variable v_sum  : integer;
    begin
        i_sys_rst   <= '1';
        i_amc1_dout <= '0';
        i_amc2_dout <= '0';
        wait for 200 ns;
        wait until rising_edge(i_sys_clk);
        i_sys_rst <= '0';

        -- -------- TC1: 两路全 0 → 各约 -10000，和约 -20000 --------
        i_amc1_dout <= '0';
        i_amc2_dout <= '0';
        for i in 1 to WAIT_CLKS loop
            wait until rising_edge(i_sys_clk);
        end loop;
        v_ch1 := to_integer(signed(o_data_ch1));
        v_ch2 := to_integer(signed(o_data_ch2));
        v_sum := to_integer(signed(o_data_sum));
        p_check("TC1 ch1 all0", v_ch1, -CODE_FS, v_pass, v_fail);
        p_check("TC1 ch2 all0", v_ch2, -CODE_FS, v_pass, v_fail);
        p_check("TC1 sum all0", v_sum, -2 * CODE_FS, v_pass, v_fail);

        -- -------- TC2: 两路全 1 → 各约 +10000，和约 +20000 --------
        i_amc1_dout <= '1';
        i_amc2_dout <= '1';
        for i in 1 to WAIT_CLKS loop
            wait until rising_edge(i_sys_clk);
        end loop;
        v_ch1 := to_integer(signed(o_data_ch1));
        v_ch2 := to_integer(signed(o_data_ch2));
        v_sum := to_integer(signed(o_data_sum));
        p_check("TC2 ch1 all1", v_ch1, CODE_FS, v_pass, v_fail);
        p_check("TC2 ch2 all1", v_ch2, CODE_FS, v_pass, v_fail);
        p_check("TC2 sum all1", v_sum, 2 * CODE_FS, v_pass, v_fail);

        -- -------- TC3: CH1=1 CH2=0 → +10000 / -10000 / sum≈0 --------
        i_amc1_dout <= '1';
        i_amc2_dout <= '0';
        for i in 1 to WAIT_CLKS loop
            wait until rising_edge(i_sys_clk);
        end loop;
        v_ch1 := to_integer(signed(o_data_ch1));
        v_ch2 := to_integer(signed(o_data_ch2));
        v_sum := to_integer(signed(o_data_sum));
        p_check("TC3 ch1 ones", v_ch1, CODE_FS, v_pass, v_fail);
        p_check("TC3 ch2 zeros", v_ch2, -CODE_FS, v_pass, v_fail);
        p_check("TC3 sum mix", v_sum, 0, v_pass, v_fail);

        -- SCLK 两脚应同源
        if o_amc1_sclk = o_amc2_sclk then
            v_pass := v_pass + 1;
            report "[PASS] SCLK tied";
        else
            v_fail := v_fail + 1;
            report "[FAIL] SCLK mismatch" severity error;
        end if;

        test_pass <= v_pass;
        test_fail <= v_fail;
        wait for 1 ns;

        report "==== amc1305_tb done: pass=" & integer'image(v_pass) &
               " fail=" & integer'image(v_fail);
        if v_fail /= 0 then
            report "TEST FAILED" severity failure;
        else
            report "TEST PASSED";
        end if;

        sim_done <= true;
        finish(0);
        wait;
    end process;

end architecture sim;
