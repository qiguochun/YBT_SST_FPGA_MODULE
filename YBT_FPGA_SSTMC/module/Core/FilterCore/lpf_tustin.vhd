--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   lpf_tustin.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.03
--Description       :   一阶低通（Tustin/双线性变换）定点实现。
--                      G(s)=WC/(s+WC)；系数 Q23。
--                      反馈状态带保护位；移位一律舍入；溢出饱和，不回绕。
--------------------------------------------------------------------------------
--Version           :   Rev 0.2
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   A1*y 与 B0*x 分拍共用一个乘法器，压到 Cyclone V 的 25 个 DSP 以内
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lpf_tustin is
    generic (
        TRI_MODE   : natural := 0;            -- 0: 外部 i_sample_pulse；1: 内部按 FS 分频
        WC         : integer := 6280;         -- 截止角频率 wn，单位 rad/s
        FS         : integer := 78125;        -- 采样频率，单位 Hz
        CALC_GAIN  : integer := 1;            -- 保留与原接口一致（本算法未使用）
        CLK_FREQ   : integer := 50_000_000;   -- 系统时钟，单位 Hz，TRI_MODE=1 时有效
        DATA_W     : positive := 32;          -- 对外数据位宽
        GUARD_BITS : natural := 4             -- 反馈状态额外小数位，吸收舍入误差
    );
    port (
        -- Global Clock
        i_sys_clk      : in  std_logic;
        i_sys_rst      : in  std_logic;

        -- User Interface
        i_input        : in  signed(DATA_W - 1 downto 0);
        i_sample_pulse : in  std_logic;  -- TRI_MODE=0 时有效
        o_output       : out signed(DATA_W - 1 downto 0)
    );
end entity lpf_tustin;

