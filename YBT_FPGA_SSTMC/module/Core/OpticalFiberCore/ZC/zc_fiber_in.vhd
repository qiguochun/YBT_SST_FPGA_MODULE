--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zc_fiber_in.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   ZC 光纤输入：解析单元接口 FPGA 回传，并检测链路故障。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   收齐边沿当拍解析；温度收到即定标；故障检测复用看门狗
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zc_fiber_in is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        DT_IN    : positive := 43           -- 回传帧宽：接口 -> 单元主控
    );
    port (
        -- Global Clock
        i_sys_clk  : in  std_logic;
        i_sys_rst  : in  std_logic;  -- 异步复位，高有效
        i_led_res  : in  std_logic;  -- LED 复位闪烁节拍
        i_clr      : in  std_logic;
        i_open_clr : in  std_logic;

        -- PHY Receive
        i_fiber_r : in  std_logic;                            -- 接口侧光纤接收
        i_dt_in   : in  std_logic_vector(DT_IN - 1 downto 0); -- 回传原始帧
        i_finish  : in  std_logic;                            -- 一帧收发完成

        -- Decode from ZC
        o_i1o      : out std_logic_vector(15 downto 0);
        o_i2o      : out std_logic_vector(15 downto 0);
        o_i3o      : out std_logic_vector(15 downto 0);
        o_t1s      : out std_logic_vector(11 downto 0);
        o_t2s      : out std_logic_vector(11 downto 0);
        o_t3s      : out std_logic_vector(11 downto 0);
        o_dzgz     : out std_logic;
        o_cerr0    : out std_logic;                     -- ZC 光纤通信故障
        o_cerr_1_4 : out std_logic_vector(4 downto 1);  -- 接口侧故障子码
        o_cerr_7_9 : out std_logic_vector(9 downto 7);
        o_cerr11   : out std_logic;
        o_dvft_4_6 : out std_logic_vector(6 downto 4);
        o_led      : out std_logic                      -- F_LED2 通信心跳
    );
end entity zc_fiber_in;

architecture rtl of zc_fiber_in is

    constant LED_TOGGLE_FRAME : natural := 5000;  -- LED 翻转间隔（帧）

    constant HDR_FAULT : std_logic_vector(4 downto 0) := "01101";
    constant HDR_OK    : std_logic_vector(4 downto 0) := "10110";

    constant CH_I1 : std_logic_vector(2 downto 0) := "001";
    constant CH_I2 : std_logic_vector(2 downto 0) := "010";
    constant CH_I3 : std_logic_vector(2 downto 0) := "011";

    constant CH_T1    : std_logic_vector(2 downto 0) := "001";
    constant CH_T2    : std_logic_vector(2 downto 0) := "010";
    constant CH_T3    : std_logic_vector(2 downto 0) := "011";
    constant CH_FAULT : std_logic_vector(2 downto 0) := "100";

    constant TEMP_GAIN   : integer := 225;
    constant TEMP_OFFSET : integer := 18118;
    constant TEMP_DIV    : integer := 16384;  -- 2^14

    signal w_clr         : std_logic;
    signal w_cerr0       : std_logic;
    signal r_finish_d    : std_logic := '0';
    signal r_i1o         : std_logic_vector(15 downto 0) := (others => '0');
    signal r_i2o         : std_logic_vector(15 downto 0) := (others => '0');
    signal r_i3o         : std_logic_vector(15 downto 0) := (others => '0');
    signal r_t1s         : std_logic_vector(11 downto 0) := (others => '0');
    signal r_t2s         : std_logic_vector(11 downto 0) := (others => '0');
    signal r_t3s         : std_logic_vector(11 downto 0) := (others => '0');
    signal r_dzgz        : std_logic := '0';
    signal r_cerr_1_4    : std_logic_vector(4 downto 1) := (others => '0');
    signal r_cerr_7_9    : std_logic_vector(9 downto 7) := (others => '0');
    signal r_cerr11      : std_logic := '0';
    signal r_dvft_4_6    : std_logic_vector(6 downto 4) := (others => '0');
    signal r_led_clk     : std_logic := '0';
    signal r_led         : std_logic := '0';

    function f_scale_temp (
        i_raw : std_logic_vector(15 downto 0)
    ) return std_logic_vector is
        variable v_eng : integer;
    begin
        v_eng := (to_integer(signed(i_raw)) * TEMP_GAIN - TEMP_OFFSET) / TEMP_DIV;
        return std_logic_vector(to_signed(v_eng, 12));
    end function f_scale_temp;

