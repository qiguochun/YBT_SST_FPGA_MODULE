--------------------------------------------------------------------------------
-- llc_pwm_wrap_glitch_tb.vhd
-- 检查移相绕回后改回 φ=0 时，周期头是否出现 < MIN_PULSE 的窄脉冲。
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_pwm_wrap_glitch_tb is
end entity;

architecture sim of llc_pwm_wrap_glitch_tb is
    constant CLK_FREQ    : positive := 120_000_000;
    constant CLK_PERIOD  : time     := 1 sec / CLK_FREQ;
    constant C_PERIOD    : positive := CLK_FREQ / 50_000;  -- 2400
    constant C_DUTY      : natural  := 1023;
    constant C_MIN_PULSE : positive := 21;
    constant C_PHASE     : integer  := 50;

    signal i_sys_clk    : std_logic := '0';
    signal i_sys_rst    : std_logic := '1';
    signal i_pwm_en     : std_logic := '0';
    signal i_pwm_period : std_logic_vector(12 downto 0) := (others => '0');
    signal i_pwm_duty   : std_logic_vector(9 downto 0)  := (others => '0');
    signal i_phase_clk  : signed(12 downto 0) := (others => '0');
    signal i_sr_en      : std_logic := '0';
    signal o_pwm1, o_pwm2, o_pwm3, o_pwm4 : std_logic;
    signal o_pwm5, o_pwm6, o_pwm7, o_pwm8 : std_logic;

    signal mon_en      : std_logic := '0';
    signal glitch_pwm2 : natural := 0;
    signal glitch_pwm3 : natural := 0;
begin
    i_sys_clk <= not i_sys_clk after CLK_PERIOD / 2;

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

    -- 改 φ 后周期头不得出现 < MIN_PULSE 的窄脉冲（CTR=0 装载 / AHC）
    p_mon_pwm2 : process
        variable v_prev : std_logic := '0';
        variable v_w    : natural;
    begin
        wait until rising_edge(i_sys_clk);
        loop
            wait until rising_edge(i_sys_clk);
            if mon_en = '1' then
                if v_prev = '0' and o_pwm2 = '1' then
                    v_w := 1;
                    loop
                        wait until rising_edge(i_sys_clk);
                        if o_pwm2 = '0' then
                            exit;
                        end if;
                        v_w := v_w + 1;
                    end loop;
                    if v_w < C_MIN_PULSE then
                        glitch_pwm2 <= glitch_pwm2 + 1;
                        wait for 0 ns;
                        report "GLITCH o_pwm2 width=" & integer'image(v_w)
                            severity error;
                    end if;
                    v_prev := '0';
                else
                    v_prev := o_pwm2;
                end if;
            else
                v_prev := o_pwm2;
            end if;
        end loop;
    end process;

    p_mon_pwm3 : process
        variable v_prev : std_logic := '0';
        variable v_w    : natural;
    begin
        wait until rising_edge(i_sys_clk);
        loop
            wait until rising_edge(i_sys_clk);
            if mon_en = '1' then
                if v_prev = '0' and o_pwm3 = '1' then
                    v_w := 1;
                    loop
                        wait until rising_edge(i_sys_clk);
                        if o_pwm3 = '0' then
                            exit;
                        end if;
                        v_w := v_w + 1;
                    end loop;
                    if v_w < C_MIN_PULSE then
                        glitch_pwm3 <= glitch_pwm3 + 1;
                        wait for 0 ns;
                        report "GLITCH o_pwm3 width=" & integer'image(v_w)
                            severity error;
                    end if;
                    v_prev := '0';
                else
                    v_prev := o_pwm3;
                end if;
            else
                v_prev := o_pwm3;
            end if;
        end loop;
    end process;

    stimulus : process
        variable v_total : natural;
    begin
        i_sys_rst    <= '1';
        i_pwm_en     <= '0';
        i_sr_en      <= '0';
        mon_en       <= '0';
        i_phase_clk  <= (others => '0');
        i_pwm_period <= std_logic_vector(to_unsigned(C_PERIOD, 13));
        i_pwm_duty   <= std_logic_vector(to_unsigned(C_DUTY, 10));
        wait for 500 ns;
        i_sys_rst <= '0';
        wait until rising_edge(i_sys_clk);

        -- 1) φ=+50 建立绕回窗
        i_phase_clk <= to_signed(C_PHASE, 13);
        i_pwm_en    <= '1';
        i_sr_en     <= '1';
        wait for 8 * C_PERIOD * CLK_PERIOD;

        -- 2) 改 φ=0，打开监视
        mon_en      <= '1';
        i_phase_clk <= (others => '0');
        wait for 12 * C_PERIOD * CLK_PERIOD;

        -- 3) φ=-50 再回 0
        mon_en      <= '0';
        i_phase_clk <= to_signed(-C_PHASE, 13);
        wait for 8 * C_PERIOD * CLK_PERIOD;
        mon_en      <= '1';
        i_phase_clk <= (others => '0');
        wait for 12 * C_PERIOD * CLK_PERIOD;
        mon_en      <= '0';

        wait for 1 us;
        v_total := glitch_pwm2 + glitch_pwm3;
        if v_total = 0 then
            report "WRAP GLITCH TB PASSED" severity note;
        else
            report "WRAP GLITCH TB FAILED cnt=" & integer'image(v_total)
                severity failure;
        end if;
        wait;
    end process;
end architecture;
