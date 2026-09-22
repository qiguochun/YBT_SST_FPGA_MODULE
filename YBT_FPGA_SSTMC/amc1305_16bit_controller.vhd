--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   amc1305_16bit_controller.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   双路 AMC1305 Sinc3 抽取。SCLK 20 MHz，采样用 120 MHz
--                      时钟使能。OSR=256，标定到 ±10000。
--                      流水：积分 → 梳状 → 去中点 → CH1 乘 → CH2 乘 → 移位/求和。
--------------------------------------------------------------------------------
--Version           :   Rev 0.5
--modifier          :   Qigc
--Modify Date       :   2026.09.22
--Modify Record     :   定标再拆：乘法与移位分拍，闭合 120 MHz Setup
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amc1305_16bit_controller is
    port (
        i_sys_clk   : in  std_logic;
        i_sys_rst   : in  std_logic;
        o_amc1_sclk : out std_logic;
        o_amc2_sclk : out std_logic;
        i_amc1_dout : in  std_logic;
        i_amc2_dout : in  std_logic;
        o_data_ch1  : out std_logic_vector(15 downto 0);
        o_data_ch2  : out std_logic_vector(15 downto 0);
        o_data_sum  : out std_logic_vector(15 downto 0);
        o_udgy      : out std_logic
    );
end entity amc1305_16bit_controller;

architecture rtl of amc1305_16bit_controller is

    constant OSR_VAL     : integer := 256;
    constant ACC_W       : integer := 32;
    constant C_MID       : signed(ACC_W - 1 downto 0) := to_signed(8388608, ACC_W); -- 2^23
    constant CODE_FS     : integer := 10000;
    constant CODE_SHIFT  : integer := 23;
    constant CODE_MAX    : integer := 32767;
    constant CODE_MIN    : integer := -32767;
    constant SCLK_DIV    : integer := 6;       -- 120 MHz / 6 = 20 MHz
    constant SCLK_RISE   : integer := 1;
    constant SCLK_FALL   : integer := 4;
    constant WARMUP_DROP : integer := 2;

    subtype t_acc  is signed(ACC_W - 1 downto 0);
    subtype t_code is signed(15 downto 0);
    subtype t_mul  is signed(ACC_W + 15 downto 0); -- 32×16 乘积

    -- 采样间隔 6 拍；满 OSR 后 5 拍后处理：COMB/DELTA/MUL1/MUL2/OUT
    type t_pipe is (
        PIPE_IDLE,
        PIPE_COMB,
        PIPE_DELTA,
        PIPE_MUL1,
        PIPE_MUL2,
        PIPE_OUT
    );

    signal r_div_cnt   : integer range 0 to SCLK_DIV - 1 := 0;
    signal r_sclk      : std_logic := '0';
    signal w_sample    : std_logic;

    signal r_ch1_sync1 : std_logic := '0';
    signal r_ch1_sync2 : std_logic := '0';
    signal r_ch2_sync1 : std_logic := '0';
    signal r_ch2_sync2 : std_logic := '0';

    signal r_ch1_i1 : t_acc := (others => '0');
    signal r_ch1_i2 : t_acc := (others => '0');
    signal r_ch1_i3 : t_acc := (others => '0');
    signal r_ch1_z1 : t_acc := (others => '0');
    signal r_ch1_z2 : t_acc := (others => '0');
    signal r_ch1_z3 : t_acc := (others => '0');

    signal r_ch2_i1 : t_acc := (others => '0');
    signal r_ch2_i2 : t_acc := (others => '0');
    signal r_ch2_i3 : t_acc := (others => '0');
    signal r_ch2_z1 : t_acc := (others => '0');
    signal r_ch2_z2 : t_acc := (others => '0');
    signal r_ch2_z3 : t_acc := (others => '0');

    signal r_ch1_y     : t_acc  := (others => '0');
    signal r_ch2_y     : t_acc  := (others => '0');
    signal r_ch1_delta : t_acc  := (others => '0');
    signal r_ch2_delta : t_acc  := (others => '0');
    signal r_ch1_mul   : t_mul  := (others => '0');
    signal r_ch2_mul   : t_mul  := (others => '0');
    signal r_ch1_code  : t_code := (others => '0');
    signal r_ch2_code  : t_code := (others => '0');
    signal r_pipe      : t_pipe := PIPE_IDLE;

    signal r_osr_cnt   : integer range 0 to OSR_VAL - 1 := 0;
    signal r_warm_cnt  : integer range 0 to WARMUP_DROP := 0;
    signal r_data_ch1  : std_logic_vector(15 downto 0) := (others => '0');
    signal r_data_ch2  : std_logic_vector(15 downto 0) := (others => '0');
    signal r_data_sum  : std_logic_vector(15 downto 0) := (others => '0');

    function f_clip16(v_code : signed(31 downto 0)) return t_code is
    begin
        if v_code > to_signed(CODE_MAX, 32) then
            return to_signed(CODE_MAX, 16);
        elsif v_code < to_signed(CODE_MIN, 32) then
            return to_signed(CODE_MIN, 16);
        else
            return resize(v_code, 16);
        end if;
    end function;

    -- 乘积右移 CODE_SHIFT 后饱和
    function f_mul_to_code(v_mul : t_mul) return t_code is
    begin
        return f_clip16(resize(shift_right(v_mul, CODE_SHIFT), 32));
    end function;

    procedure p_integ(
        din        : in  std_logic;
        i1, i2, i3 : in  t_acc;
        o1, o2, o3 : out t_acc
    ) is
        variable v_i1 : t_acc;
        variable v_i2 : t_acc;
        variable v_i3 : t_acc;
    begin
        v_i1 := i1;
        if din = '1' then
            v_i1 := v_i1 + 1;
        end if;
        v_i2 := i2 + v_i1;
        v_i3 := i3 + v_i2;
        o1   := v_i1;
        o2   := v_i2;
        o3   := v_i3;
    end procedure;

    procedure p_comb(
        i3, z1, z2, z3     : in  t_acc;
        y, nz1, nz2, nz3   : out t_acc
    ) is
        variable v_d1 : t_acc;
        variable v_d2 : t_acc;
        variable v_d3 : t_acc;
    begin
        v_d1 := i3 - z1;
        v_d2 := v_d1 - z2;
        v_d3 := v_d2 - z3;
        nz1  := i3;
        nz2  := v_d1;
        nz3  := v_d2;
        y    := v_d3;
    end procedure;