architecture rtl of lpf_tustin is

    constant C_SHIFT   : natural := 23;
    constant C_STATE_W : natural := DATA_W + GUARD_BITS;
    constant C_ACC_W   : natural := 64;
    constant C_Q23     : signed(24 downto 0) := to_signed(2 ** C_SHIFT, 25); -- 8388608

    -- 系数：分子*2^23 后按 den 做对称舍入除法
    function f_round_div(v_num : signed(31 downto 0); v_den : signed(31 downto 0)) return signed is
        variable v_prod : signed(56 downto 0);
        variable v_den64 : signed(63 downto 0);
        variable v_half  : signed(63 downto 0);
        variable v_adj   : signed(63 downto 0);
        variable v_q     : signed(63 downto 0);
    begin
        v_prod  := v_num * C_Q23;
        v_den64 := resize(v_den, 64);
        v_half  := shift_right(abs(v_den64), 1);
        if v_prod(v_prod'high) = v_den64(v_den64'high) then
            v_adj := resize(v_prod, 64) + v_half;
        else
            v_adj := resize(v_prod, 64) - v_half;
        end if;
        v_q := v_adj / v_den64;
        return resize(v_q, 32);
    end function;

    function f_coeff_a1(p_wc, p_fs : integer) return signed is
    begin
        return f_round_div(to_signed(2 * p_fs - p_wc, 32), to_signed(2 * p_fs + p_wc, 32));
    end function;

    function f_coeff_b0(p_wc, p_fs : integer) return signed is
    begin
        return f_round_div(to_signed(p_wc, 32), to_signed(2 * p_fs + p_wc, 32));
    end function;

    -- 对称舍入右移：|半 LSB| 加在远离零的方向，无直流偏置
    function f_round_asr(v_in : signed; v_shift : natural) return signed is
        variable v_half : signed(v_in'range);
        variable v_adj  : signed(v_in'range);
    begin
        if v_shift = 0 then
            return v_in;
        end if;
        v_half := (others => '0');
        v_half(v_shift - 1) := '1';
        if v_in(v_in'high) = '1' then
            v_adj := v_in - v_half;
        else
            v_adj := v_in + v_half;
        end if;
        return shift_right(v_adj, v_shift);
    end function;

    -- 饱和到 v_out_w 位有符号数，防止 IIR 反馈回绕
    function f_sat(v_in : signed; v_out_w : natural) return signed is
        variable v_max : signed(v_out_w - 1 downto 0);
        variable v_min : signed(v_out_w - 1 downto 0);
        variable v_ext_max : signed(v_in'range);
        variable v_ext_min : signed(v_in'range);
    begin
        v_max := (others => '1');
        v_max(v_out_w - 1) := '0';
        v_min := (others => '0');
        v_min(v_out_w - 1) := '1';
        v_ext_max := resize(v_max, v_in'length);
        v_ext_min := resize(v_min, v_in'length);
        if v_in > v_ext_max then
            return v_max;
        elsif v_in < v_ext_min then
            return v_min;
        else
            return resize(v_in, v_out_w);
        end if;
    end function;

    constant C_A1      : signed(31 downto 0) := f_coeff_a1(WC, FS);
    constant C_B0      : signed(31 downto 0) := f_coeff_b0(WC, FS);
    constant C_CNT_MAX : natural := CLK_FREQ / FS;

    signal r_xn1      : signed(DATA_W - 1 downto 0) := (others => '0');
    signal r_xn       : signed(DATA_W - 1 downto 0) := (others => '0');
    signal r_yn1      : signed(C_STATE_W - 1 downto 0) := (others => '0');
    signal r_yn       : signed(C_STATE_W - 1 downto 0) := (others => '0');
    signal r_product1 : signed(C_ACC_W - 1 downto 0) := (others => '0');
    signal r_product2 : signed(C_ACC_W - 1 downto 0) := (others => '0');
    signal r_sum_pre  : signed(C_ACC_W - 1 downto 0) := (others => '0');
    signal r_sum      : signed(C_ACC_W - 1 downto 0) := (others => '0');
    signal r_out      : signed(DATA_W - 1 downto 0) := (others => '0');

    signal r_cnt      : unsigned(15 downto 0) := (others => '0');
    signal w_sampling : std_logic;
    signal r_sampling : std_logic_vector(5 downto 0) := (others => '0');

begin

    o_output <= r_out;

    -- ===================== 内部采样节拍 =====================
    p_cnt : process (i_sys_rst, i_sys_clk)
    begin
        if i_sys_rst = '1' then
            r_cnt <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if TRI_MODE = 1 then
                if r_cnt = to_unsigned(C_CNT_MAX - 1, 16) then
                    r_cnt <= (others => '0');
                else
                    r_cnt <= r_cnt + 1;
                end if;
            else
                r_cnt <= (others => '0');
            end if;
        end if;
    end process p_cnt;

    w_sampling <= '1' when (TRI_MODE = 1) and (r_cnt = 0) else '0';

    -- ===================== 采样脉冲移位链 =====================
    p_sample_pipe : process (i_sys_rst, i_sys_clk)
    begin
        if i_sys_rst = '1' then
            r_sampling <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if TRI_MODE = 1 then
                r_sampling <= r_sampling(4 downto 0) & w_sampling;
            else
                r_sampling <= r_sampling(4 downto 0) & i_sample_pulse;
            end if;
        end if;
    end process p_sample_pipe;

    -- ===================== 乘 =====================
    -- y[n] = A1*y[n-1] + B0*(x[n]+x[n-1])
    -- y 带 GUARD 小数位；x 和先饱和再左移 GUARD，与 y 对齐。
    -- 32×(DATA_W+GUARD) 有符号乘在 Cyclone V 上占 2 个 DSP。
    -- 两路若同拍各做一个，每实例 4 个；7 路就是 28，超过 5CEBA2 的 25。
    -- sampling(0) 做 A1*y，sampling(1) 做 B0*x，共用同一个乘法器。加法仍在 sampling(2)。
    p_mul : process (i_sys_rst, i_sys_clk)
        variable v_xsum   : signed(DATA_W downto 0);
        variable v_xguard : signed(C_STATE_W - 1 downto 0);
        variable v_coef   : signed(31 downto 0);
        variable v_data   : signed(C_STATE_W - 1 downto 0);
        variable v_prod   : signed(C_STATE_W + 31 downto 0);
    begin
        if i_sys_rst = '1' then
            r_product1 <= (others => '0');
            r_product2 <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            v_xsum   := resize(r_xn, DATA_W + 1) + resize(r_xn1, DATA_W + 1);
            v_xguard := shift_left(resize(f_sat(v_xsum, DATA_W), C_STATE_W), GUARD_BITS);

            if r_sampling(0) = '1' then
                v_coef := C_A1;
                v_data := r_yn1;
            else
                v_coef := C_B0;
                v_data := v_xguard;
            end if;
            v_prod := v_coef * v_data;

            if r_sampling(0) = '1' then
                r_product1 <= resize(v_prod, C_ACC_W);
            elsif r_sampling(1) = '1' then
                r_product2 <= resize(v_prod, C_ACC_W);
            end if;
        end if;
    end process p_mul;

    -- ===================== 加 =====================
    p_add : process (i_sys_rst, i_sys_clk)
    begin
        if i_sys_rst = '1' then
            r_sum_pre <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_sampling(2) = '1' then
                r_sum_pre <= r_product1 + r_product2;
            end if;
        end if;
    end process p_add;

    -- ===================== Q23 舍入偏置 =====================
    p_round_bias : process (i_sys_rst, i_sys_clk)
        variable v_half : signed(C_ACC_W - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_sum <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_sampling(3) = '1' then
                v_half := (others => '0');
                v_half(C_SHIFT - 1) := '1';
                if r_sum_pre(r_sum_pre'high) = '1' then
                    r_sum <= r_sum_pre - v_half;
                else
                    r_sum <= r_sum_pre + v_half;
                end if;
            end if;
        end if;
    end process p_round_bias;

    -- ===================== 右移为带保护位的 y[n]，饱和 =====================
    p_shift_sat : process (i_sys_rst, i_sys_clk)
    begin
        if i_sys_rst = '1' then
            r_yn <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_sampling(4) = '1' then
                r_yn <= f_sat(shift_right(r_sum, C_SHIFT), C_STATE_W);
            end if;
        end if;
    end process p_shift_sat;

    -- ===================== 状态更新；输出再舍入去掉保护位 =====================
    p_state : process (i_sys_rst, i_sys_clk)
        variable v_out_wide : signed(C_ACC_W - 1 downto 0);
    begin
        if i_sys_rst = '1' then
            r_yn1 <= (others => '0');
            r_xn1 <= (others => '0');
            r_xn  <= (others => '0');
            r_out <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if r_sampling(5) = '1' then
                r_yn1 <= r_yn;
                r_xn1 <= r_xn;
                r_xn  <= i_input;
                v_out_wide := f_round_asr(resize(r_yn, C_ACC_W), GUARD_BITS);
                r_out <= f_sat(v_out_wide, DATA_W);
            end if;
        end if;
    end process p_state;

end architecture rtl;
