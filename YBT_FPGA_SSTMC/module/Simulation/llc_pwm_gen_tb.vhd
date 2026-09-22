--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_pwm_gen_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   llc_pwm_gen 模块级仿真 Testbench。
--                      主工况：50 kHz、占空比 50%(duty=1023)、移相 ±50 clk。
--                      运行（GHDL）：ghdl -a ../Core/PwmCore/llc_pwm_gen.vhd llc_pwm_gen_tb.vhd
--                                   ghdl -e llc_pwm_gen_tb
--                                   ghdl -r llc_pwm_gen_tb --vcd=llc_pwm_gen_tb.vcd
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.22
--Modify Record     :   修脉宽中途起算；记分板 wait 0ns；主工况 50k/±50
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- 不用 std.env，便于 ModelSim 以 VHDL-2002/-2008 均可编译

entity llc_pwm_gen_tb is
end entity llc_pwm_gen_tb;

architecture sim of llc_pwm_gen_tb is

    -- ===================== 与 DUT 一致的算法常数（用于期望模型） =====================
    constant CLK_FREQ           : positive := 120_000_000;
    constant CLK_PERIOD         : time     := 1 sec / CLK_FREQ;

    constant C_PERIOD_MIN       : positive := CLK_FREQ / 80_000;   -- 1500
    constant C_PERIOD_MAX       : positive := CLK_FREQ / 20_000;   -- 6000
    constant C_PERIOD_TRAIL_HI  : positive := CLK_FREQ / 33_500;   -- 3582
    constant C_DEADTIME         : positive := CLK_FREQ / 5_000_000; -- 24
    constant C_SR_LEAD          : positive := CLK_FREQ / 2_000_000; -- 60
    constant C_SR_TRAIL_SHORT   : positive := CLK_FREQ / 2_000_000;  -- 60
    constant C_SR_TRAIL_LONG    : positive := CLK_FREQ / 100_000;   -- 1200
    constant C_MIN_PULSE        : positive := 21;
    constant C_DUTY_SHIFT       : positive := 11;
    constant C_DUTY_OFF_TH      : positive := 41;

    -- 本 TB 主工况：50 kHz、占空比 50%（口线满量程 1023）、移相 ±50
    constant C_PERIOD_50K       : positive := CLK_FREQ / 50_000;   -- 2400
    constant C_DUTY_50PCT       : natural  := 1023;                -- 0～1023 → 0～50%
    constant C_PHASE_LAG        : integer  := 50;                  -- +50：1 滞后 4
    constant C_PHASE_LEAD       : integer  := -50;                 -- -50：1 超前 4

    constant C_RST_HOLD         : time     := 500 ns;
    constant C_SETTLE_CYCLES    : positive := 4;  -- 使能后等待稳定周期数

    -- ===================== DUT 接口 =====================
    signal i_sys_clk    : std_logic := '0';
    signal i_sys_rst    : std_logic := '1';
    signal i_pwm_en     : std_logic := '0';
    signal i_pwm_period : std_logic_vector(12 downto 0) := (others => '0');
    signal i_pwm_duty   : std_logic_vector(9 downto 0)  := (others => '0');
    signal i_phase_clk  : signed(12 downto 0) := (others => '0');
    signal i_sr_en      : std_logic := '0';

    signal o_pwm1       : std_logic;
    signal o_pwm2       : std_logic;
    signal o_pwm3       : std_logic;
    signal o_pwm4       : std_logic;
    signal o_pwm5       : std_logic;
    signal o_pwm6       : std_logic;
    signal o_pwm7       : std_logic;
    signal o_pwm8       : std_logic;

    -- ===================== 记分板 =====================
    signal test_pass    : natural := 0;
    signal test_fail    : natural := 0;

    -- ===================== 期望参数记录（与 DUT reload 算法一致） =====================
    type t_pwm_expect is record
        period     : natural;
        half       : natural;
        on_width   : natural;
        dead_eff   : natural;
        pri_neg_on : natural;
        trail      : natural;
        sr_pos_on  : natural;
        sr_pos_off : natural;
        sr_neg_on  : natural;
        sr_neg_off : natural;
        sr_pos_ok  : boolean;
        sr_neg_ok  : boolean;
    end record;

    -- ===================== 工具函数 / 过程 =====================
    function f_calc_expect (
        period_in : natural;
        duty_in   : natural
    ) return t_pwm_expect is
        variable v       : t_pwm_expect;
        variable v_period: natural;
        variable v_half  : natural;
        variable v_on_max: natural;
        variable v_on_w  : natural;
        variable v_dead  : natural;
        variable v_trail : natural;
        variable v_prod  : natural;
    begin
        v_period := period_in;
        if v_period < C_PERIOD_MIN then
            v_period := C_PERIOD_MIN;
        elsif v_period > C_PERIOD_MAX then
            v_period := C_PERIOD_MAX;
        end if;

        v.period := v_period;
        v_half   := v_period / 2;
        v.half   := v_half;

        v_on_max := v_half - C_DEADTIME;
        if v_on_max < C_MIN_PULSE then
            v_on_max := C_MIN_PULSE;
        end if;

        v_prod := duty_in * v_period;
        v_on_w := v_prod / (2**C_DUTY_SHIFT);
        if v_on_w < C_MIN_PULSE then
            v_on_w := C_MIN_PULSE;
        elsif v_on_w > v_on_max then
            v_on_w := v_on_max;
        end if;
        v.on_width := v_on_w;

        v_dead := v_half - v_on_w;
        if v_dead < C_DEADTIME then
            v_dead := C_DEADTIME;
        end if;
        v.dead_eff   := v_dead;
        v.pri_neg_on := v_half + v_dead;

        if v_period <= C_PERIOD_TRAIL_HI then
            v_trail := C_SR_TRAIL_SHORT;
        else
            v_trail := C_SR_TRAIL_LONG;
        end if;
        v.trail := v_trail;

        v.sr_pos_on  := v_dead + C_SR_LEAD;
        v.sr_pos_off := v_half - v_trail;
        if v.sr_pos_off <= (v.sr_pos_on + C_MIN_PULSE) then
            v.sr_pos_off := v.sr_pos_on + C_MIN_PULSE;
        end if;
        if v.sr_pos_off > v_half then
            v.sr_pos_off := v_half;
        end if;
        v.sr_pos_ok := (v.sr_pos_off > v.sr_pos_on);

        v.sr_neg_on  := v_half + v_dead + C_SR_LEAD;
        v.sr_neg_off := v_period - v_trail;
        if v.sr_neg_off <= (v.sr_neg_on + C_MIN_PULSE) then
            v.sr_neg_off := v.sr_neg_on + C_MIN_PULSE;
        end if;
        if v.sr_neg_off > v_period then
            v.sr_neg_off := v_period;
        end if;
        v.sr_neg_ok := (v.sr_neg_off > v.sr_neg_on);

        return v;
    end function f_calc_expect;

    procedure p_wait_cycles (
        constant n : in positive
    ) is
    begin
        for i in 1 to n loop
            wait until rising_edge(i_sys_clk);
        end loop;
    end procedure p_wait_cycles;

    procedure p_check_eq (
        signal pass_cnt : inout natural;
        signal fail_cnt : inout natural;
        constant name   : in string;
        constant expect : in natural;
        constant actual : in natural;
        constant tol    : in natural := 1
    ) is
        variable v_diff : integer;
    begin
        v_diff := abs(actual - expect);
        if v_diff <= tol then
            pass_cnt <= pass_cnt + 1;
            wait for 0 ns;  -- 让 signal 更新，避免同 delta 多次 +1 丢失
            report "[PASS] " & name & " expect=" & integer'image(expect) &
                   " actual=" & integer'image(actual);
        else
            fail_cnt <= fail_cnt + 1;
            wait for 0 ns;
            report "[FAIL] " & name & " expect=" & integer'image(expect) &
                   " actual=" & integer'image(actual) &
                   " diff=" & integer'image(v_diff)
                severity error;
        end if;
    end procedure p_check_eq;

    procedure p_check_all_off (
        signal pass_cnt : inout natural;
        signal fail_cnt : inout natural;
        constant tag    : in string
    ) is
    begin
        wait until falling_edge(i_sys_clk);
        if o_pwm1 = '0' and o_pwm2 = '0' and o_pwm3 = '0' and o_pwm4 = '0' and
           o_pwm5 = '0' and o_pwm6 = '0' and o_pwm7 = '0' and o_pwm8 = '0' then
            pass_cnt <= pass_cnt + 1;
            wait for 0 ns;
            report "[PASS] " & tag & " all outputs off";
        else
            fail_cnt <= fail_cnt + 1;
            wait for 0 ns;
            report "[FAIL] " & tag & " outputs not all off" severity error;
        end if;
    end procedure p_check_all_off;

    -- 测量 signal 下一次完整高电平脉宽（clk 数）
    -- 必须先对齐 0→1，否则若调用时已为高会从中途起算（测短）
    procedure p_meas_pulse_width (
        signal sig  : in std_logic;
        variable width : out natural
    ) is
        variable v_w   : natural;
        variable v_prev : std_logic;
    begin
        v_prev := sig;
        loop
            wait until rising_edge(i_sys_clk);
            if v_prev = '0' and sig = '1' then
                exit;
            end if;
            v_prev := sig;
        end loop;

        v_w := 1;
        wait until rising_edge(i_sys_clk);
        while sig = '1' loop
            v_w := v_w + 1;
            wait until rising_edge(i_sys_clk);
        end loop;
        width := v_w;
    end procedure p_meas_pulse_width;

    -- 测量 pwm1 相邻两次上升沿间隔（整周期 clk 数）
    procedure p_meas_pwm1_period (
        variable period_clks : out natural
    ) is
        variable cnt  : natural := 0;
        variable prev : std_logic := '1';
    begin
        -- 等到第一次 0→1
        loop
            wait until rising_edge(i_sys_clk);
            if prev = '0' and o_pwm1 = '1' then
                exit;
            end if;
            prev := o_pwm1;
        end loop;

        cnt  := 0;
        prev := '1';
        loop
            wait until rising_edge(i_sys_clk);
            cnt := cnt + 1;
            if prev = '0' and o_pwm1 = '1' then
                period_clks := cnt;
                exit;
            end if;
            prev := o_pwm1;
        end loop;
    end procedure p_meas_pwm1_period;

    procedure p_apply_pwm (
        signal   en_o     : out std_logic;
        signal   period_o : out std_logic_vector(12 downto 0);
        signal   duty_o   : out std_logic_vector(9 downto 0);
        signal   sr_en_o  : out std_logic;
        constant en       : in  std_logic;
        constant period   : in  natural;
        constant duty     : in  natural;
        constant sr_en    : in  std_logic
    ) is
    begin
        en_o     <= en;
        period_o <= std_logic_vector(to_unsigned(period, 13));
        duty_o   <= std_logic_vector(to_unsigned(duty, 10));
        sr_en_o  <= sr_en;
    end procedure p_apply_pwm;

    procedure p_run_and_check (
        signal   pass_cnt : inout natural;
        signal   fail_cnt : inout natural;
        signal   en_o     : out std_logic;
        signal   period_o : out std_logic_vector(12 downto 0);
        signal   duty_o   : out std_logic_vector(9 downto 0);
        signal   sr_en_o  : out std_logic;
        constant tc_name  : in string;
        constant period   : in natural;
        constant duty     : in natural;
        constant sr_en    : in std_logic
    ) is
        variable v_exp          : t_pwm_expect;
        variable v_pri_pos_w    : natural;
        variable v_pri_neg_w    : natural;
        variable v_sr_pos_w     : natural;
        variable v_sr_neg_w     : natural;
        variable v_full_period  : natural;
        variable v_settle       : natural;
        variable v_prev1        : std_logic;
    begin
        v_exp := f_calc_expect(period, duty);
        p_apply_pwm(en_o, period_o, duty_o, sr_en_o, '1', period, duty, sr_en);

        v_settle := v_exp.period * C_SETTLE_CYCLES;
        p_wait_cycles(v_settle);

        -- 整周期（结束时 o_pwm1 为高，后续脉宽测量必须重新对齐 0→1）
        p_meas_pwm1_period(v_full_period);
        p_check_eq(pass_cnt, fail_cnt, tc_name & " full_period", v_exp.period, v_full_period, 1);

        -- 原边正半周脉宽（pwm1）
        p_meas_pulse_width(o_pwm1, v_pri_pos_w);
        p_check_eq(pass_cnt, fail_cnt, tc_name & " pri_pos_width", v_exp.on_width, v_pri_pos_w, 1);

        -- 原边负半周脉宽（pwm2）
        p_meas_pulse_width(o_pwm2, v_pri_neg_w);
        p_check_eq(pass_cnt, fail_cnt, tc_name & " pri_neg_width", v_exp.on_width, v_pri_neg_w, 1);

        -- 互补：等下一次 pwm1 上升沿时采样 pwm2
        v_prev1 := '1';
        loop
            wait until rising_edge(i_sys_clk);
            if v_prev1 = '0' and o_pwm1 = '1' then
                exit;
            end if;
            v_prev1 := o_pwm1;
        end loop;
        if o_pwm2 = '0' then
            pass_cnt <= pass_cnt + 1;
            wait for 0 ns;
            report "[PASS] " & tc_name & " pri pos/neg exclusive (sample)";
        else
            fail_cnt <= fail_cnt + 1;
            wait for 0 ns;
            report "[FAIL] " & tc_name & " pwm1/pwm2 overlap" severity error;
        end if;

        if sr_en = '1' then
            if v_exp.sr_pos_ok then
                p_meas_pulse_width(o_pwm5, v_sr_pos_w);
                p_check_eq(pass_cnt, fail_cnt, tc_name & " sr_pos_width",
                           v_exp.sr_pos_off - v_exp.sr_pos_on, v_sr_pos_w, 1);
            else
                if o_pwm5 = '0' and o_pwm8 = '0' then
                    pass_cnt <= pass_cnt + 1;
                    wait for 0 ns;
                    report "[PASS] " & tc_name & " sr_pos invalid window, kept off";
                else
                    fail_cnt <= fail_cnt + 1;
                    wait for 0 ns;
                    report "[FAIL] " & tc_name & " sr_pos should stay off" severity error;
                end if;
            end if;

            if v_exp.sr_neg_ok then
                p_meas_pulse_width(o_pwm6, v_sr_neg_w);
                p_check_eq(pass_cnt, fail_cnt, tc_name & " sr_neg_width",
                           v_exp.sr_neg_off - v_exp.sr_neg_on, v_sr_neg_w, 1);
            else
                if o_pwm6 = '0' and o_pwm7 = '0' then
                    pass_cnt <= pass_cnt + 1;
                    wait for 0 ns;
                    report "[PASS] " & tc_name & " sr_neg invalid window, kept off";
                else
                    fail_cnt <= fail_cnt + 1;
                    wait for 0 ns;
                    report "[FAIL] " & tc_name & " sr_neg should stay off" severity error;
                end if;
            end if;
        else
            if o_pwm5 = '0' and o_pwm6 = '0' and o_pwm7 = '0' and o_pwm8 = '0' then
                pass_cnt <= pass_cnt + 1;
                wait for 0 ns;
                report "[PASS] " & tc_name & " SR off when i_sr_en=0";
            else
                fail_cnt <= fail_cnt + 1;
                wait for 0 ns;
                report "[FAIL] " & tc_name & " SR outputs active while disabled" severity error;
            end if;
        end if;
    end procedure p_run_and_check;

