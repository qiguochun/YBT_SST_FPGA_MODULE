--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_pwm_gen.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   LLC 全桥 PWM：占空比反推死区；臂 A(1/2)、臂 B(4/3)
--                      互补；i_phase_clk 有符号移相（+：1 滞后 4；-：1 超前 4）。
--                      φ=0 时 1=4、2=3。重装 5 拍（提前在 period-6 启动，
--                      与周期回绕对齐提交，避免绕回窗在周期头留下窄脉冲）。
--                      SR 嵌在载波正/负窗。
--------------------------------------------------------------------------------
--Version           :   Rev 0.6
--modifier          :   Qigc
--Modify Date       :   2026.09.22
--Modify Record     :   重装提前对齐周期边界，消除绕回切换窄脉冲
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity llc_pwm_gen is
    generic (
        CLK_FREQ : positive := 120_000_000
    );
    port (
        i_sys_clk    : in  std_logic;
        i_sys_rst    : in  std_logic;
        i_pwm_en     : in  std_logic;
        i_pwm_period : in  std_logic_vector(12 downto 0); -- clk，80k=1500，20k=6000
        i_pwm_duty   : in  std_logic_vector(9 downto 0);  -- 0～1023 → 0～50%
        i_phase_clk  : in  signed(12 downto 0);           -- +：1 滞后 4；-：1 超前 4
        i_sr_en      : in  std_logic;
        o_pwm1       : out std_logic;  -- 臂 A 上
        o_pwm2       : out std_logic;  -- 臂 A 下
        o_pwm3       : out std_logic;  -- 臂 B 上（与 4 互补）
        o_pwm4       : out std_logic;  -- 臂 B 下
        o_pwm5       : out std_logic;  -- SR
        o_pwm6       : out std_logic;
        o_pwm7       : out std_logic;
        o_pwm8       : out std_logic
    );
end entity llc_pwm_gen;