begin

    o_amc1_sclk <= r_sclk;
    o_amc2_sclk <= r_sclk;
    o_data_ch1  <= r_data_ch1;
    o_data_ch2  <= r_data_ch2;
    o_data_sum  <= r_data_sum;
    o_udgy      <= '0';

    w_sample <= '1' when (r_div_cnt = 0) and (r_sclk = '0') else '0';

    p_sclk : process (i_sys_rst, i_sys_clk)
        variable v_cnt : integer range 0 to SCLK_DIV;
    begin
        if i_sys_rst = '1' then
            r_div_cnt <= 0;
            r_sclk    <= '0';
        elsif rising_edge(i_sys_clk) then
            v_cnt := r_div_cnt + 1;
            if v_cnt = SCLK_DIV then
                v_cnt := 0;
            end if;
            if v_cnt = SCLK_RISE then
                r_sclk <= '1';
            elsif v_cnt = SCLK_FALL then
                r_sclk <= '0';
            end if;
            r_div_cnt <= v_cnt;
        end if;
    end process p_sclk;

    p_dout_sync : process (i_sys_rst, i_sys_clk)
    begin
        if i_sys_rst = '1' then
            r_ch1_sync1 <= '0';
            r_ch1_sync2 <= '0';
            r_ch2_sync1 <= '0';
            r_ch2_sync2 <= '0';
        elsif rising_edge(i_sys_clk) then
            r_ch1_sync1 <= i_amc1_dout;
            r_ch1_sync2 <= r_ch1_sync1;
            r_ch2_sync1 <= i_amc2_dout;
            r_ch2_sync2 <= r_ch2_sync1;
        end if;
    end process p_dout_sync;

    p_decim : process (i_sys_rst, i_sys_clk)
        variable v1_i1, v1_i2, v1_i3       : t_acc;
        variable v1_y, v1_z1, v1_z2, v1_z3 : t_acc;
        variable v2_i1, v2_i2, v2_i3       : t_acc;
        variable v2_y, v2_z1, v2_z2, v2_z3 : t_acc;
        variable v_c1, v_c2                : t_code;
        variable v_sum                     : signed(31 downto 0);
    begin
        if i_sys_rst = '1' then
            r_ch1_i1     <= (others => '0');
            r_ch1_i2     <= (others => '0');
            r_ch1_i3     <= (others => '0');
            r_ch1_z1     <= (others => '0');
            r_ch1_z2     <= (others => '0');
            r_ch1_z3     <= (others => '0');
            r_ch2_i1     <= (others => '0');
            r_ch2_i2     <= (others => '0');
            r_ch2_i3     <= (others => '0');
            r_ch2_z1     <= (others => '0');
            r_ch2_z2     <= (others => '0');
            r_ch2_z3     <= (others => '0');
            r_ch1_y      <= (others => '0');
            r_ch2_y      <= (others => '0');
            r_ch1_delta  <= (others => '0');
            r_ch2_delta  <= (others => '0');
            r_ch1_mul    <= (others => '0');
            r_ch2_mul    <= (others => '0');
            r_ch1_code   <= (others => '0');
            r_ch2_code   <= (others => '0');
            r_pipe       <= PIPE_IDLE;
            r_osr_cnt    <= 0;
            r_warm_cnt   <= 0;
            r_data_ch1   <= (others => '0');
            r_data_ch2   <= (others => '0');
            r_data_sum   <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if w_sample = '1' then
                p_integ(r_ch1_sync2, r_ch1_i1, r_ch1_i2, r_ch1_i3, v1_i1, v1_i2, v1_i3);
                p_integ(r_ch2_sync2, r_ch2_i1, r_ch2_i2, r_ch2_i3, v2_i1, v2_i2, v2_i3);
                r_ch1_i1 <= v1_i1;
                r_ch1_i2 <= v1_i2;
                r_ch1_i3 <= v1_i3;
                r_ch2_i1 <= v2_i1;
                r_ch2_i2 <= v2_i2;
                r_ch2_i3 <= v2_i3;

                if r_osr_cnt = OSR_VAL - 1 then
                    r_osr_cnt <= 0;
                    r_pipe    <= PIPE_COMB;
                else
                    r_osr_cnt <= r_osr_cnt + 1;
                end if;

            elsif r_pipe = PIPE_COMB then
                p_comb(r_ch1_i3, r_ch1_z1, r_ch1_z2, r_ch1_z3, v1_y, v1_z1, v1_z2, v1_z3);
                p_comb(r_ch2_i3, r_ch2_z1, r_ch2_z2, r_ch2_z3, v2_y, v2_z1, v2_z2, v2_z3);
                r_ch1_y  <= v1_y;
                r_ch1_z1 <= v1_z1;
                r_ch1_z2 <= v1_z2;
                r_ch1_z3 <= v1_z3;
                r_ch2_y  <= v2_y;
                r_ch2_z1 <= v2_z1;
                r_ch2_z2 <= v2_z2;
                r_ch2_z3 <= v2_z3;
                r_pipe   <= PIPE_DELTA;

            elsif r_pipe = PIPE_DELTA then
                r_ch1_delta <= r_ch1_y - C_MID;
                r_ch2_delta <= r_ch2_y - C_MID;
                r_pipe      <= PIPE_MUL1;

            elsif r_pipe = PIPE_MUL1 then
                -- 单独一拍：DSP 乘法寄存
                r_ch1_mul <= resize(r_ch1_delta, ACC_W) * to_signed(CODE_FS, 16);
                r_pipe    <= PIPE_MUL2;

            elsif r_pipe = PIPE_MUL2 then
                r_ch2_mul <= resize(r_ch2_delta, ACC_W) * to_signed(CODE_FS, 16);
                r_pipe    <= PIPE_OUT;

            elsif r_pipe = PIPE_OUT then
                v_c1 := f_mul_to_code(r_ch1_mul);
                v_c2 := f_mul_to_code(r_ch2_mul);
                r_ch1_code <= v_c1;
                r_ch2_code <= v_c2;
                if r_warm_cnt < WARMUP_DROP then
                    r_warm_cnt <= r_warm_cnt + 1;
                else
                    v_sum      := resize(v_c1, 32) + resize(v_c2, 32);
                    r_data_ch1 <= std_logic_vector(v_c1);
                    r_data_ch2 <= std_logic_vector(v_c2);
                    r_data_sum <= std_logic_vector(f_clip16(v_sum));
                end if;
                r_pipe <= PIPE_IDLE;
            end if;
        end if;
    end process p_decim;

end architecture rtl;
