--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   amc1035_5ch_controller.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   五路 AMC1035 Sinc3 抽取。系统钟 50 MHz，SCLK 为 10 MHz。
--                      采样用时钟使能，不用分频时钟。OSR=256。
--                      比特流先标到 ±10000，再套原温度标定，供过温比较。
--                      积分、梳状差分、定标、温度标定各占一拍。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.21
--Modify Record     :   按编程规范整改实体名与端口名
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amc1035_5ch_controller is
    port (
        -- Global Clock
        i_sys_clk   : in  std_logic;
        i_sys_rst   : in  std_logic;

        -- User Interface
        o_amc1_sclk : out std_logic;
        o_amc2_sclk : out std_logic;
        o_amc3_sclk : out std_logic;
        o_amc4_sclk : out std_logic;
        o_amc5_sclk : out std_logic;
        i_amc1_dout : in  std_logic;
        i_amc2_dout : in  std_logic;
        i_amc3_dout : in  std_logic;
        i_amc4_dout : in  std_logic;
        i_amc5_dout : in  std_logic;
        o_data_ch1  : out std_logic_vector(11 downto 0);
        o_data_ch2  : out std_logic_vector(11 downto 0);
        o_data_ch3  : out std_logic_vector(11 downto 0);
        o_data_ch4  : out std_logic_vector(11 downto 0);
        o_data_ch5  : out std_logic_vector(11 downto 0);
        o_valid     : out std_logic
    );
end entity amc1035_5ch_controller;

