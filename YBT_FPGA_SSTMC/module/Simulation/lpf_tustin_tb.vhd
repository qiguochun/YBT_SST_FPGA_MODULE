--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_tustin_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   lpf_tustin 模块级仿真。
--                      覆盖复位、阶跃直流增益、负向阶跃、大信号饱和、
--                      高速/低速参数配置。
--                      ModelSim：见同目录 run_lpf_tustin_tb.do
--------------------------------------------------------------------------------
--Version           :   Rev 0.0
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use std.env.all;

entity lpf_tustin_tb is
end entity lpf_tustin_tb;

architecture sim of lpf_tustin_tb is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz

    signal i_sys_clk : std_logic := '0';
    signal i_sys_rst : std_logic := '1';
    signal sim_done  : boolean := false;

    -- DUT A：低速参数，100 Hz / 1 kHz 采样
    signal a_in    : signed(31 downto 0) := (others => '0');
    signal a_pulse : std_logic := '0';
    signal a_out   : signed(31 downto 0);

    -- DUT B：高速参数，1 kHz / 78.125 kHz 采样
    signal b_in    : signed(31 downto 0) := (others => '0');
    signal b_pulse : std_logic := '0';
    signal b_out   : signed(31 downto 0);

    -- DUT C：保护位更多，测饱和
    signal c_in    : signed(31 downto 0) := (others => '0');
    signal c_pulse : std_logic := '0';
    signal c_out   : signed(31 downto 0);

    signal pass_cnt : natural := 0;
    signal fail_cnt : natural := 0;

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
            report "[PASS] " & name severity note;
        else
            fail_cnt <= fail_cnt + 1;
            report "[FAIL] " & name & " | " & detail severity error;
        end if;
    end procedure;

    procedure p_wait_clks (n : natural) is
    begin
        for i in 1 to n loop
            wait until rising_edge(i_sys_clk);
        end loop;
    end procedure;

    -- 发一次采样脉冲，并等流水线完成（约 8 拍）
    procedure p_sample (
        signal pulse : out std_logic
    ) is
    begin
        wait until rising_edge(i_sys_clk);
        pulse <= '1';
        wait until rising_edge(i_sys_clk);
        pulse <= '0';
        p_wait_clks(10);
    end procedure;

    procedure p_sample_n (
        signal pulse : out std_logic;
        n            : in  natural
    ) is
    begin
        for i in 1 to n loop
            p_sample(pulse);
        end loop;
    end procedure;

