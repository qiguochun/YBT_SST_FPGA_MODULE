--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   llc_pwm_gen.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.01
--Description       :   SHB LLC 三电平：双载波（两路同频同斜率锯齿）。
--                      上桥 S1/S2 = 主载波 pwm1/2；下桥 S3/S4 = 从载波 pwm3/4。
--                      φ=0：S1≡S4、S2≡S3（模态 a/b：满 Vin / 续流，不是两电平对角）。
--                      小 φ：从桥整组平移，插入 S1+S3 / S2+S4 半压窗做均压。
--                      Shadow 两拍常算；仅主 CTR=0 装 Active，并从 CTR←TBPHS。
--                      AQ 半周比较 → 组内 AHC 死区 → 整组移相。
--                      占空比只改 RED=FED（缓启）；+φ：S1 超前 S4；−φ：S1 滞后 S4。
--                      正负阶跃插一拍 φ=0。SR 挂主载波。
--------------------------------------------------------------------------------
--Version           :   Rev 1.0
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   双载波收束：两级 Shadow + CTR=0 装载；去掉 4 拍重装/blank
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
        i_pwm_period : in  std_logic_vector(12 downto 0); -- Ts clk，80k=1500，20k=6000
        i_pwm_duty   : in  std_logic_vector(9 downto 0);  -- 0～1023 → 0～50%
        i_phase_clk  : in  signed(12 downto 0);           -- +：1 超前 4；-：1 滞后 4
        i_sr_en      : in  std_logic;
        o_pwm1       : out std_logic;  -- FL1S1 上桥 S1
        o_pwm2       : out std_logic;  -- FL1S2 上桥 S2
        o_pwm3       : out std_logic;  -- FL2S1 下桥 S3（φ=0 时 = S2）
        o_pwm4       : out std_logic;  -- FL2S2 下桥 S4（φ=0 时 = S1）
        o_pwm5       : out std_logic;
        o_pwm6       : out std_logic;
        o_pwm7       : out std_logic;
        o_pwm8       : out std_logic
    );
end entity llc_pwm_gen;

