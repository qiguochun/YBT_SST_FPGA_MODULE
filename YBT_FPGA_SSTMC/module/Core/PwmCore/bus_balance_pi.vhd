--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   bus_balance_pi.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   正负母线均压 PI（仅 P+I，无积分重装）。
--                      err = Vpos - Vneg（同码标度）。|err|≤ERR_DEAD 时按 0；
--                      否则钳到 ±ERR_SAT。
--                      u = Kp×err + ∫(Ki×err)，输出为相对开关周期的 Q14 分数，
--                      限幅到 ±PHASE_LIM（默认 ≈4%）。
--
--                      定标（Q14）：2^14 = 16384 表示 1.0 = 100% 周期。
--                      默认 PHASE_LIM=655 → |u|≤655/16384 ≈ 4.00% 周期。
--                      外部换成时钟数（本模块不做）：
--                        i_phase_clk = resize( (o_phase_q × period) >>> 14 , 13)
--                      例：80 kHz、period=1500 → 满偏 (655×1500)>>14 = 60 clk。
--
--                      符号约定（与 llc_pwm_gen.i_phase_clk 同极性，直连不取反）：
--                        桥臂 A = pwm1/2，桥臂 B = pwm4/3；φ=0 时 1=4、2=3。
--                        o_phase_q > 0 → i_phase_clk > 0 → 推臂 A → 1 滞后 4
--                          （约定：正母线偏高时走此方向；若台架极性相反则改 err 符号
--                           或对 i_phase_clk 取反，二者择一，勿重复取反）。
--                        o_phase_q < 0 → i_phase_clk < 0 → 推臂 B → 1 超前 4
--                          （负母线偏高）。
--                        本模块只输出 Q14；边沿由 llc_pwm_gen 按上述约定执行。
--
--                      定点与 llc_period_pi 相同：I/增益为 Q(PI_SHIFT)。
--                      i_enable 为控制周期脉冲；积分仅在未顶满或有退饱和方向时更新。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.22
--Modify Record     :   符号约定对齐 llc_pwm_gen（1 相对 4 超前/滞后）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_balance_pi is
    generic (
        ERR_SAT    : natural  := 2000;   -- 误差限幅（码），约按母线差分满偏的一部分取
        ERR_DEAD   : natural  := 20;     -- 误差死区（码），抑制抖振
        PI_SHIFT   : natural  := 14;     -- I 与增益定点位数（与输出 Q 一致）
        PHASE_LIM  : natural  := 655;    -- |u| 上限，Q14：655/16384 ≈ 4% 周期
        DATA_W     : positive := 16      -- 母线输入位宽
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_enable     : in  std_logic;                         -- 控制周期脉冲
        i_clear      : in  std_logic;                         -- 脉冲：清积分并回零输出
        i_bus_pos    : in  signed(DATA_W - 1 downto 0);       -- 正母线
        i_bus_neg    : in  signed(DATA_W - 1 downto 0);       -- 负母线
        i_kp         : in  signed(31 downto 0);               -- Kp 口（Q14）
        i_ki         : in  signed(31 downto 0);               -- Ki 口（Q14，已含 Ts）
        o_phase_q    : out signed(15 downto 0);               -- Q14；+→1滞后4，-→1超前4（同 llc）
        o_err        : out signed(15 downto 0)                -- 限幅后误差，便于调试
    );
end entity bus_balance_pi;