architecture rtl of amc1035_5ch_controller is

    -- 10 MHz / 256 = 39.0625 kHz。直流增益 R^3 = 2^24，中点 2^23。
    constant CH_NUM      : integer := 5;
    constant OSR_VAL     : integer := 256;     -- 抽取比
    constant ACC_W       : integer := 32;      -- 积分位宽，大于 1+3*log2(OSR)=25
    constant C_MID       : signed(ACC_W - 1 downto 0) := to_signed(8388608, ACC_W); -- R^3/2 = 2^23
    constant CODE_FS     : integer := 10000;   -- 满量程码，对应比特流全 0 / 全 1
    constant CODE_SHIFT  : integer := 23;      -- log2(R^3/2)，与 C_MID 同一指数
    constant CODE_MAX    : integer := 32767;   -- 定标中间值饱和上限
    constant CODE_MIN    : integer := -32767;  -- 定标中间值饱和下限
    constant TEMP_MAX    : integer := 2047;    -- 12 位有符号饱和上限
    constant TEMP_MIN    : integer := -2048;   -- 12 位有符号饱和下限
    constant TEMP_SHIFT  : integer := 14;      -- 原标定除以 16384
    constant SCLK_DIV    : integer := 5;       -- 50 MHz / 5 = 10 MHz
    constant SCLK_RISE   : integer := 1;       -- 计数到此时拉高，高电平 2 拍
    constant SCLK_FALL   : integer := 3;       -- 计数到此时拉低，低电平 3 拍，占空比 40%
    constant WARMUP_DROP : integer := 2;       -- 丢掉复位后前两帧

    -- 原温度标定：(code * gain - bias) / 16384。CH1~3 与 CH4~5 系数不同。
    type t_coef is array (0 to CH_NUM - 1) of integer;
    constant CAL_GAIN : t_coef := (785, 785, 785, 938, 938);
    constant CAL_BIAS : t_coef := (5797, 5797, 5797, 14089, 14089);

    subtype t_acc is signed(ACC_W - 1 downto 0);
    type t_acc_vec is array (0 to CH_NUM - 1) of t_acc;
    type t_code_vec is array (0 to CH_NUM - 1) of integer range CODE_MIN to CODE_MAX;
    type t_data_vec is array (0 to CH_NUM - 1) of std_logic_vector(11 downto 0);

    -- 两次采样间隔 5 拍：积分后依次做差分、±10000 定标、温度标定
    type t_pipe is (PIPE_IDLE, PIPE_COMB, PIPE_CODE, PIPE_CAL);

    signal r_div_cnt : integer range 0 to SCLK_DIV - 1 := 0;
    signal r_sclk    : std_logic := '0';
    signal w_sample  : std_logic;
    signal w_dout    : std_logic_vector(CH_NUM - 1 downto 0);

    signal r_sync1   : std_logic_vector(CH_NUM - 1 downto 0) := (others => '0');
    signal r_sync2   : std_logic_vector(CH_NUM - 1 downto 0) := (others => '0');

    signal r_i1      : t_acc_vec := (others => (others => '0'));
    signal r_i2      : t_acc_vec := (others => (others => '0'));
    signal r_i3      : t_acc_vec := (others => (others => '0'));
    signal r_z1      : t_acc_vec := (others => (others => '0'));
    signal r_z2      : t_acc_vec := (others => (others => '0'));
    signal r_z3      : t_acc_vec := (others => (others => '0'));
    signal r_y       : t_acc_vec := (others => (others => '0'));
    signal r_code    : t_code_vec := (others => 0);

    signal r_osr_cnt  : integer range 0 to OSR_VAL - 1 := 0;
    signal r_warm_cnt : integer range 0 to WARMUP_DROP := 0;
    signal r_pipe     : t_pipe := PIPE_IDLE;
    signal r_data     : t_data_vec := (others => (others => '0'));
    signal r_valid    : std_logic := '0';

    function f_clip_code(v_code : integer) return integer is
    begin
        if v_code > CODE_MAX then
            return CODE_MAX;
        elsif v_code < CODE_MIN then
            return CODE_MIN;
        else
            return v_code;
        end if;
    end function;

    -- (raw - 2^23) * 10000 / 2^23，截断到整数
    function f_to_code(v_raw : t_acc) return integer is
        variable v_mul : signed(ACC_W + 15 downto 0);
    begin
        v_mul := resize(v_raw - C_MID, ACC_W) * to_signed(CODE_FS, 16);
        return f_clip_code(to_integer(resize(shift_right(v_mul, CODE_SHIFT), 32)));
    end function;

    -- 原公式 (code * gain - bias) / 16384，向 0 截断，再饱和到 12 位
    function f_to_temp(v_code : integer; v_gain : integer; v_bias : integer) return integer is
        variable v_num : signed(31 downto 0);
        variable v_mag : signed(31 downto 0);
        variable v_q   : integer;
    begin
        v_num := to_signed(v_code * v_gain - v_bias, 32);
        if v_num < 0 then
            v_mag := shift_right(-v_num, TEMP_SHIFT);
            v_q   := -to_integer(v_mag);
        else
            v_q := to_integer(shift_right(v_num, TEMP_SHIFT));
        end if;
        if v_q > TEMP_MAX then
            return TEMP_MAX;
        elsif v_q < TEMP_MIN then
            return TEMP_MIN;
        else
            return v_q;
        end if;
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
        i3, z1, z2, z3   : in  t_acc;
        y, nz1, nz2, nz3 : out t_acc
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
    o_amc3_sclk <= r_sclk;
    o_amc4_sclk <= r_sclk;
    o_amc5_sclk <= r_sclk;
    o_data_ch1  <= r_data(0);
    o_data_ch2  <= r_data(1);
    o_data_ch3  <= r_data(2);
    o_data_ch4  <= r_data(3);
    o_data_ch5  <= r_data(4);
    o_valid     <= r_valid;

    w_dout <= i_amc5_dout & i_amc4_dout & i_amc3_dout & i_amc2_dout & i_amc1_dout;

    -- 分频计数为 0 且 SCLK 仍为低：每个 10 MHz 周期采一次
    w_sample <= '1' when (r_div_cnt = 0) and (r_sclk = '0') else '0';

    -- 高 2 拍、低 3 拍。50 MHz 无法把 10 MHz 分成 50% 占空比
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
            r_sync1 <= (others => '0');
            r_sync2 <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            r_sync1 <= w_dout;
            r_sync2 <= r_sync1;
        end if;
    end process p_dout_sync;

    -- 第 1 拍积分，第 2 拍梳状差分，第 3 拍得到 ±10000，第 4 拍做温度标定。
    p_decim : process (i_sys_rst, i_sys_clk)
        variable v_i1, v_i2, v_i3    : t_acc;
        variable v_y, v_z1, v_z2, v_z3 : t_acc;
        variable v_temp              : integer;
    begin
        if i_sys_rst = '1' then
            r_i1      <= (others => (others => '0'));
            r_i2      <= (others => (others => '0'));
            r_i3      <= (others => (others => '0'));
            r_z1      <= (others => (others => '0'));
            r_z2      <= (others => (others => '0'));
            r_z3      <= (others => (others => '0'));
            r_y       <= (others => (others => '0'));
            r_code    <= (others => 0);
            r_pipe    <= PIPE_IDLE;
            r_osr_cnt <= 0;
            r_warm_cnt <= 0;
            r_data    <= (others => (others => '0'));
            r_valid   <= '0';
        elsif rising_edge(i_sys_clk) then
            r_valid <= '0';
            if w_sample = '1' then
                for v_ch in 0 to CH_NUM - 1 loop
                    p_integ(r_sync2(v_ch), r_i1(v_ch), r_i2(v_ch), r_i3(v_ch), v_i1, v_i2, v_i3);
                    r_i1(v_ch) <= v_i1;
                    r_i2(v_ch) <= v_i2;
                    r_i3(v_ch) <= v_i3;
                end loop;
                if r_osr_cnt = OSR_VAL - 1 then
                    r_osr_cnt <= 0;
                    r_pipe    <= PIPE_COMB;
                else
                    r_osr_cnt <= r_osr_cnt + 1;
                end if;
            elsif r_pipe = PIPE_COMB then
                for v_ch in 0 to CH_NUM - 1 loop
                    p_comb(r_i3(v_ch), r_z1(v_ch), r_z2(v_ch), r_z3(v_ch), v_y, v_z1, v_z2, v_z3);
                    r_y(v_ch)  <= v_y;
                    r_z1(v_ch) <= v_z1;
                    r_z2(v_ch) <= v_z2;
                    r_z3(v_ch) <= v_z3;
                end loop;
                r_pipe <= PIPE_CODE;
            elsif r_pipe = PIPE_CODE then
                for v_ch in 0 to CH_NUM - 1 loop
                    r_code(v_ch) <= f_to_code(r_y(v_ch));
                end loop;
                r_pipe <= PIPE_CAL;
            elsif r_pipe = PIPE_CAL then
                if r_warm_cnt < WARMUP_DROP then
                    r_warm_cnt <= r_warm_cnt + 1;
                else
                    for v_ch in 0 to CH_NUM - 1 loop
                        v_temp := f_to_temp(r_code(v_ch), CAL_GAIN(v_ch), CAL_BIAS(v_ch));
                        r_data(v_ch) <= std_logic_vector(to_signed(v_temp, 12));
                    end loop;
                    r_valid <= '1';
                end if;
                r_pipe <= PIPE_IDLE;
            end if;
        end if;
    end process p_decim;

end architecture rtl;