begin

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2 when not sim_done else '0';

    U_LPF_LS : entity work.lpf_tustin
        generic map (
            TRI_MODE   => 0,
            WC         => 628,
            FS         => 1000,
            CLK_FREQ   => 50_000_000,
            GUARD_BITS => 8
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_input        => a_in,
            i_sample_pulse => a_pulse,
            o_output       => a_out
        );

    U_LPF_HS : entity work.lpf_tustin
        generic map (
            TRI_MODE   => 0,
            WC         => 6283,
            FS         => 78125,
            CLK_FREQ   => 50_000_000,
            GUARD_BITS => 4
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_input        => b_in,
            i_sample_pulse => b_pulse,
            o_output       => b_out
        );

    U_LPF_SAT : entity work.lpf_tustin
        generic map (
            TRI_MODE   => 0,
            WC         => 628,
            FS         => 1000,
            CLK_FREQ   => 50_000_000,
            GUARD_BITS => 8
        )
        port map (
            i_sys_clk      => i_sys_clk,
            i_sys_rst      => i_sys_rst,
            i_input        => c_in,
            i_sample_pulse => c_pulse,
            o_output       => c_out
        );

    p_stim : process
        variable v_err   : integer;
        variable v_exp   : integer;
        variable v_tol   : integer;
        variable v_a1    : real;
        variable v_b0    : real;
        variable v_y     : real;
        variable v_x     : real;
        variable v_x1    : real;
        variable v_gold  : integer;
        variable v_max_e : integer;
    begin
        i_sys_rst <= '1';
        a_in <= (others => '0');
        b_in <= (others => '0');
        c_in <= (others => '0');
        a_pulse <= '0';
        b_pulse <= '0';
        c_pulse <= '0';
        p_wait_clks(5);
        i_sys_rst <= '0';
        p_wait_clks(5);

        ------------------------------------------------------------------
        -- 1) 复位后输出为 0
        ------------------------------------------------------------------
        p_check(pass_cnt, fail_cnt, "RST_A_ZERO", a_out = 0,
            "a_out=" & integer'image(to_integer(a_out)));
        p_check(pass_cnt, fail_cnt, "RST_B_ZERO", b_out = 0,
            "b_out=" & integer'image(to_integer(b_out)));

        ------------------------------------------------------------------
        -- 2) 低速正向阶跃：直流增益应为 1
        ------------------------------------------------------------------
        a_in <= to_signed(10000, 32);
        p_sample_n(a_pulse, 40);
        v_err := abs(to_integer(a_out) - 10000);
        p_check(pass_cnt, fail_cnt, "LS_STEP_POS_DC", v_err <= 5,
            "a_out=" & integer'image(to_integer(a_out)) & " err=" & integer'image(v_err));

        ------------------------------------------------------------------
        -- 3) 低速负向阶跃
        ------------------------------------------------------------------
        a_in <= to_signed(-8000, 32);
        p_sample_n(a_pulse, 40);
        v_err := abs(to_integer(a_out) - (-8000));
        p_check(pass_cnt, fail_cnt, "LS_STEP_NEG_DC", v_err <= 5,
            "a_out=" & integer'image(to_integer(a_out)) & " err=" & integer'image(v_err));

        ------------------------------------------------------------------
        -- 4) 与离散黄金模型逐步比对（前 15 拍，容差放宽到舍入）
        ------------------------------------------------------------------
        i_sys_rst <= '1';
        p_wait_clks(3);
        i_sys_rst <= '0';
        p_wait_clks(3);
        a_in <= to_signed(5000, 32);
        v_a1 := real(2 * 1000 - 628) / real(2 * 1000 + 628);
        v_b0 := real(628) / real(2 * 1000 + 628);
        v_y  := 0.0;
        v_x  := 0.0;
        v_x1 := 0.0;
        v_max_e := 0;
        for k in 1 to 15 loop
            -- DUT：本拍采样使用的是上一拍更新后的 xn（与 RTL 状态机一致）
            p_sample(a_pulse);
            -- 黄金：与 RTL 相同的状态时序
            -- 乘加使用当前 v_x / v_x1 / v_y，再更新
            v_y  := v_a1 * v_y + v_b0 * (v_x + v_x1);
            v_x1 := v_x;
            v_x  := 5000.0;
            v_gold := integer(round(v_y));
            v_err  := abs(to_integer(a_out) - v_gold);
            if v_err > v_max_e then
                v_max_e := v_err;
            end if;
        end loop;
        p_check(pass_cnt, fail_cnt, "LS_GOLDEN_TRACK", v_max_e <= 3,
            "max_err=" & integer'image(v_max_e));

        ------------------------------------------------------------------
        -- 5) 高速阶跃直流增益（极点约 0.96，需更多拍）
        ------------------------------------------------------------------
        b_in <= to_signed(10000, 32);
        p_sample_n(b_pulse, 250);
        v_err := abs(to_integer(b_out) - 10000);
        p_check(pass_cnt, fail_cnt, "HS_STEP_POS_DC", v_err <= 20,
            "b_out=" & integer'image(to_integer(b_out)) & " err=" & integer'image(v_err));

        ------------------------------------------------------------------
        -- 6) 大信号：2*x 仍在 int32 内，应逼近输入；再测顶格不回绕
        ------------------------------------------------------------------
        c_in <= to_signed(1_000_000_000, 32);
        p_sample_n(c_pulse, 40);
        v_err := abs(to_integer(c_out) - 1_000_000_000);
        -- Q23 系数量化会使直流增益略偏 1（约 0.25 ppm），1e9 上约 249
        p_check(pass_cnt, fail_cnt, "SAT_SAFE_DC", v_err <= 300,
            "c_out=" & integer'image(to_integer(c_out)) & " err=" & integer'image(v_err));

        c_in <= to_signed(2147483000, 32);
        p_sample_n(c_pulse, 40);
        p_check(pass_cnt, fail_cnt, "SAT_POS_NO_WRAP", to_integer(c_out) > 0,
            "c_out=" & integer'image(to_integer(c_out)));

        c_in <= to_signed(-2147483000, 32);
        p_sample_n(c_pulse, 40);
        p_check(pass_cnt, fail_cnt, "SAT_NEG_NO_WRAP", to_integer(c_out) < 0,
            "c_out=" & integer'image(to_integer(c_out)));

        ------------------------------------------------------------------
        -- 7) 小信号阶跃：检查无巨大直流偏置（舍入）
        ------------------------------------------------------------------
        i_sys_rst <= '1';
        p_wait_clks(3);
        i_sys_rst <= '0';
        p_wait_clks(3);
        a_in <= to_signed(1, 32);
        p_sample_n(a_pulse, 50);
        v_err := abs(to_integer(a_out) - 1);
        p_check(pass_cnt, fail_cnt, "LS_UNIT_STEP", v_err <= 1,
            "a_out=" & integer'image(to_integer(a_out)));

        ------------------------------------------------------------------
        report "======== lpf_tustin_tb DONE: PASS=" & integer'image(pass_cnt) &
               " FAIL=" & integer'image(fail_cnt) & " ========" severity note;
        if fail_cnt /= 0 then
            report "SIMULATION FAILED" severity failure;
        end if;
        sim_done <= true;
        finish(0);
        wait;
    end process p_stim;

end architecture sim;
