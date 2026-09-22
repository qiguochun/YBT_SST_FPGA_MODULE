--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   filter_core_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   filter_core 封装级仿真（5 路温度）。
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity filter_core_tb is
end entity filter_core_tb;

architecture sim of filter_core_tb is

    constant CLK_PERIOD : time := 20 ns;
    constant HS_FS      : positive := 10000;
    constant HS_WC_HZ   : positive := 2000;
    constant LS_FS      : positive := 1000;
    constant LS_WC_HZ   : positive := 200;
    constant STEP_VAL   : integer := 1000;
    constant HS_SAMPLES : natural := 80;
    constant LS_SAMPLES : natural := 80;
    constant TOL_PCT    : integer := 5;

    signal i_sys_clk         : std_logic := '0';
    signal i_sys_rst         : std_logic := '1';
    signal i_hs_sample_pulse : std_logic := '0';
    signal i_ls_sample_pulse : std_logic := '0';
    signal i_bus_pos         : signed(31 downto 0) := (others => '0');
    signal i_bus_neg         : signed(31 downto 0) := (others => '0');
    signal i_temp1           : signed(31 downto 0) := (others => '0');
    signal i_temp2           : signed(31 downto 0) := (others => '0');
    signal i_temp3           : signed(31 downto 0) := (others => '0');
    signal i_temp4           : signed(31 downto 0) := (others => '0');
    signal i_temp5           : signed(31 downto 0) := (others => '0');
    signal o_hs_bus_pos      : signed(31 downto 0);
    signal o_hs_bus_neg      : signed(31 downto 0);
    signal o_ls_bus_pos      : signed(31 downto 0);
    signal o_ls_bus_neg      : signed(31 downto 0);
    signal o_ls_temp1        : signed(31 downto 0);
    signal o_ls_temp2        : signed(31 downto 0);
    signal o_ls_temp3        : signed(31 downto 0);
    signal o_ls_temp4        : signed(31 downto 0);
    signal o_ls_temp5        : signed(31 downto 0);
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
            report "[PASS] " & name & " got=" & integer'image(got);
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
        for i in 1 to 10 loop
            wait until rising_edge(i_sys_clk);
        end loop;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2 when not sim_done else '0';

    dut : entity work.filter_core
        generic map (
            CLK_FREQ => 50_000_000,
            HS_FS => HS_FS, HS_WC_HZ => HS_WC_HZ,
            LS_FS => LS_FS, LS_WC_HZ => LS_WC_HZ
        )
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_hs_sample_pulse => i_hs_sample_pulse,
            i_ls_sample_pulse => i_ls_sample_pulse,
            i_bus_pos => i_bus_pos, i_bus_neg => i_bus_neg,
            i_temp1 => i_temp1, i_temp2 => i_temp2, i_temp3 => i_temp3,
            i_temp4 => i_temp4, i_temp5 => i_temp5,
            o_hs_bus_pos => o_hs_bus_pos, o_hs_bus_neg => o_hs_bus_neg,
            o_ls_bus_pos => o_ls_bus_pos, o_ls_bus_neg => o_ls_bus_neg,
            o_ls_temp1 => o_ls_temp1, o_ls_temp2 => o_ls_temp2,
            o_ls_temp3 => o_ls_temp3, o_ls_temp4 => o_ls_temp4,
            o_ls_temp5 => o_ls_temp5
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

        if (o_hs_bus_pos = 0) and (o_hs_bus_neg = 0) and
           (o_ls_bus_pos = 0) and (o_ls_bus_neg = 0) and
           (o_ls_temp1 = 0) and (o_ls_temp5 = 0) then
            v_pass := v_pass + 1;
            report "[PASS] TC1 reset zero";
        else
            v_fail := v_fail + 1;
            report "[FAIL] TC1 reset zero" severity error;
        end if;

        i_bus_pos <= to_signed(STEP_VAL, 32);
        i_bus_neg <= to_signed(-STEP_VAL, 32);
        i_temp1 <= to_signed(100, 32);
        i_temp2 <= to_signed(200, 32);
        i_temp3 <= to_signed(300, 32);
        i_temp4 <= to_signed(400, 32);
        i_temp5 <= to_signed(500, 32);
        for i in 1 to HS_SAMPLES loop
            p_pulse(i_hs_sample_pulse);
        end loop;
        p_check("TC2 hs_pos", to_integer(o_hs_bus_pos), STEP_VAL, v_pass, v_fail);
        p_check("TC2 hs_neg", to_integer(o_hs_bus_neg), -STEP_VAL, v_pass, v_fail);

        for i in 1 to LS_SAMPLES loop
            p_pulse(i_ls_sample_pulse);
        end loop;
        p_check("TC3 ls_pos", to_integer(o_ls_bus_pos), STEP_VAL, v_pass, v_fail);
        p_check("TC3 ls_neg", to_integer(o_ls_bus_neg), -STEP_VAL, v_pass, v_fail);
        p_check("TC3 t1", to_integer(o_ls_temp1), 100, v_pass, v_fail);
        p_check("TC3 t2", to_integer(o_ls_temp2), 200, v_pass, v_fail);
        p_check("TC3 t3", to_integer(o_ls_temp3), 300, v_pass, v_fail);
        p_check("TC3 t4", to_integer(o_ls_temp4), 400, v_pass, v_fail);
        p_check("TC3 t5", to_integer(o_ls_temp5), 500, v_pass, v_fail);

        report "==== pass=" & integer'image(v_pass) & " fail=" & integer'image(v_fail);
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