architecture rtl of llc_pwm_gen is

    -- period 13b：6000 < 8191；duty 10b；prod 23b：1023×6000=6138000 < 2^23
    -- φ 口 signed 13b（±4095）；TBPHS/死区同 13b。20 kHz 满偏 4%≈240 clk，口宽够。
    constant PERIOD_WIDTH : positive := 13;
    constant DUTY_WIDTH   : positive := 10;
    constant DUTY_SHIFT   : positive := 11;
    constant PROD_WIDTH   : positive := DUTY_WIDTH + PERIOD_WIDTH;  -- 23

    constant MIN_PULSE   : positive := 21;
    constant DUTY_OFF_TH : positive := 41;

    constant PERIOD_MIN        : positive := CLK_FREQ / 80_000;
    constant PERIOD_MAX        : positive := CLK_FREQ / 20_000;
    constant PERIOD_HALF_MIN   : positive := PERIOD_MIN / 2;
    constant PERIOD_TRAIL_HIGH : positive := CLK_FREQ / 33_500;

    constant DEADTIME_PRIMARY : positive := CLK_FREQ / 5_000_000;  -- 200 ns
    constant SR_LEAD          : positive := CLK_FREQ / 2_000_000;
    constant SR_TRAIL_SHORT   : positive := CLK_FREQ / 2_000_000;
    constant SR_TRAIL_LONG    : positive := CLK_FREQ / 100_000;

    subtype T_CNT  is unsigned(PERIOD_WIDTH - 1 downto 0);
    subtype T_PROD is unsigned(PROD_WIDTH - 1 downto 0);
    subtype T_PHI  is signed(PERIOD_WIDTH - 1 downto 0);

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

    type t_ahc is record
        prev    : std_logic;
        a       : std_logic;
        b       : std_logic;
        fed_lvl : std_logic;
        red_p   : std_logic;
        fed_p   : std_logic;
        red_cnt : T_CNT;
        fed_cnt : T_CNT;
    end record;

    constant C_AHC_OFF : t_ahc := (
        prev    => '0', a => '0', b => '0', fed_lvl => '1',
        red_p   => '0', fed_p => '0',
        red_cnt => (others => '0'), fed_cnt => (others => '0')
    );

    -- 双载波
    signal r_cnt_m : T_CNT := (others => '0');
    signal r_cnt_s : T_CNT := (others => '0');

    -- Active（仅主 CTR=0 更新）
    signal r_period : T_CNT := U_PERIOD_MIN;
    signal r_half   : T_CNT := U_PERIOD_HALF_MIN;
    signal r_dead   : T_CNT := U_INIT_DEAD;
    signal r_phase  : T_PHI := (others => '0');
    signal r_sr_pos : t_edge := (others => (others => '0'));
    signal r_sr_neg : t_edge := (others => (others => '0'));

    -- Shadow 两拍：0 锁存/乘，1 死区+TBPHS
    signal r_p_period : T_CNT := U_PERIOD_MIN;
    signal r_p_phase  : T_PHI := (others => '0');
    signal r_p_prod   : T_PROD := (others => '0');
    signal r_sh_period : T_CNT := U_PERIOD_MIN;
    signal r_sh_dead   : T_CNT := U_INIT_DEAD;
    signal r_sh_phase  : T_PHI := (others => '0');
    signal r_sh_tbphs  : T_CNT := (others => '0');
    signal r_sh_sr_pos : t_edge := (others => (others => '0'));
    signal r_sh_sr_neg : t_edge := (others => (others => '0'));

    signal r_pwm   : std_logic_vector(1 to 8) := (others => '0');
    signal r_ahc_m : t_ahc := C_AHC_OFF;
    signal r_ahc_s : t_ahc := C_AHC_OFF;
    signal r_sr_d0 : std_logic := '0';
    signal r_sr_d1 : std_logic := '0';

    signal w_run : std_logic;

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

    -- 饱和到 ±(period-1) 且不超出 signed 13b
    function f_sat_phi(phi : T_PHI; period : T_CNT) return T_PHI is
        variable v : integer;
        variable lim : integer;
    begin
        v   := to_integer(phi);
        lim := to_integer(period) - 1;
        if lim < 1 then
            lim := 1;
        end if;
        if v > lim then
            v := lim;
        elsif v < -lim then
            v := -lim;
        end if;
        return to_signed(v, PERIOD_WIDTH);
    end function;

    -- +φ：TBPHS=period−φ（从滞后，1 超前 4）；−φ：TBPHS=|φ|
    function f_tbphs(phi : T_PHI; period : T_CNT) return T_CNT is
        variable a : integer;
        variable p : integer;
    begin
        a := to_integer(phi);
        p := to_integer(period);
        if a > 0 then
            return to_unsigned(p - a, PERIOD_WIDTH);
        elsif a < 0 then
            return to_unsigned(-a, PERIOD_WIDTH);
        else
            return (others => '0');
        end if;
    end function;

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

    function f_ahc_step(st : t_ahc; aq : std_logic; dead : T_CNT) return t_ahc is
        variable v : t_ahc;
    begin
        v := st;
        if (aq = '1') and (v.prev = '0') then
            v.red_p   := '1';
            v.red_cnt := dead;
        end if;
        if aq = '0' then
            v.a       := '0';
            v.red_p   := '0';
            v.red_cnt := (others => '0');
        end if;
        if v.red_p = '1' then
            if v.red_cnt > 0 then
                v.red_cnt := v.red_cnt - 1;
            else
                v.a     := '1';
                v.red_p := '0';
            end if;
        end if;
        if (aq = '0') and (v.prev = '1') then
            v.fed_p   := '1';
            v.fed_cnt := dead;
        end if;
        if aq = '1' then
            v.fed_lvl := '1';
            v.fed_p   := '0';
            v.fed_cnt := (others => '0');
        end if;
        if v.fed_p = '1' then
            if v.fed_cnt > 0 then
                v.fed_cnt := v.fed_cnt - 1;
            else
                v.fed_lvl := '0';
                v.fed_p   := '0';
            end if;
        end if;
        v.b    := not v.fed_lvl;
        v.prev := aq;
        return v;
    end function;

    function f_aq(cnt, half : T_CNT) return std_logic is
    begin
        if cnt < half then
            return '1';
        else
            return '0';
        end if;
    end function;

    function f_sign_cross(a, b : T_PHI) return boolean is
        constant C_ZERO : T_PHI := (others => '0');
    begin
        return (a(a'high) /= b(b'high)) and (a /= C_ZERO) and (b /= C_ZERO);
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

    w_run <= '1' when (i_pwm_en = '1') and (unsigned(i_pwm_duty) >= DUTY_OFF_TH) else '0';

    -- Shadow 常算（停波也算，使能后 CTR=0 即有合法影子）
    process (i_sys_clk, i_sys_rst)
        variable v_period : T_CNT;
        variable v_half   : T_CNT;
        variable v_on_max : T_CNT;
        variable v_on_w   : T_CNT;
        variable v_dead   : T_CNT;
        variable v_phi    : T_PHI;
        variable v_trail  : T_CNT;
    begin
        if i_sys_rst = '1' then
            r_p_period   <= U_PERIOD_MIN;
            r_p_phase    <= (others => '0');
            r_p_prod     <= (others => '0');
            r_sh_period  <= U_PERIOD_MIN;
            r_sh_dead    <= U_INIT_DEAD;
            r_sh_phase   <= (others => '0');
            r_sh_tbphs   <= (others => '0');
            r_sh_sr_pos  <= (others => (others => '0'));
            r_sh_sr_neg  <= (others => (others => '0'));
            r_sr_d0      <= '0';
            r_sr_d1      <= '0';
        elsif rising_edge(i_sys_clk) then
            r_sr_d0 <= i_sr_en;
            r_sr_d1 <= r_sr_d0;

            -- 拍 1：用拍 0 的乘积/周期写 Shadow
            v_half := shift_right(r_p_period, 1);
            v_on_max := v_half - U_DEADTIME;
            if v_on_max < U_MIN_PULSE then
                v_on_max := U_MIN_PULSE;
            end if;
            v_on_w := f_clamp(
                resize(shift_right(r_p_prod, DUTY_SHIFT), PERIOD_WIDTH),
                U_MIN_PULSE, v_on_max);
            v_dead := v_half - v_on_w;
            if v_dead < U_DEADTIME then
                v_dead := U_DEADTIME;
            end if;
            v_phi := f_sat_phi(r_p_phase, r_p_period);
            if r_p_period <= U_PERIOD_TRAIL_HIGH then
                v_trail := U_SR_TRAIL_SHORT;
            else
                v_trail := U_SR_TRAIL_LONG;
            end if;
            r_sh_period <= r_p_period;
            r_sh_dead   <= v_dead;
            r_sh_phase  <= v_phi;
            r_sh_tbphs  <= f_tbphs(v_phi, r_p_period);
            r_sh_sr_pos <= f_sr_edge(v_dead + U_SR_LEAD, v_half - v_trail, v_half);
            r_sh_sr_neg <= f_sr_edge(
                v_half + v_dead + U_SR_LEAD,
                r_p_period - v_trail,
                r_p_period);

            -- 拍 0：锁存命令、乘法进 DSP
            v_period := f_clamp(unsigned(i_pwm_period), U_PERIOD_MIN, U_PERIOD_MAX);
            r_p_period <= v_period;
            r_p_phase  <= i_phase_clk;
            r_p_prod   <= unsigned(i_pwm_duty) * v_period;
        end if;
    end process;

    -- 双锯齿 + 主 CTR=0 装载 + AHC。顺序与示波器一致：装载 → 比较/死区 → 计数+1
    process (i_sys_clk, i_sys_rst)
        variable v_period : T_CNT;
        variable v_half   : T_CNT;
        variable v_dead   : T_CNT;
        variable v_cnt_s  : T_CNT;
        variable v_phi    : T_PHI;
        variable v_tbphs  : T_CNT;
        variable v_sr_pos : t_edge;
        variable v_sr_neg : t_edge;
        variable v_ahc_m  : t_ahc;
        variable v_ahc_s  : t_ahc;
    begin
        if i_sys_rst = '1' then
            r_pwm     <= (others => '0');
            r_cnt_m   <= (others => '0');
            r_cnt_s   <= (others => '0');
            r_period  <= U_PERIOD_MIN;
            r_half    <= U_PERIOD_HALF_MIN;
            r_dead    <= U_INIT_DEAD;
            r_phase   <= (others => '0');
            r_sr_pos  <= (others => (others => '0'));
            r_sr_neg  <= (others => (others => '0'));
            r_ahc_m   <= C_AHC_OFF;
            r_ahc_s   <= C_AHC_OFF;
        elsif rising_edge(i_sys_clk) then
            if w_run = '0' then
                r_pwm    <= (others => '0');
                r_cnt_m  <= (others => '0');
                r_cnt_s  <= (others => '0');
                r_ahc_m  <= C_AHC_OFF;
                r_ahc_s  <= C_AHC_OFF;
                r_phase  <= (others => '0');
            else
                v_period := r_period;
                v_half   := r_half;
                v_dead   := r_dead;
                v_cnt_s  := r_cnt_s;
                v_sr_pos := r_sr_pos;
                v_sr_neg := r_sr_neg;

                if r_cnt_m = 0 then
                    if f_sign_cross(r_phase, r_sh_phase) then
                        v_phi   := (others => '0');
                        v_tbphs := (others => '0');
                    else
                        v_phi   := r_sh_phase;
                        v_tbphs := r_sh_tbphs;
                    end if;
                    v_period := r_sh_period;
                    v_half   := shift_right(r_sh_period, 1);
                    v_dead   := r_sh_dead;
                    v_cnt_s  := v_tbphs;
                    v_sr_pos := r_sh_sr_pos;
                    v_sr_neg := r_sh_sr_neg;
                    r_period <= v_period;
                    r_half   <= v_half;
                    r_dead   <= v_dead;
                    r_phase  <= v_phi;
                    r_sr_pos <= v_sr_pos;
                    r_sr_neg <= v_sr_neg;
                end if;

                v_ahc_m := f_ahc_step(r_ahc_m, f_aq(r_cnt_m, v_half), v_dead);
                v_ahc_s := f_ahc_step(r_ahc_s, f_aq(v_cnt_s, v_half), v_dead);
                r_ahc_m <= v_ahc_m;
                r_ahc_s <= v_ahc_s;
                r_pwm(1) <= v_ahc_m.a;  -- S1
                r_pwm(2) <= v_ahc_m.b;  -- S2
                r_pwm(4) <= v_ahc_s.a;  -- S4（与 S1 同 AQ）
                r_pwm(3) <= v_ahc_s.b;  -- S3（与 S2 同 AQ）

                if (r_sr_d1 = '1') and (v_sr_pos.off_t > v_sr_pos.on_t) and
                   (r_cnt_m >= v_sr_pos.on_t) and (r_cnt_m < v_sr_pos.off_t) then
                    r_pwm(5) <= '1';
                    r_pwm(8) <= '1';
                else
                    r_pwm(5) <= '0';
                    r_pwm(8) <= '0';
                end if;
                if (r_sr_d1 = '1') and (v_sr_neg.off_t > v_sr_neg.on_t) and
                   (r_cnt_m >= v_sr_neg.on_t) and (r_cnt_m < v_sr_neg.off_t) then
                    r_pwm(6) <= '1';
                    r_pwm(7) <= '1';
                else
                    r_pwm(6) <= '0';
                    r_pwm(7) <= '0';
                end if;

                if r_cnt_m = (v_period - 1) then
                    r_cnt_m <= (others => '0');
                else
                    r_cnt_m <= r_cnt_m + 1;
                end if;
                if v_cnt_s = (v_period - 1) then
                    r_cnt_s <= (others => '0');
                else
                    r_cnt_s <= v_cnt_s + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
