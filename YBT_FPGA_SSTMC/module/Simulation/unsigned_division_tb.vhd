--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   unsigned_division_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   unsigned_division 模块级仿真。
--                      覆盖余数左移、除零、start 上升沿、典型商余数。
--                      运行（GHDL）：ghdl -a ../Core/MathCore/unsigned_division.vhd unsigned_division_tb.vhd
--                                   ghdl -e unsigned_division_tb
--                                   ghdl -r unsigned_division_tb
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--modifier          :
--Modify Date       :
--Modify Record     :
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity unsigned_division_tb is
end entity unsigned_division_tb;

architecture sim of unsigned_division_tb is

    constant CLK_PERIOD : time := 10 ns;
    constant W_DVD      : positive := 16;
    constant W_DVS      : positive := 8;

    signal i_sys_clk   : std_logic := '0';
    signal i_sys_rst   : std_logic := '1';
    signal i_start     : std_logic := '0';
    signal i_dividend  : std_logic_vector(W_DVD - 1 downto 0) := (others => '0');
    signal i_divisor   : std_logic_vector(W_DVS - 1 downto 0) := (others => '0');
    signal o_quotient  : std_logic_vector(W_DVD - 1 downto 0);
    signal o_remainder : std_logic_vector(W_DVS - 1 downto 0);
    signal o_done      : std_logic;
    signal o_busy      : std_logic;
    signal o_div_zero  : std_logic;

    signal test_pass : natural := 0;
    signal test_fail : natural := 0;

    procedure p_check (
        signal pass_cnt : inout natural;
        signal fail_cnt : inout natural;
        name            : in    string;
        cond            : in    boolean;
        detail          : in    string
    ) is
    begin
        if cond then
            pass_cnt <= pass_cnt + 1;
        else
            fail_cnt <= fail_cnt + 1;
            report "[FAIL] " & name & " " & detail severity error;
        end if;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    dut : entity work.unsigned_division
        generic map (
            WIDTH_DVD => W_DVD,
            WIDTH_DVS => W_DVS
        )
        port map (
            i_sys_clk   => i_sys_clk,
            i_sys_rst   => i_sys_rst,
            i_start     => i_start,
            i_dividend  => i_dividend,
            i_divisor   => i_divisor,
            o_quotient  => o_quotient,
            o_remainder => o_remainder,
            o_done      => o_done,
            o_busy      => o_busy,
            o_div_zero  => o_div_zero
        );

    stimulus : process
        variable v_timeout : boolean;

        procedure p_wait_done is
        begin
            v_timeout := true;
            for i in 0 to W_DVD + 8 loop
                wait until rising_edge(i_sys_clk);
                if o_done = '1' then
                    v_timeout := false;
                    exit;
                end if;
            end loop;
        end procedure;

        procedure p_issue_start (dvd : natural; dvs : natural) is
        begin
            i_dividend <= std_logic_vector(to_unsigned(dvd, W_DVD));
            i_divisor  <= std_logic_vector(to_unsigned(dvs, W_DVS));
            wait until rising_edge(i_sys_clk);
            i_start <= '1';
            wait until rising_edge(i_sys_clk);
            i_start <= '0';
        end procedure;

        procedure p_div_check (name : string; dvd : natural; dvs : natural) is
            variable v_q : natural;
            variable v_r : natural;
        begin
            p_issue_start(dvd, dvs);
            p_wait_done;
            v_q := dvd / dvs;
            v_r := dvd mod dvs;
            p_check(test_pass, test_fail, name,
                    (v_timeout = false) and
                    (o_div_zero = '0') and
                    (unsigned(o_quotient) = to_unsigned(v_q, W_DVD)) and
                    (unsigned(o_remainder) = to_unsigned(v_r, W_DVS)),
                    "dvd=" & integer'image(dvd) &
                    " dvs=" & integer'image(dvs) &
                    " got q=" & integer'image(to_integer(unsigned(o_quotient))) &
                    " r=" & integer'image(to_integer(unsigned(o_remainder))) &
                    " exp q=" & integer'image(v_q) &
                    " r=" & integer'image(v_r));
            wait until rising_edge(i_sys_clk);
        end procedure;
    begin
        report "========================================";
        report " unsigned_division_tb start";
        report "========================================";

        i_start <= '0';
        i_sys_rst <= '1';
        wait for 100 ns;
        wait until rising_edge(i_sys_clk);
        i_sys_rst <= '0';
        wait until rising_edge(i_sys_clk);

        -- ---------- 定向：原先丢位失败向量 ----------
        p_div_check("TC1 256/129", 256, 129);
        p_div_check("TC2 65535/255", 65535, 255);
        p_div_check("TC3 32768/130", 32768, 130);
        p_div_check("TC4 4096/200", 4096, 200);
        p_div_check("TC5 0/7", 0, 7);
        p_div_check("TC6 100/1", 100, 1);
        p_div_check("TC7 100/100", 100, 100);
        p_div_check("TC8 99/100", 99, 100);
        p_div_check("TC9 255/128", 255, 128);

        -- ---------- 除零 ----------
        p_issue_start(7, 0);
        p_wait_done;
        p_check(test_pass, test_fail, "TC10 div0 flag",
                (v_timeout = false) and (o_div_zero = '1') and (o_busy = '0') and
                (unsigned(o_quotient) = 0) and (unsigned(o_remainder) = 0),
                "div0 handshake");
        wait until rising_edge(i_sys_clk);
        p_check(test_pass, test_fail, "TC10 div0 pulse",
                (o_done = '0') and (o_div_zero = '0'),
                "div0 should be 1-cycle");

        -- ---------- start 保持高电平不得自动连除 ----------
        i_dividend <= std_logic_vector(to_unsigned(20, W_DVD));
        i_divisor  <= std_logic_vector(to_unsigned(3, W_DVS));
        wait until rising_edge(i_sys_clk);
        i_start <= '1';
        p_wait_done;
        p_check(test_pass, test_fail, "TC11 first held-start",
                (v_timeout = false) and
                (unsigned(o_quotient) = to_unsigned(6, W_DVD)) and
                (unsigned(o_remainder) = to_unsigned(2, W_DVS)),
                "20/3");
        for i in 0 to 40 loop
            wait until rising_edge(i_sys_clk);
            if (o_done = '1') or (o_busy = '1') then
                p_check(test_pass, test_fail, "TC11 no auto restart", false, "retrig while start held");
                exit;
            end if;
            if i = 40 then
                p_check(test_pass, test_fail, "TC11 no auto restart", true, "");
            end if;
        end loop;
        i_start <= '0';
        wait until rising_edge(i_sys_clk);

        -- ---------- 扫描：除数 MSB=1 的丢位区 ----------
        for dvs in 129 to 255 loop
            p_div_check("sweep " & integer'image(256) & "/" & integer'image(dvs), 256, dvs);
            p_div_check("sweep " & integer'image(65535) & "/" & integer'image(dvs), 65535, dvs);
        end loop;

        for dvs in 1 to 255 loop
            p_div_check("small " & integer'image(200) & "/" & integer'image(dvs), 200, dvs);
        end loop;

        wait for 1 us;
        report "========================================";
        report " TEST SUMMARY: PASS=" & integer'image(test_pass) &
               " FAIL=" & integer'image(test_fail);
        report "========================================";

        if test_fail = 0 then
            report "ALL TESTS PASSED" severity note;
        else
            report "SOME TESTS FAILED" severity failure;
        end if;

        stop;
    end process stimulus;

end architecture sim;
