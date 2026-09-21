--------------------------------------------------------------------------------
--Project Name      :   YBT_FPGA_SSTMC
--Moudle Name       :   zc_fiber_core.vhd
--Original Author   :   Qigc
--Creation Date     :   2026.09.16
--Description       :   单元主控 <-> 单元接口（ZC）光纤通信封装。
--                      例化 zc_fiber_out（下发）、zc_fiber_in（回传解析）及 TX_Comm PHY。
--------------------------------------------------------------------------------
--Version           :   Rev 0.3
--modifier          :   Qigc
--Modify Date       :   2026.09.16
--Modify Record     :   按 VHDL-2008 规范整改：端口 snake_case、r_/w_ 命名
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity zc_fiber_core is
    generic (
        CLK_FREQ : positive := 50_000_000;  -- 系统时钟频率，单位 Hz
        DELAY    : positive := 20;          -- PHY 每 bit 时钟数，400 ns @ 50 MHz
        DT_IN    : positive := 43;          -- 回传帧宽：接口 -> 单元主控
        DT_OUT   : positive := 21           -- 下行帧宽：单元主控 -> 接口
    );
    port (
        -- Global Clock
        i_sys_clk  : in  std_logic;
        i_sys_rst  : in  std_logic;  -- 异步复位，高有效
        i_tx_clk   : in  std_logic;  -- 20 kHz 帧时钟
        i_led_res  : in  std_logic;  -- LED 复位闪烁节拍

        -- Command to ZC
        i_clr      : in  std_logic;
        i_bs       : in  std_logic;
        i_dpwm_new : in  std_logic;
        i_pt       : in  std_logic_vector(15 downto 0);

        -- Fiber PHY
        i_fiber_r : in  std_logic;  -- 接口侧光纤接收
        o_fiber_t : out std_logic;  -- 接口侧光纤发送（已取反）

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
        o_sin_ft   : out std_logic;                     -- 单次通信故障脉冲
        o_led      : out std_logic                      -- F_LED2 通信心跳
    );
end entity zc_fiber_core;

architecture rtl of zc_fiber_core is

    signal w_dt_in   : std_logic_vector(DT_IN - 1 downto 0) := (others => '0');
    signal w_dt_out  : std_logic_vector(DT_OUT - 1 downto 0) := (others => '0');
    signal w_fiber_t : std_logic := '0';
    signal w_finish  : std_logic := '0';

begin

    o_fiber_t <= not w_fiber_t;

    U_ZC_FIBER_OUT : entity work.zc_fiber_out
        generic map (
            DT_OUT => DT_OUT
        )
        port map (
            -- Global Clock
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_tx_clk   => i_tx_clk,
            -- Command to ZC
            i_clr      => i_clr,
            i_bs       => i_bs,
            i_dpwm_new => i_dpwm_new,
            i_pt       => i_pt,
            -- Frame to PHY
            o_dt_out   => w_dt_out
        );

    U_ZC_FIBER_IN : entity work.zc_fiber_in
        generic map (
            CLK_FREQ => CLK_FREQ,
            DT_IN    => DT_IN
        )
        port map (
            -- Global Clock
            i_sys_clk  => i_sys_clk,
            i_sys_rst  => i_sys_rst,
            i_led_res  => i_led_res,
            i_clr      => i_clr,
            -- PHY Receive
            i_fiber_r  => i_fiber_r,
            i_dt_in    => w_dt_in,
            i_finish   => w_finish,
            -- Decode from ZC
            o_i1o      => o_i1o,
            o_i2o      => o_i2o,
            o_i3o      => o_i3o,
            o_t1s      => o_t1s,
            o_t2s      => o_t2s,
            o_t3s      => o_t3s,
            o_dzgz     => o_dzgz,
            o_cerr0    => o_cerr0,
            o_cerr_1_4 => o_cerr_1_4,
            o_cerr_7_9 => o_cerr_7_9,
            o_cerr11   => o_cerr11,
            o_dvft_4_6 => o_dvft_4_6,
            o_led      => o_led
        );

    -- TX_Comm 为遗留 PHY，端口名保留原风格
    U_ZC_COMM : entity work.TX_Comm
        generic map (
            DELAY => DELAY,
            DtinN => DT_IN,
            DtOUT => DT_OUT
        )
        port map (
            RESET    => i_sys_rst,
            CLK      => i_sys_clk,
            TXclk    => i_tx_clk,
            FiberR   => i_fiber_r,
            TXdtIn   => w_dt_in,
            TXdtOut  => w_dt_out,
            FiberT   => w_fiber_t,
            TXSinFt  => o_sin_ft,
            TXFinish => w_finish
        );

end architecture rtl;