architecture rtl of bus_balance_pi is

    constant C_ONE   : integer := 2 ** PI_SHIFT;              -- Q14：1.0 = 16384
    constant C_I_LIM : integer := PHASE_LIM * (2 ** PI_SHIFT);

    type t_pipe is (
        IDLE,
        ERR_CALC,
        KP_TERM,
        KI_TERM,
        U_UNSAT,
        I_ALLOW,
        I_UPDATE,
        U_CMD
    );
    signal r_pipe : t_pipe := IDLE;

    signal r_en_d    : std_logic := '0';
    signal w_en_rise : std_logic;

    signal r_bus_pos : signed(DATA_W - 1 downto 0) := (others => '0');
    signal r_bus_neg : signed(DATA_W - 1 downto 0) := (others => '0');
    signal r_kp      : signed(31 downto 0) := (others => '0');
    signal r_ki      : signed(31 downto 0) := (others => '0');

    signal r_err_sat  : signed(15 downto 0) := (others => '0');
    signal r_kp_q     : signed(31 downto 0) := (others => '0');
    signal r_ki_q     : signed(31 downto 0) := (others => '0');
    signal r_integral : signed(31 downto 0) := (others => '0');
    signal r_u_unsat  : signed(31 downto 0) := (others => '0');
    signal r_allow_i  : std_logic := '0';
    signal r_phase    : signed(15 downto 0) := (others => '0');

    function f_clamp_i(v, lo, hi : integer) return integer is
    begin
        if v > hi then
            return hi;
        elsif v < lo then
            return lo;
        else
            return v;
        end if;
    end function;

    function f_sat32(x : signed(63 downto 0)) return signed is
        constant C_MAX : signed(63 downto 0) := to_signed(2147483647, 64);
        constant C_MIN : signed(63 downto 0) := to_signed(-2147483648, 64);
    begin
        if x > C_MAX then
            return to_signed(2147483647, 32);
        elsif x < C_MIN then
            return to_signed(-2147483648, 32);
        else
            return resize(x, 32);
        end if;
    end function;

    function f_sat_add32(a, b : signed(31 downto 0)) return signed is
    begin
        return f_sat32(resize(a, 64) + resize(b, 64));
    end function;

    function f_pi_acc(
        gain : signed(31 downto 0);
        err  : signed(15 downto 0)
    ) return signed is
    begin
        return f_sat32(resize(gain * err, 64));
    end function;

    -- Qn → 整数，对称舍入
    function f_q_to_i(x : signed(31 downto 0)) return signed is
        variable v_x   : signed(47 downto 0);
        variable v_rnd : signed(47 downto 0);
    begin
        if PI_SHIFT = 0 then
            return x;
        end if;
        v_rnd := shift_left(to_signed(1, 48), PI_SHIFT - 1);
        if x(x'high) = '1' then
            v_x := resize(x, 48) - v_rnd;
        else
            v_x := resize(x, 48) + v_rnd;
        end if;
        return f_sat32(resize(shift_right(v_x, PI_SHIFT), 64));
    end function;

begin

    -- 限幅不得超过 1.0（100% 周期）
    assert PHASE_LIM <= C_ONE
        report "bus_balance_pi: PHASE_LIM exceeds 1.0 (2^PI_SHIFT)"
        severity failure;

    o_phase_q <= r_phase;
    o_err       <= r_err_sat;
    w_en_rise   <= i_enable and (not r_en_d);

    p_pi : process (i_sys_clk, i_sys_rst)
        variable v_err     : integer;
        variable v_err_sat : integer;
        variable v_u_unsat : integer;
        variable v_u_cmd   : integer;
        variable v_i       : integer;
    begin
        if i_sys_rst = '1' then
            r_pipe     <= IDLE;
            r_en_d     <= '0';
            r_allow_i  <= '0';
            r_err_sat  <= (others => '0');
            r_kp_q     <= (others => '0');
            r_ki_q     <= (others => '0');
            r_integral <= (others => '0');
            r_u_unsat  <= (others => '0');
            r_phase    <= (others => '0');
            r_kp       <= (others => '0');
            r_ki       <= (others => '0');
            r_bus_pos  <= (others => '0');
            r_bus_neg  <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_en_d <= i_enable;

            if i_clear = '1' then
                r_pipe     <= IDLE;
                r_allow_i  <= '0';
                r_err_sat  <= (others => '0');
                r_kp_q     <= (others => '0');
                r_ki_q     <= (others => '0');
                r_integral <= (others => '0');
                r_u_unsat  <= (others => '0');
                r_phase    <= (others => '0');
            else
                case r_pipe is
                    when IDLE =>
                        if w_en_rise = '1' then
                            r_kp      <= i_kp;
                            r_ki      <= i_ki;
                            r_bus_pos <= i_bus_pos;
                            r_bus_neg <= i_bus_neg;
                            r_pipe    <= ERR_CALC;
                        end if;

                    when ERR_CALC =>
                        v_err := to_integer(r_bus_pos) - to_integer(r_bus_neg);
                        if (v_err >= -ERR_DEAD) and (v_err <= ERR_DEAD) then
                            v_err_sat := 0;
                        elsif v_err > ERR_SAT then
                            v_err_sat := ERR_SAT;
                        elsif v_err < -ERR_SAT then
                            v_err_sat := -ERR_SAT;
                        else
                            v_err_sat := v_err;
                        end if;
                        r_err_sat <= to_signed(v_err_sat, 16);
                        r_pipe    <= KP_TERM;

                    when KP_TERM =>
                        r_kp_q <= f_pi_acc(r_kp, r_err_sat);
                        r_pipe <= KI_TERM;

                    when KI_TERM =>
                        r_ki_q <= f_pi_acc(r_ki, r_err_sat);
                        r_pipe <= U_UNSAT;

                    when U_UNSAT =>
                        -- 未限幅：u = (I + Kp×err) / 2^N
                        r_u_unsat <= f_q_to_i(f_sat_add32(r_integral, r_kp_q));
                        r_pipe    <= I_ALLOW;

                    when I_ALLOW =>
                        v_u_unsat := to_integer(r_u_unsat);
                        -- 开区间照常积；顶到上限仅 err<0 可退；顶到下限仅 err>0 可退
                        if ((v_u_unsat > -PHASE_LIM) and (v_u_unsat < PHASE_LIM)) or
                           ((v_u_unsat >= PHASE_LIM) and (to_integer(r_err_sat) < 0)) or
                           ((v_u_unsat <= -PHASE_LIM) and (to_integer(r_err_sat) > 0)) then
                            r_allow_i <= '1';
                        else
                            r_allow_i <= '0';
                        end if;
                        r_pipe <= I_UPDATE;

                    when I_UPDATE =>
                        if r_allow_i = '1' then
                            v_i := to_integer(f_sat_add32(r_integral, r_ki_q));
                            v_i := f_clamp_i(v_i, -C_I_LIM, C_I_LIM);
                            r_integral <= to_signed(v_i, 32);
                        end if;
                        r_pipe <= U_CMD;

                    when U_CMD =>
                        v_u_cmd := to_integer(f_q_to_i(f_sat_add32(r_integral, r_kp_q)));
                        v_u_cmd := f_clamp_i(v_u_cmd, -PHASE_LIM, PHASE_LIM);
                        r_phase <= to_signed(v_u_cmd, 16);
                        r_pipe  <= IDLE;

                    when others =>
                        r_pipe <= IDLE;
                end case;
            end if;
        end if;
    end process p_pi;

end architecture rtl;
