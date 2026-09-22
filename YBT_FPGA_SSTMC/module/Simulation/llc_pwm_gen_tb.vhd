--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_pwm_gen_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   持续随机：占空比固定 50%；每 40 us（25 kHz）在
--                        2000～6000 clk 内随机跳开关周期（20～60 kHz）；
--                        每 1 ms（1 kHz）移相在 ±100 clk 内随机跳。
--                        φ>0：S1 超前 S4 → ph14=t1r-t4r 为负。
--                        每开关周期测 ph14/ph23/dt12/dt34。
--------------------------------------------------------------------------------
--Version           :   Rev 1.1
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   25 kHz 改频、1 kHz 改 φ、50% 占空、循环随机
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity llc_pwm_gen_tb is
end entity llc_pwm_gen_tb;

architecture sim of llc_pwm_gen_tb is

    constant CLK_FREQ   : positive := 120_000_000;
    constant CLK_PERIOD : time     := 1 sec / CLK_FREQ;

    constant C_PERIOD_MIN : positive := 2000;            -- 60 kHz @120 MHz
    constant C_PERIOD_MAX : positive := 6000;            -- 20 kHz
    constant C_FREQ_MIN   : positive := CLK_FREQ / C_PERIOD_MAX;
    constant C_FREQ_MAX   : positive := CLK_FREQ / C_PERIOD_MIN;
    constant C_PH_MIN      : integer  := -100;
    constant C_PH_MAX      : integer  := 100;
    constant C_DUTY        : natural  := 1023;           -- 10bit 满度 → 半周 50%
    constant C_RST_HOLD    : time     := 500 ns;
    constant C_FREQ_UPDATE : time     := 40 us;          -- 25 kHz 改输入频率
    constant C_PH_UPDATE   : time     := 1 ms;           -- 1 kHz 改移相

    signal i_sys_clk    : std_logic := '0';
    signal i_sys_rst    : std_logic := '1';
    signal i_pwm_en     : std_logic := '0';
    signal i_pwm_period : std_logic_vector(12 downto 0) := (others => '0');
    signal i_pwm_duty   : std_logic_vector(9 downto 0)  := (others => '0');
    signal i_phase_clk  : signed(12 downto 0) := (others => '0');
    signal i_sr_en      : std_logic := '0';

    signal o_pwm1, o_pwm2, o_pwm3, o_pwm4 : std_logic;
    signal o_pwm5, o_pwm6, o_pwm7, o_pwm8 : std_logic;

    signal m_ph14 : integer := 0;
    signal m_ph23 : integer := 0;
    signal m_dt12 : integer := 0;
    signal m_dt34 : integer := 0;
    signal m_idx  : natural := 0;

    -- 当前命令（便于 Wave）
    signal m_cmd_period : natural := C_PERIOD_MAX;
    signal m_cmd_phase  : integer := 0;
    signal m_cmd_ph_tgt : integer := 0;
    signal m_cmd_freq   : natural := C_FREQ_MIN;

    -- pwm1～4 高电平时钟计数：高 +1，低清 0；下降沿锁存脉宽
    signal m_hi1_cnt, m_hi2_cnt, m_hi3_cnt, m_hi4_cnt : natural := 0;
    signal m_hi1_w,   m_hi2_w,   m_hi3_w,   m_hi4_w   : natural := 0;

    function f_wrap_diff(d : integer; period : natural) return integer is
        variable v : integer := d;
        variable half : integer;
    begin
        half := integer(period) / 2;
        while v > half loop
            v := v - integer(period);
        end loop;
        while v < -half loop
            v := v + integer(period);
        end loop;
        return v;
    end function;

    -- 均匀整数 [lo, hi]（-2002：不读 out 参数）
    procedure p_rand_int (
        variable seed1, seed2 : inout positive;
        constant lo, hi : in integer;
        variable r : out integer
    ) is
        variable u : real;
        variable v : integer;
    begin
        uniform(seed1, seed2, u);
        v := lo + integer(trunc(u * real(hi - lo + 1)));
        if v > hi then
            v := hi;
        end if;
        if v < lo then
            v := lo;
        end if;
        r := v;
    end procedure;

    procedure p_meas_cycle (
        signal clk : in std_logic;
        signal p1, p2, p3, p4 : in std_logic;
        constant period : in natural;
        variable ph14 : out integer;
        variable ph23 : out integer;
        variable dt12 : out integer;
        variable dt34 : out integer
    ) is
        variable t : natural := 0;
        variable prev1, prev2, prev3, prev4 : std_logic;
        variable t1r, t2r, t3r, t4r : integer := -1;
        variable t1f, t4f           : integer := -1;
    begin
        ph14 := -9999; ph23 := -9999; dt12 := -9999; dt34 := -9999;
        prev1 := p1; prev2 := p2; prev3 := p3; prev4 := p4;

        loop
            wait until rising_edge(clk);
            if prev1 = '0' and p1 = '1' then
                t1r := 0; t := 0; exit;
            elsif prev4 = '0' and p4 = '1' then
                t4r := 0; t := 0; exit;
            end if;
            prev1 := p1; prev2 := p2; prev3 := p3; prev4 := p4;
        end loop;
        prev1 := p1; prev2 := p2; prev3 := p3; prev4 := p4;

        while t < period loop
            wait until rising_edge(clk);
            t := t + 1;
            if prev1 = '0' and p1 = '1' and t1r < 0 then t1r := integer(t); end if;
            if prev4 = '0' and p4 = '1' and t4r < 0 then t4r := integer(t); end if;
            if prev1 = '1' and p1 = '0' and t1r >= 0 and t1f < 0 then t1f := integer(t); end if;
            if prev4 = '1' and p4 = '0' and t4r >= 0 and t4f < 0 then t4f := integer(t); end if;
            if prev2 = '0' and p2 = '1' then
                if (t1f >= 0) and (integer(t) >= t1f) then
                    if t2r < 0 then t2r := integer(t); end if;
                elsif t1f < 0 and t2r < 0 then
                    t2r := integer(t);
                end if;
            end if;
            if prev3 = '0' and p3 = '1' then
                if (t4f >= 0) and (integer(t) >= t4f) then
                    if t3r < 0 then t3r := integer(t); end if;
                elsif t4f < 0 and t3r < 0 then
                    t3r := integer(t);
                end if;
            end if;
            prev1 := p1; prev2 := p2; prev3 := p3; prev4 := p4;
            exit when t1r >= 0 and t4r >= 0 and t1f >= 0 and t4f >= 0 and
                      t2r >= 0 and t3r >= 0 and t2r >= t1f and t3r >= t4f;
        end loop;

        if (t2r >= 0) and (t1f >= 0) and (t2r < t1f) then t2r := -1; end if;
        if (t3r >= 0) and (t4f >= 0) and (t3r < t4f) then t3r := -1; end if;

        if (t2r < 0) or (t3r < 0) then
            while t < (period + period / 2) loop
                wait until rising_edge(clk);
                t := t + 1;
                if prev2 = '0' and p2 = '1' and t1f >= 0 and integer(t) >= t1f and t2r < 0 then
                    t2r := integer(t);
                end if;
                if prev3 = '0' and p3 = '1' and t4f >= 0 and integer(t) >= t4f and t3r < 0 then
                    t3r := integer(t);
                end if;
                prev2 := p2; prev3 := p3;
                exit when t2r >= 0 and t3r >= 0;
            end loop;
        end if;

        if (t1r >= 0) and (t4r >= 0) then
            ph14 := f_wrap_diff(t1r - t4r, period);
        end if;
        if (t2r >= 0) and (t3r >= 0) then
            ph23 := f_wrap_diff(t2r - t3r, period);
        end if;
        if (t1f >= 0) and (t2r >= 0) and (t2r >= t1f) then
            dt12 := t2r - t1f;
        end if;
        if (t4f >= 0) and (t3r >= 0) and (t3r >= t4f) then
            dt34 := t3r - t4f;
        end if;
    end procedure;

