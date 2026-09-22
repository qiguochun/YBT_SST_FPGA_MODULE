--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   filter_core_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   filter_core 封装级仿真。
--                      高速/低速阶跃后稳态逼近直流增益≈1；复位清零。
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity filter_core_tb is
end entity filter_core_tb;

architecture sim of filter_core_tb is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    -- 仿真加速：提高截止、降低采样间隔
    constant HS_FS      : positive := 10000;
    constant HS_WC_HZ   : positive := 2000;
    constant LS_FS      : positive := 1000;
    constant LS_WC_HZ   : positive := 200;
    constant STEP_VAL   : integer := 1000;
    constant HS_SAMPLES : natural := 80;
    constant LS_SAMPLES : natural := 80;
    constant TOL_PCT    : integer := 5;  -- 稳态允许 ±5%

    signal i_sys_clk         : std_logic := '0';
    signal i_sys_rst         : std_logic := '1';
    signal i_hs_sample_pulse : std_logic := '0';
    signal i_ls_sample_pulse : std_logic := '0';
    signal i_bus_pos         : signed(31 downto 0) := (others => '0');
    signal i_bus_neg         : signed(31 downto 0) := (others => '0');
    signal i_temp            : signed(31 downto 0) := (others => '0');
    signal o_hs_bus_pos      : signed(31 downto 0);
    signal o_hs_bus_neg      : signed(31 downto 0);
    signal o_ls_bus_pos      : signed(31 downto 0);
    signal o_ls_bus_neg      : signed(31 downto 0);
    signal o_ls_temp         : signed(31 downto 0);

    signal sim_done : boolean := false;

    procedure p_check(
        name     : in string;
        got      : in integer;
        expect   : in integer;
        pass_cnt : inout natural;
        fail_cnt : inout natural
    ) is
        variable v_tol : integer;
    begin
        v_tol := (abs(expect) * TOL_PCT) / 100;
        if v_tol < 2 then
            v_tol := 2;
        end if;
        if abs(got - expect) <= v_tol then
            pass_cnt := pass_cnt + 1;
            report "[PASS] " & name & " got=" & integer'image(got) &
                   " expect=" & integer'image(expect);
        else
            fail_cnt := fail_cnt + 1;
            report "[FAIL] " & name & " got=" & integer'image(got) &
                   " expect=" & integer'image(expect) severity error;
        end if;
    end procedure;

    procedure p_pulse(signal pulse : out std_logic) is
    begin
        wait until rising_edge(i_sys_clk);
        pulse <= '1';
        wait until rising_edge(i_sys_clk);
        pulse <= '0';
        -- 等 lpf 流水线消化
        for i in 1 to 10 loop
            wait until rising_edge(i_sys_clk);
        end loop;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.filter_core
        generic map (
            CLK_FREQ => 50_000_000,
            HS_FS    => HS_FS,
            HS_WC_HZ => HS_WC_HZ,
            LS_FS    => LS_FS,
            LS_WC_HZ => LS_WC_HZ
        )
        port map (
            i_sys_clk         => i_sys_clk,
            i_sys_rst         => i_sys_rst,
            i_hs_sample_pulse => i_hs_sample_pulse,
            i_ls_sample_pulse => i_ls_sample_pulse,
            i_bus_pos         => i_bus_pos,
            i_bus_neg         => i_bus_neg,
            i_temp            => i_temp,
            o_hs_bus_pos      => o_hs_bus_pos,
            o_hs_bus_neg      => o_hs_bus_neg,
            o_ls_bus_pos      => o_ls_bus_pos,
            o_ls_bus_neg      => o_ls_bus_neg,
            o_ls_temp         => o_ls_temp
        );

    p_stim : process
        variable v_pass : natural := 0;
        variable v_fail : natural := 0;
    begin
        report "=== filter_core_tb START ===";
        i_sys_rst <= '1';
        wait for 200 ns;
        wait until rising_edge(i_sys_clk);
        i_sys_rst <= '0';
        wait until rising_edge(i_sys_clk);

        -- TC1: 复位后输出接近 0
        if (o_hs_bus_pos = 0) and (o_hs_bus_neg = 0) and
           (o_ls_bus_pos = 0) and (o_ls_bus_neg = 0) and (o_ls_temp = 0) then
            v_pass := v_pass + 1;
            report "[PASS] TC1 reset zero";
        else
            v_fail := v_fail + 1;
            report "[FAIL] TC1 reset zero" severity error;
        end if;

        -- TC2: 高速正/负母线阶跃
        i_bus_pos <= to_signed(STEP_VAL, 32);
        i_bus_neg <= to_signed(-STEP_VAL, 32);
        i_temp    <= to_signed(STEP_VAL / 2, 32);
        for i in 1 to HS_SAMPLES loop
            p_pulse(i_hs_sample_pulse);
        end loop;
        p_check("TC2 hs_bus_pos", to_integer(o_hs_bus_pos), STEP_VAL, v_pass, v_fail);
        p_check("TC2 hs_bus_neg", to_integer(o_hs_bus_neg), -STEP_VAL, v_pass, v_fail);

        -- TC3: 低速三路阶跃
        for i in 1 to LS_SAMPLES loop
            p_pulse(i_ls_sample_pulse);
        end loop;
        p_check("TC3 ls_bus_pos", to_integer(o_ls_bus_pos), STEP_VAL, v_pass, v_fail);
        p_check("TC3 ls_bus_neg", to_integer(o_ls_bus_neg), -STEP_VAL, v_pass, v_fail);
        p_check("TC3 ls_temp", to_integer(o_ls_temp), STEP_VAL / 2, v_pass, v_fail);

        report "==== filter_core_tb done: pass=" & integer'image(v_pass) &
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
