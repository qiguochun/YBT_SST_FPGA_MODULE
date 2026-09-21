--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   fault_prot.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.21
--Description       :   硬件故障滤波与保护确认。
--                      过温五路、硬件故障四路共用同一确认过程。
--                      硬件故障锁存默认关闭，输出保持 0。
--------------------------------------------------------------------------------
--Version           :   Rev 0.2
--modifier          :   Qigc
--Modify Date       :   2026.09.21
--Modify Record     :   过温/滤波改为共用过程，去掉逐路复制
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

        -- Sample / hardware fault in
        i_udgy : in  std_logic;                      -- 直流过压标志
        i_t4   : in  std_logic_vector(11 downto 0);  -- T4~T6 用 T1 阈值
        i_t5   : in  std_logic_vector(11 downto 0);
        i_t6   : in  std_logic_vector(11 downto 0);
        i_t7   : in  std_logic_vector(11 downto 0);  -- T7/T8 用 T2 阈值
        i_t8   : in  std_logic_vector(11 downto 0);
        i_flt1 : in  std_logic;                      -- 硬件故障，低有效
        i_flt2 : in  std_logic;
        i_flt3 : in  std_logic;
        i_flt4 : in  std_logic;

        -- Fault bits
        o_cerr10   : out std_logic;                     -- 直流过压
        o_dvft_ot  : out std_logic_vector(11 downto 7); -- T4~T8 过温
        o_dvft_hw  : out std_logic_vector(3 downto 0)   -- F_FLT1~4，当前不锁存
    );
end entity fault_prot;

architecture rtl of fault_prot is

    constant CLK_DIV        : integer := 2500;   -- 50us @50MHz
    constant OV_CONFIRM_CNT : integer := 800;    -- 800*50us = 40ms
    constant FLT_FILTER_CNT : integer := 180;    -- 180/50MHz = 3.6us
    constant HW_LATCH_EN    : boolean := false;  -- 与原 Dv_Ft 一致：滤波后不锁存

    constant T1_ACT   : integer := 162;
    constant T1_RES   : integer := 142;
    constant T2_ACT   : integer := 176;
    constant T2_RES   : integer := 156;
    constant OT_TIMER : integer := 60000;        -- 60000*50us = 3s

    signal r_cerr10  : std_logic := '0';
    signal r_dvft_ot : std_logic_vector(11 downto 7) := (others => '0');
    signal r_dvft_hw : std_logic_vector(3 downto 0) := (others => '0');

begin

    o_cerr10  <= r_cerr10;
    o_dvft_ot <= r_dvft_ot;
    o_dvft_hw <= r_dvft_hw;

    -- ===================== 过压 / 过温确认 =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_cnt_clk : integer range 0 to 4095 := 0;
        variable v_gy_cnt  : integer range 0 to 4095 := 0;
        variable v_ot      : std_logic_vector(11 downto 7);

        procedure p_ot(
            constant c_temp : in std_logic_vector(11 downto 0);
            constant c_act  : in integer;
            constant c_res  : in integer;
            variable v_cnt  : inout integer;
            variable v_flt  : inout std_logic
        ) is
            variable v_val : integer;
        begin
            v_val := to_integer(signed(c_temp));
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

        variable v_t4 : integer range 0 to 65535 := 0;
        variable v_t5 : integer range 0 to 65535 := 0;
        variable v_t6 : integer range 0 to 65535 := 0;
        variable v_t7 : integer range 0 to 65535 := 0;
        variable v_t8 : integer range 0 to 65535 := 0;
    begin
        if (i_sys_rst = '1') or (i_clr = '1') then
            v_cnt_clk := 0;
            v_gy_cnt  := 0;
            v_t4 := 0;
            v_t5 := 0;
            v_t6 := 0;
            v_t7 := 0;
            v_t8 := 0;
            r_cerr10  <= '0';
            r_dvft_ot <= (others => '0');
        elsif rising_edge(i_sys_clk) then
            v_cnt_clk := v_cnt_clk + 1;
            if v_cnt_clk = CLK_DIV then
                v_cnt_clk := 0;
                if i_udgy = '1' then
                    if v_gy_cnt >= OV_CONFIRM_CNT then
                        r_cerr10 <= '1';
                    else
                        v_gy_cnt := v_gy_cnt + 1;
                    end if;
                else
                    v_gy_cnt := 0;
                end if;

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

    -- ===================== 硬件故障输入滤波 =====================
    process (i_sys_clk, i_sys_rst, i_clr)
        variable v_hw : std_logic_vector(3 downto 0);
        variable v_c1 : integer range 0 to 511 := 0;
        variable v_c2 : integer range 0 to 511 := 0;
        variable v_c3 : integer range 0 to 511 := 0;
        variable v_c4 : integer range 0 to 511 := 0;

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
            v_hw := r_dvft_hw;
            p_filter(i_flt1, HW_LATCH_EN, v_c1, v_hw(0));
            p_filter(i_flt2, HW_LATCH_EN, v_c2, v_hw(1));
            p_filter(i_flt3, HW_LATCH_EN, v_c3, v_hw(2));
            p_filter(i_flt4, HW_LATCH_EN, v_c4, v_hw(3));
            r_dvft_hw <= v_hw;
        end if;
    end process;

end architecture rtl;