begin

    -- ===================== DUT 例化 =====================
    U_DUT : entity work.llc_pwm_gen
        generic map (
            CLK_FREQ => CLK_FREQ
        )
        port map (
            i_sys_clk    => i_sys_clk,
            i_sys_rst    => i_sys_rst,
            i_pwm_en     => i_pwm_en,
            i_pwm_period => i_pwm_period,
            i_pwm_duty   => i_pwm_duty,
            i_phase_clk  => i_phase_clk,
            i_sr_en      => i_sr_en,
            o_pwm1       => o_pwm1,
            o_pwm2       => o_pwm2,
            o_pwm3       => o_pwm3,
            o_pwm4       => o_pwm4,
            o_pwm5       => o_pwm5,
            o_pwm6       => o_pwm6,
            o_pwm7       => o_pwm7,
            o_pwm8       => o_pwm8
        );

    -- ===================== 120 MHz 时钟 =====================
    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    -- ===================== 主激励：50 kHz / duty50% / φ=±50 =====================
    stimulus : process
        variable v_prev : std_logic;
        variable v_lag  : natural;
    begin
        report "========================================";
        report " llc_pwm_gen_tb: 50kHz duty50% phase+/-50";
        report " period=" & integer'image(C_PERIOD_50K) &
               " duty=" & integer'image(C_DUTY_50PCT);
        report "========================================";

        -- ---------- TC0：复位 ----------
        i_sys_rst    <= '1';
        i_pwm_en     <= '0';
        i_sr_en      <= '0';
        i_phase_clk  <= (others => '0');
        i_pwm_period <= (others => '0');
        i_pwm_duty   <= (others => '0');
        wait for C_RST_HOLD;
        i_sys_rst <= '0';
        wait until falling_edge(i_sys_clk);

        p_check_all_off(test_pass, test_fail, "TC0 reset release");
        p_wait_cycles(10);

        -- ---------- TC1：50 kHz、duty=1023(≈50%)、φ=0、SR 开 ----------
        i_phase_clk <= (others => '0');
        p_run_and_check(test_pass, test_fail, i_pwm_en, i_pwm_period, i_pwm_duty, i_sr_en,
                        "TC1 50k duty50% ph0 SRon", C_PERIOD_50K, C_DUTY_50PCT, '1');

        -- ---------- TC2：φ=+50，pwm1 滞后 pwm4；同臂不重叠 ----------
        i_phase_clk <= to_signed(C_PHASE_LAG, 13);
        p_apply_pwm(i_pwm_en, i_pwm_period, i_pwm_duty, i_sr_en,
                    '1', C_PERIOD_50K, C_DUTY_50PCT, '1');
        p_wait_cycles(C_PERIOD_50K * C_SETTLE_CYCLES);
        v_prev := '1';
        loop
            wait until rising_edge(i_sys_clk);
            if v_prev = '0' and o_pwm4 = '1' then
                exit;
            end if;
            v_prev := o_pwm4;
        end loop;
        v_lag := 0;
        if o_pwm1 = '0' then
            loop
                wait until rising_edge(i_sys_clk);
                v_lag := v_lag + 1;
                if o_pwm1 = '1' then
                    exit;
                end if;
            end loop;
        end if;
        p_check_eq(test_pass, test_fail, "TC2 phase+50 lag 4->1", C_PHASE_LAG, v_lag, 1);
        if o_pwm1 = '1' and o_pwm2 = '1' then
            test_fail <= test_fail + 1;
            wait for 0 ns;
            report "[FAIL] TC2 pwm1/pwm2 overlap" severity error;
        else
            test_pass <= test_pass + 1;
            wait for 0 ns;
            report "[PASS] TC2 pwm1/pwm2 exclusive";
        end if;
        if o_pwm3 = '1' and o_pwm4 = '1' then
            test_fail <= test_fail + 1;
            wait for 0 ns;
            report "[FAIL] TC2 pwm3/pwm4 overlap" severity error;
        else
            test_pass <= test_pass + 1;
            wait for 0 ns;
            report "[PASS] TC2 pwm3/pwm4 exclusive";
        end if;

        -- ---------- TC3：φ=-50，pwm1 超前 pwm4（测 1→4 滞后 =50） ----------
        i_phase_clk <= to_signed(C_PHASE_LEAD, 13);
        p_apply_pwm(i_pwm_en, i_pwm_period, i_pwm_duty, i_sr_en,
                    '1', C_PERIOD_50K, C_DUTY_50PCT, '1');
        p_wait_cycles(C_PERIOD_50K * C_SETTLE_CYCLES);
        v_prev := '1';
        loop
            wait until rising_edge(i_sys_clk);
            if v_prev = '0' and o_pwm1 = '1' then
                exit;
            end if;
            v_prev := o_pwm1;
        end loop;
        v_lag := 0;
        if o_pwm4 = '0' then
            loop
                wait until rising_edge(i_sys_clk);
                v_lag := v_lag + 1;
                if o_pwm4 = '1' then
                    exit;
                end if;
            end loop;
        end if;
        p_check_eq(test_pass, test_fail, "TC3 phase-50 lag 1->4", 50, v_lag, 1);
        if o_pwm1 = '1' and o_pwm2 = '1' then
            test_fail <= test_fail + 1;
            wait for 0 ns;
            report "[FAIL] TC3 pwm1/pwm2 overlap" severity error;
        else
            test_pass <= test_pass + 1;
            wait for 0 ns;
            report "[PASS] TC3 pwm1/pwm2 exclusive";
        end if;
        if o_pwm3 = '1' and o_pwm4 = '1' then
            test_fail <= test_fail + 1;
            wait for 0 ns;
            report "[FAIL] TC3 pwm3/pwm4 overlap" severity error;
        else
            test_pass <= test_pass + 1;
            wait for 0 ns;
            report "[PASS] TC3 pwm3/pwm4 exclusive";
        end if;

        -- ---------- TC4：φ 回 0，1=4、2=3 ----------
        i_phase_clk <= (others => '0');
        p_apply_pwm(i_pwm_en, i_pwm_period, i_pwm_duty, i_sr_en,
                    '1', C_PERIOD_50K, C_DUTY_50PCT, '1');
        p_wait_cycles(C_PERIOD_50K * C_SETTLE_CYCLES);
        if o_pwm1 = o_pwm4 and o_pwm2 = o_pwm3 then
            test_pass <= test_pass + 1;
            wait for 0 ns;
            report "[PASS] TC4 phase0 diagonal match sample";
        else
            test_fail <= test_fail + 1;
            wait for 0 ns;
            report "[FAIL] TC4 phase0 1!=4 or 2!=3" severity error;
        end if;

        -- ---------- 汇总 ----------
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

        wait;
    end process stimulus;

end architecture sim;