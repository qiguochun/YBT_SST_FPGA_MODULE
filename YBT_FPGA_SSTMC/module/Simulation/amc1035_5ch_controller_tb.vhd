--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   amc1035_5ch_controller_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   amc1035_5ch_controller 模块级仿真。
--                      全 0 / 全 1 比特流核对温度定标输出；SCLK 同源。
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity amc1035_5ch_controller_tb is
end entity amc1035_5ch_controller_tb;

architecture sim of amc1035_5ch_controller_tb is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz
    -- 每帧：OSR=256 × SCLK_DIV=5，再加暖机 2 帧与流水余量
    constant FRAME_CLKS : integer := 256 * 5;
    constant WAIT_CLKS  : integer := FRAME_CLKS * 5 + 200;

    -- 全 1 / 全 0 理论温度（12 位有符号）
    -- CH1~3: gain=785 bias=5797；CH4~5: gain=938 bias=14089；/16384
    constant TEMP_ALL1_CH13 : integer := 478;
    constant TEMP_ALL0_CH13 : integer := -479;
    constant TEMP_ALL1_CH45 : integer := 571;
    constant TEMP_ALL0_CH45 : integer := -573;
    constant TOL            : integer := 2;

    signal i_sys_clk   : std_logic := '0';
    signal i_sys_rst   : std_logic := '1';
    signal i_amc1_dout : std_logic := '0';
    signal i_amc2_dout : std_logic := '0';
    signal i_amc3_dout : std_logic := '0';
    signal i_amc4_dout : std_logic := '0';
    signal i_amc5_dout : std_logic := '0';
    signal o_amc1_sclk : std_logic;
    signal o_amc2_sclk : std_logic;
    signal o_amc3_sclk : std_logic;
    signal o_amc4_sclk : std_logic;
    signal o_amc5_sclk : std_logic;
    signal o_data_ch1  : std_logic_vector(11 downto 0);
    signal o_data_ch2  : std_logic_vector(11 downto 0);
    signal o_data_ch3  : std_logic_vector(11 downto 0);
    signal o_data_ch4  : std_logic_vector(11 downto 0);
    signal o_data_ch5  : std_logic_vector(11 downto 0);
    signal o_valid     : std_logic;

    signal sim_done : boolean := false;

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

    dut : entity work.amc1035_5ch_controller
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            o_amc1_sclk => o_amc1_sclk,
            o_amc2_sclk => o_amc2_sclk,
            o_amc3_sclk => o_amc3_sclk,
            o_amc4_sclk => o_amc4_sclk,
            o_amc5_sclk => o_amc5_sclk,
            i_amc1_dout => i_amc1_dout,
            i_amc2_dout => i_amc2_dout,
            i_amc3_dout => i_amc3_dout,
            i_amc4_dout => i_amc4_dout,
            i_amc5_dout => i_amc5_dout,
            o_data_ch1  => o_data_ch1,
            o_data_ch2  => o_data_ch2,
            o_data_ch3  => o_data_ch3,
            o_data_ch4  => o_data_ch4,
            o_data_ch5  => o_data_ch5,
            o_valid     => o_valid
        );

    p_stim : process
        variable v_pass : natural := 0;
        variable v_fail : natural := 0;
        variable v1, v2, v3, v4, v5 : integer;
        variable t1, t2 : time;
    begin
        report "=== amc1035_5ch_controller_tb START ===";
        i_sys_rst   <= '1';
        i_amc1_dout <= '0';
        i_amc2_dout <= '0';
        i_amc3_dout <= '0';
        i_amc4_dout <= '0';
        i_amc5_dout <= '0';
        wait for 200 ns;
        wait until rising_edge(i_sys_clk);
        i_sys_rst <= '0';

        -- TC1: SCLK 周期 ≈ 100 ns（10 MHz）
        wait until rising_edge(o_amc1_sclk);
        t1 := now;
        wait until rising_edge(o_amc1_sclk);
        t2 := now;
        if (t2 - t1) = 100 ns then
            v_pass := v_pass + 1;
            report "[PASS] TC1 SCLK period 100 ns";
        else
            v_fail := v_fail + 1;
            report "[FAIL] TC1 SCLK period got " & time'image(t2 - t1) severity error;
        end if;

        -- TC2: 全 1
        i_amc1_dout <= '1';
        i_amc2_dout <= '1';
        i_amc3_dout <= '1';
        i_amc4_dout <= '1';
        i_amc5_dout <= '1';
        for i in 1 to WAIT_CLKS loop
            wait until rising_edge(i_sys_clk);
        end loop;
        v1 := to_integer(signed(o_data_ch1));
        v2 := to_integer(signed(o_data_ch2));
        v3 := to_integer(signed(o_data_ch3));
        v4 := to_integer(signed(o_data_ch4));
        v5 := to_integer(signed(o_data_ch5));
        p_check("TC2 ch1 all1", v1, TEMP_ALL1_CH13, v_pass, v_fail);
        p_check("TC2 ch2 all1", v2, TEMP_ALL1_CH13, v_pass, v_fail);
        p_check("TC2 ch3 all1", v3, TEMP_ALL1_CH13, v_pass, v_fail);
        p_check("TC2 ch4 all1", v4, TEMP_ALL1_CH45, v_pass, v_fail);
        p_check("TC2 ch5 all1", v5, TEMP_ALL1_CH45, v_pass, v_fail);

        -- TC3: 全 0
        i_amc1_dout <= '0';
        i_amc2_dout <= '0';
        i_amc3_dout <= '0';
        i_amc4_dout <= '0';
        i_amc5_dout <= '0';
        for i in 1 to WAIT_CLKS loop
            wait until rising_edge(i_sys_clk);
        end loop;
        v1 := to_integer(signed(o_data_ch1));
        v2 := to_integer(signed(o_data_ch2));
        v3 := to_integer(signed(o_data_ch3));
        v4 := to_integer(signed(o_data_ch4));
        v5 := to_integer(signed(o_data_ch5));
        p_check("TC3 ch1 all0", v1, TEMP_ALL0_CH13, v_pass, v_fail);
        p_check("TC3 ch2 all0", v2, TEMP_ALL0_CH13, v_pass, v_fail);
        p_check("TC3 ch3 all0", v3, TEMP_ALL0_CH13, v_pass, v_fail);
        p_check("TC3 ch4 all0", v4, TEMP_ALL0_CH45, v_pass, v_fail);
        p_check("TC3 ch5 all0", v5, TEMP_ALL0_CH45, v_pass, v_fail);

        -- TC4: SCLK 五脚同源
        if (o_amc1_sclk = o_amc2_sclk) and (o_amc1_sclk = o_amc3_sclk) and
           (o_amc1_sclk = o_amc4_sclk) and (o_amc1_sclk = o_amc5_sclk) then
            v_pass := v_pass + 1;
            report "[PASS] TC4 SCLK tied";
        else
            v_fail := v_fail + 1;
            report "[FAIL] TC4 SCLK mismatch" severity error;
        end if;

        -- TC5: 复位清零
        i_sys_rst <= '1';
        wait for 100 ns;
        wait until rising_edge(i_sys_clk);
        if (unsigned(o_data_ch1) = 0) and (unsigned(o_data_ch2) = 0) and
           (unsigned(o_data_ch3) = 0) and (unsigned(o_data_ch4) = 0) and
           (unsigned(o_data_ch5) = 0) and (o_valid = '0') then
            v_pass := v_pass + 1;
            report "[PASS] TC5 reset clears";
        else
            v_fail := v_fail + 1;
            report "[FAIL] TC5 reset clears" severity error;
        end if;

        report "==== amc1035_tb done: pass=" & integer'image(v_pass) &
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