architecture rtl of llc_pwm_gen is

    constant PERIOD_WIDTH : positive := 13;     
    constant DUTY_WIDTH   : positive := 10;
    constant DUTY_SHIFT   : positive := 11;

    constant MIN_PULSE    : positive := 21;          --最短脉冲175ns
    constant DUTY_OFF_TH  : positive := 41;          --最小占空比
    -- 重装置 busy 后 5 拍算完；cnt=period-6 启动 → period-1 提交，与回绕对齐
    constant RELOAD_START_LEAD : positive := 6;

    constant PERIOD_MIN        : positive := CLK_FREQ / 80_000;
    constant PERIOD_MAX        : positive := CLK_FREQ / 20_000;
    constant PERIOD_HALF_MIN   : positive := PERIOD_MIN / 2;          --周期一半最小值
    constant PERIOD_TRAIL_HIGH : positive := CLK_FREQ / 33_500;       --SR切换阈值

    constant DEADTIME_PRIMARY  : positive := CLK_FREQ / 5_000_000;  -- 200 ns  峭壁死区

    constant SR_LEAD           : positive := CLK_FREQ / 2_000_000;  -- 0.5 us
    constant SR_TRAIL_SHORT    : positive := CLK_FREQ / 2_000_000;
    constant SR_TRAIL_LONG     : positive := CLK_FREQ / 100_000;     -- 10 us

    subtype T_CNT is unsigned(PERIOD_WIDTH - 1 downto 0);

    constant U_PERIOD_MIN        : T_CNT := to_unsigned(PERIOD_MIN, PERIOD_WIDTH);
    constant U_PERIOD_MAX        : T_CNT := to_unsigned(PERIOD_MAX, PERIOD_WIDTH);
    constant U_PERIOD_HALF_MIN   : T_CNT := to_unsigned(PERIOD_HALF_MIN, PERIOD_WIDTH);
    constant U_PERIOD_TRAIL_HIGH : T_CNT := to_unsigned(PERIOD_TRAIL_HIGH, PERIOD_WIDTH);
    constant U_DEADTIME          : T_CNT := to_unsigned(DEADTIME_PRIMARY, PERIOD_WIDTH);

    constant U_SR_LEAD           : T_CNT := to_unsigned(SR_LEAD, PERIOD_WIDTH);
    constant U_MIN_PULSE         : T_CNT := to_unsigned(MIN_PULSE, PERIOD_WIDTH);
    constant U_SR_TRAIL_SHORT    : T_CNT := to_unsigned(SR_TRAIL_SHORT, PERIOD_WIDTH);
    constant U_SR_TRAIL_LONG     : T_CNT := to_unsigned(SR_TRAIL_LONG, PERIOD_WIDTH);
    constant U_INIT_DEAD         : T_CNT := to_unsigned(PERIOD_HALF_MIN - MIN_PULSE, PERIOD_WIDTH);

    type t_edge is record
        on_t  : T_CNT;
        off_t : T_CNT;
    end record;
    type t_edge4 is array (1 to 4) of t_edge;

    signal r_cycle_cnt  : T_CNT := (others => '0');
    signal r_pwm_period : T_CNT := U_PERIOD_MIN;
    signal r_pwm_run_d  : std_logic := '0';
    signal r_sr_en_d0   : std_logic := '0';
    signal r_sr_en_d1   : std_logic := '0';

    signal r_pri     : t_edge4 := (
        1 => (U_INIT_DEAD, U_PERIOD_HALF_MIN),
        2 => (U_PERIOD_HALF_MIN + U_DEADTIME, U_PERIOD_MIN),
        3 => (U_PERIOD_HALF_MIN + U_DEADTIME, U_PERIOD_MIN),
        4 => (U_INIT_DEAD, U_PERIOD_HALF_MIN)
    );
    signal r_sr_pos  : t_edge := (others => (others => '0'));
    signal r_sr_neg  : t_edge := (others => (others => '0'));

    signal r_pwm : std_logic_vector(1 to 8) := (others => '0');

    signal r_reload_busy  : std_logic := '0';                                  --重装载
    signal r_reload_stage : unsigned(2 downto 0) := (others => '0');           --重装载阶段

    signal r_pipe_period  : T_CNT := U_PERIOD_MIN;                             --限幅后的周期
    signal r_pipe_half    : T_CNT := U_PERIOD_HALF_MIN;                         --周期一半

    signal r_pipe_prod    : unsigned(DUTY_WIDTH + PERIOD_WIDTH - 1 downto 0) := (others => '0'); --duty*period
    signal r_pipe_on_w    : T_CNT := U_MIN_PULSE;                                --半周内导通宽度
    signal r_pipe_dead    : T_CNT := U_INIT_DEAD;                                --死区

    signal r_pipe_trail   : T_CNT := U_SR_TRAIL_SHORT;                          --SR提前关断量
    signal r_pipe_duty    : std_logic_vector(DUTY_WIDTH - 1 downto 0) := (others => '0');   --锁存的占空比
    signal r_pipe_phase   : signed(12 downto 0) := (others => '0');                         --锁存的输入脉冲

    signal w_pwm_run      : std_logic;
    signal w_period_end   : std_logic;
    signal w_reload_arm   : std_logic;
    signal w_reload       : std_logic;

    function f_clamp(v, lo, hi : T_CNT) return T_CNT is
    begin
        if v < lo then
            return lo;
        elsif v > hi then
            return hi;
        else
            return v;
        end if;
    end function;

    function f_add_mod(a : T_CNT; b : natural; period : T_CNT) return T_CNT is
        variable v : unsigned(PERIOD_WIDTH downto 0);
    begin
        v := resize(a, PERIOD_WIDTH + 1) + to_unsigned(b, PERIOD_WIDTH + 1);
        if v >= resize(period, PERIOD_WIDTH + 1) then
            v := v - resize(period, PERIOD_WIDTH + 1);
        end if;
        return resize(v, PERIOD_WIDTH);
    end function;

    function f_in_win(cnt : T_CNT; e : t_edge) return std_logic is
    begin
        if e.on_t = e.off_t then
            return '0';
        elsif e.on_t < e.off_t then
            if (cnt >= e.on_t) and (cnt < e.off_t) then
                return '1';
            else
                return '0';
            end if;
        else
            if (cnt >= e.on_t) or (cnt < e.off_t) then
                return '1';
            else
                return '0';
            end if;
        end if;
    end function;

    -- 开窗 [on, off)，off 钳到 lim 且不少于 on+MIN_PULSE
    function f_sr_edge(on_t, off_raw, lim : T_CNT) return t_edge is
        variable v_off : T_CNT;
    begin
        v_off := off_raw;
        if v_off <= (on_t + U_MIN_PULSE) then
            v_off := on_t + U_MIN_PULSE;
        end if;
        if v_off > lim then
            v_off := lim;
        end if;
        return (on_t, v_off);
    end function;