begin

    w_clr      <= i_clr or i_open_clr;
    o_cerr0    <= w_cerr0;
    o_i1o      <= r_i1o;
    o_i2o      <= r_i2o;
    o_i3o      <= r_i3o;
    o_t1s      <= r_t1s;
    o_t2s      <= r_t2s;
    o_t3s      <= r_t3s;
    o_dzgz     <= r_dzgz;
    o_cerr_1_4 <= r_cerr_1_4;
    o_cerr_7_9 <= r_cerr_7_9;
    o_cerr11   <= r_cerr11;
    o_dvft_4_6 <= r_dvft_4_6;
    o_led      <= r_led;

    U_WATCHDOG : entity work.fiber_link_watchdog
        generic map (
            CLK_FREQ => CLK_FREQ
        )
        port map (
            i_sys_clk => i_sys_clk,
            i_sys_rst => i_sys_rst,
            i_clr     => w_clr,
            i_fiber_r => i_fiber_r,
            i_finish  => i_finish,
            o_cerr    => w_cerr0
        );

    -- ===================== 回传帧解析 =====================
    -- bit42~38: 帧头  bit37~35: 电流通道  bit18~16: 温度/故障通道
    process (i_sys_clk, i_sys_rst)
        variable v_cnt_led : integer range 0 to 8191 := 0;
    begin
        if i_sys_rst = '1' then
            r_finish_d <= '0';
            r_dzgz     <= '0';
            r_i1o      <= (others => '0');
            r_i2o      <= (others => '0');
            r_i3o      <= (others => '0');
            r_t1s      <= (others => '0');
            r_t2s      <= (others => '0');
            r_t3s      <= (others => '0');
            r_cerr_1_4 <= (others => '0');
            r_cerr_7_9 <= (others => '0');
            r_cerr11   <= '0';
            r_dvft_4_6 <= (others => '0');
            v_cnt_led  := 0;
            r_led_clk  <= '0';
            r_led      <= '0';
        elsif rising_edge(i_sys_clk) then
            if w_cerr0 = '1' then
                r_finish_d <= '0';
                r_dzgz     <= '0';
                r_i1o      <= (others => '0');
                r_i2o      <= (others => '0');
                r_i3o      <= (others => '0');
                r_t1s      <= (others => '0');
                r_t2s      <= (others => '0');
                r_t3s      <= (others => '0');
                r_cerr_1_4 <= (others => '0');
                r_cerr_7_9 <= (others => '0');
                r_cerr11   <= '0';
                r_dvft_4_6 <= (others => '0');
                v_cnt_led  := 0;
                r_led_clk  <= '0';
                r_led      <= '0';
            else
                if (i_finish = '1') and (r_finish_d = '0') then
                    case i_dt_in(42 downto 38) is
                        when HDR_FAULT =>
                            r_dzgz <= '1';
                        when HDR_OK =>
                            r_dzgz <= '0';
                        when others =>
                            null;
                    end case;

                    case i_dt_in(37 downto 35) is
                        when CH_I1 =>
                            r_i1o <= i_dt_in(34 downto 19);
                        when CH_I2 =>
                            r_i2o <= i_dt_in(34 downto 19);
                        when CH_I3 =>
                            r_i3o <= i_dt_in(34 downto 19);
                        when others =>
                            null;
                    end case;

                    case i_dt_in(18 downto 16) is
                        when CH_T1 =>
                            r_t1s <= f_scale_temp(i_dt_in(15 downto 0));
                        when CH_T2 =>
                            r_t2s <= f_scale_temp(i_dt_in(15 downto 0));
                        when CH_T3 =>
                            r_t3s <= f_scale_temp(i_dt_in(15 downto 0));
                        when CH_FAULT =>
                            r_cerr_1_4 <= i_dt_in(4 downto 1);
                            r_cerr_7_9 <= i_dt_in(9 downto 7);
                            r_cerr11   <= i_dt_in(11);
                            r_dvft_4_6 <= i_dt_in(14 downto 12);
                        when others =>
                            null;
                    end case;

                    if v_cnt_led >= LED_TOGGLE_FRAME then
                        v_cnt_led := 1;
                        r_led_clk <= not r_led_clk;
                    else
                        v_cnt_led := v_cnt_led + 1;
                    end if;
                end if;

                r_finish_d <= i_finish;
                r_led      <= r_led_clk xor i_led_res;
            end if;
        end if;
    end process;

end architecture rtl;