begin

    U_DUT : entity work.llc_pwm_gen
        generic map (CLK_FREQ => CLK_FREQ)
        port map (
            i_sys_clk => i_sys_clk, i_sys_rst => i_sys_rst,
            i_pwm_en => i_pwm_en, i_pwm_period => i_pwm_period,
            i_pwm_duty => i_pwm_duty, i_phase_clk => i_phase_clk,
            i_sr_en => i_sr_en,
            o_pwm1 => o_pwm1, o_pwm2 => o_pwm2, o_pwm3 => o_pwm3, o_pwm4 => o_pwm4,
            o_pwm5 => o_pwm5, o_pwm6 => o_pwm6, o_pwm7 => o_pwm7, o_pwm8 => o_pwm8
        );

    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

    -- pwm1～4 高电平计数：高 +1，低清 0
    p_hi_cnt : process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            m_hi1_cnt <= 0; m_hi2_cnt <= 0; m_hi3_cnt <= 0; m_hi4_cnt <= 0;
            m_hi1_w   <= 0; m_hi2_w   <= 0; m_hi3_w   <= 0; m_hi4_w   <= 0;
        elsif rising_edge(i_sys_clk) then
            if o_pwm1 = '1' then
                m_hi1_cnt <= m_hi1_cnt + 1;
            else
                if m_hi1_cnt > 0 then m_hi1_w <= m_hi1_cnt; end if;
                m_hi1_cnt <= 0;
            end if;
            if o_pwm2 = '1' then
                m_hi2_cnt <= m_hi2_cnt + 1;
            else
                if m_hi2_cnt > 0 then m_hi2_w <= m_hi2_cnt; end if;
                m_hi2_cnt <= 0;
            end if;
            if o_pwm3 = '1' then
                m_hi3_cnt <= m_hi3_cnt + 1;
            else
                if m_hi3_cnt > 0 then m_hi3_w <= m_hi3_cnt; end if;
                m_hi3_cnt <= 0;
            end if;
            if o_pwm4 = '1' then
                m_hi4_cnt <= m_hi4_cnt + 1;
            else
                if m_hi4_cnt > 0 then m_hi4_w <= m_hi4_cnt; end if;
                m_hi4_cnt <= 0;
            end if;
        end if;
    end process p_hi_cnt;

    -- 25 kHz：开关周期在 2000～6000 内随机跳动
    p_rand_freq : process
        variable v_seed1, v_seed2 : positive := 12345;
        variable v_period : integer;
        variable v_freq   : integer;
    begin
        v_period := integer(C_PERIOD_MAX);
        i_pwm_period <= std_logic_vector(to_unsigned(C_PERIOD_MAX, 13));
        m_cmd_period <= C_PERIOD_MAX;
        m_cmd_freq   <= C_FREQ_MIN;
        wait until i_pwm_en = '1';
        wait until rising_edge(i_sys_clk);
        loop
            p_rand_int(v_seed1, v_seed2, integer(C_PERIOD_MIN), integer(C_PERIOD_MAX), v_period);
            v_freq := integer(CLK_FREQ) / v_period;
            i_pwm_period <= std_logic_vector(to_unsigned(v_period, 13));
            m_cmd_period <= v_period;
            m_cmd_freq   <= v_freq;
            wait for C_FREQ_UPDATE;
        end loop;
    end process p_rand_freq;

    -- 1 kHz：移相在 ±100 clk 内随机跳
    p_rand_phase : process
        variable v_seed1, v_seed2 : positive := 67891;
        variable v_phi : integer := 0;
    begin
        i_phase_clk  <= (others => '0');
        m_cmd_phase  <= 0;
        m_cmd_ph_tgt <= 0;
        wait until i_pwm_en = '1';
        wait until rising_edge(i_sys_clk);
        loop
            p_rand_int(v_seed1, v_seed2, C_PH_MIN, C_PH_MAX, v_phi);
            i_phase_clk  <= to_signed(v_phi, 13);
            m_cmd_phase  <= v_phi;
            m_cmd_ph_tgt <= v_phi;
            wait for C_PH_UPDATE;
        end loop;
    end process p_rand_phase;

    -- 每开关周期测一次（用当前 m_cmd_period）
    p_meas : process
        variable v_ph14, v_ph23, v_dt12, v_dt34 : integer;
        variable v_period : natural;
        variable v_i : natural := 0;
    begin
        wait until i_pwm_en = '1';
        wait until rising_edge(i_sys_clk);
        loop
            v_period := m_cmd_period;
            if v_period < C_PERIOD_MIN then
                v_period := C_PERIOD_MIN;
            end if;
            p_meas_cycle(i_sys_clk, o_pwm1, o_pwm2, o_pwm3, o_pwm4, v_period,
                         v_ph14, v_ph23, v_dt12, v_dt34);
            v_i := v_i + 1;
            m_ph14 <= v_ph14; m_ph23 <= v_ph23;
            m_dt12 <= v_dt12; m_dt34 <= v_dt34;
            m_idx  <= v_i;
            wait for 0 ns;
            report "CYC" & integer'image(v_i) &
                   " f=" & integer'image(m_cmd_freq) &
                   " ph_tgt=" & integer'image(m_cmd_ph_tgt) &
                   " ph_cmd=" & integer'image(m_cmd_phase) &
                   " ph14=" & integer'image(v_ph14) &
                   " ph23=" & integer'image(v_ph23) &
                   " dt12=" & integer'image(v_dt12) &
                   " dt34=" & integer'image(v_dt34) &
                   " hi1w=" & integer'image(m_hi1_w) &
                   " hi2w=" & integer'image(m_hi2_w) &
                   " hi3w=" & integer'image(m_hi3_w) &
                   " hi4w=" & integer'image(m_hi4_w);
        end loop;
    end process p_meas;

    stimulus : process
    begin
        report "========================================";
        report " duty=50%; f cmd @25 kHz; phase cmd @1 kHz; random forever";
        report "========================================";

        i_sys_rst  <= '1';
        i_pwm_en   <= '0';
        i_sr_en    <= '0';
        i_pwm_duty <= std_logic_vector(to_unsigned(C_DUTY, 10));
        wait for C_RST_HOLD;
        i_sys_rst <= '0';
        wait until rising_edge(i_sys_clk);

        i_pwm_en <= '1';
        i_sr_en  <= '1';
        wait;
    end process;

end architecture sim;
