--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   fault_prot.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   硬件故障滤波与保护确认。
--                      过压：滤波后高速正/负母线之和，滞回后确认。
--                      压差：|UTh-UBh|>240 持续 10ms 锁存，不自动恢复；暂不上报。
--                      过温：滤波后低速五路温度，与硬件故障四路共用确认过程。
--                      计时统一用 delay_core 的 1us/1ms/1s 脉冲，禁止自行分频。
--                      硬件故障锁存默认关闭，输出保持 0。
--------------------------------------------------------------------------------
--Version           :   Rev 0.5
--modifier          :   Qigc
--Modify Date       :   2026.09.23
--Modify Record     :   增加正负母线压差故障（10ms 锁存，输出暂不外接）
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fault_prot is
    port (
        -- Global Clock
        i_sys_clk : in  std_logic;
        i_sys_rst : in  std_logic;  -- 异步复位，高有效
        i_clr     : in  std_logic;  -- 系统清除，高有效，与复位同样清故障

        -- delay_core 公共时基（单周期脉冲）
        i_delay_1us : in  std_logic;
        i_delay_1ms : in  std_logic;
        i_delay_1s  : in  std_logic;

        -- Sample / hardware fault in（滤波后量）
        i_uth  : in  signed(31 downto 0);  -- 高速滤波正母线 UTh
        i_ubh  : in  signed(31 downto 0);  -- 高速滤波负母线 UBh
        i_t4   : in  signed(31 downto 0);  -- 低速滤波 T4~T6 用 T1 阈值
        i_t5   : in  signed(31 downto 0);
        i_t6   : in  signed(31 downto 0);
        i_t7   : in  signed(31 downto 0);  -- T7/T8 用 T2 阈值
        i_t8   : in  signed(31 downto 0);
        i_flt1 : in  std_logic;            -- 硬件故障，低有效
        i_flt2 : in  std_logic;
        i_flt3 : in  std_logic;
        i_flt4 : in  std_logic;

        -- Fault bits
        o_cerr10     : out std_logic;                     -- 直流过压
        o_dvft_ot    : out std_logic_vector(11 downto 7); -- T4~T8 过温
        o_dvft_hw    : out std_logic_vector(3 downto 0);  -- F_FLT1~4，当前不锁存
        o_bus_imbal  : out std_logic                      -- 正负压差大；暂不上报，顶层先 open
    );
end entity fault_prot;

architecture rtl of fault_prot is

    constant OV_CONFIRM_CNT : integer := 40;   -- 40*1ms = 40ms
    constant IMBAL_CNT      : integer := 10;   -- 10*1ms = 10ms
    constant IMBAL_TH       : integer := 240;  -- |UTh-UBh| 阈值
    constant FLT_FILTER_CNT : integer := 4;    -- 4*1us ≈ 原 3.6us
    constant HW_LATCH_EN    : boolean := false;

    -- 原 AMC1305 对两路之和的过压滞回
    constant OV_ACT : integer := 10553;
    constant OV_RES : integer := 10162;

    constant T1_ACT   : integer := 162;
    constant T1_RES   : integer := 142;
    constant T2_ACT   : integer := 176;
    constant T2_RES   : integer := 156;
    constant OT_TIMER : integer := 3;          -- 3*1s = 3s

    signal r_cerr10    : std_logic := '0';
    signal r_dvft_ot   : std_logic_vector(11 downto 7) := (others => '0');
    signal r_dvft_hw   : std_logic_vector(3 downto 0) := (others => '0');
    signal r_bus_imbal : std_logic := '0';

