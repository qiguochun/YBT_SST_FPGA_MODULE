--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   bus_balance_pi.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.22
--Description       :   正负母线均压 PI（仅 P+I，无积分重装）。
--                      输入为 ADC 码；真实电压 = 码 × 0.12793102 V。
--                      err = Vneg - Vpos（下−上，同码标度）。|err|≤ERR_DEAD 时按 0；
--                      否则钳到 ±ERR_SAT。
--                      u = (I + Kp×err) / 2^PI_SHIFT，I 累加 Ki×err（Ki 已含 Ts）。
--                      限幅到 ±PHASE_LIM（默认 ±100）。
--
--                      误差定标（码）：
--                        ERR_SAT  = 117  ≈ 15 V / 0.12793102
--                        ERR_DEAD =  39  ≈  5 V / 0.12793102
--
--                      内置增益（端口 i_kp/i_ki 保留，当前不采样），fs=1 kHz，f_bw=10 Hz：
--                        wi = 2π·f_bw
--                        C(s) = Kp_r · (1 + wi/s)   →  零点放在带宽
--                        Kp_r 使 err=ERR_SAT 时 P 项 = 0.5·PHASE_LIM（半限幅，留余量给 I）
--                          Kp = 0.5·PHASE_LIM·2^14 / ERR_SAT = 7002
--                          Ki = Kp · wi · Ts               = 440
--                        （Kp/Ki 均为 Q14；Ki 已乘 Ts）
--                        Kp_eff = Kp/2^14 ≈ 0.427（每码 → ≈0.43 个输出单位）
--
--                      定标（Q14）：2^14 = 16384 表示 1.0 = 100% 周期。
--                      默认 PHASE_LIM=100 → |u|≤100/16384 ≈ 0.61% 周期。
--                      外部换成时钟数（本模块不做）：
--                        i_phase_clk = resize( (o_phase_q × period) >>> 14 , 13)
--
--                      符号约定（与 llc_pwm_gen.i_phase_clk / 示波器 Φ 同极性）：
--                        o_phase_q > 0 → S1 超前 S4；下母线偏高 → err>0 → +φ。
--                      i_enable 为控制周期脉冲；积分仅在未顶满或有退饱和方向时更新。
--------------------------------------------------------------------------------
--Version           :   Rev 0.10
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   恢复 i_kp/i_ki 口（预留，当前仍用内置 C_KP/C_KI）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bus_balance_pi is
    generic (
        ERR_SAT    : natural  := 117;    -- 误差限幅（码）≈15 V / 0.12793102
        ERR_DEAD   : natural  := 39;     -- 误差死区（码）≈5 V / 0.12793102
        PI_SHIFT   : natural  := 14;     -- I 与增益定点位数（与输出 Q 一致）
        PHASE_LIM  : natural  := 100;    -- |u| 上限，Q14：100/16384 ≈ 0.61% 周期
        DATA_W     : positive := 16;     -- 母线输入位宽（ADC 码）
        -- 内置 PI（Q14）。改带宽：Ki≈Kp·2π·f_bw/fs；Kp≈0.5·PHASE_LIM·2^14/ERR_SAT
        C_KP       : integer  := 7002;   -- Kp：err=117 → P≈50（半限幅）
        C_KI       : integer  := 440     -- Ki：已含 Ts=1ms；零点≈10 Hz
    );
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;

        -- User Interface
        i_enable     : in  std_logic;                         -- 控制周期脉冲（1 kHz）
        i_clear      : in  std_logic;                         -- 脉冲：清积分并回零输出
        i_bus_pos    : in  signed(DATA_W - 1 downto 0);       -- 正母线
        i_bus_neg    : in  signed(DATA_W - 1 downto 0);       -- 负母线
        i_kp         : in  signed(31 downto 0);               -- Kp 口（Q14）；预留，当前不用
        i_ki         : in  signed(31 downto 0);               -- Ki 口（Q14，已含 Ts）；预留，当前不用
        o_phase_q    : out signed(15 downto 0);               -- Q14；+→S1超前S4，-→S1滞后S4（同 llc）
        o_err        : out signed(15 downto 0)                -- 限幅后误差（下−上），便于调试
    );
end entity bus_balance_pi;

architecture rtl of bus_balance_pi is

    constant C_ONE   : integer := 2 ** PI_SHIFT;              -- Q14：1.0 = 16384
    constant C_I_LIM : integer := PHASE_LIM * (2 ** PI_SHIFT);

    constant C_KP_S : signed(31 downto 0) := to_signed(C_KP, 32);
    constant C_KI_S : signed(31 downto 0) := to_signed(C_KI, 32);

    -- 预留口：读入以免综合“未用输入”告警；不参与 PI
    signal r_kp_ext : signed(31 downto 0) := (others => '0');
    signal r_ki_ext : signed(31 downto 0) := (others => '0');
    attribute keep : boolean;
    attribute keep of r_kp_ext : signal is true;
    attribute keep of r_ki_ext : signal is true;

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
            r_bus_pos  <= (others => '0');
            r_bus_neg  <= (others => '0');
            r_kp_ext   <= (others => '0');
            r_ki_ext   <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_en_d <= i_enable;
            -- 外部增益口仅寄存，PI 仍用 C_KP_S / C_KI_S
            r_kp_ext <= i_kp;
            r_ki_ext <= i_ki;

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
                            r_bus_pos <= i_bus_pos;
                            r_bus_neg <= i_bus_neg;
                            r_pipe    <= ERR_CALC;
                        end if;

                    when ERR_CALC =>
                        v_err := to_integer(r_bus_neg) - to_integer(r_bus_pos);
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
                        r_kp_q <= f_pi_acc(C_KP_S, r_err_sat);
                        r_pipe <= KI_TERM;

                    when KI_TERM =>
                        r_ki_q <= f_pi_acc(C_KI_S, r_err_sat);
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
