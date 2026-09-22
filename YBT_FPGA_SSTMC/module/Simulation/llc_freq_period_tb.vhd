--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_freq_period_tb.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.23
--Description       :   验证 SSTMC_FPGA.P_LLC_FREQ + U_LLC_PERIOD_DIV：
--                      sig_P15t（单位 10Hz）→ period = 12_000_000 / clamp(f)。
--                      限幅：0 或 >8000 → 8000（80kHz, period=1500）；
--                            <2000 → 2000（20kHz, period=6000）。
--                      不例化整板，逻辑与顶层 508～554 行一致（numeric_std）。
--------------------------------------------------------------------------------
--Version           :   Rev 0.1
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_freq_period_tb is
end entity llc_freq_period_tb;

architecture sim of llc_freq_period_tb is

    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz = CLKIN

    constant LLC_F_MIN        : integer := 2000;
    constant LLC_F_MAX        : integer := 8000;
    constant LLC_PERIOD_MIN   : integer := 1500;   -- 80 kHz
    constant LLC_PERIOD_MAX   : integer := 6000;   -- 20 kHz
    constant LLC_PERIOD_SCALE : integer := 12_000_000;
    constant LLC_DIV_DVD_W    : integer := 24;
    constant LLC_DIV_DVS_W    : integer := 13;

    constant C_LLC_DIVIDEND : std_logic_vector(LLC_DIV_DVD_W - 1 downto 0) :=
        std_logic_vector(to_unsigned(LLC_PERIOD_SCALE, LLC_DIV_DVD_W));

    signal clk     : std_logic := '0';
    signal rst     : std_logic := '1';
    signal sig_P15t : std_logic_vector(15 downto 0) := (others => '0');

    signal sig_llc_freq_r      : std_logic_vector(15 downto 0) := (others => '0');
    signal w_llc_pwm_period_50 : std_logic_vector(12 downto 0) :=
        std_logic_vector(to_unsigned(LLC_PERIOD_MIN, 13));
    signal w_llc_div_start   : std_logic := '0';
    signal w_llc_div_divisor : std_logic_vector(LLC_DIV_DVS_W - 1 downto 0) :=
        std_logic_vector(to_unsigned(LLC_F_MAX, LLC_DIV_DVS_W));
    signal w_llc_div_quot  : std_logic_vector(LLC_DIV_DVD_W - 1 downto 0);
    signal w_llc_div_done  : std_logic;
    signal w_llc_div_busy  : std_logic;

    signal m_pass : natural := 0;
    signal m_fail : natural := 0;
    signal m_exp  : natural := 0;
    signal m_got  : natural := 0;

    function f_exp_period(freq_raw : integer) return integer is
        variable v : integer;
    begin
        v := freq_raw;
        if (v = 0) or (v > LLC_F_MAX) then
            v := LLC_F_MAX;
        elsif v < LLC_F_MIN then
            v := LLC_F_MIN;
        end if;
        return LLC_PERIOD_SCALE / v;
    end function;

    procedure p_set_freq(signal p15 : out std_logic_vector; constant f : in integer) is
    begin
        p15 <= std_logic_vector(to_unsigned(f, 16));
    end procedure;

    procedure p_wait_period (
        signal clk_i  : in  std_logic;
        signal period : in  std_logic_vector;
        signal busy   : in  std_logic;
        signal done   : in  std_logic;
        constant exp  : in  integer;
        constant name : in  string;
        signal pass_n : inout natural;
        signal fail_n : inout natural;
        signal exp_s  : out natural;
        signal got_s  : out natural
    ) is
        variable v_got : integer;
        variable v_t   : natural := 0;
    begin
        exp_s <= exp;
        -- 等启动：busy 或 done，最多约 40 拍启动窗口 + 24 拍除法
        while (busy = '0') and (done = '0') and (v_t < 50) loop
            wait until rising_edge(clk_i);
            v_t := v_t + 1;
        end loop;
        -- 等 done
        v_t := 0;
        while (done = '0') and (v_t < 64) loop
            wait until rising_edge(clk_i);
            v_t := v_t + 1;
        end loop;
        -- done 当拍写 period，再等 1 拍可读稳
        wait until rising_edge(clk_i);
        v_got := to_integer(unsigned(period));
        got_s <= v_got;
        wait for 0 ns;
        if v_got = exp then
            pass_n <= pass_n + 1;
            report "[PASS] " & name & " period=" & integer'image(v_got);
        else
            fail_n <= fail_n + 1;
            report "[FAIL] " & name & " got=" & integer'image(v_got) &
                   " exp=" & integer'image(exp) severity error;
        end if;
        wait for 0 ns;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    ---------------------------------------------------------------------------
    -- 与 SSTMC_FPGA.P_LLC_FREQ 等价（CLKIN=clk, sig_RES=rst）
    ---------------------------------------------------------------------------
    P_LLC_FREQ : process (rst, clk)
        variable v_freq_cmd : integer range 0 to 8191;
    begin
        if rst = '1' then
            sig_llc_freq_r      <= (others => '0');
            w_llc_pwm_period_50 <= std_logic_vector(to_unsigned(LLC_PERIOD_MIN, 13));
            w_llc_div_start     <= '0';
            w_llc_div_divisor   <= std_logic_vector(to_unsigned(LLC_F_MAX, LLC_DIV_DVS_W));
        elsif rising_edge(clk) then
            w_llc_div_start <= '0';

            if w_llc_div_done = '1' then
                w_llc_pwm_period_50 <= w_llc_div_quot(12 downto 0);
            end if;

            if (sig_P15t /= sig_llc_freq_r) and (w_llc_div_busy = '0') and
               (w_llc_div_start = '0') then
                sig_llc_freq_r <= sig_P15t;
                v_freq_cmd := to_integer(unsigned(sig_P15t));
                if (v_freq_cmd = 0) or (v_freq_cmd > LLC_F_MAX) then
                    v_freq_cmd := LLC_F_MAX;
                elsif v_freq_cmd < LLC_F_MIN then
                    v_freq_cmd := LLC_F_MIN;
                end if;
                w_llc_div_divisor <= std_logic_vector(
                    to_unsigned(v_freq_cmd, LLC_DIV_DVS_W));
                w_llc_div_start <= '1';
            end if;
        end if;
    end process P_LLC_FREQ;

    U_LLC_PERIOD_DIV : entity work.unsigned_division
        generic map (
            WIDTH_DVD => LLC_DIV_DVD_W,
            WIDTH_DVS => LLC_DIV_DVS_W
        )
        port map (
            i_sys_clk   => clk,
            i_sys_rst   => rst,
            i_start     => w_llc_div_start,
            i_dividend  => C_LLC_DIVIDEND,
            i_divisor   => w_llc_div_divisor,
            o_quotient  => w_llc_div_quot,
            o_remainder => open,
            o_done      => w_llc_div_done,
            o_busy      => w_llc_div_busy,
            o_div_zero  => open
        );

    stimulus : process
        variable v_f   : integer;
        variable v_exp : integer;
        variable v_got : integer;
        variable v_t   : natural;
    begin
        report "======== llc_freq_period_tb START ========";

        rst <= '1';
        p_set_freq(sig_P15t, 0);
        wait for 200 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        -- 复位默认 period=1500，且 P15t=0 与 r 相同，不应再除
        if to_integer(unsigned(w_llc_pwm_period_50)) = LLC_PERIOD_MIN then
            m_pass <= m_pass + 1;
            report "[PASS] reset period=1500";
        else
            m_fail <= m_fail + 1;
            report "[FAIL] reset period" severity error;
        end if;
        wait for 0 ns;

        -- 典型点
        p_set_freq(sig_P15t, 8000);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      1500, "f=8000 -> 80kHz", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 2000);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      6000, "f=2000 -> 20kHz", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 2500);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      4800, "f=2500 -> 48kHz", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 4000);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      3000, "f=4000 -> 30kHz", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 6000);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      2000, "f=6000 -> 60kHz", m_pass, m_fail, m_exp, m_got);

        -- clamp: 0 / over / under
        p_set_freq(sig_P15t, 0);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      1500, "f=0 clamp -> 8000", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 9000);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      1500, "f=9000 clamp -> 8000", m_pass, m_fail, m_exp, m_got);

        p_set_freq(sig_P15t, 1500);
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      6000, "f=1500 clamp -> 2000", m_pass, m_fail, m_exp, m_got);

        -- 忙时改命令：先发 4000，忙时立刻改 2500，最终应为 4800
        p_set_freq(sig_P15t, 4000);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        v_t := 0;
        while (w_llc_div_busy = '0') and (v_t < 20) loop
            wait until rising_edge(clk);
            v_t := v_t + 1;
        end loop;
        p_set_freq(sig_P15t, 2500);  -- busy 期间改
        -- 等第一次 done（4000→3000），再等第二次（2500→4800）
        wait until rising_edge(clk) and w_llc_div_done = '1';
        wait until rising_edge(clk);
        v_got := to_integer(unsigned(w_llc_pwm_period_50));
        if v_got /= 3000 then
            report "[WARN] mid busy first result=" & integer'image(v_got) &
                   " (expect 3000 before 2nd div)";
        end if;
        p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                      4800, "busy change 4000->2500", m_pass, m_fail, m_exp, m_got);

        -- 同值再写：不应启动（period 保持）
        v_got := to_integer(unsigned(w_llc_pwm_period_50));
        p_set_freq(sig_P15t, 2500);
        for i in 1 to 40 loop
            wait until rising_edge(clk);
            if w_llc_div_start = '1' then
                m_fail <= m_fail + 1;
                report "[FAIL] same freq re-trigger" severity error;
                exit;
            end if;
            if i = 40 then
                m_pass <= m_pass + 1;
                report "[PASS] same freq no re-start";
            end if;
        end loop;
        wait for 0 ns;

        -- 扫几个与 TB 开关周期 2000～6000 对应的频率点
        for f in 0 to 4 loop
            case f is
                when 0 => v_f := 2000;  -- period 6000
                when 1 => v_f := 2400;  -- 5000
                when 2 => v_f := 3000;  -- 4000
                when 3 => v_f := 4000;  -- 3000
                when others => v_f := 6000; -- 2000
            end case;
            v_exp := f_exp_period(v_f);
            p_set_freq(sig_P15t, v_f);
            p_wait_period(clk, w_llc_pwm_period_50, w_llc_div_busy, w_llc_div_done,
                          v_exp,
                          "sweep f=" & integer'image(v_f),
                          m_pass, m_fail, m_exp, m_got);
        end loop;

        wait for 1 us;
        report "======== RESULT pass=" & integer'image(m_pass) &
               " fail=" & integer'image(m_fail) & " ========";
        if m_fail = 0 then
            report "llc_freq_period_tb PASSED" severity note;
        else
            report "llc_freq_period_tb FAILED" severity failure;
        end if;
        wait;
    end process;

end architecture sim;