begin

    o_cerr10    <= r_cerr10;
    o_dvft_ot   <= r_dvft_ot;
    o_dvft_hw   <= r_dvft_hw;
    o_bus_imbal <= r_bus_imbal;

    -- ===================== 过压确认（1 ms 节拍） =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_gy_cnt : integer range 0 to 255 := 0;
        variable v_udgy   : std_logic := '0';
        variable v_sum    : integer;
    begin
        if (i_sys_rst = '1') or (i_clr = '1') then
            v_gy_cnt := 0;
            v_udgy   := '0';
            r_cerr10 <= '0';
        elsif rising_edge(i_sys_clk) then
            if i_delay_1ms = '1' then
                v_sum := to_integer(i_uth) + to_integer(i_ubh);
                if v_udgy = '0' then
                    if v_sum > OV_ACT then
                        v_udgy := '1';
                    end if;
                else
                    if v_sum < OV_RES then
                        v_udgy := '0';
                    end if;
                end if;

                if v_udgy = '1' then
                    if v_gy_cnt >= OV_CONFIRM_CNT then
                        r_cerr10 <= '1';
                    else
                        v_gy_cnt := v_gy_cnt + 1;
                    end if;
                else
                    v_gy_cnt := 0;
                end if;
            end if;
        end if;
    end process;

    -- ===================== 正负压差大（1 ms 节拍，锁存不恢复） =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_imbal_cnt : integer range 0 to 31 := 0;
        variable v_diff      : integer;
    begin
        if (i_sys_rst = '1') or (i_clr = '1') then
            v_imbal_cnt := 0;
            r_bus_imbal <= '0';
        elsif rising_edge(i_sys_clk) then
            if i_delay_1ms = '1' then
                if r_bus_imbal = '0' then
                    v_diff := to_integer(i_uth) - to_integer(i_ubh);
                    if v_diff < 0 then
                        v_diff := -v_diff;
                    end if;
                    if v_diff > IMBAL_TH then
                        if v_imbal_cnt < IMBAL_CNT then
                            v_imbal_cnt := v_imbal_cnt + 1;
                        end if;
                        if v_imbal_cnt >= IMBAL_CNT then
                            r_bus_imbal <= '1';
                        end if;
                    else
                        v_imbal_cnt := 0;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ===================== 过温确认（1 s 节拍） =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_ot : std_logic_vector(11 downto 7);

        procedure p_ot(
            constant c_temp : in signed(31 downto 0);
            constant c_act  : in integer;
            constant c_res  : in integer;
            variable v_cnt  : inout integer;
            variable v_flt  : inout std_logic
        ) is
            variable v_val : integer;
        begin
            v_val := to_integer(c_temp);
            if v_val > c_act then
                if v_cnt >= OT_TIMER then
                    v_flt := '1';
                else
                    v_cnt := v_cnt + 1;
                end if;
            elsif v_val < c_res then
                v_cnt := 0;
            end if;
        end procedure p_ot;

        variable v_t4 : integer range 0 to 15 := 0;
        variable v_t5 : integer range 0 to 15 := 0;
        variable v_t6 : integer range 0 to 15 := 0;
        variable v_t7 : integer range 0 to 15 := 0;
        variable v_t8 : integer range 0 to 15 := 0;
    begin
        if (i_sys_rst = '1') or (i_clr = '1') then
            v_t4 := 0;
            v_t5 := 0;
            v_t6 := 0;
            v_t7 := 0;
            v_t8 := 0;
            r_dvft_ot <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_delay_1s = '1' then
                v_ot := r_dvft_ot;
                p_ot(i_t4, T1_ACT, T1_RES, v_t4, v_ot(7));
                p_ot(i_t5, T1_ACT, T1_RES, v_t5, v_ot(8));
                p_ot(i_t6, T1_ACT, T1_RES, v_t6, v_ot(9));
                p_ot(i_t7, T2_ACT, T2_RES, v_t7, v_ot(10));
                p_ot(i_t8, T2_ACT, T2_RES, v_t8, v_ot(11));
                r_dvft_ot <= v_ot;
            end if;
        end if;
    end process;

    -- ===================== 硬件故障输入滤波（1 us 节拍） =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_hw : std_logic_vector(3 downto 0);
        variable v_c1 : integer range 0 to 15 := 0;
        variable v_c2 : integer range 0 to 15 := 0;
        variable v_c3 : integer range 0 to 15 := 0;
        variable v_c4 : integer range 0 to 15 := 0;

        procedure p_filter(
            constant c_flt     : in std_logic;
            constant c_latch   : in boolean;
            variable v_cnt     : inout integer;
            variable v_bit     : inout std_logic
        ) is
        begin
            if c_flt = '0' then
                if v_cnt >= FLT_FILTER_CNT then
                    if c_latch then
                        v_bit := '1';
                    end if;
                else
                    v_cnt := v_cnt + 1;
                end if;
            else
                v_cnt := 0;
            end if;
        end procedure p_filter;
    begin
        if (i_sys_rst = '1') or (i_clr = '1') then
            v_c1 := 0;
            v_c2 := 0;
            v_c3 := 0;
            v_c4 := 0;
            r_dvft_hw <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            if i_delay_1us = '1' then
                v_hw := r_dvft_hw;
                p_filter(i_flt1, HW_LATCH_EN, v_c1, v_hw(0));
                p_filter(i_flt2, HW_LATCH_EN, v_c2, v_hw(1));
                p_filter(i_flt3, HW_LATCH_EN, v_c3, v_hw(2));
                p_filter(i_flt4, HW_LATCH_EN, v_c4, v_hw(3));
                r_dvft_hw <= v_hw;
            end if;
        end if;
    end process;

end architecture rtl;