begin

    o_pwm1 <= r_pwm(1);
    o_pwm2 <= r_pwm(2);
    o_pwm3 <= r_pwm(3);
    o_pwm4 <= r_pwm(4);
    o_pwm5 <= r_pwm(5);
    o_pwm6 <= r_pwm(6);
    o_pwm7 <= r_pwm(7);
    o_pwm8 <= r_pwm(8);

    w_pwm_run <= '1' when (i_pwm_en = '1') and (unsigned(i_pwm_duty) >= DUTY_OFF_TH) else '0';
    w_period_end <= '1' when r_cycle_cnt = (r_pwm_period - 1) else '0';
    -- 提前 RELOAD_START_LEAD 拍启动，使第 5 拍提交落在 period-1（与回绕同沿）
    w_reload_arm <= '1' when r_cycle_cnt = (r_pwm_period - RELOAD_START_LEAD) else '0';
    w_reload <= '1' when (w_pwm_run = '1') and ((w_reload_arm = '1') or (r_pwm_run_d = '0')) else '0';

    -- 载波 + SR 同步
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_cycle_cnt <= (others => '0');
            r_pwm_run_d <= '0';
            r_sr_en_d0  <= '0';
            r_sr_en_d1  <= '0';
        elsif rising_edge(i_sys_clk) then
            r_pwm_run_d <= w_pwm_run;
            r_sr_en_d0  <= i_sr_en;
            r_sr_en_d1  <= r_sr_en_d0;

            if (w_pwm_run = '0') or (w_period_end = '1') then
                r_cycle_cnt <= (others => '0');
            else
                r_cycle_cnt <= r_cycle_cnt + 1;
            end if;
        end if;
    end process;

    -- 周期重装 5 拍：限幅 → 乘 → 脉宽/trail → 死区 → 边沿+SR
    -- 稳态在 period-6 启动，period-1 写入 r_pri/r_sr，回绕后无旧绕回残段
    process (i_sys_clk, i_sys_rst)
        variable v_period  : T_CNT;
        variable v_on_max  : T_CNT;
        variable v_on_w    : T_CNT;
        variable v_dead    : T_CNT;
        variable v_b1, v_b2 : t_edge;
        variable v_sh_a    : natural;
        variable v_sh_b    : natural;
        variable v_phi     : integer;
    begin
        if i_sys_rst = '1' then
            r_reload_busy  <= '0';
            r_reload_stage <= (others => '0');
            r_pipe_period  <= U_PERIOD_MIN;
            r_pipe_half    <= U_PERIOD_HALF_MIN;
            r_pipe_prod    <= (others => '0');
            r_pipe_on_w    <= U_MIN_PULSE;
            r_pipe_dead    <= U_INIT_DEAD;
            r_pipe_trail   <= U_SR_TRAIL_SHORT;
            r_pipe_duty    <= (others => '0');
            r_pipe_phase   <= (others => '0');
            r_pwm_period   <= U_PERIOD_MIN;
            r_pri          <= (
                1 => (U_INIT_DEAD, U_PERIOD_HALF_MIN),
                2 => (U_PERIOD_HALF_MIN + U_DEADTIME, U_PERIOD_MIN),
                3 => (U_PERIOD_HALF_MIN + U_DEADTIME, U_PERIOD_MIN),
                4 => (U_INIT_DEAD, U_PERIOD_HALF_MIN)
            );
            r_sr_pos       <= (others => (others => '0'));
            r_sr_neg       <= (others => (others => '0'));
        elsif rising_edge(i_sys_clk) then
            if r_reload_busy = '1' then
                case r_reload_stage is
                    when "000" =>
                        v_period := f_clamp(unsigned(i_pwm_period), U_PERIOD_MIN, U_PERIOD_MAX);
                        r_pipe_period  <= v_period;
                        r_pipe_half    <= shift_right(v_period, 1);
                        r_pipe_duty    <= i_pwm_duty;
                        r_pipe_phase   <= i_phase_clk;
                        r_reload_stage <= "001";

                    when "001" =>
                        r_pipe_prod    <= unsigned(r_pipe_duty) * r_pipe_period;
                        r_reload_stage <= "010";

                    when "010" =>
                        v_on_max := r_pipe_half - U_DEADTIME;
                        if v_on_max < U_MIN_PULSE then          --开通最小值限制
                            v_on_max := U_MIN_PULSE;           
                        end if;
                        v_on_w := f_clamp(
                            resize(shift_right(r_pipe_prod, DUTY_SHIFT), PERIOD_WIDTH),
                            U_MIN_PULSE, v_on_max);
                        r_pipe_on_w <= v_on_w;                  --限制为最小开通周期以及最大开通周期
                        if r_pipe_period <= U_PERIOD_TRAIL_HIGH then
                            r_pipe_trail <= U_SR_TRAIL_SHORT;
                        else
                            r_pipe_trail <= U_SR_TRAIL_LONG;     --根据开关频率选择提前关断时间
                        end if;
                        r_reload_stage <= "011";

                    when "011" =>
                        v_dead := r_pipe_half - r_pipe_on_w;     --死区计算
                        if v_dead < U_DEADTIME then
                            v_dead := U_DEADTIME;                --死区最小值限制
                        end if;
                        r_pipe_dead    <= v_dead;
                        r_reload_stage <= "100";

                    when others =>
                        -- 基准窗；臂 A 移 sh_a，臂 B 移 sh_b（其一为 0）
                        v_b1 := (r_pipe_dead, r_pipe_half);
                        v_b2 := (r_pipe_half + r_pipe_dead, r_pipe_period);
                        v_phi := to_integer(r_pipe_phase);
                        if v_phi >= 0 then
                            v_sh_a := v_phi;
                            v_sh_b := 0;
                        else
                            v_sh_a := 0;
                            v_sh_b := -v_phi;
                        end if;

                        r_pri(1) <= (
                            f_add_mod(v_b1.on_t,  v_sh_a, r_pipe_period),
                            f_add_mod(v_b1.off_t, v_sh_a, r_pipe_period));
                        r_pri(2) <= (
                            f_add_mod(v_b2.on_t,  v_sh_a, r_pipe_period),
                            f_add_mod(v_b2.off_t, v_sh_a, r_pipe_period));
                        r_pri(4) <= (
                            f_add_mod(v_b1.on_t,  v_sh_b, r_pipe_period),
                            f_add_mod(v_b1.off_t, v_sh_b, r_pipe_period));
                        r_pri(3) <= (
                            f_add_mod(v_b2.on_t,  v_sh_b, r_pipe_period),
                            f_add_mod(v_b2.off_t, v_sh_b, r_pipe_period));

                        r_sr_pos <= f_sr_edge(
                            r_pipe_dead + U_SR_LEAD,
                            r_pipe_half - r_pipe_trail,
                            r_pipe_half);
                        r_sr_neg <= f_sr_edge(
                            r_pipe_half + r_pipe_dead + U_SR_LEAD,
                            r_pipe_period - r_pipe_trail,
                            r_pipe_period);

                        r_pwm_period   <= r_pipe_period;
                        r_reload_busy  <= '0';
                        r_reload_stage <= "000";
                end case;
            elsif w_reload = '1' then
                r_reload_busy  <= '1';
                r_reload_stage <= "000";
            end if;
        end if;
    end process;

    -- 门极（Moore）
    process (i_sys_clk, i_sys_rst)
    begin
        if i_sys_rst = '1' then
            r_pwm <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_pwm_run = '0' then
                r_pwm <= (others => '0');
            else
                r_pwm(1) <= f_in_win(r_cycle_cnt, r_pri(1));
                r_pwm(2) <= f_in_win(r_cycle_cnt, r_pri(2));
                r_pwm(3) <= f_in_win(r_cycle_cnt, r_pri(3));
                r_pwm(4) <= f_in_win(r_cycle_cnt, r_pri(4));

                if (r_sr_en_d1 = '1') and (r_sr_pos.off_t > r_sr_pos.on_t) and
                   (r_cycle_cnt >= r_sr_pos.on_t) and (r_cycle_cnt < r_sr_pos.off_t) then
                    r_pwm(5) <= '1';
                    r_pwm(8) <= '1';
                else
                    r_pwm(5) <= '0';
                    r_pwm(8) <= '0';
                end if;

                if (r_sr_en_d1 = '1') and (r_sr_neg.off_t > r_sr_neg.on_t) and
                   (r_cycle_cnt >= r_sr_neg.on_t) and (r_cycle_cnt < r_sr_neg.off_t) then
                    r_pwm(6) <= '1';
                    r_pwm(7) <= '1';
                else
                    r_pwm(6) <= '0';
                    r_pwm(7) <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
